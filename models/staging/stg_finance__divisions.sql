{{ config(materialized='table') }}

with source as (

    select * from {{ source('raw', 'd_m') }}

),

renamed as (

    select
        d_cd as division_code
        , d_nm as division_name

    from source

)

select * from renamed
