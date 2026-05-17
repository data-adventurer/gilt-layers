{{
    config(
        materialized = 'table',
        file_format  = 'delta'
    )
}}

-- Core enriched entity for gilt-layers.
-- One row per account, fully denormalised with customer, branch, and division
-- context. All gold models join to this bridge rather than performing their
-- own multi-hop joins — keeps gold models clean and lineage easy to follow.

with accounts as (

    select * from {{ ref('int_finance__accounts_decoded') }}

),

customers as (

    select * from {{ ref('int_finance__customers_decoded') }}

),

branches as (

    select * from {{ ref('stg_finance__branches') }}

),

divisions as (

    select * from {{ ref('stg_finance__divisions') }}

),

bridge as (

    select

        -- ── Account ────────────────────────────────────────────────────────
        a.account_id,
        a.customer_id,
        a.branch_code,

        a.account_type_code,
        a.account_type,
        a.account_status_code,
        a.account_status,
        a.open_date,
        a.close_date,
        a.balance,
        a.balance_band,
        a.account_age_days,
        a.account_age_months,
        a.is_retail_product,
        a.is_commercial_product,
        a.is_open,
        a.is_closed                                                 as account_is_closed,
        a.is_frozen,

        -- ── Customer ───────────────────────────────────────────────────────
        c.crm_reference,
        c.date_of_birth,
        c.onboard_date,
        c.segment_code,
        c.customer_segment,
        c.customer_status_code,
        c.customer_status,
        c.risk_score,
        c.know_your_cust_flag,
        c.customer_age,
        c.age_bucket,
        c.tenure_days,
        c.tenure_months,
        c.is_retail_customer,
        c.is_commercial_customer,
        c.is_active                                                 as customer_is_active,
        c.is_dormant                                                as customer_is_dormant,
        c.is_closed                                                 as customer_is_closed,
        c.is_high_risk_retail,
        c.is_high_risk_commercial,
        c.is_new_retail_customer,
        c.is_new_commercial_customer,

        -- ── Branch ─────────────────────────────────────────────────────────
        b.branch_name,
        b.region_code,

        case b.region_code
            when 'NE' then 'Northeast'
            when 'SE' then 'Southeast'
            when 'MW' then 'Midwest'
            when 'SW' then 'Southwest'
            when 'W'  then 'West'
        end                                                         as region_name,

        -- ── Division ───────────────────────────────────────────────────────
        d.division_code,
        d.division_name

    from accounts a
    inner join customers c
        on a.customer_id = c.customer_id
    inner join branches b
        on a.branch_code = b.branch_code
    inner join divisions d
        on b.division_code = d.division_code

)

select * from bridge