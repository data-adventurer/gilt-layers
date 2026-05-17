{{
    config(
        materialized = 'table',
        file_format  = 'delta'
    )
}}

-- Grain: account
-- One row per account. Extends int_finance__account_customer_bridge with
-- aggregated transaction and fee stats. Gold models join to the bridge
-- rather than re-doing multi-hop joins, so the CTEs here are pre-aggregations
-- only. All bridge columns are carried through for Tableau filtering.

with bridge as (

    select * from {{ ref('int_finance__acct_cust_bridge') }}

),

transaction_stats as (

    select
        account_id,

        count(*)                                                    as total_transaction_count,
        count(case when is_settled  then 1 end)                     as settled_transaction_count,
        count(case when is_pending  then 1 end)                     as pending_transaction_count,
        count(case when is_returned then 1 end)                     as returned_transaction_count,

        -- Gross debit and credit volumes (always positive)
        sum(case when transaction_indicator = 'D' then transaction_amount
                 else 0                           end)              as total_debit_volume,
        sum(case when transaction_indicator = 'C' then transaction_amount
                 else 0                           end)              as total_credit_volume,

        -- Net flow: positive = net inflow, negative = net outflow
        sum(signed_amount)                                          as net_flow,

        avg(transaction_amount)                                     as avg_transaction_amount,
        max(transaction_date)                                       as last_transaction_date,
        min(transaction_date)                                       as first_transaction_date

    from {{ ref('int_finance__transactions_decoded') }}
    group by account_id

),

fee_stats as (

    select
        account_id,
        count(*)                                                    as total_fee_count,
        sum(fee_amount)                                             as total_fees_charged,
        max(fee_date)                                               as last_fee_date

    from {{ ref('int_finance__fees_decoded') }}
    group by account_id

),

final as (

    select

        -- ── All bridge columns ─────────────────────────────────────────────
        -- Full account, customer, branch, and division context from the bridge.
        -- Tableau can filter by any of these without additional joins.
        b.*,

        -- ── Transaction stats ──────────────────────────────────────────────
        -- COALESCE to 0 for accounts with no transactions on record.
        coalesce(t.total_transaction_count,      0)                 as total_transaction_count,
        coalesce(t.settled_transaction_count,    0)                 as settled_transaction_count,
        coalesce(t.pending_transaction_count,    0)                 as pending_transaction_count,
        coalesce(t.returned_transaction_count,   0)                 as returned_transaction_count,
        coalesce(t.total_debit_volume,           0)                 as total_debit_volume,
        coalesce(t.total_credit_volume,          0)                 as total_credit_volume,
        coalesce(t.net_flow,                     0)                 as net_flow,
        t.avg_transaction_amount,
        t.last_transaction_date,
        t.first_transaction_date,

        -- Days since last transaction — null-safe for accounts with no history
        datediff(
            current_date(), t.last_transaction_date
        )                                                           as days_since_last_transaction,

        -- ── Fee stats ──────────────────────────────────────────────────────
        coalesce(f.total_fee_count,              0)                 as total_fee_count,
        coalesce(f.total_fees_charged,           0)                 as total_fees_charged,
        f.last_fee_date,

        -- ── Derived flags ──────────────────────────────────────────────────
        -- Dormancy: no transaction in the last 90 days.
        -- Null-safe: accounts with no transaction history are treated as dormant.
        coalesce(
            datediff(current_date(), t.last_transaction_date) > 90,
            true
        )                                                           as is_dormant_account

    from bridge          b
    left join transaction_stats t on b.account_id = t.account_id
    left join fee_stats         f on b.account_id = f.account_id

)

select * from final