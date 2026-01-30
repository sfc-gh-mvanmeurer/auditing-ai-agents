# Auditing AI Agents in Snowflake

A complete implementation for auditing Cortex Agents using Snowflake's native observability features, ACCOUNT_USAGE, and an AI-powered Auditor Agent.

## Overview

This repository provides:
- **SQL scripts** to set up audit infrastructure
- **Semantic models** for Cortex Analyst-powered auditing
- **Cortex Search services** for conversation and policy search
- **An Auditor Agent** that helps human auditors investigate agent behavior
- **LLM-as-a-Judge** evaluation pipelines for systematic quality assessment

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   AUDITOR AGENT                         │
│            (Snowflake Intelligence)                     │
├─────────────────────────────────────────────────────────┤
│  ┌──────────────────┐    ┌──────────────────────────┐   │
│  │  Cortex Analyst  │    │     Cortex Search        │   │
│  │  - Query metrics │    │  - Conversation logs     │   │
│  │  - Access history│    │  - Policy documents      │   │
│  │  - User patterns │    │  - Audit notes           │   │
│  └────────┬─────────┘    └────────────┬─────────────┘   │
│           ▼                           ▼                 │
│  ┌─────────────────────────────────────────────────┐    │
│  │            AUDIT DATA SOURCES                   │    │
│  │  • SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS      │    │
│  │  • SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY        │    │
│  │  • SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY       │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

## Five-Layer Observability Stack

| Layer | Purpose | Data Source |
|-------|---------|-------------|
| **Cortex Agent Monitoring** | Built-in conversation traces | `AI_OBSERVABILITY_EVENTS` |
| **AI Observability** | Systematic evaluation (built-in) | `AI_OBSERVABILITY_EVENTS` |
| **LLM-as-a-Judge** | Custom evaluation pipelines | `CORTEX.COMPLETE` + audit views |
| **ACCOUNT_USAGE** | Platform-level SQL auditing | `ACCOUNT_USAGE.*` |
| **Auditor Agent** | AI-assisted investigation | All of the above |

## Quick Start

### Prerequisites

- Snowflake account with Cortex features enabled
- ACCOUNTADMIN role (for initial setup)
- At least one Cortex Agent deployed to audit

### Installation

Execute the SQL scripts in order:

```bash
# 1. Create database and base permissions
snowsql -f sql/00_setup_database.sql

# 2. Create audit views over observability data
snowsql -f sql/01_create_audit_views.sql

# 3. Create Cortex Search services (optional)
snowsql -f sql/02_cortex_search_services.sql

# 4. Create the Auditor Agent (optional)
snowsql -f sql/03_auditor_agent.sql

# 5. Run sample audit queries
snowsql -f sql/04_sample_queries.sql

# 6. Set up LLM-as-a-judge evaluations (optional)
snowsql -f sql/05_llm_judge_evaluations.sql
```

### Configuration

Update the following placeholders in the SQL scripts before running:

| Placeholder | Description |
|-------------|-------------|
| `YOUR_AGENT_DATABASE` | Database containing your agents |
| `YOUR_AGENT_SCHEMA` | Schema containing your agents |
| `YOUR_AGENT_NAME` | Name of the agent to audit |
| `YOUR_WAREHOUSE` | Warehouse for audit queries |

## Repository Structure

```
auditing-ai-agents/
├── README.md
├── sql/
│   ├── 00_setup_database.sql         # Database, schema, roles
│   ├── 01_create_audit_views.sql     # Views over observability data
│   ├── 02_cortex_search_services.sql # Search for conversations/policies
│   ├── 03_auditor_agent.sql          # The AI Auditor Agent
│   ├── 04_sample_queries.sql         # Ready-to-run audit queries
│   └── 05_llm_judge_evaluations.sql  # LLM-as-a-judge evaluation pipeline
├── semantic_models/
│   └── agent_audit_analyst.yaml      # Cortex Analyst semantic model
└── docs/
    └── permissions_reference.md      # Required permissions guide
```

## SQL Scripts

| Script | Description |
|--------|-------------|
| `00_setup_database.sql` | Creates the `AUDIT_DB` database, schemas, warehouse, and audit roles (`AGENT_AUDIT_VIEWER`, `AGENT_AUDIT_ADMIN`) |
| `01_create_audit_views.sql` | Flattens `AI_OBSERVABILITY_EVENTS` into queryable views; joins with `ACCESS_HISTORY` for data lineage |
| `02_cortex_search_services.sql` | Creates Cortex Search services over agent conversations, compliance policies, and audit notes |
| `03_auditor_agent.sql` | Defines the Auditor Agent with system prompt and tool configuration |
| `04_sample_queries.sql` | Ready-to-run audit queries for common scenarios |
| `05_llm_judge_evaluations.sql` | Custom LLM-as-a-judge functions for groundedness, relevance, safety, and comprehensiveness |

## Semantic Model

The `agent_audit_analyst.yaml` semantic model enables natural language queries over audit data via Cortex Analyst:

- **AGENT_EVENTS**: Conversation counts, feedback rates, response times
- **DATA_ACCESS**: Tables and columns accessed by agents
- **QUERY_FAILURES**: Failed queries with error categorization

## Documentation

- [Permissions Reference](docs/permissions_reference.md) - Required roles and privileges
- [Snowflake Cortex Agent Monitoring](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-monitor)
- [Snowflake AI Observability](https://docs.snowflake.com/en/user-guide/snowflake-cortex/ai-observability)
- [ACCESS_HISTORY View](https://docs.snowflake.com/en/sql-reference/account-usage/access_history)
- [QUERY_HISTORY View](https://docs.snowflake.com/en/sql-reference/account-usage/query_history)

## License

MIT

## Author

Michael van Meurer - Senior Solutions Engineer, Snowflake
