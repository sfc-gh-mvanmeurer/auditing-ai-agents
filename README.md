# Auditing AI Agents in Snowflake

Audit infrastructure for Cortex Agents using Snowflake's native observability features, ACCOUNT_USAGE, and an AI-powered Auditor Agent.

## Features

- **Audit views** over `AI_OBSERVABILITY_EVENTS` and `ACCOUNT_USAGE`
- **Cortex Search** for conversation and policy search
- **Auditor Agent** for AI-assisted investigation
- **LLM-as-a-Judge** evaluation pipelines

## Quick Start

```bash
# Execute in order:
snowsql -f sql/00_setup_database.sql      # Database and roles
snowsql -f sql/01_create_audit_views.sql  # Audit views
snowsql -f sql/02_cortex_search_services.sql  # Search services (optional)
snowsql -f sql/03_auditor_agent.sql       # Auditor Agent (optional)
snowsql -f sql/04_sample_queries.sql      # Sample queries
snowsql -f sql/05_llm_judge_evaluations.sql   # LLM evaluations (optional)
```

Update placeholders before running:
- `YOUR_AGENT_DATABASE` / `YOUR_AGENT_SCHEMA` / `YOUR_AGENT_NAME`
- `YOUR_WAREHOUSE`

## Project Structure

```
auditing-ai-agents/
├── sql/
│   ├── 00_setup_database.sql         # Database, schema, roles
│   ├── 01_create_audit_views.sql     # Views over observability data
│   ├── 02_cortex_search_services.sql # Search services
│   ├── 03_auditor_agent.sql          # AI Auditor Agent
│   ├── 04_sample_queries.sql         # Ready-to-run queries
│   └── 05_llm_judge_evaluations.sql  # LLM-as-a-judge pipeline
├── semantic_models/
│   └── agent_audit_analyst.yaml      # Cortex Analyst semantic model
└── docs/
    └── permissions_reference.md      # Required permissions
```

## Five-Layer Observability Stack

| Layer | Purpose | Data Source |
|-------|---------|-------------|
| Cortex Agent Monitoring | Conversation traces | `AI_OBSERVABILITY_EVENTS` |
| AI Observability | Built-in evaluation | `AI_OBSERVABILITY_EVENTS` |
| LLM-as-a-Judge | Custom evaluations | `CORTEX.COMPLETE` + audit views |
| ACCOUNT_USAGE | Platform SQL auditing | `ACCOUNT_USAGE.*` |
| Auditor Agent | AI-assisted investigation | All above |

## Prerequisites

- Snowflake account with Cortex features enabled
- ACCOUNTADMIN role for initial setup
- At least one Cortex Agent deployed to audit

## License

MIT
