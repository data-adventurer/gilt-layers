{{
    config(
        materialized = 'table',
        file_format  = 'delta'
    )
}}

with fees as (

    select * from {{ ref('stg_finance__fees') }}

),

-- Used purely to test t_id linkage — not joined for column expansion.
-- 1,015 fee records intentionally have no matching transaction (standalone
-- periodic fees). This left join surfaces them via is_standalone_fee.
transactions as (

    select transaction_id from {{ ref('stg_finance__transactions') }}

),

decoded as (

    select

        f.fee_id,
        f.account_id,
        f.transaction_id,

        f.fee_type_code,
        f.fee_amount,
        f.fee_date,

        case f.fee_type_code
            when 'MAINT'     then 'Maintenance'
            when 'OD'        then 'Overdraft'
            when 'ATM'       then 'ATM Surcharge'
            when 'POS_INTCH' then 'POS Interchange'
            when 'TRADE_FIN' then 'Trade Finance'
            when 'WIRE'      then 'Wire Transfer'
            when 'LN_INT'    then 'Loan Interest'
            when 'SVC'       then 'Service Charge'
        end                                                         as fee_type,

        -- Division classification by fee type
        f.fee_type_code in ('MAINT', 'OD', 'ATM', 'POS_INTCH')    as is_retail_fee,
        f.fee_type_code in ('TRADE_FIN', 'WIRE', 'LN_INT', 'SVC')  as is_commercial_fee,

        -- Standalone flag: fee not linked to any transaction record.
        -- These are valid revenue records — expected behaviour, not data quality issues.
        t.transaction_id is null                                    as is_standalone_fee,

        -- Date parts for monthly aggregation in gold_fee_revenue
        date_trunc('month', f.fee_date)                             as fee_month,
        year(f.fee_date)                                            as fee_year,
        month(f.fee_date)                                           as fee_month_num

    from fees f
    left join transactions t
        on f.transaction_id = t.transaction_id

)

select * from decoded