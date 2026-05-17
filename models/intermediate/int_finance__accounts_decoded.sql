{{
    config(
        materialized = 'table',
        file_format  = 'delta'
    )
}}

with source as (

    select * from {{ ref('stg_finance__accounts') }}

),

decoded as (

    select

        account_id,
        customer_id,
        branch_code,

        account_type_code,
        account_status_code,

        open_date,
        close_date,
        balance,

        -- Decoded human-readable labels
        case account_type_code
            when 'SAV'     then 'Savings'
            when 'CHK'     then 'Checking'
            when 'CC'      then 'Credit Card'
            when 'LN'      then 'Retail Loan'
            when 'COM_CHK' then 'Commercial Checking'
            when 'COM_LN'  then 'Commercial Loan'
        end                                                         as account_type,

        case account_status_code
            when 'O' then 'Open'
            when 'C' then 'Closed'
            when 'F' then 'Frozen'
        end                                                         as account_status,

        -- Division classification
        account_type_code in ('SAV', 'CHK', 'CC', 'LN')           as is_retail_product,
        account_type_code in ('COM_CHK', 'COM_LN')                 as is_commercial_product,

        -- Status flags
        account_status_code = 'O'                                   as is_open,
        account_status_code = 'C'                                   as is_closed,
        account_status_code = 'F'                                   as is_frozen,

        -- Account age
        datediff(current_date(), open_date)                         as account_age_days,
        floor(datediff(current_date(), open_date) / 30.44)          as account_age_months,

        -- Balance banding for segmentation
        case
            when balance < 0                        then 'Negative'
            when balance between 0     and 9999     then 'Low'
            when balance between 10000 and 49999    then 'Mid'
            else                                         'High'
        end                                                         as balance_band

    from source

)

select * from decoded