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
    WAREHOUSE = AUDIT_WH
    TARGET_LAG = '1 hour'
    ON conversation_text
    ATTRIBUTES user_name, agent_name, thread_id, event_date, feedback_sentiment, tool_used
AS (
    SELECT 
        -- Searchable text: combine query and response
        COALESCE(USER_QUERY, '') || ' ' || COALESCE(AGENT_RESPONSE, '') as conversation_text,
        
        -- Filterable attributes
        USER_NAME as user_name,
        AGENT_NAME as agent_name,
        THREAD_ID as thread_id,
        EVENT_DATE::STRING as event_date,
        FEEDBACK_SENTIMENT as feedback_sentiment,
        TOOL_USED as tool_used
        
    FROM AGENT_AUDIT.OBSERVABILITY.AGENT_CONVERSATIONS
    WHERE conversation_text IS NOT NULL
      AND LENGTH(conversation_text) > 10
);

COMMENT ON CORTEX SEARCH SERVICE CORTEX.AGENT_CONVERSATION_SEARCH IS 
'Search service for finding specific agent conversations by content';

--------------------------------------------------------------------------------
-- 2. COMPLIANCE POLICY SEARCH
--------------------------------------------------------------------------------
-- Enables natural language search over compliance policies

CREATE OR REPLACE CORTEX SEARCH SERVICE CORTEX.COMPLIANCE_POLICY_SEARCH
    WAREHOUSE = AUDIT_WH
    TARGET_LAG = '1 day'
    ON policy_text
    ATTRIBUTES policy_id, policy_name, policy_category, effective_date
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
    WAREHOUSE = AUDIT_WH
    TARGET_LAG = '1 hour'
    ON note_text
    ATTRIBUTES auditor_name, investigation_id, agent_name, severity, created_date
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
-- 5. TEST SEARCH SERVICES
--------------------------------------------------------------------------------

-- Test policy search
SELECT 'Testing policy search...' as status;

SELECT 
    policy_name,
    policy_category,
    LEFT(policy_text, 200) as policy_preview
FROM TABLE(
    CORTEX.COMPLIANCE_POLICY_SEARCH!SEARCH(
        query => 'data access security',
        columns => ['policy_text'],
        limit => 3
    )
);

-- Note: Conversation search will only work once you have conversation data
-- SELECT 
--     agent_name,
--     user_name,
--     LEFT(conversation_text, 200) as conversation_preview
-- FROM TABLE(
--     CORTEX.AGENT_CONVERSATION_SEARCH!SEARCH(
--         query => 'access denied',
--         columns => ['conversation_text'],
--         limit => 5
--     )
-- );

--------------------------------------------------------------------------------
-- 6. VERIFY SEARCH SERVICES CREATED
--------------------------------------------------------------------------------

SELECT 'Search services created' as status;

SHOW CORTEX SEARCH SERVICES IN SCHEMA CORTEX;

--------------------------------------------------------------------------------
-- NEXT STEPS
--------------------------------------------------------------------------------
/*
1. Run 03_auditor_agent.sql to create the AI Auditor Agent
2. Search services will auto-refresh based on TARGET_LAG settings
3. Use these searches in the Auditor Agent for natural language investigation

Example usage:

-- Search for conversations mentioning "denied"
SELECT * FROM TABLE(
    CORTEX.AGENT_CONVERSATION_SEARCH!SEARCH(
        query => 'permission denied access',
        columns => ['conversation_text'],
        filter => {'feedback_sentiment': 'NEGATIVE'},
        limit => 10
    )
);

*/
