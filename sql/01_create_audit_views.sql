/*
AUDITING AI AGENTS IN SNOWFLAKE - Script 01: Create Audit Views
Creates flattened views over AI_OBSERVABILITY_EVENTS and ACCOUNT_USAGE.
Requires: Run 00_setup_database.sql first
*/

USE ROLE ACCOUNTADMIN;
USE DATABASE AGENT_AUDIT;
USE SCHEMA OBSERVABILITY;
USE WAREHOUSE AUDIT_WH;

--------------------------------------------------------------------------------
-- 1. FLATTENED AGENT EVENTS VIEW
--------------------------------------------------------------------------------
-- Transforms the nested AI_OBSERVABILITY_EVENTS into a queryable format
-- Based on actual schema discovered from sample data

CREATE OR REPLACE VIEW AGENT_EVENTS_FLATTENED AS
SELECT 
    -- Agent identification (from RECORD_ATTRIBUTES)
    RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING as AGENT_NAME,
    RECORD_ATTRIBUTES:"snow.ai.observability.database.name"::STRING as AGENT_DATABASE,
    RECORD_ATTRIBUTES:"snow.ai.observability.schema.name"::STRING as AGENT_SCHEMA,
    RECORD_ATTRIBUTES:"snow.ai.observability.object.type"::STRING as OBJECT_TYPE,
    
    -- User and session info (from RESOURCE_ATTRIBUTES)
    RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as USER_NAME,
    RESOURCE_ATTRIBUTES:"snow.user.id"::NUMBER as USER_ID,
    RESOURCE_ATTRIBUTES:"snow.session.id"::NUMBER as SESSION_ID,
    RESOURCE_ATTRIBUTES:"snow.session.role.primary.name"::STRING as ROLE_NAME,
    
    -- Thread and trace info (from RECORD_ATTRIBUTES and TRACE)
    RECORD_ATTRIBUTES:"snow.ai.observability.agent.thread_id"::NUMBER as THREAD_ID,
    TRACE:"trace_id"::STRING as TRACE_ID,
    TRACE:"span_id"::STRING as SPAN_ID,
    RECORD_ATTRIBUTES:"request_id"::STRING as REQUEST_ID,
    
    -- Event/Span details (from RECORD)
    RECORD_TYPE,
    RECORD:"name"::STRING as SPAN_NAME,
    RECORD:"kind"::STRING as SPAN_KIND,
    RECORD:"status":"code"::STRING as STATUS_CODE,
    
    -- Scope info
    SCOPE:"name"::STRING as SCOPE_NAME,
    
    -- Input/Output content (from RECORD_ATTRIBUTES)
    RECORD_ATTRIBUTES:"ai.observability.input_id"::STRING as INPUT_ID,
    COALESCE(
        RECORD_ATTRIBUTES:"ai.observability.record_root.input"::STRING,
        RECORD_ATTRIBUTES:"snow.ai.observability.record_root.input"::STRING
    ) as SPAN_INPUT,
    COALESCE(
        RECORD_ATTRIBUTES:"ai.observability.record_root.output"::STRING,
        RECORD_ATTRIBUTES:"snow.ai.observability.record_root.output"::STRING,
        RECORD_ATTRIBUTES:"snow.ai.observability.agent.response"::STRING
    ) as SPAN_OUTPUT,
    
    -- Feedback fields (if present in RECORD_ATTRIBUTES)
    RECORD_ATTRIBUTES:"feedback":"positive"::BOOLEAN as FEEDBACK_POSITIVE,
    RECORD_ATTRIBUTES:"feedback":"comment"::STRING as FEEDBACK_COMMENT,
    CASE 
        WHEN RECORD_ATTRIBUTES:"feedback":"positive" = true THEN 'POSITIVE'
        WHEN RECORD_ATTRIBUTES:"feedback":"positive" = false THEN 'NEGATIVE'
        ELSE NULL
    END as FEEDBACK_SENTIMENT,
    
    -- Timing
    TIMESTAMP as EVENT_TIMESTAMP,
    START_TIMESTAMP as SPAN_START_TIME,
    DATE(TIMESTAMP) as EVENT_DATE,
    HOUR(TIMESTAMP) as EVENT_HOUR,
    
    -- Calculate duration if both timestamps available
    DATEDIFF('millisecond', START_TIMESTAMP, TIMESTAMP) as SPAN_DURATION_MS,
    
    -- Raw columns for detailed analysis
    RECORD as RAW_RECORD,
    RECORD_ATTRIBUTES as RAW_RECORD_ATTRIBUTES,
    RESOURCE_ATTRIBUTES as RAW_RESOURCE_ATTRIBUTES
    
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
WHERE RECORD_ATTRIBUTES:"snow.ai.observability.object.type"::STRING = 'Cortex Agent';

COMMENT ON VIEW AGENT_EVENTS_FLATTENED IS 
'Flattened view of Cortex Agent events from AI_OBSERVABILITY_EVENTS';

--------------------------------------------------------------------------------
-- 2. AGENT CONVERSATIONS VIEW
--------------------------------------------------------------------------------
-- Extracts conversation content for search and analysis

CREATE OR REPLACE VIEW AGENT_CONVERSATIONS AS
SELECT 
    AGENT_NAME,
    AGENT_DATABASE,
    AGENT_SCHEMA,
    USER_NAME,
    ROLE_NAME,
    THREAD_ID,
    TRACE_ID,
    EVENT_TIMESTAMP,
    EVENT_DATE,
    
    -- User query (input to agent)
    SPAN_INPUT as USER_QUERY,
    
    -- Agent response (output from agent)
    SPAN_OUTPUT as AGENT_RESPONSE,
    
    -- Response metadata
    SPAN_DURATION_MS as RESPONSE_TIME_MS,
    SPAN_NAME,
    STATUS_CODE,
    
    -- Feedback if available
    FEEDBACK_SENTIMENT,
    FEEDBACK_COMMENT
    
FROM AGENT_EVENTS_FLATTENED
WHERE SPAN_NAME IN ('Agent', 'response_generation', 'agent_turn')
   OR SPAN_INPUT IS NOT NULL;

COMMENT ON VIEW AGENT_CONVERSATIONS IS 
'User queries and agent responses extracted for conversation analysis';

--------------------------------------------------------------------------------
-- 3. AGENT TOOL USAGE VIEW
--------------------------------------------------------------------------------
-- Tracks which tools agents are using and how often

CREATE OR REPLACE VIEW AGENT_TOOL_USAGE AS
SELECT 
    AGENT_NAME,
    AGENT_DATABASE,
    AGENT_SCHEMA,
    USER_NAME,
    ROLE_NAME,
    THREAD_ID,
    TRACE_ID,
    SPAN_ID,
    EVENT_TIMESTAMP,
    EVENT_DATE,
    
    -- Tool/Span details
    SPAN_NAME,
    SPAN_KIND,
    STATUS_CODE,
    SPAN_DURATION_MS as EXECUTION_TIME_MS,
    
    -- Tool input/output (may contain sensitive data - consider masking)
    LEFT(SPAN_INPUT, 500) as TOOL_INPUT_PREVIEW,
    LEFT(SPAN_OUTPUT, 500) as TOOL_OUTPUT_PREVIEW,
    INPUT_ID
    
FROM AGENT_EVENTS_FLATTENED
WHERE SPAN_NAME IS NOT NULL;

COMMENT ON VIEW AGENT_TOOL_USAGE IS 
'Tool invocations by agents for usage pattern analysis';

--------------------------------------------------------------------------------
-- 4. AGENT FEEDBACK SUMMARY VIEW
--------------------------------------------------------------------------------
-- Aggregates user feedback for quality monitoring

CREATE OR REPLACE VIEW AGENT_FEEDBACK_SUMMARY AS
SELECT 
    AGENT_NAME,
    AGENT_DATABASE,
    AGENT_SCHEMA,
    EVENT_DATE,
    
    -- Counts
    COUNT(*) as TOTAL_FEEDBACK,
    SUM(CASE WHEN FEEDBACK_SENTIMENT = 'POSITIVE' THEN 1 ELSE 0 END) as POSITIVE_COUNT,
    SUM(CASE WHEN FEEDBACK_SENTIMENT = 'NEGATIVE' THEN 1 ELSE 0 END) as NEGATIVE_COUNT,
    
    -- Rates
    ROUND(POSITIVE_COUNT / NULLIF(TOTAL_FEEDBACK, 0) * 100, 2) as POSITIVE_RATE_PCT,
    ROUND(NEGATIVE_COUNT / NULLIF(TOTAL_FEEDBACK, 0) * 100, 2) as NEGATIVE_RATE_PCT,
    
    -- Comments (for investigation)
    ARRAY_AGG(DISTINCT FEEDBACK_COMMENT) as FEEDBACK_COMMENTS
    
FROM AGENT_EVENTS_FLATTENED
WHERE FEEDBACK_POSITIVE IS NOT NULL
GROUP BY AGENT_NAME, AGENT_DATABASE, AGENT_SCHEMA, EVENT_DATE;

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
-- 9. CORTEX ANALYST REQUESTS FLATTENED VIEW
--------------------------------------------------------------------------------
-- Transforms CORTEX_ANALYST_REQUESTS_RAW into a queryable format
-- Based on actual schema discovered from sample data

CREATE OR REPLACE VIEW CORTEX_ANALYST_REQUESTS_FLATTENED AS
SELECT 
    -- Timing
    TIMESTAMP as REQUEST_TIMESTAMP,
    DATE(TIMESTAMP) as REQUEST_DATE,
    HOUR(TIMESTAMP) as REQUEST_HOUR,
    
    -- User and session info (from RESOURCE_ATTRIBUTES)
    RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as USER_NAME,
    RESOURCE_ATTRIBUTES:"snow.user.id"::NUMBER as USER_ID,
    RESOURCE_ATTRIBUTES:"snow.session.id"::NUMBER as SESSION_ID,
    RESOURCE_ATTRIBUTES:"snow.session.role.primary.name"::STRING as ROLE_NAME,
    
    -- Semantic model info (from RESOURCE_ATTRIBUTES)
    RESOURCE_ATTRIBUTES:"snow.semantic_model.name"::STRING as SEMANTIC_MODEL_PATH,
    RESOURCE_ATTRIBUTES:"snow.semantic_model.type"::STRING as SEMANTIC_MODEL_TYPE,
    RESOURCE_ATTRIBUTES:"snow.semantic_model.hash"::STRING as SEMANTIC_MODEL_HASH,
    RESOURCE_ATTRIBUTES:"snow.semantic_model.tables_referenced" as TABLES_REFERENCED,
    ARRAY_SIZE(RESOURCE_ATTRIBUTES:"snow.semantic_model.tables_referenced") as TABLE_COUNT,
    
    -- Request identifiers (from RECORD_ATTRIBUTES)
    RECORD_ATTRIBUTES:"request_id"::STRING as REQUEST_ID,
    RECORD_ATTRIBUTES:"llm.app.type"::STRING as APP_TYPE,
    RECORD_ATTRIBUTES:"llm.record.record_type"::STRING as RECORD_TYPE_ATTR,
    
    -- Question and SQL (from RECORD_ATTRIBUTES)
    RECORD_ATTRIBUTES:"latest_question"::STRING as USER_QUESTION,
    RECORD_ATTRIBUTES:"generated_sql"::STRING as GENERATED_SQL,
    LENGTH(RECORD_ATTRIBUTES:"generated_sql"::STRING) as SQL_LENGTH,
    
    -- Response metrics (from RECORD_ATTRIBUTES)
    RECORD_ATTRIBUTES:"response_status_code"::NUMBER as RESPONSE_STATUS_CODE,
    RECORD_ATTRIBUTES:"response_time_ms"::NUMBER as RESPONSE_TIME_MS,
    CASE 
        WHEN RECORD_ATTRIBUTES:"response_status_code"::NUMBER = 200 THEN 'SUCCESS'
        ELSE 'FAILED'
    END as REQUEST_STATUS,
    
    -- Response metadata
    RECORD_ATTRIBUTES:"response_body":"response_metadata":"question_category"::STRING as QUESTION_CATEGORY,
    RECORD_ATTRIBUTES:"response_body":"response_metadata":"model_names"[0]::STRING as LLM_MODEL_USED,
    
    -- Confidence and verified query info
    RECORD_ATTRIBUTES:"response_body":"message":"content"[1]:"confidence":"verified_query_used":"name"::STRING 
        as VERIFIED_QUERY_NAME,
    RECORD_ATTRIBUTES:"response_body":"message":"content"[1]:"confidence":"verified_query_used":"verified_by"::STRING 
        as VERIFIED_QUERY_BY,
    CASE 
        WHEN RECORD_ATTRIBUTES:"response_body":"message":"content"[1]:"confidence":"verified_query_used" IS NOT NULL 
        THEN TRUE ELSE FALSE 
    END as USED_VERIFIED_QUERY,
    
    -- Cortex Search usage
    ARRAY_SIZE(RECORD_ATTRIBUTES:"response_body":"response_metadata":"cortex_search_retrieval") 
        as CORTEX_SEARCH_CALLS,
    
    -- Interpretation text
    RECORD_ATTRIBUTES:"response_body":"message":"content"[0]:"text"::STRING as INTERPRETATION_TEXT,
    
    -- Warnings
    RECORD_ATTRIBUTES:"response_body":"warnings" as WARNINGS,
    ARRAY_SIZE(RECORD_ATTRIBUTES:"response_body":"warnings") as WARNING_COUNT,
    
    -- Raw for detailed analysis
    RECORD_ATTRIBUTES as RAW_RECORD_ATTRIBUTES,
    RESOURCE_ATTRIBUTES as RAW_RESOURCE_ATTRIBUTES

FROM SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW
WHERE RECORD:"name"::STRING = 'CORTEX_ANALYST_REQUEST';

COMMENT ON VIEW CORTEX_ANALYST_REQUESTS_FLATTENED IS 
'Flattened view of Cortex Analyst requests with all key fields extracted';

--------------------------------------------------------------------------------
-- 10. CORTEX ANALYST USAGE SUMMARY VIEW
--------------------------------------------------------------------------------
-- Aggregates Cortex Analyst usage by semantic model and user

CREATE OR REPLACE VIEW CORTEX_ANALYST_USAGE_SUMMARY AS
SELECT 
    SEMANTIC_MODEL_PATH,
    USER_NAME,
    ROLE_NAME,
    REQUEST_DATE,
    
    -- Request counts
    COUNT(*) as TOTAL_REQUESTS,
    SUM(CASE WHEN REQUEST_STATUS = 'SUCCESS' THEN 1 ELSE 0 END) as SUCCESSFUL_REQUESTS,
    SUM(CASE WHEN REQUEST_STATUS = 'FAILED' THEN 1 ELSE 0 END) as FAILED_REQUESTS,
    ROUND(SUCCESSFUL_REQUESTS / NULLIF(TOTAL_REQUESTS, 0) * 100, 2) as SUCCESS_RATE_PCT,
    
    -- Verified query usage
    SUM(CASE WHEN USED_VERIFIED_QUERY THEN 1 ELSE 0 END) as VERIFIED_QUERY_HITS,
    ROUND(VERIFIED_QUERY_HITS / NULLIF(TOTAL_REQUESTS, 0) * 100, 2) as VERIFIED_QUERY_HIT_RATE_PCT,
    
    -- Performance
    AVG(RESPONSE_TIME_MS) as AVG_RESPONSE_TIME_MS,
    MIN(RESPONSE_TIME_MS) as MIN_RESPONSE_TIME_MS,
    MAX(RESPONSE_TIME_MS) as MAX_RESPONSE_TIME_MS,
    MEDIAN(RESPONSE_TIME_MS) as MEDIAN_RESPONSE_TIME_MS,
    
    -- SQL complexity proxy
    AVG(SQL_LENGTH) as AVG_SQL_LENGTH,
    AVG(TABLE_COUNT) as AVG_TABLES_REFERENCED,
    
    -- Cortex Search usage
    SUM(CORTEX_SEARCH_CALLS) as TOTAL_SEARCH_CALLS,
    
    -- Warnings
    SUM(WARNING_COUNT) as TOTAL_WARNINGS

FROM CORTEX_ANALYST_REQUESTS_FLATTENED
GROUP BY SEMANTIC_MODEL_PATH, USER_NAME, ROLE_NAME, REQUEST_DATE;

COMMENT ON VIEW CORTEX_ANALYST_USAGE_SUMMARY IS 
'Daily usage summary for Cortex Analyst by semantic model and user';

--------------------------------------------------------------------------------
-- 11. CORTEX ANALYST PERFORMANCE VIEW
--------------------------------------------------------------------------------
-- Tracks Cortex Analyst performance metrics over time

CREATE OR REPLACE VIEW CORTEX_ANALYST_PERFORMANCE AS
SELECT 
    REQUEST_DATE,
    REQUEST_HOUR,
    SEMANTIC_MODEL_PATH,
    
    -- Volume
    COUNT(*) as REQUEST_COUNT,
    
    -- Success rates
    SUM(CASE WHEN REQUEST_STATUS = 'SUCCESS' THEN 1 ELSE 0 END) as SUCCESSFUL,
    SUM(CASE WHEN REQUEST_STATUS = 'FAILED' THEN 1 ELSE 0 END) as FAILED,
    ROUND(SUCCESSFUL / NULLIF(REQUEST_COUNT, 0) * 100, 2) as SUCCESS_RATE_PCT,
    
    -- Response time percentiles
    AVG(RESPONSE_TIME_MS) as AVG_RESPONSE_MS,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY RESPONSE_TIME_MS) as P50_RESPONSE_MS,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY RESPONSE_TIME_MS) as P90_RESPONSE_MS,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY RESPONSE_TIME_MS) as P99_RESPONSE_MS,
    
    -- Question categories
    COUNT(DISTINCT QUESTION_CATEGORY) as UNIQUE_CATEGORIES,
    ARRAY_AGG(DISTINCT QUESTION_CATEGORY) as CATEGORIES_SEEN,
    
    -- Model usage
    COUNT(DISTINCT LLM_MODEL_USED) as MODELS_USED,
    ARRAY_AGG(DISTINCT LLM_MODEL_USED) as MODEL_NAMES

FROM CORTEX_ANALYST_REQUESTS_FLATTENED
GROUP BY REQUEST_DATE, REQUEST_HOUR, SEMANTIC_MODEL_PATH;

COMMENT ON VIEW CORTEX_ANALYST_PERFORMANCE IS 
'Hourly performance metrics for Cortex Analyst by semantic model';

--------------------------------------------------------------------------------
-- 12. CORTEX ANALYST VERIFIED QUERIES VIEW
--------------------------------------------------------------------------------
-- Tracks which verified queries are being matched

CREATE OR REPLACE VIEW CORTEX_ANALYST_VERIFIED_QUERY_USAGE AS
SELECT 
    REQUEST_DATE,
    SEMANTIC_MODEL_PATH,
    VERIFIED_QUERY_NAME,
    VERIFIED_QUERY_BY,
    
    -- Usage counts
    COUNT(*) as TIMES_MATCHED,
    COUNT(DISTINCT USER_NAME) as UNIQUE_USERS,
    
    -- Sample questions that matched this verified query
    ARRAY_AGG(DISTINCT USER_QUESTION) as SAMPLE_QUESTIONS,
    
    -- Performance when using verified query
    AVG(RESPONSE_TIME_MS) as AVG_RESPONSE_TIME_MS

FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE USED_VERIFIED_QUERY = TRUE
GROUP BY REQUEST_DATE, SEMANTIC_MODEL_PATH, VERIFIED_QUERY_NAME, VERIFIED_QUERY_BY;

COMMENT ON VIEW CORTEX_ANALYST_VERIFIED_QUERY_USAGE IS 
'Tracks how often verified queries are matched by user questions';

--------------------------------------------------------------------------------
-- 13. CORTEX ANALYST SEARCH INTEGRATION VIEW
--------------------------------------------------------------------------------
-- Tracks Cortex Search service usage within Cortex Analyst

CREATE OR REPLACE VIEW CORTEX_ANALYST_SEARCH_USAGE AS
SELECT 
    car.TIMESTAMP as REQUEST_TIMESTAMP,
    car.RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as USER_NAME,
    car.RESOURCE_ATTRIBUTES:"snow.semantic_model.name"::STRING as SEMANTIC_MODEL,
    car.RECORD_ATTRIBUTES:"latest_question"::STRING as USER_QUESTION,
    
    -- Search service details
    search.value:"service"::STRING as SEARCH_SERVICE,
    search.value:"query"::STRING as SEARCH_QUERY,
    ARRAY_SIZE(search.value:"response_body":"results") as RESULTS_RETURNED,
    search.value:"response_body":"request_id"::STRING as SEARCH_REQUEST_ID

FROM SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW car,
LATERAL FLATTEN(
    input => car.RECORD_ATTRIBUTES:"response_body":"response_metadata":"cortex_search_retrieval", 
    OUTER => TRUE
) search
WHERE car.RECORD_ATTRIBUTES:"response_body":"response_metadata":"cortex_search_retrieval" IS NOT NULL
  AND ARRAY_SIZE(car.RECORD_ATTRIBUTES:"response_body":"response_metadata":"cortex_search_retrieval") > 0;

COMMENT ON VIEW CORTEX_ANALYST_SEARCH_USAGE IS 
'Tracks Cortex Search service calls made by Cortex Analyst for RAG';

--------------------------------------------------------------------------------
-- 14. COMBINED AGENT + ANALYST VIEW
--------------------------------------------------------------------------------
-- Joins agent events with Cortex Analyst requests when agents use Analyst as a tool

CREATE OR REPLACE VIEW AGENT_ANALYST_CORRELATION AS
SELECT 
    ae.EVENT_TIMESTAMP as AGENT_EVENT_TIME,
    car.REQUEST_TIMESTAMP as ANALYST_REQUEST_TIME,
    DATEDIFF('second', ae.EVENT_TIMESTAMP, car.REQUEST_TIMESTAMP) as TIME_DIFF_SECONDS,
    
    -- Agent info
    ae.AGENT_NAME,
    ae.AGENT_DATABASE,
    ae.AGENT_SCHEMA,
    ae.THREAD_ID as AGENT_THREAD_ID,
    ae.TRACE_ID as AGENT_TRACE_ID,
    
    -- User info (should match)
    ae.USER_NAME as AGENT_USER,
    car.USER_NAME as ANALYST_USER,
    ae.ROLE_NAME,
    
    -- Analyst info
    car.SEMANTIC_MODEL_PATH,
    car.USER_QUESTION as ANALYST_QUESTION,
    LEFT(car.GENERATED_SQL, 500) as GENERATED_SQL_PREVIEW,
    car.RESPONSE_TIME_MS as ANALYST_RESPONSE_MS,
    car.USED_VERIFIED_QUERY,
    car.VERIFIED_QUERY_NAME,
    
    -- Request IDs for correlation
    ae.REQUEST_ID as AGENT_REQUEST_ID,
    car.REQUEST_ID as ANALYST_REQUEST_ID

FROM AGENT_EVENTS_FLATTENED ae
JOIN CORTEX_ANALYST_REQUESTS_FLATTENED car
    ON ae.USER_NAME = car.USER_NAME
    AND car.REQUEST_TIMESTAMP BETWEEN DATEADD('second', -30, ae.EVENT_TIMESTAMP) 
                                   AND DATEADD('second', 30, ae.EVENT_TIMESTAMP)
WHERE ae.SPAN_NAME = 'Agent'
ORDER BY ae.EVENT_TIMESTAMP DESC;

COMMENT ON VIEW AGENT_ANALYST_CORRELATION IS 
'Correlates Cortex Agent events with Cortex Analyst requests to track agent tool usage';

--------------------------------------------------------------------------------
-- 15. VERIFY VIEWS CREATED
--------------------------------------------------------------------------------

SELECT 'Views created successfully' as status;

SELECT 
    TABLE_SCHEMA,
    TABLE_NAME,
    COMMENT
FROM AGENT_AUDIT.INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'OBSERVABILITY'
ORDER BY TABLE_NAME;

-- NEXT: Run 02_cortex_search_services.sql
