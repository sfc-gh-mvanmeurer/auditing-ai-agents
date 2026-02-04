# Permissions Reference for AI Agent Auditing

This document details the permissions required for each auditing capability.

## Role Hierarchy

```
ACCOUNTADMIN
    └── AGENT_AUDIT_ADMIN
            └── AGENT_AUDIT_VIEWER
```

## AGENT_AUDIT_VIEWER Role

**Purpose:** View audit data and run queries

### Required Grants

```sql
-- Database access
GRANT USAGE ON DATABASE AGENT_AUDIT TO ROLE AGENT_AUDIT_VIEWER;
GRANT USAGE ON ALL SCHEMAS IN DATABASE AGENT_AUDIT TO ROLE AGENT_AUDIT_VIEWER;
GRANT SELECT ON ALL VIEWS IN DATABASE AGENT_AUDIT TO ROLE AGENT_AUDIT_VIEWER;

-- Warehouse access
GRANT USAGE ON WAREHOUSE AUDIT_WH TO ROLE AGENT_AUDIT_VIEWER;

-- Cortex access
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE AGENT_AUDIT_VIEWER;

-- AI Observability access
GRANT APPLICATION ROLE SNOWFLAKE.AI_OBSERVABILITY_EVENTS_LOOKUP TO ROLE AGENT_AUDIT_VIEWER;

-- ACCOUNT_USAGE access (for QUERY_HISTORY, ACCESS_HISTORY)
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE AGENT_AUDIT_VIEWER;

-- Monitor specific agents
GRANT MONITOR ON AGENT <database>.<schema>.<agent_name> TO ROLE AGENT_AUDIT_VIEWER;
```

## AGENT_AUDIT_ADMIN Role

**Purpose:** Manage audit infrastructure, delete data

### Additional Grants (beyond VIEWER)

```sql
-- Full database control
GRANT ALL PRIVILEGES ON DATABASE AGENT_AUDIT TO ROLE AGENT_AUDIT_ADMIN;

-- Can delete observability data
GRANT APPLICATION ROLE SNOWFLAKE.AI_OBSERVABILITY_ADMIN TO ROLE AGENT_AUDIT_ADMIN;

-- Can create audit infrastructure
GRANT CREATE SCHEMA ON DATABASE AGENT_AUDIT TO ROLE AGENT_AUDIT_ADMIN;
GRANT CREATE TABLE ON ALL SCHEMAS IN DATABASE AGENT_AUDIT TO ROLE AGENT_AUDIT_ADMIN;
GRANT CREATE VIEW ON ALL SCHEMAS IN DATABASE AGENT_AUDIT TO ROLE AGENT_AUDIT_ADMIN;
```

## Granting Monitor on Agents

### For a Specific Agent

```sql
GRANT MONITOR ON AGENT HHS_SI_DEMO.CORTEX.FRAUD_INVESTIGATION_ASSISTANT 
    TO ROLE AGENT_AUDIT_VIEWER;
```

### For All Future Agents in a Schema

```sql
GRANT MONITOR ON FUTURE AGENTS IN SCHEMA HHS_SI_DEMO.CORTEX 
    TO ROLE AGENT_AUDIT_VIEWER;
```

### For All Existing Agents in a Schema

```sql
GRANT MONITOR ON ALL AGENTS IN SCHEMA HHS_SI_DEMO.CORTEX 
    TO ROLE AGENT_AUDIT_VIEWER;
```

## Creating Auditor Users

```sql
-- Create a compliance auditor user
CREATE USER compliance_auditor
    PASSWORD = 'SecurePassword123!'
    DEFAULT_ROLE = AGENT_AUDIT_VIEWER
    DEFAULT_WAREHOUSE = AUDIT_WH
    MUST_CHANGE_PASSWORD = TRUE;

-- Grant the audit role
GRANT ROLE AGENT_AUDIT_VIEWER TO USER compliance_auditor;
```

## AI Observability Prerequisites

For using the full AI Observability evaluation features:

```sql
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE <role>;
GRANT APPLICATION ROLE SNOWFLAKE.AI_OBSERVABILITY_EVENTS_LOOKUP TO ROLE <role>;
GRANT CREATE EXTERNAL AGENT ON SCHEMA <database>.<schema> TO ROLE <role>;
GRANT CREATE TASK ON SCHEMA <database>.<schema> TO ROLE <role>;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE <role>;
```

## Cortex Search Service Permissions

```sql
-- Grant usage on search services
GRANT USAGE ON CORTEX SEARCH SERVICE AGENT_AUDIT.CORTEX.AGENT_CONVERSATION_SEARCH 
    TO ROLE AGENT_AUDIT_VIEWER;
GRANT USAGE ON CORTEX SEARCH SERVICE AGENT_AUDIT.CORTEX.COMPLIANCE_POLICY_SEARCH 
    TO ROLE AGENT_AUDIT_VIEWER;
```

## Cortex Analyst Permissions

```sql
-- Grant usage on Cortex Analyst
GRANT USAGE ON CORTEX ANALYST AGENT_AUDIT.CORTEX.AGENT_AUDIT_ANALYST 
    TO ROLE AGENT_AUDIT_VIEWER;
```

## Auditor Agent Permissions

```sql
-- Grant usage and monitor on the auditor agent itself
GRANT USAGE ON AGENT AGENT_AUDIT.CORTEX.AGENT_AUDITOR 
    TO ROLE AGENT_AUDIT_VIEWER;
GRANT MONITOR ON AGENT AGENT_AUDIT.CORTEX.AGENT_AUDITOR 
    TO ROLE AGENT_AUDIT_ADMIN;
```

## Troubleshooting Permission Issues

### "Cannot access AI_OBSERVABILITY_EVENTS"

```sql
-- Verify application role is granted
SHOW GRANTS TO ROLE AGENT_AUDIT_VIEWER;

-- Should show:
-- AI_OBSERVABILITY_EVENTS_LOOKUP application role

-- If missing:
GRANT APPLICATION ROLE SNOWFLAKE.AI_OBSERVABILITY_EVENTS_LOOKUP 
    TO ROLE AGENT_AUDIT_VIEWER;
```

### "Cannot view agent events"

```sql
-- Verify MONITOR privilege on the agent
SHOW GRANTS ON AGENT <database>.<schema>.<agent_name>;

-- If missing MONITOR for your role:
GRANT MONITOR ON AGENT <database>.<schema>.<agent_name> 
    TO ROLE AGENT_AUDIT_VIEWER;
```

### "Cannot query ACCOUNT_USAGE"

```sql
-- Verify SNOWFLAKE database access
SHOW GRANTS ON DATABASE SNOWFLAKE;

-- Grant if missing:
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE 
    TO ROLE AGENT_AUDIT_VIEWER;
```

## Security Best Practices

1. **Least Privilege:** Start with AGENT_AUDIT_VIEWER; only grant ADMIN when needed
2. **Audit the Auditors:** Monitor the AGENT_AUDITOR agent itself
3. **Regular Review:** Periodically review who has audit access
4. **Separate Concerns:** Don't grant audit roles to users who operate the agents
5. **MFA Required:** Enforce MFA for all audit role users
