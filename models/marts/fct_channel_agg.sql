{{
    config(
        materialized = 'table',
        file_format  = 'delta'
    )
}}

-- Grain: channel × month × division
-- One row per channel per calendar month per division.
-- Division context is included so Tableau can apply the correct
-- digital adoption definition per division (retail excludes WIRE;
-- commercial includes it).

with transactions as (

    select * from {{ ref('int_finance__transactions_decoded') }}

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
        t.transaction_month,
        t.transaction_year,
        t.transaction_month_num,
        t.transaction_channel_code,
        t.channel,
        t.is_digital_retail,
        t.is_digital_commercial,
        t.is_wire,
        t.is_settled,
        t.is_pending,
        t.is_returned,
        t.transaction_amount,
        b.division_code,
        b.division_name

    from transactions t
    inner join bridge b on t.account_id = b.account_id

),

aggregated as (

    select

        -- Grain
        transaction_month,
        transaction_year,
        transaction_month_num,
        transaction_channel_code,
        channel,
        division_code,
        division_name,

        -- Channel classification (consistent per channel — safe to carry through)
        is_digital_retail,
        is_digital_commercial,
        is_wire,

        -- Volume
        count(*)                                                    as transaction_count,
        sum(transaction_amount)                                                 as total_volume,
        avg(transaction_amount)                                                 as avg_transaction_amount,
        min(transaction_amount)                                                 as min_transaction_amount,
        max(transaction_amount)                                                 as max_transaction_amount,

        -- Settlement status breakdown
        count(case when is_settled  then 1 end)                     as settled_count,
        count(case when is_pending  then 1 end)                     as pending_count,
        count(case when is_returned then 1 end)                     as returned_count,

        -- Settlement rates
        -- Cast to decimal to avoid integer division returning 0
        round(
            count(case when is_settled  then 1 end) / cast(count(*) as decimal(10, 4)) * 100,
            2
        )                                                           as settled_pct,
        round(
            count(case when is_pending  then 1 end) / cast(count(*) as decimal(10, 4)) * 100,
            2
        )                                                           as pending_pct,
        round(
            count(case when is_returned then 1 end) / cast(count(*) as decimal(10, 4)) * 100,
            2
        )                                                           as returned_pct

    from joined
    group by
        transaction_month,
        transaction_year,
        transaction_month_num,
        transaction_channel_code,
        channel,
        division_code,
        division_name,
        is_digital_retail,
        is_digital_commercial,
        is_wire

)

select * from aggregated