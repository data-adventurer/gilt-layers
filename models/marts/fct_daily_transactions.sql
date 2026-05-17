{{
    config(
        materialized = 'table',
        file_format  = 'delta'
    )
}}

-- Grain: transaction_date × division
-- One row per calendar day per division. Every day in the Jan 2023–Dec 2024
-- window has at least one transaction (no gap-filling needed based on source data).
-- Feeds the transaction trend line chart and channel breakdown in Tableau.
-- Settled/pending/returned volumes are kept separate so Commercial Banking
-- can include pending transactions in their volume metric via the semantic layer.

with transactions as (

    select * from {{ ref('int_finance__transactions_decoded') }}

),

bridge as (

    select
        account_id,
        division_code,
        division_name
    from {{ ref('int_finance__acct_cust_bridge') }}

),

joined as (

    select
        t.transaction_date,
        t.transaction_month,
        t.transaction_year,
        t.transaction_month_num,
        t.transaction_day_of_week,
        t.transaction_amount,
        t.signed_amount,
        t.transaction_type_code,
        t.transaction_channel_code,
        t.is_settled,
        t.is_pending,
        t.is_returned,
        t.is_digital_retail,
        t.is_digital_commercial,
        t.is_wire,
        t.settlement_lag_days,
        b.division_code,
        b.division_name

    from transactions t
    inner join bridge b on t.account_id = b.account_id

),

aggregated as (

    select

        -- Grain
        transaction_date,
        transaction_month,
        transaction_year,
        transaction_month_num,
        transaction_day_of_week,
        division_code,
        division_name,

        -- ── Volume ────────────────────────────────────────────────────────
        count(*)                                                    as total_transaction_count,
        sum(transaction_amount)                                     as total_volume,
        avg(transaction_amount)                                     as avg_transaction_amount,

        -- ── Settlement status breakdown ───────────────────────────────────
        -- Retail Banking volume = settled only.
        -- Commercial Banking volume = settled + pending (wire settlement lag).
        -- Both are surfaced here; the semantic layer picks the right one.
        count(case when is_settled  then 1 end)                     as settled_count,
        count(case when is_pending  then 1 end)                     as pending_count,
        count(case when is_returned then 1 end)                     as returned_count,
        sum(case when is_settled  then transaction_amount else 0 end)           as settled_volume,
        sum(case when is_pending  then transaction_amount else 0 end)           as pending_volume,
        sum(case when is_returned then transaction_amount else 0 end)           as returned_volume,

        -- ── Debit / credit split ──────────────────────────────────────────
        sum(case when signed_amount < 0 then transaction_amount else 0 end)     as total_debit_volume,
        sum(case when signed_amount > 0 then transaction_amount else 0 end)     as total_credit_volume,
        sum(signed_amount)                                          as net_flow,

        -- ── Channel breakdown ─────────────────────────────────────────────
        count(case when transaction_channel_code = 'POS'  then 1 end)           as pos_count,
        count(case when transaction_channel_code = 'ONL'  then 1 end)           as online_count,
        count(case when transaction_channel_code = 'MOB'  then 1 end)           as mobile_count,
        count(case when transaction_channel_code = 'BR'   then 1 end)           as branch_count,
        count(case when transaction_channel_code = 'ATM'  then 1 end)           as atm_count,
        count(case when transaction_channel_code = 'WIRE' then 1 end)           as wire_count,

        -- ── Transaction type breakdown ────────────────────────────────────
        count(case when transaction_type_code = 'POS' then 1 end)   as type_pos_count,
        count(case when transaction_type_code = 'DEP' then 1 end)   as type_deposit_count,
        count(case when transaction_type_code = 'TFR' then 1 end)   as type_transfer_count,
        count(case when transaction_type_code = 'WDR' then 1 end)   as type_withdrawal_count,
        count(case when transaction_type_code = 'FEE' then 1 end)   as type_fee_count,
        count(case when transaction_type_code = 'INT' then 1 end)   as type_interest_count,
        count(case when transaction_type_code = 'ATM' then 1 end)   as type_atm_count,

        -- ── Digital adoption counts ───────────────────────────────────────
        -- Separate retail and commercial counts surface here for the semantic layer.
        count(case when is_digital_retail      then 1 end)          as digital_count_retail_def,
        count(case when is_digital_commercial  then 1 end)          as digital_count_commercial_def,

        -- ── Settlement quality ────────────────────────────────────────────
        avg(settlement_lag_days)                                    as avg_settlement_lag_days,
        max(settlement_lag_days)                                    as max_settlement_lag_days

    from joined
    group by
        transaction_date,
        transaction_month,
        transaction_year,
        transaction_month_num,
        transaction_day_of_week,
        division_code,
        division_name

)

select * from aggregated