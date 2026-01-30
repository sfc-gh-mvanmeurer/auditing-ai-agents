/*
================================================================================
AUDITING AI AGENTS IN SNOWFLAKE
Script 04: Sample Audit Queries
================================================================================

Ready-to-run queries for common audit scenarios. Use these as templates
for your audit investigations.

Prerequisites:
- Run scripts 00, 01 first
- Have some agent activity in AI_OBSERVABILITY_EVENTS

================================================================================
*/

USE ROLE AGENT_AUDIT_VIEWER;  -- Or AGENT_AUDIT_ADMIN
USE DATABASE AGENT_AUDIT;
USE SCHEMA OBSERVABILITY;
USE WAREHOUSE AUDIT_WH;

--------------------------------------------------------------------------------
-- SECTION A: AGENT ACTIVITY OVERVIEW
--------------------------------------------------------------------------------

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
    TOOL_USED,
    COUNT(*) as usage_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY AGENT_NAME), 2) as pct_of_agent
FROM AGENT_TOOL_USAGE
WHERE EVENT_DATE >= DATEADD('day', -30, CURRENT_DATE())
  AND TOOL_USED IS NOT NULL
GROUP BY AGENT_NAME, TOOL_USED
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

--------------------------------------------------------------------------------
-- SECTION B: USER FEEDBACK ANALYSIS
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- SECTION C: SECURITY ANALYSIS
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- SECTION D: DATA ACCESS LINEAGE
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- SECTION E: USER BEHAVIOR ANALYSIS
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- SECTION F: CORTEX FUNCTION USAGE
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- SECTION G: COMPLIANCE REPORTING QUERIES
--------------------------------------------------------------------------------

-- G1. Monthly audit summary
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

-- G2. Data access report for compliance
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

--------------------------------------------------------------------------------
-- SECTION H: INVESTIGATION TEMPLATES
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- EXPORT TEMPLATES
--------------------------------------------------------------------------------

-- Export audit data for external review
/*
COPY INTO @my_stage/audit_export/
FROM (
    SELECT * FROM USER_ACTIVITY_SUMMARY
    WHERE activity_date >= DATEADD('month', -1, CURRENT_DATE())
)
FILE_FORMAT = (TYPE = CSV HEADER = TRUE)
OVERWRITE = TRUE;
*/
