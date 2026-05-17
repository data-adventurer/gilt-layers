{{ config(materialized='table') }}

with source as (

    select * from {{ ref('branches') }}

),

renamed as (

    select
        br_cd as branch_code
        , br_nm as branch_name
        , rgn_cd as region_code
        , d_cd as division_code

    from source

)

select * from renamed
