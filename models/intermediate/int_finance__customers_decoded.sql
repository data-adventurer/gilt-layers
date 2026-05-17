{{
    config(
        materialized = 'table',
        file_format  = 'delta'
    )
}}

with source as (

    select * from {{ ref('stg_finance__customers') }}

),

decoded as (

    select

        customer_id,
        crm_reference,

        date_of_birth,
        onboard_date,

        segment_code,
        customer_status_code,
        risk_score,
        know_your_cust_flag,

        -- Decoded labels
        case segment_code
            when 'RTL' then 'Retail'
            when 'PRM' then 'Premium'
            when 'COM' then 'Commercial'
        end                                                         as customer_segment,

        case customer_status_code
            when 'AC' then 'Active'
            when 'DM' then 'Dormant'
            when 'CL' then 'Closed'
        end                                                         as customer_status,

        -- Division classification
        segment_code in ('RTL', 'PRM')                    as is_retail_customer,
        segment_code = 'COM'                               as is_commercial_customer,

        -- Status flags
        customer_status_code = 'AC'                                 as is_active,
        customer_status_code = 'DM'                                 as is_dormant,
        customer_status_code = 'CL'                                 as is_closed,

        -- Age and age banding
        floor(
            datediff(current_date(), date_of_birth) / 365.25
        )                                                           as customer_age,

        case
            when floor(datediff(current_date(), date_of_birth) / 365.25) < 31
                then '18-30'
            when floor(datediff(current_date(), date_of_birth) / 365.25) < 46
                then '31-45'
            when floor(datediff(current_date(), date_of_birth) / 365.25) < 61
                then '46-60'
            else '60+'
        end                                                         as age_bucket,

        -- Tenure
        datediff(current_date(), onboard_date)                      as tenure_days,
        floor(datediff(current_date(), onboard_date) / 30.44)       as tenure_months,

        -- New customer flags
        -- Thresholds differ by division and are enforced in the semantic layer.
        -- Both flags are surfaced here so the bridge model can carry both.
        datediff(current_date(), onboard_date) <= 90                as is_new_retail_customer,
        datediff(current_date(), onboard_date) <= 180               as is_new_commercial_customer,

        -- Risk flags
        -- Retail threshold: >= 40. Commercial threshold: >= 30.
        -- Both are surfaced here; the semantic layer picks the correct one per division.
        risk_score >= 40                                            as is_high_risk_retail,
        risk_score >= 30                                            as is_high_risk_commercial

    from source

)

select * from decoded