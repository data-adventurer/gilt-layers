{{
    config(
        materialized = 'table',
        file_format  = 'delta'
    )
}}

-- Grain: customer
-- One row per customer. Aggregates account portfolio, transaction behaviour,
-- fee exposure, and activity recency for each customer. Transaction lookback
-- windows (30/90/365 days) are computed relative to the current date so the
-- model stays accurate on each scheduled run without hardcoded dates.
-- Division-specific flags are resolved here for the semantic layer — a customer
-- is classified by their segment, not by the division of any single account.

with customers as (

    select * from {{ ref('int_finance__customers_decoded') }}

),

-- Pull from the bridge rather than re-joining accounts → customers.
-- The bridge already carries all account and division context.
bridge as (

    select * from {{ ref('int_finance__acct_cust_bridge') }}

),

transactions as (

    select * from {{ ref('int_finance__transactions_decoded') }}

),

fees as (

    select * from {{ ref('int_finance__fees_decoded') }}

),

-- ── Account portfolio per customer ────────────────────────────────────────
account_stats as (

    select
        customer_id,

        count(*)                                                    as total_account_count,
        count(case when is_open               then 1 end)           as open_account_count,
        count(case when account_is_closed     then 1 end)           as closed_account_count,
        count(case when is_frozen             then 1 end)           as frozen_account_count,

        -- Account type breakdown
        count(case when account_type_code = 'SAV'     then 1 end)   as savings_account_count,
        count(case when account_type_code = 'CHK'     then 1 end)   as checking_account_count,
        count(case when account_type_code = 'CC'      then 1 end)   as credit_card_count,
        count(case when account_type_code = 'LN'      then 1 end)   as retail_loan_count,
        count(case when account_type_code = 'COM_CHK' then 1 end)   as commercial_checking_count,
        count(case when account_type_code = 'COM_LN'  then 1 end)   as commercial_loan_count,

        -- Balance aggregates (across all open accounts)
        sum(case when is_open then balance else 0 end)              as total_balance,
        avg(case when is_open then balance end)                     as avg_account_balance,
        max(case when is_open then balance end)                     as max_account_balance,

        -- Division context (a customer's accounts may span divisions in theory,
        -- but segment drives the semantic layer classification, not account division)
        max(division_code)                                          as primary_division_code,
        max(division_name)                                          as primary_division_name

    from bridge
    group by customer_id

),

-- ── Transactions linked to each customer via account ─────────────────────
customer_transactions as (

    select
        b.customer_id,
        t.transaction_id,
        t.transaction_date,
        t.transaction_amount,
        t.signed_amount,
        t.transaction_channel_code,
        t.is_settled,
        t.is_returned,
        t.is_digital_retail,
        t.is_digital_commercial

    from transactions t
    inner join bridge b on t.account_id = b.account_id

),

transaction_stats as (

    select
        customer_id,

        -- All-time counts and volume
        count(*)                                                    as total_transaction_count,
        count(case when is_settled  then 1 end)                     as settled_transaction_count,
        count(case when is_returned then 1 end)                     as returned_transaction_count,
        sum(transaction_amount)                                                 as total_transaction_volume,
        avg(transaction_amount)                                                 as avg_transaction_amount,

        -- Recency windows (relative to current date for accuracy on each run)
        count(
            case when transaction_date >= date_add(current_date(), -30)
                 then 1 end
        )                                                           as txn_count_30d,
        count(
            case when transaction_date >= date_add(current_date(), -90)
                 then 1 end
        )                                                           as txn_count_90d,
        count(
            case when transaction_date >= date_add(current_date(), -365)
                 then 1 end
        )                                                           as txn_count_365d,

        sum(
            case when transaction_date >= date_add(current_date(), -30)
                 then transaction_amount else 0 end
        )                                                           as txn_volume_30d,
        sum(
            case when transaction_date >= date_add(current_date(), -90)
                 then transaction_amount else 0 end
        )                                                           as txn_volume_90d,
        sum(
            case when transaction_date >= date_add(current_date(), -365)
                 then transaction_amount else 0 end
        )                                                           as txn_volume_365d,

        -- Recency
        max(transaction_date)                                       as last_transaction_date,
        datediff(
            current_date(), max(transaction_date)
        )                                                           as days_since_last_transaction,

        -- Preferred channel: the channel used most frequently by this customer
        -- Resolved using mode — in case of a tie, the first alphabetically is returned
        mode(transaction_channel_code)                              as preferred_channel_code,

        -- Digital ratio (retail definition — used by semantic layer for retail customers)
        round(
            count(case when is_digital_retail then 1 end)
            / cast(count(*) as decimal(10, 4)) * 100,
            2
        )                                                           as digital_ratio_retail,

        -- Digital ratio (commercial definition — includes WIRE)
        round(
            count(case when is_digital_commercial then 1 end)
            / cast(count(*) as decimal(10, 4)) * 100,
            2
        )                                                           as digital_ratio_commercial

    from customer_transactions
    group by customer_id

),

-- ── Fee exposure per customer ─────────────────────────────────────────────
customer_fees as (

    select
        b.customer_id,
        f.fee_amount,
        f.is_retail_fee,
        f.is_commercial_fee

    from fees    f
    inner join bridge b on f.account_id = b.account_id

),

fee_stats as (

    select
        customer_id,
        count(*)                                                    as total_fee_count,
        sum(fee_amount)                                             as total_fees_charged,
        avg(fee_amount)                                             as avg_fee_amount,
        sum(case when is_retail_fee     then fee_amount else 0 end) as retail_fees_charged,
        sum(case when is_commercial_fee then fee_amount else 0 end) as commercial_fees_charged

    from customer_fees
    group by customer_id

),

-- ── Final assembly ────────────────────────────────────────────────────────
final as (

    select

        -- ── Customer identity ──────────────────────────────────────────────
        c.customer_id,
        c.crm_reference,
        c.segment_code,
        c.customer_segment,
        c.customer_status_code,
        c.customer_status,
        c.date_of_birth,
        c.onboard_date,
        c.customer_age,
        c.age_bucket,
        c.tenure_days,
        c.tenure_months,
        c.risk_score,
        c.know_your_cust_flag,

        -- Division classification (driven by customer segment, not account division)
        c.is_retail_customer,
        c.is_commercial_customer,

        -- Status flags
        c.is_active,
        c.is_dormant,
        c.is_closed,

        -- Division-specific risk and new-customer flags
        c.is_high_risk_retail,
        c.is_high_risk_commercial,
        c.is_new_retail_customer,
        c.is_new_commercial_customer,

        -- ── Account portfolio ──────────────────────────────────────────────
        coalesce(a.total_account_count,       0)                    as total_account_count,
        coalesce(a.open_account_count,        0)                    as open_account_count,
        coalesce(a.closed_account_count,      0)                    as closed_account_count,
        coalesce(a.frozen_account_count,      0)                    as frozen_account_count,
        coalesce(a.savings_account_count,     0)                    as savings_account_count,
        coalesce(a.checking_account_count,    0)                    as checking_account_count,
        coalesce(a.credit_card_count,         0)                    as credit_card_count,
        coalesce(a.retail_loan_count,         0)                    as retail_loan_count,
        coalesce(a.commercial_checking_count, 0)                    as commercial_checking_count,
        coalesce(a.commercial_loan_count,     0)                    as commercial_loan_count,
        coalesce(a.total_balance,             0)                    as total_balance,
        a.avg_account_balance,
        a.max_account_balance,
        a.primary_division_code,
        a.primary_division_name,

        -- ── Transaction behaviour ──────────────────────────────────────────
        coalesce(t.total_transaction_count,   0)                    as total_transaction_count,
        coalesce(t.settled_transaction_count, 0)                    as settled_transaction_count,
        coalesce(t.returned_transaction_count,0)                    as returned_transaction_count,
        coalesce(t.total_transaction_volume,  0)                    as total_transaction_volume,
        t.avg_transaction_amount,
        coalesce(t.txn_count_30d,             0)                    as txn_count_30d,
        coalesce(t.txn_count_90d,             0)                    as txn_count_90d,
        coalesce(t.txn_count_365d,            0)                    as txn_count_365d,
        coalesce(t.txn_volume_30d,            0)                    as txn_volume_30d,
        coalesce(t.txn_volume_90d,            0)                    as txn_volume_90d,
        coalesce(t.txn_volume_365d,           0)                    as txn_volume_365d,
        t.last_transaction_date,
        t.days_since_last_transaction,
        t.preferred_channel_code,
        t.digital_ratio_retail,
        t.digital_ratio_commercial,

        -- ── Fee exposure ───────────────────────────────────────────────────
        coalesce(f.total_fee_count,           0)                    as total_fee_count,
        coalesce(f.total_fees_charged,        0)                    as total_fees_charged,
        f.avg_fee_amount,
        coalesce(f.retail_fees_charged,       0)                    as retail_fees_charged,
        coalesce(f.commercial_fees_charged,   0)                    as commercial_fees_charged,

        -- ── Derived flags ──────────────────────────────────────────────────
        -- A customer is behaviourally dormant if they have had no transaction
        -- in the last 90 days regardless of their c_st_cd status code.
        coalesce(
            t.days_since_last_transaction > 90,
            true
        )                                                           as is_behaviourally_dormant

    from customers          c
    left join account_stats a on c.customer_id = a.customer_id
    left join transaction_stats t on c.customer_id = t.customer_id
    left join fee_stats      f on c.customer_id = f.customer_id

)

select * from final