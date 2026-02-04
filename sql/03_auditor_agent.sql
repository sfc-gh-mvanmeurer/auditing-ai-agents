/*
================================================================================
AUDITING AI AGENTS IN SNOWFLAKE
Script 03: The Auditor Agent
================================================================================

This script creates an AI-powered Auditor Agent that helps human auditors
investigate agent behavior using natural language queries.

The Auditor Agent combines:
- Cortex Analyst: Query metrics and patterns
- Cortex Search: Find specific conversations and policies

Prerequisites:
- Run 00, 01, 02 scripts first
- Cortex Agents enabled on your account
- Semantic model uploaded (see semantic_models/ folder)

================================================================================
*/

USE ROLE ACCOUNTADMIN;
USE DATABASE AGENT_AUDIT;
USE WAREHOUSE AUDIT_WH;

--------------------------------------------------------------------------------
-- 1. CREATE CORTEX ANALYST TOOL
--------------------------------------------------------------------------------
-- First, upload the semantic model YAML to a stage

CREATE STAGE IF NOT EXISTS CORTEX.SEMANTIC_MODELS
    COMMENT = 'Stage for Cortex Analyst semantic model files';

-- NOTE: Upload the semantic model YAML file manually:
-- PUT file://semantic_models/agent_audit_analyst.yaml @CORTEX.SEMANTIC_MODELS AUTO_COMPRESS=FALSE;

-- Create the Cortex Analyst tool
-- Uncomment after uploading the semantic model:

/*
CREATE OR REPLACE CORTEX ANALYST CORTEX.AGENT_AUDIT_ANALYST
    WAREHOUSE = AUDIT_WH
    SEMANTIC_MODEL = '@CORTEX.SEMANTIC_MODELS/agent_audit_analyst.yaml'
    COMMENT = 'Cortex Analyst for querying agent audit metrics';

GRANT USAGE ON CORTEX ANALYST CORTEX.AGENT_AUDIT_ANALYST 
    TO ROLE AGENT_AUDIT_VIEWER;
*/

--------------------------------------------------------------------------------
-- 2. CREATE THE AUDITOR AGENT
--------------------------------------------------------------------------------

-- Uncomment after Cortex Analyst and Search services are created:

/*
CREATE OR REPLACE AGENT CORTEX.AGENT_AUDITOR
    WAREHOUSE = AUDIT_WH
    EXTERNAL_ACCESS_INTEGRATIONS = ()  -- No external access needed
    COMMENT = 'AI-assisted auditor for Cortex Agent governance and compliance'
    TOOLS = (
        CORTEX.AGENT_AUDIT_ANALYST,          -- Metrics and patterns
        CORTEX.AGENT_CONVERSATION_SEARCH,    -- Conversation search
        CORTEX.COMPLIANCE_POLICY_SEARCH,     -- Policy search
        CORTEX.AUDIT_NOTES_SEARCH            -- Past audit notes
    )
    SYSTEM_PROMPT = $$
You are an AI Compliance Auditor Assistant helping human auditors investigate 
agent behavior, data access patterns, and policy compliance in Snowflake.

## Your Role
You AUGMENT human auditors - you do not replace their judgment. Present evidence 
and analysis; let humans make compliance determinations.

## Available Tools

### agent_audit_analyst (Cortex Analyst)
Use for QUANTITATIVE questions about agent activity:
- "How many conversations did the fraud agent have last week?"
- "What's the positive feedback rate for each agent?"
- "Which tables were accessed most frequently?"
- "Show me failed query trends by error type"
- "Compare agent usage this month vs. last month"
- "What's the average response time by agent?"

### agent_conversation_search (Cortex Search)
Use for finding SPECIFIC conversations by content:
- "Find conversations where users mentioned 'denied access'"
- "Show me interactions with negative feedback"
- "Find cases where the agent discussed patient data"
- "Search for prompt injection attempts"

### compliance_policy_search (Cortex Search)
Use for POLICY questions:
- "What are our data retention requirements?"
- "Find policies about PII handling"
- "What's the escalation procedure for security incidents?"
- "Show me policies related to data access"

### audit_notes_search (Cortex Search)
Use for HISTORICAL context from past audits:
- "Have we seen this pattern before?"
- "What did the previous auditor conclude about this issue?"
- "Find related investigations"
- "Show me past findings about this agent"

## Response Guidelines

ALWAYS:
→ Cite specific data sources and query results
→ Include date ranges for any metrics reported
→ Flag if data seems incomplete or unusual
→ Suggest follow-up questions the auditor might want to ask
→ Distinguish between facts (from data) and interpretations

NEVER:
→ Make definitive compliance determinations (that's the human's job)
→ Recommend disciplinary actions against users
→ Access data outside the audit scope
→ Speculate about user intent without evidence
→ Minimize or dismiss potential security concerns

## When Findings Suggest Policy Violations

Present the evidence factually:
1. What the data shows (with sources and timestamps)
2. Which policy may be relevant (cite specific policy)
3. What additional information might clarify the situation
4. Recommend human review for final determination

## Example Interactions

User: "Show me a summary of agent activity last week"
→ Use agent_audit_analyst to get metrics
→ Include: conversation counts, feedback rates, tool usage, any anomalies

User: "Find any suspicious conversations"
→ Use agent_conversation_search for injection attempts, policy violations
→ Present findings with context, don't make accusations

User: "Is this behavior allowed under our policies?"
→ Use compliance_policy_search to find relevant policies
→ Present policy text, let human determine compliance

## Formatting

- Use tables for metrics when comparing multiple items
- Use bullet points for findings and recommendations
- Include [Source: tool_name] tags for traceability
- Provide conversation thread IDs for human follow-up
$$;

-- Grant usage on the auditor agent
GRANT USAGE ON AGENT CORTEX.AGENT_AUDITOR TO ROLE AGENT_AUDIT_VIEWER;
GRANT MONITOR ON AGENT CORTEX.AGENT_AUDITOR TO ROLE AGENT_AUDIT_ADMIN;
*/

--------------------------------------------------------------------------------
-- 3. ALTERNATIVE: MANUAL AGENT QUERIES
--------------------------------------------------------------------------------
-- If you can't create the full agent, use these queries directly

-- Get agent events for investigation
CREATE OR REPLACE FUNCTION CORTEX.GET_AGENT_EVENTS(
    p_agent_name VARCHAR,
    p_days_back INTEGER DEFAULT 7
)
RETURNS TABLE (
    event_type VARCHAR,
    user_name VARCHAR,
    thread_id VARCHAR,
    tool_used VARCHAR,
    feedback_sentiment VARCHAR,
    event_timestamp TIMESTAMP_NTZ
)
AS
$$
    SELECT 
        EVENT_TYPE,
        USER_NAME,
        THREAD_ID,
        TOOL_USED,
        FEEDBACK_SENTIMENT,
        EVENT_TIMESTAMP
    FROM AGENT_AUDIT.OBSERVABILITY.AGENT_EVENTS_FLATTENED
    WHERE (p_agent_name IS NULL OR AGENT_NAME = p_agent_name)
      AND EVENT_TIMESTAMP >= DATEADD('day', -p_days_back, CURRENT_TIMESTAMP())
    ORDER BY EVENT_TIMESTAMP DESC
$$;

-- Get feedback summary
CREATE OR REPLACE FUNCTION CORTEX.GET_FEEDBACK_SUMMARY(
    p_agent_name VARCHAR,
    p_days_back INTEGER DEFAULT 30
)
RETURNS TABLE (
    agent_name VARCHAR,
    total_feedback INTEGER,
    positive_count INTEGER,
    negative_count INTEGER,
    positive_rate FLOAT
)
AS
$$
    SELECT 
        AGENT_NAME,
        COUNT(*) as total_feedback,
        SUM(CASE WHEN FEEDBACK_SENTIMENT = 'POSITIVE' THEN 1 ELSE 0 END) as positive_count,
        SUM(CASE WHEN FEEDBACK_SENTIMENT = 'NEGATIVE' THEN 1 ELSE 0 END) as negative_count,
        ROUND(positive_count / NULLIF(total_feedback, 0) * 100, 2) as positive_rate
    FROM AGENT_AUDIT.OBSERVABILITY.AGENT_EVENTS_FLATTENED
    WHERE EVENT_TYPE = 'CORTEX_AGENT_FEEDBACK'
      AND (p_agent_name IS NULL OR AGENT_NAME = p_agent_name)
      AND EVENT_TIMESTAMP >= DATEADD('day', -p_days_back, CURRENT_TIMESTAMP())
    GROUP BY AGENT_NAME
$$;

--------------------------------------------------------------------------------
-- 4. VERIFY SETUP
--------------------------------------------------------------------------------

SELECT 'Auditor functions created' as status;

SHOW USER FUNCTIONS IN SCHEMA CORTEX;

--------------------------------------------------------------------------------
-- USAGE EXAMPLES
--------------------------------------------------------------------------------
/*

-- Once the agent is created, query it like this:

-- Via SQL
SELECT SNOWFLAKE.CORTEX.AGENT(
    'AGENT_AUDIT.CORTEX.AGENT_AUDITOR',
    'Show me a summary of the fraud investigation agent activity last week'
);

-- Via Snowsight
Navigate to: AI & ML → Agents → AGENT_AUDITOR → Chat

-- Sample questions to ask the Auditor Agent:
1. "What agents have the lowest user satisfaction scores?"
2. "Find conversations where users tried to access other users' data"
3. "Show me the trend of failed queries over the past month"
4. "What are our policies about handling PHI data?"
5. "Have there been any security incidents with the claims agent?"
6. "Which users have the most interactions with the fraud agent?"
7. "Find conversations with negative feedback and summarize the issues"

*/
