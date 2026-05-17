{{ config(materialized='table') }}

with source as (

    select * from {{ source('raw', 't_l') }}

),

renamed as (

    select
        t_id::string as transaction_id
        , a_id::string as account_id
        , t_dt as transaction_date
        , t_post_dt as posting_date
        , t_amt as transaction_amount
        , t_dr_cr as transaction_indicator
        , t_typ as transaction_type_code
        , t_ch as transaction_channel_code
        , t_st as settlement_status

    from source

)

select * from renamed
