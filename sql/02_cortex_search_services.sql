/*
================================================================================
AUDITING AI AGENTS IN SNOWFLAKE
Script 02: Cortex Search Services
================================================================================

This script creates Cortex Search services for:
- Searching agent conversation logs
- Searching compliance policies
- Searching past audit notes

Prerequisites:
- Run 00_setup_database.sql and 01_create_audit_views.sql first
- Cortex Search enabled on your account
- Some conversation data in AI_OBSERVABILITY_EVENTS

================================================================================
*/

USE ROLE ACCOUNTADMIN;
USE DATABASE AGENT_AUDIT;
USE WAREHOUSE AUDIT_WH;

--------------------------------------------------------------------------------
-- 1. AGENT CONVERSATION SEARCH
--------------------------------------------------------------------------------
-- Enables natural language search over agent conversations

CREATE OR REPLACE CORTEX SEARCH SERVICE CORTEX.AGENT_CONVERSATION_SEARCH
    ON conversation_text
    ATTRIBUTES user_name, agent_name, thread_id, event_date, feedback_sentiment
    WAREHOUSE = AUDIT_WH
    TARGET_LAG = '1 hour'
AS (
    SELECT 
        -- Searchable text: combine query and response
        COALESCE(USER_QUERY, '') || ' ' || COALESCE(AGENT_RESPONSE, '') as conversation_text,
        
        -- Filterable attributes
        USER_NAME as user_name,
        AGENT_NAME as agent_name,
        CAST(THREAD_ID AS STRING) as thread_id,
        EVENT_DATE::STRING as event_date,
        FEEDBACK_SENTIMENT as feedback_sentiment
        
    FROM AGENT_AUDIT.OBSERVABILITY.AGENT_CONVERSATIONS
    WHERE USER_QUERY IS NOT NULL OR AGENT_RESPONSE IS NOT NULL
);

COMMENT ON CORTEX SEARCH SERVICE CORTEX.AGENT_CONVERSATION_SEARCH IS 
'Search service for finding specific agent conversations by content';

--------------------------------------------------------------------------------
-- 2. COMPLIANCE POLICY SEARCH
--------------------------------------------------------------------------------
-- Enables natural language search over compliance policies

CREATE OR REPLACE CORTEX SEARCH SERVICE CORTEX.COMPLIANCE_POLICY_SEARCH
    ON policy_text
    ATTRIBUTES policy_id, policy_name, policy_category, effective_date
    WAREHOUSE = AUDIT_WH
    TARGET_LAG = '1 day'
AS (
    SELECT 
        -- Searchable text: policy content
        policy_text,
        
        -- Filterable attributes
        policy_id,
        policy_name,
        policy_category,
        effective_date::STRING as effective_date
        
    FROM AGENT_AUDIT.REFERENCE.COMPLIANCE_POLICIES
    WHERE policy_text IS NOT NULL
);

COMMENT ON CORTEX SEARCH SERVICE CORTEX.COMPLIANCE_POLICY_SEARCH IS 
'Search service for finding relevant compliance policies';

--------------------------------------------------------------------------------
-- 3. AUDIT NOTES SEARCH
--------------------------------------------------------------------------------
-- Enables natural language search over past audit notes

CREATE OR REPLACE CORTEX SEARCH SERVICE CORTEX.AUDIT_NOTES_SEARCH
    ON note_text
    ATTRIBUTES auditor_name, investigation_id, agent_name, severity, created_date
    WAREHOUSE = AUDIT_WH
    TARGET_LAG = '1 hour'
AS (
    SELECT 
        -- Searchable text: audit note content
        note_text,
        
        -- Filterable attributes
        auditor_name,
        investigation_id,
        agent_name,
        severity,
        created_date::STRING as created_date
        
    FROM AGENT_AUDIT.REFERENCE.AUDIT_NOTES
    WHERE note_text IS NOT NULL
);

COMMENT ON CORTEX SEARCH SERVICE CORTEX.AUDIT_NOTES_SEARCH IS 
'Search service for finding past audit notes and investigations';

--------------------------------------------------------------------------------
-- 4. GRANT SEARCH ACCESS
--------------------------------------------------------------------------------

-- Grant usage on search services to audit viewers
GRANT USAGE ON CORTEX SEARCH SERVICE CORTEX.AGENT_CONVERSATION_SEARCH 
    TO ROLE AGENT_AUDIT_VIEWER;
GRANT USAGE ON CORTEX SEARCH SERVICE CORTEX.COMPLIANCE_POLICY_SEARCH 
    TO ROLE AGENT_AUDIT_VIEWER;
GRANT USAGE ON CORTEX SEARCH SERVICE CORTEX.AUDIT_NOTES_SEARCH 
    TO ROLE AGENT_AUDIT_VIEWER;

--------------------------------------------------------------------------------
-- 5. VERIFY SEARCH SERVICES CREATED
--------------------------------------------------------------------------------

SELECT 'Verifying search services...' as status;

-- Check if search services exist
SHOW CORTEX SEARCH SERVICES IN SCHEMA AGENT_AUDIT.CORTEX;

-- Check if underlying data exists
SELECT 'Checking underlying data...' as status;

SELECT 'COMPLIANCE_POLICIES' as source_table, COUNT(*) as row_count 
FROM AGENT_AUDIT.REFERENCE.COMPLIANCE_POLICIES;

SELECT 'AUDIT_NOTES' as source_table, COUNT(*) as row_count 
FROM AGENT_AUDIT.REFERENCE.AUDIT_NOTES;

SELECT 'AGENT_CONVERSATIONS (view)' as source_table, COUNT(*) as row_count 
FROM AGENT_AUDIT.OBSERVABILITY.AGENT_CONVERSATIONS;

--------------------------------------------------------------------------------
-- 6. TEST SEARCH SERVICES (run separately after services are ready)
--------------------------------------------------------------------------------
-- NOTE: Search services need time to build. Check the service status first:
-- DESCRIBE CORTEX SEARCH SERVICE AGENT_AUDIT.CORTEX.COMPLIANCE_POLICY_SEARCH;

-- Per Snowflake documentation, the correct way to query Cortex Search Services
-- in SQL is using SNOWFLAKE.CORTEX.SEARCH_PREVIEW() function.
-- Reference: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/query-cortex-search-service

-- ============================================================================
-- TEST QUERY 1: Search Compliance Policies
-- ============================================================================
-- This returns the raw JSON results
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'AGENT_AUDIT.CORTEX.COMPLIANCE_POLICY_SEARCH',
        '{
            "query": "data access security",
            "columns": ["policy_text", "policy_name", "policy_category"],
            "limit": 5
        }'
    )
)['results'] as results;

-- This flattens the results into rows for easier reading
SELECT 
    value['policy_name']::STRING as policy_name,
    value['policy_category']::STRING as policy_category,
    LEFT(value['policy_text']::STRING, 200) as policy_preview
FROM TABLE(FLATTEN(PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'AGENT_AUDIT.CORTEX.COMPLIANCE_POLICY_SEARCH',
        '{
            "query": "data access security",
            "columns": ["policy_text", "policy_name", "policy_category"],
            "limit": 5
        }'
    )
)['results']));

-- ============================================================================
-- TEST QUERY 2: Search Agent Conversations
-- ============================================================================
-- Only works if you have conversation data in AI_OBSERVABILITY_EVENTS
SELECT 
    value['agent_name']::STRING as agent_name,
    value['user_name']::STRING as user_name,
    value['feedback_sentiment']::STRING as sentiment,
    LEFT(value['conversation_text']::STRING, 200) as conversation_preview
FROM TABLE(FLATTEN(PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'AGENT_AUDIT.CORTEX.AGENT_CONVERSATION_SEARCH',
        '{
            "query": "access denied error",
            "columns": ["conversation_text", "agent_name", "user_name", "feedback_sentiment"],
            "limit": 5
        }'
    )
)['results']));

-- ============================================================================
-- TEST QUERY 3: Search with Filter
-- ============================================================================
-- Filter uses the @eq operator for exact matches
SELECT 
    value['policy_name']::STRING as policy_name,
    value['policy_category']::STRING as policy_category,
    LEFT(value['policy_text']::STRING, 200) as policy_preview
FROM TABLE(FLATTEN(PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'AGENT_AUDIT.CORTEX.COMPLIANCE_POLICY_SEARCH',
        '{
            "query": "security requirements",
            "columns": ["policy_text", "policy_name", "policy_category"],
            "filter": {"@eq": {"policy_category": "DATA_ACCESS"}},
            "limit": 5
        }'
    )
)['results']));

-- ============================================================================
-- TEST QUERY 4: Search Audit Notes
-- ============================================================================
SELECT 
    value['investigation_id']::STRING as investigation_id,
    value['agent_name']::STRING as agent_name,
    value['severity']::STRING as severity,
    LEFT(value['note_text']::STRING, 200) as note_preview
FROM TABLE(FLATTEN(PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'AGENT_AUDIT.CORTEX.AUDIT_NOTES_SEARCH',
        '{
            "query": "suspicious activity",
            "columns": ["note_text", "investigation_id", "agent_name", "severity"],
            "limit": 5
        }'
    )
)['results']));

--------------------------------------------------------------------------------
-- NEXT STEPS
--------------------------------------------------------------------------------
/*
1. Verify services are created: SHOW CORTEX SEARCH SERVICES IN SCHEMA AGENT_AUDIT.CORTEX;
2. Check service status: DESCRIBE CORTEX SEARCH SERVICE AGENT_AUDIT.CORTEX.COMPLIANCE_POLICY_SEARCH;
3. Wait for services to finish building (status should show as ACTIVE)
4. Run 03_auditor_agent.sql to create the AI Auditor Agent

TROUBLESHOOTING:
----------------
If search queries return no results:
1. Verify the service exists: SHOW CORTEX SEARCH SERVICES IN SCHEMA AGENT_AUDIT.CORTEX;
2. Check service status is ACTIVE: DESCRIBE CORTEX SEARCH SERVICE AGENT_AUDIT.CORTEX.COMPLIANCE_POLICY_SEARCH;
3. Ensure the underlying tables/views have data
4. Use fully qualified service names in SEARCH_PREVIEW()

Query Syntax Reference:
-----------------------
-- Basic query (returns raw JSON):
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        '<database>.<schema>.<service_name>',
        '{"query": "search text", "columns": ["col1", "col2"], "limit": 10}'
    )
)['results'] as results;

-- Flattened results (returns rows):
SELECT value['column_name']::STRING as column_name
FROM TABLE(FLATTEN(PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        '<database>.<schema>.<service_name>',
        '{"query": "search text", "columns": ["column_name"], "limit": 10}'
    )
)['results']));

-- With filter:
'{"query": "...", "columns": [...], "filter": {"@eq": {"column": "value"}}, "limit": 10}'

*/
