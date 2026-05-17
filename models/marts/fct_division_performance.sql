{{
    config(
        materialized = 'table',
        file_format  = 'delta'
    )
}}

-- Grain: division × month
-- One row per division per calendar month. A clean rollup of
-- gold_branch_performance to the division level — avoids re-aggregating
-- from raw intermediate models to keep division and branch numbers consistent.
-- The semantic layer applies division-specific metric definitions on top of
-- this model (e.g. digital adoption rate, high-risk threshold, fee revenue
-- composition) without changing the underlying data.

with branch_perf as (

    -- Rolling up from gold_branch_performance ensures division totals
    -- always reconcile with branch totals in Tableau.
    select * from {{ ref('fct_branch_performance') }}

),

-- ── Month-over-month window for delta calculations ─────────────────────────
-- LAG is computed here rather than in Tableau so the semantic layer
-- can expose mom_fee_revenue_delta as a first-class metric.
aggregated as (

    select

        -- Grain
        report_month,
        report_year,
        report_month_num,
        division_code,
        division_name,

        -- ── Account metrics ────────────────────────────────────────────────
        sum(accounts_opened)                                        as accounts_opened,
        sum(active_account_count)                                   as active_account_count,
        sum(frozen_account_count)                                   as frozen_account_count,
        sum(total_balance)                                          as total_balance,
        avg(avg_account_balance)                                    as avg_account_balance,

        -- ── Customer metrics ───────────────────────────────────────────────
        sum(total_customer_count)                                   as total_customer_count,
        sum(active_customer_count)                                   as active_customer_count,
        sum(dormant_customer_count)                                 as dormant_customer_count,

        -- ── Transaction metrics ────────────────────────────────────────────
        sum(total_transaction_count)                                as total_transaction_count,
        sum(total_transaction_volume)                               as total_transaction_volume,
        avg(avg_transaction_amount)                                 as avg_transaction_amount,
        sum(settled_count)                                          as settled_count,
        sum(pending_count)                                          as pending_count,
        sum(returned_count)                                         as returned_count,

        -- Digital counts (both definitions, semantic layer picks the right one)
        sum(digital_count_retail_def)                               as digital_count_retail_def,
        sum(digital_count_commercial_def)                           as digital_count_commercial_def,

        -- Digital adoption rates — recomputed at division level from raw counts
        -- rather than averaging branch percentages (avoids weighting errors)
        round(
            sum(digital_count_retail_def)
            / nullif(cast(sum(total_transaction_count) as decimal(10,4)), 0) * 100,
            2
        )                                                           as digital_pct_retail_def,
        round(
            sum(digital_count_commercial_def)
            / nullif(cast(sum(total_transaction_count) as decimal(10,4)), 0) * 100,
            2
        )                                                           as digital_pct_commercial_def,

        -- ── Fee metrics ────────────────────────────────────────────────────
        sum(total_fee_count)                                        as total_fee_count,
        sum(total_fee_revenue)                                      as total_fee_revenue,

        -- Retail fee types
        sum(maintenance_fee_revenue)                                as maintenance_fee_revenue,
        sum(overdraft_fee_revenue)                                  as overdraft_fee_revenue,
        sum(atm_fee_revenue)                                        as atm_fee_revenue,
        sum(pos_interchange_revenue)                                as pos_interchange_revenue,

        -- Commercial fee types
        sum(trade_finance_revenue)                                  as trade_finance_revenue,
        sum(wire_fee_revenue)                                       as wire_fee_revenue,
        sum(loan_interest_revenue)                                  as loan_interest_revenue,
        sum(service_charge_revenue)                                 as service_charge_revenue,

        -- Branch count — useful for Tableau tooltips and averages
        count(distinct branch_code)                                 as branch_count

    from branch_perf
    group by
        report_month,
        report_year,
        report_month_num,
        division_code,
        division_name

),

-- ── Month-over-month deltas ────────────────────────────────────────────────
with_mom as (

    select

        *,

        -- Transaction volume delta
        total_transaction_volume - lag(total_transaction_volume)
            over (
                partition by division_code
                order by report_month
            )                                                       as mom_transaction_volume_delta,

        -- Fee revenue delta
        total_fee_revenue - lag(total_fee_revenue)
            over (
                partition by division_code
                order by report_month
            )                                                       as mom_fee_revenue_delta,

        -- Active account delta (net account growth month-over-month)
        active_account_count - lag(active_account_count)
            over (
                partition by division_code
                order by report_month
            )                                                       as mom_active_account_delta,

        -- Active customer delta
        active_customer_count - lag(active_customer_count)
            over (
                partition by division_code
                order by report_month
            )                                                       as mom_active_customer_delta,

        -- Total balance delta
        total_balance - lag(total_balance)
            over (
                partition by division_code
                order by report_month
            )                                                       as mom_balance_delta,

        -- Month-over-month % change in fee revenue
        -- nullif guards against division-by-zero in months with zero prior revenue
        round(
            (total_fee_revenue - lag(total_fee_revenue)
                over (partition by division_code order by report_month))
            / nullif(lag(total_fee_revenue)
                over (partition by division_code order by report_month), 0) * 100,
            2
        )                                                           as mom_fee_revenue_pct_change

    from aggregated

)

select * from with_mom