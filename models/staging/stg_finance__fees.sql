{{ config(materialized='table') }}

with source as (

    select * from {{ source('raw', 'f_l') }}

),

renamed as (

    select
        f_id::string as fee_id
        , a_id::string as account_id
        , t_id::string as transaction_id
        , f_typ as fee_type_code
        , f_amt as fee_amount
        , f_dt as fee_date

    from source

)

select * from renamed
