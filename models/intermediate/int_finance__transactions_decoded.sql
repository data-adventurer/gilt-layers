{{
    config(
        materialized = 'table',
        file_format  = 'delta'
    )
}}

with source as (

    select * from {{ ref('stg_finance__transactions') }}

),

decoded as (

    select

        transaction_id,
        account_id,

        transaction_date,
        posting_date,

        transaction_amount,
        transaction_indicator,
        transaction_type_code,
        transaction_channel_code,
        settlement_status,

        -- Decoded labels
        case transaction_type_code
            when 'POS' then 'Point of Sale'
            when 'DEP' then 'Deposit'
            when 'TFR' then 'Transfer'
            when 'WDR' then 'Withdrawal'
            when 'FEE' then 'Fee'
            when 'INT' then 'Interest'
            when 'ATM' then 'ATM'
        end                                                         as transaction_type,

        case transaction_channel_code
            when 'POS'  then 'Point of Sale'
            when 'ONL'  then 'Online'
            when 'MOB'  then 'Mobile'
            when 'BR'   then 'Branch'
            when 'ATM'  then 'ATM'
            when 'WIRE' then 'Wire Transfer'
        end                                                         as channel,

        case settlement_status
            when 'S' then 'Settled'
            when 'P' then 'Pending'
            when 'R' then 'Returned'
        end                                                         as transaction_status,

        -- Signed amount: D (debit) = money leaving account, C (credit) = money arriving
        case transaction_indicator
            when 'D' then -transaction_amount
            when 'C' then  transaction_amount
        end                                                         as signed_amount,

        -- Status flags
        settlement_status = 'S'                               as is_settled,
        settlement_status = 'P'                               as is_pending,
        settlement_status = 'R'                               as is_returned,

        -- Channel classification
        -- Retail digital: MOB + ONL only.
        -- Commercial digital: MOB + ONL + WIRE (wire is included per semantic layer definition).
        -- Both flags surfaced here; the semantic layer selects the correct one per division.
        transaction_channel_code in ('MOB', 'ONL')                              as is_digital_retail,
        transaction_channel_code in ('MOB', 'ONL', 'WIRE')                      as is_digital_commercial,
        transaction_channel_code = 'WIRE'                                       as is_wire,

        -- Settlement lag: days between transaction initiation and posting
        datediff(posting_date, transaction_date)                    as settlement_lag_days,

        -- Date parts for monthly and yearly aggregation in gold models
        date_trunc('month', transaction_date)                       as transaction_month,
        year(transaction_date)                                      as transaction_year,
        month(transaction_date)                                     as transaction_month_num,
        dayofweek(transaction_date)                                 as transaction_day_of_week

    from source

)

select * from decoded