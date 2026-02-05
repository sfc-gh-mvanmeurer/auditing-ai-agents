/*
================================================================================
AUDITING AI AGENTS IN SNOWFLAKE
Script 03: The Auditor Agent
================================================================================

This script creates an AI-powered Auditor Agent that helps human auditors
investigate agent behavior using natural language queries.

The Auditor Agent combines:
- Cortex Analyst: Query metrics and patterns via Semantic Views
- Cortex Search: Find specific conversations and policies

Prerequisites:
- Run 00, 01, 02 scripts first
- Cortex Agents enabled on your account

Reference: https://docs.snowflake.com/en/user-guide/views-semantic/sql

================================================================================
*/

USE ROLE ACCOUNTADMIN;
USE DATABASE AGENT_AUDIT;
USE WAREHOUSE AUDIT_WH;

--------------------------------------------------------------------------------
-- 1. CREATE SEMANTIC VIEWS FOR CORTEX ANALYST
--------------------------------------------------------------------------------
-- Semantic Views provide structured metadata that enables natural language
-- queries via Cortex Analyst without requiring a separate YAML file.

-- ============================================================================
-- Semantic View 1: Agent Activity Analytics
-- ============================================================================
-- For analyzing agent events, spans, and overall activity patterns

CREATE OR REPLACE SEMANTIC VIEW OBSERVABILITY.AGENT_ACTIVITY_ANALYTICS

  TABLES (
    agent_events AS AGENT_AUDIT.OBSERVABILITY.AGENT_EVENTS_FLATTENED
      PRIMARY KEY (TRACE_ID, SPAN_ID)
      COMMENT = 'Flattened Cortex Agent events from AI Observability'
  )

  FACTS (
    agent_events.duration_ms AS SPAN_DURATION_MS
      COMMENT = 'Duration of the span or operation in milliseconds',
    agent_events.thread_id AS THREAD_ID
      COMMENT = 'Conversation thread identifier'
  )

  DIMENSIONS (
    agent_events.agent_name AS AGENT_NAME
      COMMENT = 'Name of the Cortex Agent',
    agent_events.agent_database AS AGENT_DATABASE
      COMMENT = 'Database where agent is deployed',
    agent_events.agent_schema AS AGENT_SCHEMA
      COMMENT = 'Schema where agent is deployed',
    agent_events.user_name AS USER_NAME
      COMMENT = 'User who invoked the agent',
    agent_events.role_name AS ROLE_NAME
      COMMENT = 'Role used for agent invocation',
    agent_events.record_type AS RECORD_TYPE
      COMMENT = 'Type of observability record span or log',
    agent_events.span_name AS SPAN_NAME
      COMMENT = 'Name of the span or operation like Agent or tool_call',
    agent_events.span_kind AS SPAN_KIND
      COMMENT = 'Kind of span internal or server',
    agent_events.status_code AS STATUS_CODE
      COMMENT = 'Execution status OK or ERROR',
    agent_events.event_date AS EVENT_DATE
      COMMENT = 'Date of the event',
    agent_events.event_hour AS EVENT_HOUR
      COMMENT = 'Hour of the event for time analysis',
    agent_events.feedback_sentiment AS FEEDBACK_SENTIMENT
      COMMENT = 'User feedback POSITIVE NEGATIVE or null',
    agent_events.trace_id AS TRACE_ID
      COMMENT = 'Unique trace identifier',
    agent_events.span_id AS SPAN_ID
      COMMENT = 'Unique span identifier within trace'
  )

  METRICS (
    agent_events.total_events AS COUNT(*)
      COMMENT = 'Total number of agent events',
    agent_events.unique_threads AS COUNT(DISTINCT THREAD_ID)
      COMMENT = 'Number of unique conversation threads',
    agent_events.unique_users AS COUNT(DISTINCT USER_NAME)
      COMMENT = 'Number of unique users',
    agent_events.unique_traces AS COUNT(DISTINCT TRACE_ID)
      COMMENT = 'Number of unique traces or requests',
    agent_events.avg_duration_ms AS AVG(SPAN_DURATION_MS)
      COMMENT = 'Average span duration in milliseconds',
    agent_events.max_duration_ms AS MAX(SPAN_DURATION_MS)
      COMMENT = 'Maximum span duration in milliseconds',
    agent_events.error_count AS COUNT_IF(STATUS_CODE = 'ERROR')
      COMMENT = 'Number of events with error status',
    agent_events.success_count AS COUNT_IF(STATUS_CODE = 'OK')
      COMMENT = 'Number of events with success status',
    agent_events.positive_feedback AS COUNT_IF(FEEDBACK_SENTIMENT = 'POSITIVE')
      COMMENT = 'Number of positive feedback events',
    agent_events.negative_feedback AS COUNT_IF(FEEDBACK_SENTIMENT = 'NEGATIVE')
      COMMENT = 'Number of negative feedback events'
  )

  COMMENT = 'Agent activity analytics for monitoring Cortex Agent events and performance';

-- Grant access
GRANT REFERENCES, SELECT ON SEMANTIC VIEW OBSERVABILITY.AGENT_ACTIVITY_ANALYTICS 
    TO ROLE AGENT_AUDIT_VIEWER;
GRANT REFERENCES, SELECT ON SEMANTIC VIEW OBSERVABILITY.AGENT_ACTIVITY_ANALYTICS 
    TO ROLE AGENT_AUDIT_ADMIN;

-- ============================================================================
-- Semantic View 2: Agent Feedback Analytics
-- ============================================================================
-- For analyzing user satisfaction and feedback patterns

CREATE OR REPLACE SEMANTIC VIEW OBSERVABILITY.AGENT_FEEDBACK_ANALYTICS

  TABLES (
    feedback AS AGENT_AUDIT.OBSERVABILITY.AGENT_FEEDBACK_SUMMARY
      PRIMARY KEY (AGENT_NAME, EVENT_DATE)
      COMMENT = 'Daily aggregated feedback metrics per agent'
  )

  FACTS (
    feedback.total AS TOTAL_FEEDBACK
      COMMENT = 'Total feedback count for the day',
    feedback.positive AS POSITIVE_COUNT
      COMMENT = 'Number of positive feedback ratings',
    feedback.negative AS NEGATIVE_COUNT
      COMMENT = 'Number of negative feedback ratings',
    feedback.positive_pct AS POSITIVE_RATE_PCT
      COMMENT = 'Percentage of positive feedback',
    feedback.negative_pct AS NEGATIVE_RATE_PCT
      COMMENT = 'Percentage of negative feedback'
  )

  DIMENSIONS (
    feedback.agent_name AS AGENT_NAME
      COMMENT = 'Name of the Cortex Agent',
    feedback.agent_database AS AGENT_DATABASE
      COMMENT = 'Database where agent is deployed',
    feedback.agent_schema AS AGENT_SCHEMA
      COMMENT = 'Schema where agent is deployed',
    feedback.event_date AS EVENT_DATE
      COMMENT = 'Date of feedback'
  )

  METRICS (
    feedback.total_feedback_all AS SUM(TOTAL_FEEDBACK)
      COMMENT = 'Sum of all feedback across period',
    feedback.total_positive AS SUM(POSITIVE_COUNT)
      COMMENT = 'Sum of positive feedback across period',
    feedback.total_negative AS SUM(NEGATIVE_COUNT)
      COMMENT = 'Sum of negative feedback across period',
    feedback.avg_positive_rate AS AVG(POSITIVE_RATE_PCT)
      COMMENT = 'Average positive feedback rate',
    feedback.days_with_feedback AS COUNT(DISTINCT EVENT_DATE)
      COMMENT = 'Number of days with feedback data'
  )

  COMMENT = 'Agent feedback analytics for monitoring user satisfaction';

-- Grant access
GRANT REFERENCES, SELECT ON SEMANTIC VIEW OBSERVABILITY.AGENT_FEEDBACK_ANALYTICS 
    TO ROLE AGENT_AUDIT_VIEWER;
GRANT REFERENCES, SELECT ON SEMANTIC VIEW OBSERVABILITY.AGENT_FEEDBACK_ANALYTICS 
    TO ROLE AGENT_AUDIT_ADMIN;

-- ============================================================================
-- Semantic View 3: Agent Conversation Analytics
-- ============================================================================
-- For analyzing conversation patterns and content

CREATE OR REPLACE SEMANTIC VIEW OBSERVABILITY.AGENT_CONVERSATION_ANALYTICS

  TABLES (
    conversations AS AGENT_AUDIT.OBSERVABILITY.AGENT_CONVERSATIONS
      PRIMARY KEY (TRACE_ID)
      COMMENT = 'Agent conversations with user queries and responses'
  )

  FACTS (
    conversations.response_time AS RESPONSE_TIME_MS
      COMMENT = 'Response generation time in milliseconds',
    conversations.thread_id AS THREAD_ID
      COMMENT = 'Conversation thread identifier'
  )

  DIMENSIONS (
    conversations.agent_name AS AGENT_NAME
      COMMENT = 'Name of the Cortex Agent',
    conversations.user_name AS USER_NAME
      COMMENT = 'User who initiated the conversation',
    conversations.role_name AS ROLE_NAME
      COMMENT = 'Role used for the conversation',
    conversations.event_date AS EVENT_DATE
      COMMENT = 'Date of the conversation',
    conversations.span_name AS SPAN_NAME
      COMMENT = 'Type of conversation span',
    conversations.status_code AS STATUS_CODE
      COMMENT = 'Execution status of the response',
    conversations.feedback_sentiment AS FEEDBACK_SENTIMENT
      COMMENT = 'User feedback POSITIVE NEGATIVE or null',
    conversations.trace_id AS TRACE_ID
      COMMENT = 'Unique conversation trace identifier'
  )

  METRICS (
    conversations.total_conversations AS COUNT(*)
      COMMENT = 'Total number of conversations',
    conversations.unique_users AS COUNT(DISTINCT USER_NAME)
      COMMENT = 'Number of unique users',
    conversations.unique_threads AS COUNT(DISTINCT THREAD_ID)
      COMMENT = 'Number of unique conversation threads',
    conversations.avg_response_time AS AVG(RESPONSE_TIME_MS)
      COMMENT = 'Average response time in milliseconds',
    conversations.positive_conversations AS COUNT_IF(FEEDBACK_SENTIMENT = 'POSITIVE')
      COMMENT = 'Conversations with positive feedback',
    conversations.negative_conversations AS COUNT_IF(FEEDBACK_SENTIMENT = 'NEGATIVE')
      COMMENT = 'Conversations with negative feedback',
    conversations.error_conversations AS COUNT_IF(STATUS_CODE = 'ERROR')
      COMMENT = 'Conversations that resulted in errors'
  )

  COMMENT = 'Agent conversation analytics for analyzing user interactions';

-- Grant access
GRANT REFERENCES, SELECT ON SEMANTIC VIEW OBSERVABILITY.AGENT_CONVERSATION_ANALYTICS 
    TO ROLE AGENT_AUDIT_VIEWER;
GRANT REFERENCES, SELECT ON SEMANTIC VIEW OBSERVABILITY.AGENT_CONVERSATION_ANALYTICS 
    TO ROLE AGENT_AUDIT_ADMIN;

-- ============================================================================
-- Semantic View 4: Cortex Analyst Usage Analytics
-- ============================================================================
-- For analyzing Cortex Analyst request patterns

CREATE OR REPLACE SEMANTIC VIEW OBSERVABILITY.CORTEX_ANALYST_ANALYTICS

  TABLES (
    analyst AS AGENT_AUDIT.OBSERVABILITY.CORTEX_ANALYST_REQUESTS_FLATTENED
      PRIMARY KEY (REQUEST_ID)
      COMMENT = 'Cortex Analyst requests and SQL generation metrics'
  )

  FACTS (
    analyst.response_time AS RESPONSE_TIME_MS
      COMMENT = 'Response generation time in milliseconds',
    analyst.sql_length AS SQL_LENGTH
      COMMENT = 'Length of generated SQL in characters',
    analyst.table_count AS TABLE_COUNT
      COMMENT = 'Number of tables referenced in the query'
  )

  DIMENSIONS (
    analyst.semantic_model AS SEMANTIC_MODEL_PATH
      COMMENT = 'Path to the semantic model used',
    analyst.user_name AS USER_NAME
      COMMENT = 'User who made the request',
    analyst.role_name AS ROLE_NAME
      COMMENT = 'Role used for the request',
    analyst.request_date AS REQUEST_DATE
      COMMENT = 'Date of the request',
    analyst.request_hour AS REQUEST_HOUR
      COMMENT = 'Hour of the request',
    analyst.used_verified AS USED_VERIFIED_QUERY
      COMMENT = 'Whether a verified query was matched',
    analyst.verified_query_name AS VERIFIED_QUERY_NAME
      COMMENT = 'Name of the verified query if matched',
    analyst.request_status AS REQUEST_STATUS
      COMMENT = 'SUCCESS or FAILED status',
    analyst.question_category AS QUESTION_CATEGORY
      COMMENT = 'Category of the user question',
    analyst.request_id AS REQUEST_ID
      COMMENT = 'Unique request identifier'
  )

  METRICS (
    analyst.total_requests AS COUNT(*)
      COMMENT = 'Total number of Analyst requests',
    analyst.unique_users AS COUNT(DISTINCT USER_NAME)
      COMMENT = 'Number of unique users',
    analyst.successful_requests AS COUNT_IF(REQUEST_STATUS = 'SUCCESS')
      COMMENT = 'Number of successful requests',
    analyst.failed_requests AS COUNT_IF(REQUEST_STATUS = 'FAILED')
      COMMENT = 'Number of failed requests',
    analyst.verified_query_hits AS COUNT_IF(USED_VERIFIED_QUERY = TRUE)
      COMMENT = 'Number of times verified queries were matched',
    analyst.avg_response_time AS AVG(RESPONSE_TIME_MS)
      COMMENT = 'Average response generation time in milliseconds',
    analyst.avg_sql_length AS AVG(SQL_LENGTH)
      COMMENT = 'Average length of generated SQL'
  )

  COMMENT = 'Cortex Analyst usage analytics for monitoring semantic model queries';

-- Grant access
GRANT REFERENCES, SELECT ON SEMANTIC VIEW OBSERVABILITY.CORTEX_ANALYST_ANALYTICS 
    TO ROLE AGENT_AUDIT_VIEWER;
GRANT REFERENCES, SELECT ON SEMANTIC VIEW OBSERVABILITY.CORTEX_ANALYST_ANALYTICS 
    TO ROLE AGENT_AUDIT_ADMIN;

-- ============================================================================
-- Verify Semantic Views Created
-- ============================================================================

SELECT 'Verifying semantic views...' AS status;

SHOW SEMANTIC VIEWS IN SCHEMA AGENT_AUDIT.OBSERVABILITY;

-- Test that underlying views have data
SELECT 'AGENT_EVENTS_FLATTENED' AS source_view, COUNT(*) AS row_count 
FROM AGENT_AUDIT.OBSERVABILITY.AGENT_EVENTS_FLATTENED;

SELECT 'AGENT_CONVERSATIONS' AS source_view, COUNT(*) AS row_count 
FROM AGENT_AUDIT.OBSERVABILITY.AGENT_CONVERSATIONS;

SELECT 'AGENT_FEEDBACK_SUMMARY' AS source_view, COUNT(*) AS row_count 
FROM AGENT_AUDIT.OBSERVABILITY.AGENT_FEEDBACK_SUMMARY;

--------------------------------------------------------------------------------
-- 2. CREATE THE AUDITOR AGENT
--------------------------------------------------------------------------------
-- Uses Semantic Views for Cortex Analyst and Cortex Search services
-- Reference: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage


-- NOTE: Uncomment after Semantic Views and Search services are created and have data

CREATE OR REPLACE AGENT AGENT_AUDIT.CORTEX.AGENT_AUDITOR
    COMMENT = 'AI-assisted auditor for Cortex Agent governance and compliance'
    PROFILE = '{
        "display_name": "Agent Auditor Assistant",
        "avatar": "🔍",
        "color": "#1E40AF"
    }'
    FROM SPECIFICATION
$$
models:
  orchestration: claude-4-sonnet

orchestration:
  budget:
    seconds: 60
    tokens: 32000

instructions:
  system: |
    You are an AI Compliance Auditor Assistant helping human auditors investigate 
    agent behavior, data access patterns, and policy compliance in Snowflake.
    
    IMPORTANT: You AUGMENT human auditors - you do not replace their judgment. 
    Present evidence and analysis; let humans make compliance determinations.
    
    You can analyze:
    - Agent activity metrics: event counts, error rates, durations
    - User feedback patterns: satisfaction scores, positive/negative rates
    - Conversation patterns: response times, thread analysis
    - Cortex Analyst usage: query patterns, verified query hits
    - Conversation content: search for specific interactions
    - Compliance policies: find relevant policy documents
    - Past audit notes: learn from previous investigations

  orchestration: |
    Tool Selection Guidelines:
    
    1. For QUANTITATIVE queries (counts, averages, trends, filtering):
       - Use AgentActivityAnalyst for agent events, error rates, durations
       - Use AgentFeedbackAnalyst for satisfaction metrics, feedback rates
       - Use ConversationAnalyst for conversation patterns, response times
       - Use AnalystUsageAnalyst for Cortex Analyst query patterns
    
    2. For CONTENT SEARCH queries (find specific text, notes, policies):
       - Use ConversationSearch for finding specific agent conversations
       - Use PolicySearch for compliance policies and procedures
       - Use AuditNotesSearch for past audit findings and investigations
    
    3. For VISUALIZATION requests:
       - Use data_to_chart to generate charts from query results
    
    Multi-tool coordination:
    - For activity summaries: query AgentActivityAnalyst + AgentFeedbackAnalyst
    - For investigations: search conversations first, then get metrics
    - For compliance checks: search PolicySearch, compare with conversation data

  response: |
    Response Guidelines:
    
    ALWAYS:
    - Lead with the direct answer - don't make auditors dig
    - Cite specific data sources and query results
    - Include date ranges for any metrics reported
    - Flag if data seems incomplete or unusual
    - Suggest follow-up questions the auditor might want to ask
    - Distinguish between facts (from data) and interpretations
    - Provide thread IDs for human follow-up
    
    NEVER:
    - Make definitive compliance determinations (that's the human's job)
    - Recommend disciplinary actions against users
    - Access data outside the audit scope
    - Speculate about user intent without evidence
    - Minimize or dismiss potential security concerns
    
    When Findings Suggest Policy Violations:
    1. State what the data shows (with sources and timestamps)
    2. Cite which policy may be relevant
    3. Suggest what additional information might clarify
    4. Recommend human review for final determination

  sample_questions:
    - question: "Show me agent activity summary for last week"
      answer: "I'll query agent events for total counts, error rates, and feedback metrics over the past 7 days."
    - question: "Which agents have the lowest satisfaction scores?"
      answer: "I'll analyze feedback data grouped by agent, ordered by positive feedback rate."
    - question: "Find conversations where users mentioned denied access"
      answer: "I'll search conversation content for access denial mentions and return relevant threads."
    - question: "What are our data retention policies?"
      answer: "I'll search the compliance policy documents for data retention requirements."
    - question: "Have we seen suspicious activity patterns before?"
      answer: "I'll search past audit notes for similar patterns and previous findings."

tools:
  # Cortex Analyst tools for structured data via Semantic Views
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: AgentActivityAnalyst
      description: "Analyzes Cortex Agent events including event counts, error rates, span durations, and activity patterns. Use for questions about agent usage, performance, and operational metrics."
  
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: AgentFeedbackAnalyst
      description: "Analyzes user feedback for agents including positive/negative rates, satisfaction trends, and feedback patterns. Use for questions about user satisfaction and agent quality."
  
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: ConversationAnalyst
      description: "Analyzes agent conversation patterns including response times, conversation counts, and thread analysis. Use for questions about conversation volume and performance."
  
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: AnalystUsageAnalyst
      description: "Analyzes Cortex Analyst usage including query patterns, verified query hits, and response times. Use for questions about how Cortex Analyst is being used."

  # Cortex Search tools for unstructured content search
  - tool_spec:
      type: cortex_search
      name: ConversationSearch
      description: "Search agent conversation content by keywords, user queries, or agent responses. Use to find specific interactions or investigate conversation content."
  
  - tool_spec:
      type: cortex_search
      name: PolicySearch
      description: "Search compliance policies, procedures, and guidelines. Use when user asks about policy requirements or compliance questions."
  
  - tool_spec:
      type: cortex_search
      name: AuditNotesSearch
      description: "Search past audit notes, findings, and investigation records. Use to find historical context or similar past cases."

  # Visualization tool
  - tool_spec:
      type: data_to_chart
      name: data_to_chart
      description: "Generate visualizations from data. Use when query results would benefit from a chart or graph."

tool_resources:
  AgentActivityAnalyst:
    semantic_view: AGENT_AUDIT.OBSERVABILITY.AGENT_ACTIVITY_ANALYTICS
  
  AgentFeedbackAnalyst:
    semantic_view: AGENT_AUDIT.OBSERVABILITY.AGENT_FEEDBACK_ANALYTICS
  
  ConversationAnalyst:
    semantic_view: AGENT_AUDIT.OBSERVABILITY.AGENT_CONVERSATION_ANALYTICS
  
  AnalystUsageAnalyst:
    semantic_view: AGENT_AUDIT.OBSERVABILITY.CORTEX_ANALYST_ANALYTICS
  
  ConversationSearch:
    name: AGENT_AUDIT.CORTEX.AGENT_CONVERSATION_SEARCH
    max_results: 10
    title_column: AGENT_NAME
    id_column: THREAD_ID
  
  PolicySearch:
    name: AGENT_AUDIT.CORTEX.COMPLIANCE_POLICY_SEARCH
    max_results: 5
    title_column: POLICY_NAME
    id_column: POLICY_ID
  
  AuditNotesSearch:
    name: AGENT_AUDIT.CORTEX.AUDIT_NOTES_SEARCH
    max_results: 10
    title_column: INVESTIGATION_ID
    id_column: INVESTIGATION_ID
$$;

-- Grant usage on the auditor agent
GRANT USAGE ON AGENT AGENT_AUDIT.CORTEX.AGENT_AUDITOR TO ROLE AGENT_AUDIT_VIEWER;
GRANT USAGE ON AGENT AGENT_AUDIT.CORTEX.AGENT_AUDITOR TO ROLE AGENT_AUDIT_ADMIN;


-- Verify agent creation (uncomment after creating agent)
SHOW AGENTS IN SCHEMA AGENT_AUDIT.CORTEX;
DESCRIBE AGENT AGENT_AUDIT.CORTEX.AGENT_AUDITOR;

/*
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
