{{ config(materialized='table') }}

with source as (

    select * from {{ source('raw', 'c_m') }}

),

renamed as (

    select
        c_id::string as customer_id
        , c_extrn_ref as crm_reference
        , c_dob as date_of_birth
        , c_onb_dt as onboard_date
        , c_seg as segment_code
        , c_st_cd as customer_status_code
        , c_rsk_sc as risk_score
        , c_kyc_flg::string as know_your_cust_flag

    from source

)

select * from renamed
