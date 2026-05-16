{{ config(materialized='table') }}

with source as (

    select * from {{ source('raw', 'a_m') }}

),

renamed as (

    select
        a_id::string as account_id
        , c_id::string as customer_id
        , a_typ as account_type_code
        , a_opn_dt as open_date
        , a_cls_dt as close_date
        , a_st as account_status_code
        , a_bal as balance
        , br_cd as branch_code

    from source

)

select * from renamed
