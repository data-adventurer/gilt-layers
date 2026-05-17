{{
    config(
        materialized = 'table',
        file_format  = 'delta'
    )
}}

-- Grain: branch × month
-- One row per branch per calendar month. Covers both the transaction window
-- (Jan 2023–Dec 2024) and pre-existing accounts opened before 2023.
-- All account metrics reflect the account's state at the time of the run —
-- opened/closed counts are based on whether the open/close date falls within
-- each month, allowing Tableau to show net account growth over time.
-- Feeds the branch heatmap and region rollup views in Tableau.

with bridge as (

    select * from {{ ref('int_finance__acct_cust_bridge') }}

),

transactions as (

    select * from {{ ref('int_finance__transactions_decoded') }}

),

fees as (

    select * from {{ ref('int_finance__fees_decoded') }}

),

-- All distinct branch × month combinations that appear in transaction data.
-- Used as the spine to ensure every branch has a row for every month it
-- was active, even if no accounts were opened or closed that month.
date_spine as (

    select distinct
        transaction_month                                           as report_month,
        year(transaction_month)                                     as report_year,
        month(transaction_month)                                    as report_month_num

    from transactions

),

branches_spine as (

    select distinct
        branch_code,
        branch_name,
        region_code,
        region_name,
        division_code,
        division_name

    from bridge

),

spine as (

    select
        d.report_month,
        d.report_year,
        d.report_month_num,
        b.branch_code,
        b.branch_name,
        b.region_code,
        b.region_name,
        b.division_code,
        b.division_name

    from date_spine      d
    cross join branches_spine b

),

-- ── Account metrics per branch per month ──────────────────────────────────
account_metrics as (

    select
        branch_code,
        date_trunc('month', open_date)                              as report_month,

        -- Accounts opened this month
        count(case
            when date_trunc('month', open_date) = date_trunc('month', open_date)
            then 1 end
        )                                                           as accounts_opened,

        -- Active accounts as of the end of the month
        -- An account is active in a month if it was open before that month ended
        -- and either never closed or closed after that month
        count(*)                                                    as active_account_count,
        count(case when is_frozen then 1 end)                       as frozen_account_count,

        -- Balance snapshot (current balance — a point-in-time balance history
        -- would require an additional source table)
        sum(case when is_open then balance else 0 end)              as total_balance,
        avg(case when is_open then balance end)                     as avg_account_balance,

        -- Customer counts (distinct customers with an account at this branch)
        count(distinct customer_id)                                 as total_customer_count,
        count(distinct case when customer_is_active
                            then customer_id end)                   as active_customer_count,
        count(distinct case when customer_is_dormant
                            then customer_id end)                   as dormant_customer_count

    from bridge
    group by branch_code, date_trunc('month', open_date)

),

-- ── Transaction metrics per branch per month ──────────────────────────────
transaction_metrics as (

    select
        b.branch_code,
        t.transaction_month                                         as report_month,

        count(*)                                                    as total_transaction_count,
        sum(t.transaction_amount)                                   as total_transaction_volume,
        avg(t.transaction_amount)                                   as avg_transaction_amount,

        count(case when t.is_settled  then 1 end)                   as settled_count,
        count(case when t.is_pending  then 1 end)                   as pending_count,
        count(case when t.is_returned then 1 end)                   as returned_count,

        -- Digital counts (both definitions carried through)
        count(case when t.is_digital_retail     then 1 end)         as digital_count_retail_def,
        count(case when t.is_digital_commercial then 1 end)         as digital_count_commercial_def,

        -- Digital adoption rates
        round(
            count(case when t.is_digital_retail then 1 end)
            / cast(count(*) as decimal(10,4)) * 100, 2
        )                                                           as digital_pct_retail_def,
        round(
            count(case when t.is_digital_commercial then 1 end)
            / cast(count(*) as decimal(10,4)) * 100, 2
        )                                                           as digital_pct_commercial_def

    from transactions t
    inner join bridge b on t.account_id = b.account_id
    group by b.branch_code, t.transaction_month

),

-- ── Fee metrics per branch per month ─────────────────────────────────────
fee_metrics as (

    select
        b.branch_code,
        f.fee_month                                                 as report_month,

        count(*)                                                    as total_fee_count,
        sum(f.fee_amount)                                           as total_fee_revenue,

        -- Fee revenue by type for the branch heatmap
        sum(case when f.fee_type_code = 'MAINT'     then f.fee_amount else 0 end) as maintenance_fee_revenue,
        sum(case when f.fee_type_code = 'OD'        then f.fee_amount else 0 end) as overdraft_fee_revenue,
        sum(case when f.fee_type_code = 'ATM'       then f.fee_amount else 0 end) as atm_fee_revenue,
        sum(case when f.fee_type_code = 'POS_INTCH' then f.fee_amount else 0 end) as pos_interchange_revenue,
        sum(case when f.fee_type_code = 'TRADE_FIN' then f.fee_amount else 0 end) as trade_finance_revenue,
        sum(case when f.fee_type_code = 'WIRE'      then f.fee_amount else 0 end) as wire_fee_revenue,
        sum(case when f.fee_type_code = 'LN_INT'    then f.fee_amount else 0 end) as loan_interest_revenue,
        sum(case when f.fee_type_code = 'SVC'       then f.fee_amount else 0 end) as service_charge_revenue

    from fees    f
    inner join bridge b on f.account_id = b.account_id
    group by b.branch_code, f.fee_month

),

final as (

    select

        -- Grain
        s.report_month,
        s.report_year,
        s.report_month_num,
        s.branch_code,
        s.branch_name,
        s.region_code,
        s.region_name,
        s.division_code,
        s.division_name,

        -- Account metrics (coalesce — months with no account events still appear)
        coalesce(a.accounts_opened,          0)                     as accounts_opened,
        coalesce(a.active_account_count,     0)                     as active_account_count,
        coalesce(a.frozen_account_count,     0)                     as frozen_account_count,
        coalesce(a.total_balance,            0)                     as total_balance,
        a.avg_account_balance,
        coalesce(a.total_customer_count,     0)                     as total_customer_count,
        coalesce(a.active_customer_count,    0)                     as active_customer_count,
        coalesce(a.dormant_customer_count,   0)                     as dormant_customer_count,

        -- Transaction metrics
        coalesce(t.total_transaction_count,  0)                     as total_transaction_count,
        coalesce(t.total_transaction_volume, 0)                     as total_transaction_volume,
        t.avg_transaction_amount,
        coalesce(t.settled_count,            0)                     as settled_count,
        coalesce(t.pending_count,            0)                     as pending_count,
        coalesce(t.returned_count,           0)                     as returned_count,
        coalesce(t.digital_count_retail_def, 0)                     as digital_count_retail_def,
        coalesce(t.digital_count_commercial_def, 0)                 as digital_count_commercial_def,
        coalesce(t.digital_pct_retail_def,   0)                     as digital_pct_retail_def,
        coalesce(t.digital_pct_commercial_def, 0)                   as digital_pct_commercial_def,

        -- Fee metrics
        coalesce(f.total_fee_count,          0)                     as total_fee_count,
        coalesce(f.total_fee_revenue,        0)                     as total_fee_revenue,
        coalesce(f.maintenance_fee_revenue,  0)                     as maintenance_fee_revenue,
        coalesce(f.overdraft_fee_revenue,    0)                     as overdraft_fee_revenue,
        coalesce(f.atm_fee_revenue,          0)                     as atm_fee_revenue,
        coalesce(f.pos_interchange_revenue,  0)                     as pos_interchange_revenue,
        coalesce(f.trade_finance_revenue,    0)                     as trade_finance_revenue,
        coalesce(f.wire_fee_revenue,         0)                     as wire_fee_revenue,
        coalesce(f.loan_interest_revenue,    0)                     as loan_interest_revenue,
        coalesce(f.service_charge_revenue,   0)                     as service_charge_revenue

    from spine               s
    left join account_metrics     a on s.branch_code = a.branch_code
                                   and s.report_month = a.report_month
    left join transaction_metrics t on s.branch_code = t.branch_code
                                   and s.report_month = t.report_month
    left join fee_metrics         f on s.branch_code = f.branch_code
                                   and s.report_month = f.report_month

)

select * from final