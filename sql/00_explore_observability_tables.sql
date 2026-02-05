/*
================================================================================
EXPLORE SNOWFLAKE AI OBSERVABILITY TABLES
================================================================================

These queries help you understand the structure and sample data in:
- SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS (Cortex Agent events)
- SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW (Cortex Analyst queries)

Run these to see what data is available before creating audit views.

================================================================================
ACTUAL SCHEMA (from DESCRIBE TABLE):
================================================================================

AI_OBSERVABILITY_EVENTS columns:
- TIMESTAMP               : Event timestamp (TIMESTAMP_NTZ)
- START_TIMESTAMP         : Event period starting timestamp (TIMESTAMP_NTZ)
- OBSERVED_TIMESTAMP      : Used for logs without timestamp (TIMESTAMP_NTZ)
- TRACE                   : Tracing context (OBJECT) - trace_id, span_id
- RESOURCE                : For future use (OBJECT)
- RESOURCE_ATTRIBUTES     : Source identification (OBJECT):
                            - snow.user.name, snow.user.id
                            - snow.session.id, snow.session.role.primary.name
- SCOPE                   : Scope for signals (OBJECT) - e.g., "snow.cortex.agent"
- SCOPE_ATTRIBUTES        : For future use (OBJECT)
- RECORD_TYPE             : Type of RECORD value (VARCHAR) - e.g., "SPAN"
- RECORD                  : Fixed fields per signal type (OBJECT):
                            - name, kind, status.code
- RECORD_ATTRIBUTES       : Variable attributes (OBJECT):
                            - snow.ai.observability.object.name (agent name)
                            - snow.ai.observability.object.type 
                            - snow.ai.observability.database.name
                            - snow.ai.observability.schema.name
                            - snow.ai.observability.agent.thread_id
                            - ai.observability.input_id, request_id
- VALUE                   : Primary event value (VARIANT)
- EXEMPLARS               : Exemplars for metrics (ARRAY)

================================================================================
*/

--------------------------------------------------------------------------------
-- 1. AI_OBSERVABILITY_EVENTS - See All Columns
--------------------------------------------------------------------------------

-- See recent events with all columns
SELECT * 
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
ORDER BY TIMESTAMP DESC
LIMIT 10;

-- Get column names from the table
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'LOCAL' 
  AND TABLE_NAME = 'AI_OBSERVABILITY_EVENTS'
ORDER BY ORDINAL_POSITION;

-- Count events by date
SELECT 
    DATE(TIMESTAMP) as event_date,
    COUNT(*) as event_count
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
GROUP BY DATE(TIMESTAMP)
ORDER BY event_date DESC;

--------------------------------------------------------------------------------
-- 2. AI_OBSERVABILITY_EVENTS - Explore Variant Structures
--------------------------------------------------------------------------------

-- See the keys in each variant column
SELECT 
    TIMESTAMP,
    OBJECT_KEYS(TRACE) as trace_keys,
    OBJECT_KEYS(RESOURCE_ATTRIBUTES) as resource_attr_keys,
    OBJECT_KEYS(SCOPE) as scope_keys,
    OBJECT_KEYS(RECORD) as record_keys,
    OBJECT_KEYS(RECORD_ATTRIBUTES) as record_attr_keys
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
ORDER BY TIMESTAMP DESC
LIMIT 5;

-- Extract user and session info from RESOURCE_ATTRIBUTES
SELECT 
    TIMESTAMP,
    RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as user_name,
    RESOURCE_ATTRIBUTES:"snow.user.id"::NUMBER as user_id,
    RESOURCE_ATTRIBUTES:"snow.session.id"::NUMBER as session_id,
    RESOURCE_ATTRIBUTES:"snow.session.role.primary.name"::STRING as role_name
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
ORDER BY TIMESTAMP DESC
LIMIT 20;

--------------------------------------------------------------------------------
-- 3. AI_OBSERVABILITY_EVENTS - Extract Key Fields
--------------------------------------------------------------------------------

-- Extract agent and observability details from RECORD_ATTRIBUTES
SELECT 
    TIMESTAMP,
    RECORD_TYPE,
    RECORD:"name"::STRING as span_name,
    RECORD:"kind"::STRING as span_kind,
    RECORD:"status":"code"::STRING as status_code,
    RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING as agent_name,
    RECORD_ATTRIBUTES:"snow.ai.observability.object.type"::STRING as object_type,
    RECORD_ATTRIBUTES:"snow.ai.observability.database.name"::STRING as database_name,
    RECORD_ATTRIBUTES:"snow.ai.observability.schema.name"::STRING as schema_name,
    RECORD_ATTRIBUTES:"snow.ai.observability.agent.thread_id"::NUMBER as thread_id,
    RECORD_ATTRIBUTES:"request_id"::STRING as request_id,
    RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as user_name
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
ORDER BY TIMESTAMP DESC
LIMIT 20;

-- Events by record type
SELECT 
    RECORD_TYPE,
    COUNT(*) as count
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
GROUP BY RECORD_TYPE
ORDER BY count DESC;

-- Events by span name (within RECORD)
SELECT 
    RECORD:"name"::STRING as span_name,
    COUNT(*) as count
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
GROUP BY span_name
ORDER BY count DESC;

-- Events by agent name
SELECT 
    RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING as agent_name,
    RECORD_ATTRIBUTES:"snow.ai.observability.database.name"::STRING as database_name,
    RECORD_ATTRIBUTES:"snow.ai.observability.schema.name"::STRING as schema_name,
    COUNT(*) as event_count
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
WHERE RECORD_ATTRIBUTES:"snow.ai.observability.object.type"::STRING = 'Cortex Agent'
GROUP BY 1, 2, 3
ORDER BY event_count DESC;

--------------------------------------------------------------------------------
-- 4. AI_OBSERVABILITY_EVENTS - Trace and Span Details
--------------------------------------------------------------------------------

-- Extract trace/span IDs from TRACE column
SELECT 
    TIMESTAMP,
    TRACE:"trace_id"::STRING as trace_id,
    TRACE:"span_id"::STRING as span_id,
    RECORD:"name"::STRING as span_name,
    RECORD:"kind"::STRING as span_kind,
    RECORD:"status":"code"::STRING as status_code,
    RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING as agent_name,
    RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as user_name
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
ORDER BY TIMESTAMP DESC
LIMIT 20;

-- Group events by trace_id to see full agent conversations
SELECT 
    TRACE:"trace_id"::STRING as trace_id,
    MIN(TIMESTAMP) as first_event,
    MAX(TIMESTAMP) as last_event,
    COUNT(*) as span_count,
    ARRAY_AGG(DISTINCT RECORD:"name"::STRING) as span_names,
    MAX(RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING) as agent_name,
    MAX(RESOURCE_ATTRIBUTES:"snow.user.name"::STRING) as user_name
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
GROUP BY trace_id
ORDER BY first_event DESC
LIMIT 20;

-- See spans within a specific trace
-- (Replace the trace_id value with one from your data)
SELECT 
    TIMESTAMP,
    TRACE:"span_id"::STRING as span_id,
    RECORD:"name"::STRING as span_name,
    RECORD:"kind"::STRING as span_kind,
    RECORD:"status":"code"::STRING as status_code,
    RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING as agent_name
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
WHERE TRACE:"trace_id"::STRING = '<YOUR_TRACE_ID_HERE>'
ORDER BY TIMESTAMP;

--------------------------------------------------------------------------------
-- 5. AI_OBSERVABILITY_EVENTS - Feedback Events
--------------------------------------------------------------------------------

-- Look for feedback-related span names or record types
SELECT 
    RECORD:"name"::STRING as span_name,
    RECORD_TYPE,
    COUNT(*) as count
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
WHERE LOWER(RECORD:"name"::STRING) LIKE '%feedback%'
   OR LOWER(RECORD_TYPE) LIKE '%feedback%'
GROUP BY span_name, RECORD_TYPE
ORDER BY count DESC;

-- Check RECORD_ATTRIBUTES for feedback fields
SELECT 
    TIMESTAMP,
    RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING as agent_name,
    RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as user_name,
    RECORD_ATTRIBUTES:"snow.ai.observability.agent.thread_id"::NUMBER as thread_id,
    RECORD_ATTRIBUTES:"feedback"::VARIANT as feedback_data,
    RECORD_ATTRIBUTES
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
WHERE RECORD_ATTRIBUTES:"feedback" IS NOT NULL
ORDER BY TIMESTAMP DESC
LIMIT 20;

-- Explore all distinct RECORD_ATTRIBUTES keys to find feedback fields
SELECT DISTINCT
    f.key as attribute_key
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS,
LATERAL FLATTEN(input => RECORD_ATTRIBUTES, OUTER => TRUE) f
ORDER BY attribute_key;

--------------------------------------------------------------------------------
-- 6. AI_OBSERVABILITY_EVENTS - Conversation Content
--------------------------------------------------------------------------------

-- Look for conversation/message related events
SELECT 
    TIMESTAMP,
    RECORD:"name"::STRING as span_name,
    RECORD_TYPE,
    RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING as agent_name,
    RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as user_name,
    RECORD_ATTRIBUTES:"snow.ai.observability.agent.thread_id"::NUMBER as thread_id
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
WHERE RECORD:"name"::STRING LIKE '%Agent%'
   OR RECORD:"name"::STRING LIKE '%Message%'
   OR RECORD:"name"::STRING LIKE '%Request%'
   OR RECORD:"name"::STRING LIKE '%Response%'
ORDER BY TIMESTAMP DESC
LIMIT 20;

-- Check for input/output content in RECORD_ATTRIBUTES
SELECT 
    TIMESTAMP,
    RECORD:"name"::STRING as span_name,
    RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING as agent_name,
    RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as user_name,
    RECORD_ATTRIBUTES:"ai.observability.input_id"::STRING as input_id,
    LEFT(RECORD_ATTRIBUTES:"input"::STRING, 500) as input_preview,
    LEFT(RECORD_ATTRIBUTES:"output"::STRING, 500) as output_preview
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
WHERE RECORD_ATTRIBUTES:"input" IS NOT NULL 
   OR RECORD_ATTRIBUTES:"output" IS NOT NULL
ORDER BY TIMESTAMP DESC
LIMIT 20;

-- Group by thread to see conversation flow
SELECT 
    RECORD_ATTRIBUTES:"snow.ai.observability.agent.thread_id"::NUMBER as thread_id,
    RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING as agent_name,
    RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as user_name,
    MIN(TIMESTAMP) as conversation_start,
    MAX(TIMESTAMP) as conversation_end,
    COUNT(*) as event_count,
    DATEDIFF('second', MIN(TIMESTAMP), MAX(TIMESTAMP)) as duration_seconds
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS
WHERE RECORD_ATTRIBUTES:"snow.ai.observability.agent.thread_id" IS NOT NULL
GROUP BY thread_id, agent_name, user_name
ORDER BY conversation_start DESC
LIMIT 20;

--------------------------------------------------------------------------------
-- 7. CORTEX_ANALYST_REQUESTS_RAW - Basic Structure
--------------------------------------------------------------------------------
-- NOTE: This table uses the SAME variant-based schema as AI_OBSERVABILITY_EVENTS!
-- User info in RESOURCE_ATTRIBUTES, event details in ATTRIBUTES, content in EVENT_ATTRIBUTES

-- See recent Cortex Analyst requests (all columns)
SELECT * 
FROM SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW
ORDER BY TIMESTAMP DESC
LIMIT 10;

-- Get actual column names
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'LOCAL' 
  AND TABLE_NAME = 'CORTEX_ANALYST_REQUESTS_RAW'
ORDER BY ORDINAL_POSITION;

-- Count requests by date
SELECT 
    DATE(TIMESTAMP) as request_date,
    COUNT(*) as request_count
FROM SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW
GROUP BY DATE(TIMESTAMP)
ORDER BY request_date DESC;

--------------------------------------------------------------------------------
-- 8. CORTEX_ANALYST_REQUESTS_RAW - Explore Variant Structure
--------------------------------------------------------------------------------

-- See keys in each variant column
SELECT 
    TIMESTAMP,
    OBJECT_KEYS(RESOURCE_ATTRIBUTES) as resource_attr_keys,
    OBJECT_KEYS(RECORD) as record_keys,
    OBJECT_KEYS(ATTRIBUTES) as attributes_keys
FROM SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW
ORDER BY TIMESTAMP DESC
LIMIT 5;

-- Extract user and semantic model info from RESOURCE_ATTRIBUTES
SELECT 
    TIMESTAMP,
    RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as user_name,
    RESOURCE_ATTRIBUTES:"snow.session.role.primary.name"::STRING as role_name,
    RESOURCE_ATTRIBUTES:"snow.semantic_model.name"::STRING as semantic_model_path,
    RESOURCE_ATTRIBUTES:"snow.semantic_model.type"::STRING as model_type,
    RESOURCE_ATTRIBUTES:"snow.semantic_model.tables_referenced" as tables_referenced
FROM SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW
ORDER BY TIMESTAMP DESC
LIMIT 10;

--------------------------------------------------------------------------------
-- 9. CORTEX_ANALYST_REQUESTS_RAW - Extract Request/Response Content  
--------------------------------------------------------------------------------
-- The rich content is in the EVENT_ATTRIBUTES (or last variant column)

-- Find the column name that contains generated_sql, latest_question, etc.
-- Look for a column with these nested keys
SELECT 
    TIMESTAMP,
    RECORD_TYPE,
    RECORD:"name"::STRING as event_name,
    ATTRIBUTES:"request_id"::STRING as request_id,
    ATTRIBUTES:"llm.app.type"::STRING as app_type
FROM SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW
ORDER BY TIMESTAMP DESC
LIMIT 10;

-- Try to find the column with the rich content (generated_sql, latest_question)
-- This might be EVENT_ATTRIBUTES or a similar name
-- Run this to see all columns and identify which has the content:
SELECT 
    TIMESTAMP,
    -- Try common column names for the content variant
    TRY_CAST(EVENT_ATTRIBUTES:"latest_question" AS STRING) as question_from_event_attrs,
    TRY_CAST(EVENT_ATTRIBUTES:"generated_sql" AS STRING) as sql_from_event_attrs
FROM SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW
ORDER BY TIMESTAMP DESC
LIMIT 5;

--------------------------------------------------------------------------------
-- 10. CORTEX_ANALYST_REQUESTS_RAW - Full Content Extraction
--------------------------------------------------------------------------------
-- Once you identify the correct column name, use these queries:

-- Extract the key Cortex Analyst request details
-- (Adjust EVENT_ATTRIBUTES to the actual column name if different)
SELECT 
    TIMESTAMP,
    RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as user_name,
    RESOURCE_ATTRIBUTES:"snow.semantic_model.name"::STRING as semantic_model,
    EVENT_ATTRIBUTES:"latest_question"::STRING as user_question,
    LEFT(EVENT_ATTRIBUTES:"generated_sql"::STRING, 500) as generated_sql_preview,
    EVENT_ATTRIBUTES:"response_status_code"::NUMBER as status_code,
    EVENT_ATTRIBUTES:"response_time_ms"::NUMBER as response_time_ms,
    ATTRIBUTES:"request_id"::STRING as request_id
FROM SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW
ORDER BY TIMESTAMP DESC
LIMIT 20;

-- Requests by semantic model
SELECT 
    RESOURCE_ATTRIBUTES:"snow.semantic_model.name"::STRING as semantic_model,
    COUNT(*) as request_count,
    COUNT(DISTINCT RESOURCE_ATTRIBUTES:"snow.user.name"::STRING) as unique_users,
    AVG(EVENT_ATTRIBUTES:"response_time_ms"::NUMBER) as avg_response_time_ms
FROM SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW
GROUP BY 1
ORDER BY request_count DESC;

-- Requests by user
SELECT 
    RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as user_name,
    RESOURCE_ATTRIBUTES:"snow.session.role.primary.name"::STRING as role_name,
    COUNT(*) as request_count,
    MIN(TIMESTAMP) as first_request,
    MAX(TIMESTAMP) as last_request
FROM SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW
GROUP BY 1, 2
ORDER BY request_count DESC;

--------------------------------------------------------------------------------
-- 11. CORTEX_ANALYST_REQUESTS_RAW - Response Analysis
--------------------------------------------------------------------------------

-- Analyze response quality and performance
SELECT 
    DATE(TIMESTAMP) as request_date,
    COUNT(*) as total_requests,
    AVG(EVENT_ATTRIBUTES:"response_time_ms"::NUMBER) as avg_response_ms,
    MIN(EVENT_ATTRIBUTES:"response_time_ms"::NUMBER) as min_response_ms,
    MAX(EVENT_ATTRIBUTES:"response_time_ms"::NUMBER) as max_response_ms,
    SUM(CASE WHEN EVENT_ATTRIBUTES:"response_status_code"::NUMBER = 200 THEN 1 ELSE 0 END) as successful,
    SUM(CASE WHEN EVENT_ATTRIBUTES:"response_status_code"::NUMBER != 200 THEN 1 ELSE 0 END) as failed
FROM SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW
GROUP BY request_date
ORDER BY request_date DESC;

-- Extract verified query usage (from confidence metadata)
SELECT 
    TIMESTAMP,
    RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as user_name,
    EVENT_ATTRIBUTES:"latest_question"::STRING as user_question,
    EVENT_ATTRIBUTES:"response_body":"message":"content"[1]:"confidence":"verified_query_used":"name"::STRING 
        as verified_query_name,
    EVENT_ATTRIBUTES:"response_body":"message":"content"[1]:"confidence":"verified_query_used":"question"::STRING 
        as verified_query_question
FROM SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW
WHERE EVENT_ATTRIBUTES:"response_body":"message":"content"[1]:"confidence":"verified_query_used" IS NOT NULL
ORDER BY TIMESTAMP DESC
LIMIT 20;

-- Extract Cortex Search retrievals used by Analyst
SELECT 
    TIMESTAMP,
    RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as user_name,
    EVENT_ATTRIBUTES:"latest_question"::STRING as user_question,
    f.value:"service"::STRING as search_service_used,
    f.value:"query"::STRING as search_query,
    ARRAY_SIZE(f.value:"response_body":"results") as results_count
FROM SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW,
LATERAL FLATTEN(input => EVENT_ATTRIBUTES:"response_body":"response_metadata":"cortex_search_retrieval", 
                OUTER => TRUE) f
WHERE EVENT_ATTRIBUTES:"response_body":"response_metadata":"cortex_search_retrieval" IS NOT NULL
ORDER BY TIMESTAMP DESC
LIMIT 20;

--------------------------------------------------------------------------------
-- 12. COMBINED: Cortex Agent events that used Cortex Analyst tool
--------------------------------------------------------------------------------

-- Find agent events that might involve Cortex Analyst
SELECT 
    obs.TIMESTAMP,
    obs.RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING as agent_name,
    obs.RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as user_name,
    obs.RECORD:"name"::STRING as span_name,
    obs.RECORD_ATTRIBUTES:"request_id"::STRING as request_id
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS obs
WHERE LOWER(obs.RECORD:"name"::STRING) LIKE '%analyst%'
   OR LOWER(obs.RECORD_ATTRIBUTES:"snow.ai.observability.object.type"::STRING) LIKE '%analyst%'
ORDER BY obs.TIMESTAMP DESC
LIMIT 20;

-- Join AI_OBSERVABILITY_EVENTS with CORTEX_ANALYST_REQUESTS_RAW
-- Match on user and approximate timestamp (both tables use similar schema)
SELECT 
    obs.TIMESTAMP as agent_event_time,
    car.TIMESTAMP as analyst_request_time,
    obs.RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING as agent_name,
    obs.RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as agent_user,
    car.RESOURCE_ATTRIBUTES:"snow.semantic_model.name"::STRING as semantic_model,
    LEFT(car.RECORD_ATTRIBUTES:"latest_question"::STRING, 200) as analyst_question,
    LEFT(car.RECORD_ATTRIBUTES:"generated_sql"::STRING, 300) as generated_sql
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS obs
JOIN SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW car
    ON obs.RESOURCE_ATTRIBUTES:"snow.user.name"::STRING = car.RESOURCE_ATTRIBUTES:"snow.user.name"::STRING
    AND car.TIMESTAMP BETWEEN DATEADD('minute', -5, obs.TIMESTAMP) 
                          AND DATEADD('minute', 5, obs.TIMESTAMP)
WHERE obs.RECORD_ATTRIBUTES:"snow.ai.observability.object.type"::STRING = 'Cortex Agent'
ORDER BY obs.TIMESTAMP DESC
LIMIT 20;

-- Correlate by request_id if available
SELECT 
    obs.TIMESTAMP as agent_event_time,
    car.TIMESTAMP as analyst_request_time,
    obs.RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING as agent_name,
    obs.RESOURCE_ATTRIBUTES:"snow.user.name"::STRING as user_name,
    obs.RECORD_ATTRIBUTES:"request_id"::STRING as agent_request_id,
    car.RECORD_ATTRIBUTES:"request_id"::STRING as analyst_request_id,
    car.RECORD_ATTRIBUTES:"latest_question"::STRING as analyst_question
FROM SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS obs
JOIN SNOWFLAKE.LOCAL.CORTEX_ANALYST_REQUESTS_RAW car
    ON obs.RECORD_ATTRIBUTES:"request_id"::STRING = car.RECORD_ATTRIBUTES:"request_id"::STRING
WHERE obs.RECORD_ATTRIBUTES:"snow.ai.observability.object.type"::STRING = 'Cortex Agent'
ORDER BY obs.TIMESTAMP DESC
LIMIT 20;

--------------------------------------------------------------------------------
-- NOTES
--------------------------------------------------------------------------------
/*
================================================================================
ACTUAL SCHEMA (from DESCRIBE TABLE)
================================================================================

1. AI_OBSERVABILITY_EVENTS columns:
   ─────────────────────────────────
   - TIMESTAMP               : Event timestamp (TIMESTAMP_NTZ)
   - START_TIMESTAMP         : Event period starting timestamp (TIMESTAMP_NTZ)
   - OBSERVED_TIMESTAMP      : Used for logs without timestamp (TIMESTAMP_NTZ)
   - TRACE                   : Tracing context (OBJECT) - trace_id, span_id
   - RESOURCE                : For future use (OBJECT)
   - RESOURCE_ATTRIBUTES     : Source identification (OBJECT):
       * "snow.user.name", "snow.user.id"
       * "snow.session.id", "snow.session.role.primary.name"
   - SCOPE                   : Scope for signals (OBJECT)
   - SCOPE_ATTRIBUTES        : For future use (OBJECT)
   - RECORD_TYPE             : Type of RECORD value (VARCHAR) - e.g., "SPAN"
   - RECORD                  : Fixed fields per signal type (OBJECT):
       * "name" (e.g., "Agent")
       * "kind" (e.g., "SPAN_KIND_INTERNAL")
       * "status" -> "code" (e.g., "STATUS_CODE_OK")
   - RECORD_ATTRIBUTES       : Variable attributes (OBJECT):
       * "snow.ai.observability.object.name" (agent name)
       * "snow.ai.observability.object.type" (e.g., "Cortex Agent")
       * "snow.ai.observability.database.name"
       * "snow.ai.observability.schema.name"
       * "snow.ai.observability.agent.thread_id"
       * "ai.observability.input_id", "request_id"
   - VALUE                   : Primary event value (VARIANT)
   - EXEMPLARS               : Exemplars for metrics (ARRAY)

2. CORTEX_ANALYST_REQUESTS_RAW columns:
   ────────────────────────────────────
   (Run DESCRIBE TABLE to confirm exact column names)
   - TIMESTAMP               : Request timestamp
   - RESOURCE_ATTRIBUTES     : Variant with semantic model & user info:
       * "snow.user.name", "snow.user.id"
       * "snow.session.id", "snow.session.role.primary.name"
       * "snow.semantic_model.name" (e.g., "@DB.SCHEMA.FILE/model.yaml")
       * "snow.semantic_model.hash"
       * "snow.semantic_model.tables_referenced" (array)
   - RECORD_TYPE             : String ("EVENT")
   - RECORD                  : Variant with event name
   - RECORD_ATTRIBUTES       : Variant with rich content (may vary):
       * "latest_question" - User's natural language question
       * "generated_sql" - SQL that Cortex Analyst produced
       * "response_status_code" (200 = success)
       * "response_time_ms" - Latency in milliseconds
       * "response_body" -> message -> content[]
       * "response_body" -> response_metadata

3. KEY EXTRACTION PATHS:
   ─────────────────────
   AI_OBSERVABILITY_EVENTS:
   - User name:   RESOURCE_ATTRIBUTES:"snow.user.name"::STRING
   - Agent name:  RECORD_ATTRIBUTES:"snow.ai.observability.object.name"::STRING
   - Thread ID:   RECORD_ATTRIBUTES:"snow.ai.observability.agent.thread_id"::NUMBER
   - Trace ID:    TRACE:"trace_id"::STRING
   - Span ID:     TRACE:"span_id"::STRING
   - Span name:   RECORD:"name"::STRING
   - Status:      RECORD:"status":"code"::STRING

   CORTEX_ANALYST_REQUESTS_RAW:
   - User name:      RESOURCE_ATTRIBUTES:"snow.user.name"::STRING
   - Semantic model: RESOURCE_ATTRIBUTES:"snow.semantic_model.name"::STRING
   - Question:       RECORD_ATTRIBUTES:"latest_question"::STRING
   - Generated SQL:  RECORD_ATTRIBUTES:"generated_sql"::STRING
   - Response time:  RECORD_ATTRIBUTES:"response_time_ms"::NUMBER
   - Status code:    RECORD_ATTRIBUTES:"response_status_code"::NUMBER
   - Request ID:     RECORD_ATTRIBUTES:"request_id"::STRING

4. TO SEE DATA, YOU NEED:
   - Active Cortex Agents with observability enabled
   - Users interacting with agents or Cortex Analyst
   - MONITOR privilege on the agents/objects
   - AI Observability enabled (default for new agents)

*/
