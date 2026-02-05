/*
AUDITING AI AGENTS IN SNOWFLAKE - Script 04: Sample Queries
Ready-to-run audit queries. Requires: Run 00, 01 first

SECTIONS: A-Activity, B-Feedback, C-Security, D-Lineage, E-Users, 
          F-Cortex, G-Compliance, H-Investigation Templates
*/

USE ROLE AGENT_AUDIT_VIEWER;  -- Or AGENT_AUDIT_ADMIN
USE DATABASE AGENT_AUDIT;
USE SCHEMA OBSERVABILITY;
USE WAREHOUSE AUDIT_WH;

-- SECTION A: AGENT ACTIVITY

-- A1. Daily agent conversation counts (last 30 days)
SELECT 
    AGENT_NAME,
    EVENT_DATE,
    COUNT(DISTINCT THREAD_ID) as conversations,
    COUNT(DISTINCT USER_NAME) as unique_users,
    COUNT(*) as total_events
FROM AGENT_EVENTS_FLATTENED
WHERE EVENT_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY AGENT_NAME, EVENT_DATE
ORDER BY EVENT_DATE DESC, conversations DESC;

-- A2. Agent tool usage distribution
SELECT 
    AGENT_NAME,
    SPAN_NAME as tool_used,
    COUNT(*) as usage_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY AGENT_NAME), 2) as pct_of_agent
FROM AGENT_TOOL_USAGE
WHERE EVENT_DATE >= DATEADD('day', -30, CURRENT_DATE())
  AND SPAN_NAME IS NOT NULL
GROUP BY AGENT_NAME, SPAN_NAME
ORDER BY AGENT_NAME, usage_count DESC;

-- A3. Average response times by agent
SELECT 
    AGENT_NAME,
    COUNT(*) as responses,
    ROUND(AVG(RESPONSE_TIME_MS), 2) as avg_response_ms,
    ROUND(MEDIAN(RESPONSE_TIME_MS), 2) as median_response_ms,
    MAX(RESPONSE_TIME_MS) as max_response_ms
FROM AGENT_CONVERSATIONS
WHERE EVENT_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY AGENT_NAME
ORDER BY avg_response_ms DESC;

-- SECTION B: FEEDBACK ANALYSIS

-- B1. Overall feedback rates by agent
SELECT 
    AGENT_NAME,
    SUM(TOTAL_FEEDBACK) as total_feedback,
    SUM(POSITIVE_COUNT) as positive,
    SUM(NEGATIVE_COUNT) as negative,
    ROUND(SUM(POSITIVE_COUNT) * 100.0 / NULLIF(SUM(TOTAL_FEEDBACK), 0), 2) as positive_rate_pct
FROM AGENT_FEEDBACK_SUMMARY
WHERE EVENT_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY AGENT_NAME
ORDER BY positive_rate_pct ASC;  -- Worst first

-- B2. Negative feedback trends (early warning)
SELECT 
    EVENT_DATE,
    AGENT_NAME,
    NEGATIVE_COUNT,
    TOTAL_FEEDBACK,
    NEGATIVE_RATE_PCT,
    -- Flag days with unusually high negative feedback
    CASE 
        WHEN NEGATIVE_RATE_PCT > 20 THEN '⚠️ HIGH'
        WHEN NEGATIVE_RATE_PCT > 10 THEN '⚡ ELEVATED'
        ELSE '✅ NORMAL'
    END as alert_level
FROM AGENT_FEEDBACK_SUMMARY
WHERE EVENT_DATE >= DATEADD('day', -14, CURRENT_DATE())
  AND TOTAL_FEEDBACK >= 5  -- Minimum sample size
ORDER BY EVENT_DATE DESC, NEGATIVE_RATE_PCT DESC;

-- B3. Conversations with negative feedback (for investigation)
SELECT 
    AGENT_NAME,
    USER_NAME,
    THREAD_ID,
    EVENT_TIMESTAMP,
    LEFT(USER_QUERY, 200) as user_query_preview,
    LEFT(AGENT_RESPONSE, 200) as agent_response_preview,
    FEEDBACK_COMMENT
FROM AGENT_CONVERSATIONS
WHERE FEEDBACK_SENTIMENT = 'NEGATIVE'
  AND EVENT_DATE >= DATEADD('day', -7, CURRENT_DATE())
ORDER BY EVENT_TIMESTAMP DESC
LIMIT 20;

-- SECTION C: SECURITY

-- C1. Failed queries by error category
SELECT 
    error_category,
    COUNT(*) as failure_count,
    COUNT(DISTINCT user_name) as affected_users,
    ARRAY_AGG(DISTINCT error_code) as error_codes
FROM FAILED_QUERIES_ANALYSIS
WHERE failure_date >= DATEADD('day', -7, CURRENT_DATE())
GROUP BY error_category
ORDER BY failure_count DESC;

-- C2. Permission denied errors (potential access issues)
SELECT 
    user_name,
    role_name,
    failure_date,
    COUNT(*) as denial_count,
    ARRAY_AGG(DISTINCT LEFT(query_preview, 100)) as query_samples
FROM FAILED_QUERIES_ANALYSIS
WHERE error_category = 'PERMISSION_DENIED'
  AND failure_date >= DATEADD('day', -7, CURRENT_DATE())
GROUP BY user_name, role_name, failure_date
ORDER BY denial_count DESC;

-- C3. Unusual query patterns (high row counts - potential data exfiltration)
SELECT 
    user_name,
    query_id,
    rows_produced,
    LEFT(query_text, 300) as query_preview,
    start_time
FROM AGENT_QUERY_HISTORY
WHERE rows_produced > 10000  -- Adjust threshold
  AND start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
ORDER BY rows_produced DESC
LIMIT 20;

-- C4. After-hours activity
SELECT 
    user_name,
    DATE(start_time) as activity_date,
    HOUR(start_time) as activity_hour,
    COUNT(*) as query_count
FROM AGENT_QUERY_HISTORY
WHERE HOUR(start_time) NOT BETWEEN 8 AND 18  -- Outside business hours
  AND DAYOFWEEK(start_time) NOT IN (0, 6)    -- Weekdays only
  AND start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY user_name, DATE(start_time), HOUR(start_time)
HAVING query_count > 5
ORDER BY activity_date DESC, query_count DESC;

-- SECTION D: DATA LINEAGE

-- D1. Most frequently accessed tables
SELECT 
    source_table,
    COUNT(*) as access_count,
    COUNT(DISTINCT user_name) as unique_users,
    SUM(rows_produced) as total_rows_returned
FROM DATA_ACCESS_LINEAGE
WHERE access_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND source_table IS NOT NULL
GROUP BY source_table
ORDER BY access_count DESC
LIMIT 20;

-- D2. Users accessing specific sensitive tables
-- Replace 'YOUR_SENSITIVE_TABLE' with actual table names
SELECT 
    user_name,
    role_name,
    COUNT(*) as access_count,
    MIN(access_time) as first_access,
    MAX(access_time) as last_access
FROM DATA_ACCESS_LINEAGE
WHERE source_table ILIKE '%CLAIMS%'  -- Adjust pattern
   OR source_table ILIKE '%PATIENT%'
   OR source_table ILIKE '%PHI%'
GROUP BY user_name, role_name
ORDER BY access_count DESC;

-- D3. Column-level access for specific tables
SELECT 
    source_table,
    f.value::STRING as column_accessed,
    COUNT(*) as access_count
FROM DATA_ACCESS_LINEAGE,
LATERAL FLATTEN(input => columns_accessed, OUTER => TRUE) f
WHERE source_table ILIKE '%YOUR_TABLE%'  -- Adjust
  AND access_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY source_table, f.value::STRING
ORDER BY access_count DESC;

-- SECTION E: USER BEHAVIOR

-- E1. User activity summary
SELECT 
    user_name,
    COUNT(DISTINCT activity_date) as active_days,
    SUM(total_queries) as total_queries,
    SUM(failed_queries) as total_failures,
    ROUND(AVG(failure_rate_pct), 2) as avg_failure_rate,
    SUM(total_rows_produced) as total_rows
FROM USER_ACTIVITY_SUMMARY
WHERE activity_date >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY user_name
ORDER BY total_queries DESC;

-- E2. Users with unusually high failure rates
SELECT 
    user_name,
    activity_date,
    total_queries,
    failed_queries,
    failure_rate_pct,
    CASE 
        WHEN failure_rate_pct > 20 THEN '⚠️ INVESTIGATE'
        WHEN failure_rate_pct > 10 THEN '⚡ MONITOR'
        ELSE '✅ NORMAL'
    END as status
FROM USER_ACTIVITY_SUMMARY
WHERE activity_date >= DATEADD('day', -7, CURRENT_DATE())
  AND total_queries >= 10  -- Minimum sample
  AND failure_rate_pct > 10
ORDER BY failure_rate_pct DESC;

-- E3. Role usage patterns
SELECT 
    role_name,
    COUNT(DISTINCT user_name) as unique_users,
    COUNT(*) as total_queries,
    SUM(rows_produced) as total_rows
FROM AGENT_QUERY_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY role_name
ORDER BY total_queries DESC;

-- SECTION F: CORTEX USAGE

-- F1. Cortex function usage by type
SELECT 
    CORTEX_FUNCTION_USED,
    COUNT(*) as call_count,
    COUNT(DISTINCT user_name) as unique_users,
    ROUND(AVG(elapsed_seconds), 2) as avg_seconds
FROM AGENT_QUERY_HISTORY
WHERE CORTEX_FUNCTION_USED IS NOT NULL
  AND start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY CORTEX_FUNCTION_USED
ORDER BY call_count DESC;

-- F2. Daily Cortex usage trend
SELECT 
    DATE(start_time) as usage_date,
    CORTEX_FUNCTION_USED,
    COUNT(*) as calls
FROM AGENT_QUERY_HISTORY
WHERE CORTEX_FUNCTION_USED IS NOT NULL
  AND start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY DATE(start_time), CORTEX_FUNCTION_USED
ORDER BY usage_date DESC, calls DESC;

-- SECTION F2: CORTEX ANALYST

-- F2.1. Cortex Analyst usage by semantic model (last 30 days)
SELECT 
    SEMANTIC_MODEL_PATH,
    COUNT(*) as total_requests,
    COUNT(DISTINCT USER_NAME) as unique_users,
    SUM(CASE WHEN REQUEST_STATUS = 'SUCCESS' THEN 1 ELSE 0 END) as successful,
    ROUND(AVG(RESPONSE_TIME_MS), 0) as avg_response_ms,
    SUM(CASE WHEN USED_VERIFIED_QUERY THEN 1 ELSE 0 END) as verified_query_hits
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE REQUEST_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY SEMANTIC_MODEL_PATH
ORDER BY total_requests DESC;

-- F2.2. Daily Cortex Analyst request volume
SELECT 
    REQUEST_DATE,
    COUNT(*) as total_requests,
    COUNT(DISTINCT USER_NAME) as unique_users,
    COUNT(DISTINCT SEMANTIC_MODEL_PATH) as models_used,
    ROUND(AVG(RESPONSE_TIME_MS), 0) as avg_response_ms,
    SUM(CASE WHEN REQUEST_STATUS = 'SUCCESS' THEN 1 ELSE 0 END) as successful,
    SUM(CASE WHEN REQUEST_STATUS = 'FAILED' THEN 1 ELSE 0 END) as failed
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE REQUEST_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY REQUEST_DATE
ORDER BY REQUEST_DATE DESC;

-- F2.3. Top Cortex Analyst users
SELECT 
    USER_NAME,
    ROLE_NAME,
    COUNT(*) as total_requests,
    COUNT(DISTINCT SEMANTIC_MODEL_PATH) as models_used,
    ROUND(AVG(RESPONSE_TIME_MS), 0) as avg_response_ms,
    SUM(CASE WHEN USED_VERIFIED_QUERY THEN 1 ELSE 0 END) as verified_query_hits,
    ROUND(SUM(CASE WHEN USED_VERIFIED_QUERY THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) as verified_hit_rate_pct
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE REQUEST_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY USER_NAME, ROLE_NAME
ORDER BY total_requests DESC
LIMIT 20;

-- F2.4. Recent Cortex Analyst questions (for review)
SELECT 
    REQUEST_TIMESTAMP,
    USER_NAME,
    SEMANTIC_MODEL_PATH,
    USER_QUESTION,
    LEFT(GENERATED_SQL, 300) as sql_preview,
    RESPONSE_TIME_MS,
    USED_VERIFIED_QUERY,
    QUESTION_CATEGORY
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE REQUEST_DATE >= DATEADD('day', -7, CURRENT_DATE())
ORDER BY REQUEST_TIMESTAMP DESC
LIMIT 50;

-- SECTION F3: ANALYST PERFORMANCE

-- F3.1. Response time percentiles by semantic model
SELECT 
    SEMANTIC_MODEL_PATH,
    COUNT(*) as request_count,
    ROUND(AVG(RESPONSE_TIME_MS), 0) as avg_ms,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY RESPONSE_TIME_MS), 0) as p50_ms,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY RESPONSE_TIME_MS), 0) as p90_ms,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY RESPONSE_TIME_MS), 0) as p99_ms,
    MAX(RESPONSE_TIME_MS) as max_ms
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE REQUEST_DATE >= DATEADD('day', -30, CURRENT_DATE())
  AND REQUEST_STATUS = 'SUCCESS'
GROUP BY SEMANTIC_MODEL_PATH
ORDER BY avg_ms DESC;

-- F3.2. Hourly performance trends (identify peak times)
SELECT 
    REQUEST_HOUR,
    COUNT(*) as request_count,
    ROUND(AVG(RESPONSE_TIME_MS), 0) as avg_response_ms,
    ROUND(SUM(CASE WHEN REQUEST_STATUS = 'SUCCESS' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) as success_rate_pct
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE REQUEST_DATE >= DATEADD('day', -7, CURRENT_DATE())
GROUP BY REQUEST_HOUR
ORDER BY REQUEST_HOUR;

-- F3.3. Slow queries investigation (>10 seconds)
SELECT 
    REQUEST_TIMESTAMP,
    USER_NAME,
    SEMANTIC_MODEL_PATH,
    USER_QUESTION,
    RESPONSE_TIME_MS,
    SQL_LENGTH,
    TABLE_COUNT as tables_referenced,
    QUESTION_CATEGORY,
    LLM_MODEL_USED
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE RESPONSE_TIME_MS > 10000  -- 10 seconds
  AND REQUEST_DATE >= DATEADD('day', -7, CURRENT_DATE())
ORDER BY RESPONSE_TIME_MS DESC
LIMIT 20;

-- F3.4. Question category distribution
SELECT 
    QUESTION_CATEGORY,
    COUNT(*) as request_count,
    ROUND(AVG(RESPONSE_TIME_MS), 0) as avg_response_ms,
    ROUND(SUM(CASE WHEN REQUEST_STATUS = 'SUCCESS' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) as success_rate_pct
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE REQUEST_DATE >= DATEADD('day', -30, CURRENT_DATE())
  AND QUESTION_CATEGORY IS NOT NULL
GROUP BY QUESTION_CATEGORY
ORDER BY request_count DESC;

-- F3.5. LLM model usage
SELECT 
    LLM_MODEL_USED,
    COUNT(*) as request_count,
    ROUND(AVG(RESPONSE_TIME_MS), 0) as avg_response_ms
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE REQUEST_DATE >= DATEADD('day', -30, CURRENT_DATE())
  AND LLM_MODEL_USED IS NOT NULL
GROUP BY LLM_MODEL_USED
ORDER BY request_count DESC;

-- SECTION F4: VERIFIED QUERIES

-- F4.1. Most frequently matched verified queries
SELECT 
    SEMANTIC_MODEL_PATH,
    VERIFIED_QUERY_NAME,
    VERIFIED_QUERY_BY,
    COUNT(*) as times_matched,
    COUNT(DISTINCT USER_NAME) as unique_users,
    ROUND(AVG(RESPONSE_TIME_MS), 0) as avg_response_ms
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE USED_VERIFIED_QUERY = TRUE
  AND REQUEST_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY SEMANTIC_MODEL_PATH, VERIFIED_QUERY_NAME, VERIFIED_QUERY_BY
ORDER BY times_matched DESC;

-- F4.2. Verified query hit rate trend
SELECT 
    REQUEST_DATE,
    SEMANTIC_MODEL_PATH,
    COUNT(*) as total_requests,
    SUM(CASE WHEN USED_VERIFIED_QUERY THEN 1 ELSE 0 END) as verified_hits,
    ROUND(SUM(CASE WHEN USED_VERIFIED_QUERY THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) as hit_rate_pct
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE REQUEST_DATE >= DATEADD('day', -14, CURRENT_DATE())
GROUP BY REQUEST_DATE, SEMANTIC_MODEL_PATH
ORDER BY REQUEST_DATE DESC, total_requests DESC;

-- F4.3. Questions that could become verified queries (frequent similar questions)
SELECT 
    SEMANTIC_MODEL_PATH,
    USER_QUESTION,
    COUNT(*) as times_asked,
    COUNT(DISTINCT USER_NAME) as unique_askers,
    ROUND(AVG(RESPONSE_TIME_MS), 0) as avg_response_ms
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE USED_VERIFIED_QUERY = FALSE  -- Not already matching a verified query
  AND REQUEST_STATUS = 'SUCCESS'
  AND REQUEST_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY SEMANTIC_MODEL_PATH, USER_QUESTION
HAVING times_asked >= 3  -- Asked multiple times
ORDER BY times_asked DESC
LIMIT 20;

-- F4.4. Verified queries by creator
SELECT 
    VERIFIED_QUERY_BY as created_by,
    COUNT(DISTINCT VERIFIED_QUERY_NAME) as verified_queries_created,
    SUM(COUNT(*)) OVER (PARTITION BY VERIFIED_QUERY_BY) as total_matches
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE USED_VERIFIED_QUERY = TRUE
  AND REQUEST_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY VERIFIED_QUERY_BY, VERIFIED_QUERY_NAME
ORDER BY total_matches DESC;

-- SECTION F5: SEARCH IN ANALYST

-- F5.1. Cortex Search services called by Cortex Analyst
SELECT 
    SEARCH_SERVICE,
    COUNT(*) as call_count,
    COUNT(DISTINCT USER_NAME) as unique_users,
    ROUND(AVG(RESULTS_RETURNED), 1) as avg_results_returned
FROM CORTEX_ANALYST_SEARCH_USAGE
WHERE REQUEST_TIMESTAMP >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY SEARCH_SERVICE
ORDER BY call_count DESC;

-- F5.2. Search retrieval patterns
SELECT 
    REQUEST_TIMESTAMP,
    USER_NAME,
    USER_QUESTION,
    SEARCH_SERVICE,
    SEARCH_QUERY,
    RESULTS_RETURNED
FROM CORTEX_ANALYST_SEARCH_USAGE
WHERE REQUEST_TIMESTAMP >= DATEADD('day', -7, CURRENT_TIMESTAMP())
ORDER BY REQUEST_TIMESTAMP DESC
LIMIT 50;

-- F5.3. Questions that triggered Cortex Search
SELECT 
    USER_QUESTION,
    COUNT(*) as times_triggered_search,
    COUNT(DISTINCT SEARCH_SERVICE) as search_services_used,
    SUM(RESULTS_RETURNED) as total_results_retrieved
FROM CORTEX_ANALYST_SEARCH_USAGE
WHERE REQUEST_TIMESTAMP >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY USER_QUESTION
ORDER BY times_triggered_search DESC
LIMIT 20;

-- SECTION F6: AGENT-ANALYST CORRELATION

-- F6.1. Agents using Cortex Analyst as a tool
SELECT 
    AGENT_NAME,
    AGENT_DATABASE || '.' || AGENT_SCHEMA as agent_location,
    COUNT(*) as analyst_calls,
    COUNT(DISTINCT ANALYST_USER) as unique_users,
    COUNT(DISTINCT SEMANTIC_MODEL_PATH) as semantic_models_used,
    ROUND(AVG(ANALYST_RESPONSE_MS), 0) as avg_analyst_response_ms
FROM AGENT_ANALYST_CORRELATION
WHERE AGENT_EVENT_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY AGENT_NAME, AGENT_DATABASE, AGENT_SCHEMA
ORDER BY analyst_calls DESC;

-- F6.2. Agent conversations that used Cortex Analyst
SELECT 
    AGENT_EVENT_TIME,
    AGENT_NAME,
    AGENT_USER,
    SEMANTIC_MODEL_PATH,
    ANALYST_QUESTION,
    GENERATED_SQL_PREVIEW,
    ANALYST_RESPONSE_MS,
    USED_VERIFIED_QUERY,
    VERIFIED_QUERY_NAME
FROM AGENT_ANALYST_CORRELATION
WHERE AGENT_EVENT_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
ORDER BY AGENT_EVENT_TIME DESC
LIMIT 30;

-- F6.3. Agent tool patterns - how often do agents use Analyst vs other tools?
SELECT 
    ae.AGENT_NAME,
    ae.SPAN_NAME as tool_or_span,
    COUNT(*) as usage_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY ae.AGENT_NAME), 1) as pct_of_agent_activity
FROM AGENT_EVENTS_FLATTENED ae
WHERE ae.EVENT_DATE >= DATEADD('day', -30, CURRENT_DATE())
  AND ae.SPAN_NAME IS NOT NULL
GROUP BY ae.AGENT_NAME, ae.SPAN_NAME
ORDER BY ae.AGENT_NAME, usage_count DESC;

-- SECTION G: COMPLIANCE REPORTING

-- G1. Monthly audit summary - Cortex Agents
SELECT 
    DATE_TRUNC('month', EVENT_DATE) as audit_month,
    AGENT_NAME,
    COUNT(DISTINCT THREAD_ID) as total_conversations,
    COUNT(DISTINCT USER_NAME) as unique_users,
    SUM(CASE WHEN FEEDBACK_SENTIMENT = 'POSITIVE' THEN 1 ELSE 0 END) as positive_feedback,
    SUM(CASE WHEN FEEDBACK_SENTIMENT = 'NEGATIVE' THEN 1 ELSE 0 END) as negative_feedback
FROM AGENT_EVENTS_FLATTENED
WHERE EVENT_DATE >= DATEADD('month', -3, CURRENT_DATE())
GROUP BY DATE_TRUNC('month', EVENT_DATE), AGENT_NAME
ORDER BY audit_month DESC, AGENT_NAME;

-- G2. Monthly audit summary - Cortex Analyst
SELECT 
    DATE_TRUNC('month', REQUEST_DATE) as audit_month,
    SEMANTIC_MODEL_PATH,
    COUNT(*) as total_requests,
    COUNT(DISTINCT USER_NAME) as unique_users,
    SUM(CASE WHEN REQUEST_STATUS = 'SUCCESS' THEN 1 ELSE 0 END) as successful_requests,
    SUM(CASE WHEN USED_VERIFIED_QUERY THEN 1 ELSE 0 END) as verified_query_hits,
    ROUND(AVG(RESPONSE_TIME_MS), 0) as avg_response_ms
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE REQUEST_DATE >= DATEADD('month', -3, CURRENT_DATE())
GROUP BY DATE_TRUNC('month', REQUEST_DATE), SEMANTIC_MODEL_PATH
ORDER BY audit_month DESC, total_requests DESC;

-- G3. Data access report for compliance
SELECT 
    DATE_TRUNC('week', access_time) as report_week,
    COUNT(DISTINCT user_name) as users_with_access,
    COUNT(DISTINCT source_table) as tables_accessed,
    SUM(rows_produced) as total_rows_retrieved,
    COUNT(*) as total_queries
FROM DATA_ACCESS_LINEAGE
WHERE access_time >= DATEADD('month', -1, CURRENT_TIMESTAMP())
GROUP BY DATE_TRUNC('week', access_time)
ORDER BY report_week DESC;

-- G4. Cortex Analyst tables accessed via generated SQL
SELECT 
    DATE_TRUNC('week', REQUEST_DATE) as report_week,
    SEMANTIC_MODEL_PATH,
    f.value::STRING as table_referenced,
    COUNT(*) as times_referenced,
    COUNT(DISTINCT USER_NAME) as unique_users
FROM CORTEX_ANALYST_REQUESTS_FLATTENED,
LATERAL FLATTEN(input => TABLES_REFERENCED, OUTER => TRUE) f
WHERE REQUEST_DATE >= DATEADD('month', -1, CURRENT_DATE())
  AND f.value IS NOT NULL
GROUP BY DATE_TRUNC('week', REQUEST_DATE), SEMANTIC_MODEL_PATH, f.value::STRING
ORDER BY report_week DESC, times_referenced DESC;

-- G5. Combined AI usage report (Agents + Analyst)
SELECT 
    DATE_TRUNC('week', event_date) as report_week,
    'CORTEX_AGENT' as ai_service,
    COUNT(DISTINCT AGENT_NAME) as unique_objects,
    COUNT(DISTINCT USER_NAME) as unique_users,
    COUNT(*) as total_events
FROM AGENT_EVENTS_FLATTENED
WHERE EVENT_DATE >= DATEADD('month', -1, CURRENT_DATE())
GROUP BY DATE_TRUNC('week', event_date)

UNION ALL

SELECT 
    DATE_TRUNC('week', REQUEST_DATE) as report_week,
    'CORTEX_ANALYST' as ai_service,
    COUNT(DISTINCT SEMANTIC_MODEL_PATH) as unique_objects,
    COUNT(DISTINCT USER_NAME) as unique_users,
    COUNT(*) as total_events
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE REQUEST_DATE >= DATEADD('month', -1, CURRENT_DATE())
GROUP BY DATE_TRUNC('week', REQUEST_DATE)

ORDER BY report_week DESC, ai_service;

-- SECTION H: INVESTIGATION TEMPLATES

-- H1. Investigate a specific user
-- Replace 'TARGET_USER' with the username to investigate
/*
DECLARE
    target_user VARCHAR DEFAULT 'TARGET_USER';
BEGIN
    -- User's recent activity
    SELECT * FROM USER_ACTIVITY_SUMMARY 
    WHERE user_name = :target_user 
    ORDER BY activity_date DESC;
    
    -- User's failed queries
    SELECT * FROM FAILED_QUERIES_ANALYSIS 
    WHERE user_name = :target_user 
    ORDER BY start_time DESC LIMIT 20;
    
    -- User's data access
    SELECT source_table, COUNT(*) as access_count
    FROM DATA_ACCESS_LINEAGE 
    WHERE user_name = :target_user 
    GROUP BY source_table ORDER BY access_count DESC;
END;
*/

-- H2. Investigate a specific conversation thread
-- Replace 'THREAD_ID' with the thread to investigate
/*
SELECT 
    EVENT_TIMESTAMP,
    EVENT_TYPE,
    TOOL_USED,
    SPAN_INPUT,
    SPAN_OUTPUT,
    FEEDBACK_SENTIMENT
FROM AGENT_EVENTS_FLATTENED
WHERE THREAD_ID = 'YOUR_THREAD_ID'
ORDER BY EVENT_TIMESTAMP;
*/

-- H3. Investigate a specific semantic model's usage
-- Replace with your semantic model path
/*
SELECT 
    REQUEST_DATE,
    COUNT(*) as requests,
    COUNT(DISTINCT USER_NAME) as users,
    ROUND(AVG(RESPONSE_TIME_MS), 0) as avg_ms,
    SUM(CASE WHEN USED_VERIFIED_QUERY THEN 1 ELSE 0 END) as verified_hits
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE SEMANTIC_MODEL_PATH ILIKE '%your_model%'
GROUP BY REQUEST_DATE
ORDER BY REQUEST_DATE DESC;
*/

-- H4. Investigate Cortex Analyst questions by a specific user
/*
SELECT 
    REQUEST_TIMESTAMP,
    USER_QUESTION,
    SEMANTIC_MODEL_PATH,
    LEFT(GENERATED_SQL, 500) as sql_preview,
    RESPONSE_TIME_MS,
    REQUEST_STATUS,
    USED_VERIFIED_QUERY
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE USER_NAME = 'TARGET_USER'
  AND REQUEST_DATE >= DATEADD('day', -30, CURRENT_DATE())
ORDER BY REQUEST_TIMESTAMP DESC;
*/

-- H5. Find all questions about a specific topic/table
/*
SELECT 
    REQUEST_TIMESTAMP,
    USER_NAME,
    USER_QUESTION,
    LEFT(GENERATED_SQL, 300) as sql_preview,
    RESPONSE_TIME_MS
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE USER_QUESTION ILIKE '%customer%'  -- Adjust search term
   OR GENERATED_SQL ILIKE '%CUSTOMER%'
ORDER BY REQUEST_TIMESTAMP DESC
LIMIT 50;
*/

-- H6. Analyze generated SQL patterns (for security review)
/*
SELECT 
    USER_NAME,
    USER_QUESTION,
    GENERATED_SQL,
    CASE 
        WHEN GENERATED_SQL ILIKE '%DELETE%' THEN 'CONTAINS_DELETE'
        WHEN GENERATED_SQL ILIKE '%DROP%' THEN 'CONTAINS_DROP'
        WHEN GENERATED_SQL ILIKE '%TRUNCATE%' THEN 'CONTAINS_TRUNCATE'
        WHEN GENERATED_SQL ILIKE '%INSERT%' THEN 'CONTAINS_INSERT'
        WHEN GENERATED_SQL ILIKE '%UPDATE%' THEN 'CONTAINS_UPDATE'
        ELSE 'READ_ONLY'
    END as sql_type
FROM CORTEX_ANALYST_REQUESTS_FLATTENED
WHERE REQUEST_DATE >= DATEADD('day', -7, CURRENT_DATE())
  AND (
      GENERATED_SQL ILIKE '%DELETE%'
      OR GENERATED_SQL ILIKE '%DROP%'
      OR GENERATED_SQL ILIKE '%TRUNCATE%'
      OR GENERATED_SQL ILIKE '%INSERT%'
      OR GENERATED_SQL ILIKE '%UPDATE%'
  )
ORDER BY REQUEST_TIMESTAMP DESC;
*/

-- EXPORT: COPY INTO @my_stage/audit_export/ FROM (...) FILE_FORMAT = (TYPE = CSV HEADER = TRUE);
