/*
================================================================================
AUDITING AI AGENTS IN SNOWFLAKE
Script 01: Create Audit Views
================================================================================

This script creates views that flatten and join observability data for easier
auditing. These views provide:
- Flattened agent events (from AI_OBSERVABILITY_EVENTS)
- Data access lineage (joining to ACCESS_HISTORY)
- Failed query analysis
- User activity summaries

Prerequisites:
- Run 00_setup_database.sql first
- AGENT_AUDIT_ADMIN or ACCOUNTADMIN role

================================================================================
*/

USE ROLE ACCOUNTADMIN;
USE DATABASE AGENT_AUDIT;
USE SCHEMA OBSERVABILITY;
USE WAREHOUSE AUDIT_WH;

--------------------------------------------------------------------------------
-- 1. FLATTENED AGENT EVENTS VIEW
--------------------------------------------------------------------------------
-- Transforms the nested AI_OBSERVABILITY_EVENTS into a queryable format

CREATE OR REPLACE VIEW AGENT_EVENTS_FLATTENED AS
SELECT 
    -- Agent identification
    RECORD:agent_name::STRING as AGENT_NAME,
    RECORD:database::STRING as AGENT_DATABASE,
    RECORD:schema::STRING as AGENT_SCHEMA,
    
    -- User and session info
    RECORD:user_name::STRING as USER_NAME,
    RECORD:thread_id::STRING as THREAD_ID,
    RECORD:session_id::STRING as SESSION_ID,
    
    -- Event details
    RECORD:name::STRING as EVENT_TYPE,
    RECORD:trace_id::STRING as TRACE_ID,
    
    -- Span details (tool execution, LLM calls, etc.)
    RECORD:spans[0]:name::STRING as SPAN_NAME,
    RECORD:spans[0]:tool_name::STRING as TOOL_USED,
    RECORD:spans[0]:input::STRING as SPAN_INPUT,
    RECORD:spans[0]:output::STRING as SPAN_OUTPUT,
    RECORD:spans[0]:duration_ms::NUMBER as SPAN_DURATION_MS,
    
    -- For multi-span events, get all spans as array
    RECORD:spans as ALL_SPANS,
    ARRAY_SIZE(RECORD:spans) as SPAN_COUNT,
    
    -- Feedback (when EVENT_TYPE = 'CORTEX_AGENT_FEEDBACK')
    RECORD:feedback:positive::BOOLEAN as FEEDBACK_POSITIVE,
    RECORD:feedback:comment::STRING as FEEDBACK_COMMENT,
    CASE 
        WHEN RECORD:name = 'CORTEX_AGENT_FEEDBACK' 
             AND RECORD:feedback:positive = true THEN 'POSITIVE'
        WHEN RECORD:name = 'CORTEX_AGENT_FEEDBACK' 
             AND RECORD:feedback:positive = false THEN 'NEGATIVE'
        ELSE NULL
    END as FEEDBACK_SENTIMENT,
    
    -- Timing
    TIMESTAMP as EVENT_TIMESTAMP,
    DATE(TIMESTAMP) as EVENT_DATE,
    HOUR(TIMESTAMP) as EVENT_HOUR,
    
    -- Raw record for detailed analysis
    RECORD as RAW_RECORD
    
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
WHERE RECORD:agent_type::STRING = 'CORTEX AGENT'
   OR RECORD:name::STRING LIKE 'CORTEX_AGENT%';

COMMENT ON VIEW AGENT_EVENTS_FLATTENED IS 
'Flattened view of Cortex Agent events from AI_OBSERVABILITY_EVENTS';

--------------------------------------------------------------------------------
-- 2. AGENT CONVERSATIONS VIEW
--------------------------------------------------------------------------------
-- Extracts conversation content for search and analysis

CREATE OR REPLACE VIEW AGENT_CONVERSATIONS AS
SELECT 
    AGENT_NAME,
    USER_NAME,
    THREAD_ID,
    EVENT_TIMESTAMP,
    EVENT_DATE,
    
    -- User query (input to agent)
    SPAN_INPUT as USER_QUERY,
    
    -- Agent response (output from agent)
    SPAN_OUTPUT as AGENT_RESPONSE,
    
    -- Response metadata
    SPAN_DURATION_MS as RESPONSE_TIME_MS,
    TOOL_USED,
    SPAN_COUNT as TOOLS_CALLED,
    
    -- Feedback if available
    FEEDBACK_SENTIMENT,
    FEEDBACK_COMMENT
    
FROM AGENT_EVENTS_FLATTENED
WHERE EVENT_TYPE IN ('CORTEX_AGENT_RESPONSE', 'CORTEX_AGENT_TURN')
   OR SPAN_NAME = 'response_generation';

COMMENT ON VIEW AGENT_CONVERSATIONS IS 
'User queries and agent responses extracted for conversation analysis';

--------------------------------------------------------------------------------
-- 3. AGENT TOOL USAGE VIEW
--------------------------------------------------------------------------------
-- Tracks which tools agents are using and how often

CREATE OR REPLACE VIEW AGENT_TOOL_USAGE AS
SELECT 
    AGENT_NAME,
    USER_NAME,
    THREAD_ID,
    EVENT_TIMESTAMP,
    EVENT_DATE,
    
    -- Tool details
    TOOL_USED,
    SPAN_NAME as EXECUTION_TYPE,
    SPAN_DURATION_MS as EXECUTION_TIME_MS,
    
    -- Tool input/output (may contain sensitive data - consider masking)
    LEFT(SPAN_INPUT, 500) as TOOL_INPUT_PREVIEW,
    LEFT(SPAN_OUTPUT, 500) as TOOL_OUTPUT_PREVIEW
    
FROM AGENT_EVENTS_FLATTENED
WHERE EVENT_TYPE = 'CORTEX_AGENT_TOOL_EXECUTION'
   OR SPAN_NAME IN ('tool_execution', 'cortex_analyst', 'cortex_search', 'web_search');

COMMENT ON VIEW AGENT_TOOL_USAGE IS 
'Tool invocations by agents for usage pattern analysis';

--------------------------------------------------------------------------------
-- 4. AGENT FEEDBACK SUMMARY VIEW
--------------------------------------------------------------------------------
-- Aggregates user feedback for quality monitoring

CREATE OR REPLACE VIEW AGENT_FEEDBACK_SUMMARY AS
SELECT 
    AGENT_NAME,
    EVENT_DATE,
    
    -- Counts
    COUNT(*) as TOTAL_FEEDBACK,
    SUM(CASE WHEN FEEDBACK_SENTIMENT = 'POSITIVE' THEN 1 ELSE 0 END) as POSITIVE_COUNT,
    SUM(CASE WHEN FEEDBACK_SENTIMENT = 'NEGATIVE' THEN 1 ELSE 0 END) as NEGATIVE_COUNT,
    
    -- Rates
    ROUND(POSITIVE_COUNT / NULLIF(TOTAL_FEEDBACK, 0) * 100, 2) as POSITIVE_RATE_PCT,
    ROUND(NEGATIVE_COUNT / NULLIF(TOTAL_FEEDBACK, 0) * 100, 2) as NEGATIVE_RATE_PCT,
    
    -- Comments (for investigation)
    ARRAY_AGG(DISTINCT FEEDBACK_COMMENT) WITHIN GROUP (ORDER BY EVENT_TIMESTAMP) 
        as FEEDBACK_COMMENTS
    
FROM AGENT_EVENTS_FLATTENED
WHERE EVENT_TYPE = 'CORTEX_AGENT_FEEDBACK'
GROUP BY AGENT_NAME, EVENT_DATE;

COMMENT ON VIEW AGENT_FEEDBACK_SUMMARY IS 
'Daily aggregated feedback metrics per agent';

--------------------------------------------------------------------------------
-- 5. QUERY HISTORY FOR AGENTS VIEW
--------------------------------------------------------------------------------
-- Joins agent events to QUERY_HISTORY for SQL-level auditing

CREATE OR REPLACE VIEW AGENT_QUERY_HISTORY AS
SELECT 
    qh.query_id,
    qh.user_name,
    qh.role_name,
    qh.warehouse_name,
    qh.query_text,
    qh.query_type,
    qh.execution_status,
    qh.error_code,
    qh.error_message,
    qh.rows_produced,
    qh.bytes_scanned,
    qh.total_elapsed_time / 1000 as elapsed_seconds,
    qh.start_time,
    qh.end_time,
    
    -- Cortex function detection
    CASE 
        WHEN CONTAINS(UPPER(qh.query_text), 'CORTEX.COMPLETE') THEN 'COMPLETE'
        WHEN CONTAINS(UPPER(qh.query_text), 'CORTEX.SUMMARIZE') THEN 'SUMMARIZE'
        WHEN CONTAINS(UPPER(qh.query_text), 'CORTEX.TRANSLATE') THEN 'TRANSLATE'
        WHEN CONTAINS(UPPER(qh.query_text), 'CORTEX.SENTIMENT') THEN 'SENTIMENT'
        WHEN CONTAINS(UPPER(qh.query_text), 'CORTEX_ANALYST') THEN 'CORTEX_ANALYST'
        WHEN CONTAINS(UPPER(qh.query_text), 'CORTEX_SEARCH') THEN 'CORTEX_SEARCH'
        ELSE NULL
    END as CORTEX_FUNCTION_USED

FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
WHERE qh.start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP())
  -- Filter to Cortex-related queries
  AND (
      CONTAINS(UPPER(qh.query_text), 'CORTEX.')
      OR CONTAINS(UPPER(qh.query_text), 'CORTEX_')
      OR qh.warehouse_name LIKE '%AGENT%'
      OR qh.warehouse_name LIKE '%CORTEX%'
  );

COMMENT ON VIEW AGENT_QUERY_HISTORY IS 
'Query history filtered to Cortex and agent-related queries';

--------------------------------------------------------------------------------
-- 6. DATA ACCESS LINEAGE VIEW
--------------------------------------------------------------------------------
-- Tracks which tables and columns were accessed

CREATE OR REPLACE VIEW DATA_ACCESS_LINEAGE AS
SELECT 
    qh.query_id,
    qh.user_name,
    qh.role_name,
    qh.start_time as access_time,
    
    -- Base objects (source tables)
    f_base.value:objectName::STRING as source_table,
    f_base.value:objectDomain::STRING as source_type,
    
    -- Columns accessed
    f_base.value:columns as columns_accessed,
    
    -- Direct objects (what query returned)
    f_direct.value:objectName::STRING as target_object,
    
    -- Query metadata
    qh.rows_produced,
    qh.bytes_scanned
    
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
JOIN SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah
    ON qh.query_id = ah.query_id,
LATERAL FLATTEN(input => ah.base_objects_accessed, OUTER => TRUE) f_base,
LATERAL FLATTEN(input => ah.direct_objects_accessed, OUTER => TRUE) f_direct
WHERE qh.start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP())
  AND qh.execution_status = 'SUCCESS';

COMMENT ON VIEW DATA_ACCESS_LINEAGE IS 
'Data lineage showing which tables and columns were accessed by queries';

--------------------------------------------------------------------------------
-- 7. FAILED QUERIES ANALYSIS VIEW
--------------------------------------------------------------------------------
-- Analyzes failed queries for security and debugging

CREATE OR REPLACE VIEW FAILED_QUERIES_ANALYSIS AS
SELECT 
    query_id,
    user_name,
    role_name,
    warehouse_name,
    error_code,
    error_message,
    
    -- Categorize errors
    CASE 
        WHEN error_code IN (1003, 2003, 3001) THEN 'PERMISSION_DENIED'
        WHEN error_code IN (2043, 2140, 2003) THEN 'OBJECT_NOT_FOUND'
        WHEN error_code IN (100132, 100183, 1003) THEN 'SYNTAX_ERROR'
        WHEN error_code IN (100051, 100052) THEN 'RESOURCE_LIMIT'
        WHEN error_message ILIKE '%timeout%' THEN 'TIMEOUT'
        ELSE 'OTHER'
    END as error_category,
    
    -- Query preview (truncated for safety)
    LEFT(query_text, 1000) as query_preview,
    
    start_time,
    DATE(start_time) as failure_date,
    HOUR(start_time) as failure_hour
    
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE execution_status = 'FAIL'
  AND start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP());

COMMENT ON VIEW FAILED_QUERIES_ANALYSIS IS 
'Failed queries categorized by error type for security analysis';

--------------------------------------------------------------------------------
-- 8. USER ACTIVITY SUMMARY VIEW
--------------------------------------------------------------------------------
-- Summarizes user activity for behavioral analysis

CREATE OR REPLACE VIEW USER_ACTIVITY_SUMMARY AS
SELECT 
    user_name,
    DATE(start_time) as activity_date,
    
    -- Query counts
    COUNT(*) as total_queries,
    SUM(CASE WHEN execution_status = 'SUCCESS' THEN 1 ELSE 0 END) as successful_queries,
    SUM(CASE WHEN execution_status = 'FAIL' THEN 1 ELSE 0 END) as failed_queries,
    
    -- Failure rate
    ROUND(failed_queries / NULLIF(total_queries, 0) * 100, 2) as failure_rate_pct,
    
    -- Resource usage
    SUM(rows_produced) as total_rows_produced,
    SUM(bytes_scanned) as total_bytes_scanned,
    AVG(total_elapsed_time) / 1000 as avg_query_seconds,
    
    -- Activity timing
    MIN(start_time) as first_query,
    MAX(start_time) as last_query,
    COUNT(DISTINCT HOUR(start_time)) as active_hours
    
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP())
GROUP BY user_name, DATE(start_time);

COMMENT ON VIEW USER_ACTIVITY_SUMMARY IS 
'Daily user activity summary for behavioral analysis';

--------------------------------------------------------------------------------
-- 9. VERIFY VIEWS CREATED
--------------------------------------------------------------------------------

SELECT 'Views created successfully' as status;

SELECT 
    TABLE_SCHEMA,
    TABLE_NAME,
    COMMENT
FROM AGENT_AUDIT.INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'OBSERVABILITY'
ORDER BY TABLE_NAME;

--------------------------------------------------------------------------------
-- NEXT STEPS
--------------------------------------------------------------------------------
/*
1. Run 02_cortex_search_services.sql to create search capabilities
2. Test views with sample queries in 04_sample_queries.sql
3. Grant MONITOR on your agents so events flow into these views

Note: Views will show data once you have:
- Cortex Agents deployed and used
- MONITOR privilege granted on those agents
- AI_OBSERVABILITY_EVENTS populated with events

*/
