{{ config(materialized='table') }}

with source as (

    select * from {{ ref('divisions') }}

),

renamed as (

    select
        d_cd as division_code
        , d_nm as division_name

    from source

)

select * from renamed
