# gilt-layers

A dbt Cloud project transforming fake finance data through the medallion architecture (bronze → silver → gold) on Databricks, with a semantic layer on top. Built as a sandbox for exploring dbt + Claude Code via the dbt MCP server.

---

## Overview

**gilt-layers** models a fictional bank with two divisions — Retail Banking and Commercial Banking — across 12 branches, 200 customers, and 443 accounts. The project takes raw transactional data through a full medallion pipeline and surfaces a semantic layer designed for a Tableau dashboard aimed at department heads and non-technical stakeholders.

The project is intentionally built as a learning and exploration environment. All data is fake and generated for demonstration purposes.

---

## Tech stack

| Layer | Tool |
|---|---|
| Data warehouse | Databricks (Delta Lake) |
| Transformation | dbt Cloud |
| Semantic layer | dbt Cloud semantic layer |
| BI / dashboarding | Tableau |
| AI integration | Claude Code + dbt MCP server |

---

## Data model

The source data covers six entities across two banking divisions and two years of transaction history (January 2023 – December 2024).

```
accounts ──→ customers
    │
    └──→ branches ──→ divisions
    │
transactions ──→ fees
```

### Medallion layers

```
seeds/                branches, divisions (static reference data, dbt-managed)
│
staging (bronze)      stg_finance__*
│                     Raw ingestion — types cast, columns renamed, no business logic
│
intermediate (silver) int_finance__*
│                     Decoded labels, derived columns, division-specific flags,
│                     account-customer-branch-division bridge
│
marts (gold)          fct_*
                      Aggregated, Tableau-ready facts at various grains
```

### Mart models

| Model | Grain | Purpose |
|---|---|---|
| `fct_account_summary` | Account | Current state + lifetime transaction and fee totals |
| `fct_customer_360` | Customer | Portfolio, behavioural windows (30/90/365d), fee exposure |
| `fct_fees_revenue` | Fee type × month × division | Fee revenue breakdown for waterfall chart |
| `fct_channel_agg` | Channel × month × division | Channel distribution and digital adoption |
| `fct_daily_transactions` | Date × division | Transaction volume trend line |
| `fct_branch_performance` | Branch × month | Branch heatmap and regional rollup |
| `fct_division_performance` | Division × month | Division scorecard with month-over-month deltas |

### Semantic layer

The semantic layer sits on top of the gold models and handles metric definitions that differ between Retail Banking and Commercial Banking — for example, `fee_revenue`, `digital_adoption_rate`, `high_risk_customer_count`, and `transaction_volume` are all defined differently per division. This means both divisions can query the same metric name and receive the numbers that are right for their business.

> ⚠️ Semantic layer configuration will be documented in a dedicated section as the project develops.

---

## Project structure

```
gilt-layers/
├── seeds/
│   ├── branches.csv
│   ├── divisions.csv
│   └── seeds.yml
├── models/
│   ├── staging/
│   │   ├── sources.yml
│   │   ├── stg_finance__accounts.sql
│   │   ├── stg_finance__customers.sql
│   │   ├── stg_finance__fees.sql
│   │   └── stg_finance__transactions.sql
│   ├── intermediate/
│   │   ├── _int_schema.yml
│   │   ├── int_finance__accounts_decoded.sql
│   │   ├── int_finance__customers_decoded.sql
│   │   ├── int_finance__fees_decoded.sql
│   │   ├── int_finance__transactions_decoded.sql
│   │   └── int_finance__acct_cust_bridge.sql
│   └── marts/
│       ├── _mrt_schema.yml
│       ├── fct_account_summary.sql
│       ├── fct_customer_360.sql
│       ├── fct_fees_revenue.sql
│       ├── fct_channel_agg.sql
│       ├── fct_daily_transactions.sql
│       ├── fct_branch_performance.sql
│       └── fct_division_performance.sql
├── dbt_project.yml
└── README.md
```

---

## Claude Code + dbt MCP server

One of the goals of this project is to demonstrate how Claude Code can interact with a dbt project via the dbt MCP server — asking questions about models, lineage, and metrics in natural language.

> ⚠️ Setup instructions for Claude Code and the dbt MCP server will be added here once that phase of the project is complete.

---

## Roadmap

- [ ] Semantic layer configuration and metric definitions
- [ ] Tableau dashboard
- [ ] Claude Code + dbt MCP server setup guide
- [ ] Additional mock data: rate reference table, loan performance table

---

## Contributing

This project is primarily a personal learning sandbox, but if you spot something wrong or have a suggestion, feel free to open an issue.

---

## License

MIT