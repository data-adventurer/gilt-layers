{{ config(materialized='table') }}

with source as (

    select * from {{ source('raw', 'b_m') }}

),

renamed as (

    select
        br_cd as branch_code
        , br_nm as branch_name
        , rgn_cd as region
        , d_cd as division

    from source

)

select * from renamed
