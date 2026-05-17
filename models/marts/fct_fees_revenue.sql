{{
    config(
        materialized = 'table',
        file_format  = 'delta'
    )
}}

-- Grain: fee_type × month × division
-- One row per fee type per calendar month per division.
-- Retail and commercial fee types are kept as separate rows so the
-- semantic layer can filter cleanly to each division's revenue definition
-- without cross-contamination.

with fees as (

    select * from {{ ref('int_finance__fees_decoded') }}

),

bridge as (

    select
        account_id,
        division_code,
        division_name
    from {{ ref('int_finance__acct_cust_bridge') }}

),

joined as (

    select
        f.fee_month,
        f.fee_year,
        f.fee_month_num,
        f.fee_type_code,
        f.fee_type,
        f.is_retail_fee,
        f.is_commercial_fee,
        f.fee_amount,
        f.is_standalone_fee,
        b.division_code,
        b.division_name

    from fees         f
    inner join bridge b on f.account_id = b.account_id

),

aggregated as (

    select

        -- Grain
        fee_month,
        fee_year,
        fee_month_num,
        fee_type_code,
        fee_type,
        division_code,
        division_name,

        -- Division classification (consistent per fee type — safe to carry through)
        is_retail_fee,
        is_commercial_fee,

        -- Volume
        count(*)                                                    as fee_count,

        -- Revenue
        sum(fee_amount)                                             as total_fee_revenue,
        avg(fee_amount)                                             as avg_fee_amount,
        min(fee_amount)                                             as min_fee_amount,
        max(fee_amount)                                             as max_fee_amount,

        -- Standalone vs transaction-linked breakdown
        -- Standalone fees (is_standalone_fee = true) are periodic charges
        -- not tied to a transaction event. Both are valid revenue.
        count(case when is_standalone_fee     then 1 end)           as standalone_fee_count,
        count(case when not is_standalone_fee then 1 end)           as transaction_linked_fee_count,
        sum(case when is_standalone_fee       then fee_amount
                 else 0                       end)                  as standalone_fee_revenue,
        sum(case when not is_standalone_fee   then fee_amount
                 else 0                       end)                  as transaction_linked_fee_revenue

    from joined
    group by
        fee_month,
        fee_year,
        fee_month_num,
        fee_type_code,
        fee_type,
        division_code,
        division_name,
        is_retail_fee,
        is_commercial_fee

)

select * from aggregated