/*
================================================================================
AUDITING AI AGENTS IN SNOWFLAKE
Script 00: Database and Role Setup
================================================================================

This script creates the foundational infrastructure for AI agent auditing:
- AGENT_AUDIT database and schemas
- Roles with appropriate permissions
- Grants for accessing observability data

Prerequisites:
- ACCOUNTADMIN role
- Cortex features enabled on your account

Usage:
  snowsql -f 00_setup_database.sql

================================================================================
*/

-- Use ACCOUNTADMIN for initial setup
USE ROLE ACCOUNTADMIN;

--------------------------------------------------------------------------------
-- 1. CREATE DATABASE AND SCHEMAS
--------------------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS AGENT_AUDIT
    COMMENT = 'Database for AI agent auditing and observability';

USE DATABASE AGENT_AUDIT;

-- Schema for observability views and data
CREATE SCHEMA IF NOT EXISTS OBSERVABILITY
    COMMENT = 'Views and tables for agent observability data';

-- Schema for reference data (policies, guidelines)
CREATE SCHEMA IF NOT EXISTS REFERENCE
    COMMENT = 'Reference data for compliance and policies';

-- Schema for Cortex services
CREATE SCHEMA IF NOT EXISTS CORTEX
    COMMENT = 'Cortex Analyst and Search services for auditing';

--------------------------------------------------------------------------------
-- 2. CREATE WAREHOUSE
--------------------------------------------------------------------------------

CREATE WAREHOUSE IF NOT EXISTS AUDIT_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    COMMENT = 'Warehouse for audit queries and Cortex services';

--------------------------------------------------------------------------------
-- 3. CREATE ROLES
--------------------------------------------------------------------------------

-- Role for users who can view audit data
CREATE ROLE IF NOT EXISTS AGENT_AUDIT_VIEWER
    COMMENT = 'Can view agent audit data and run queries';

-- Role for users who can manage audit infrastructure
CREATE ROLE IF NOT EXISTS AGENT_AUDIT_ADMIN
    COMMENT = 'Can manage audit infrastructure and delete data';

-- Role hierarchy
GRANT ROLE AGENT_AUDIT_VIEWER TO ROLE AGENT_AUDIT_ADMIN;
GRANT ROLE AGENT_AUDIT_ADMIN TO ROLE ACCOUNTADMIN;

--------------------------------------------------------------------------------
-- 4. GRANT DATABASE AND SCHEMA PERMISSIONS
--------------------------------------------------------------------------------

-- Viewer permissions
GRANT USAGE ON DATABASE AGENT_AUDIT TO ROLE AGENT_AUDIT_VIEWER;
GRANT USAGE ON ALL SCHEMAS IN DATABASE AGENT_AUDIT TO ROLE AGENT_AUDIT_VIEWER;
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE AGENT_AUDIT TO ROLE AGENT_AUDIT_VIEWER;
GRANT SELECT ON ALL TABLES IN DATABASE AGENT_AUDIT TO ROLE AGENT_AUDIT_VIEWER;
GRANT SELECT ON FUTURE TABLES IN DATABASE AGENT_AUDIT TO ROLE AGENT_AUDIT_VIEWER;
GRANT SELECT ON ALL VIEWS IN DATABASE AGENT_AUDIT TO ROLE AGENT_AUDIT_VIEWER;
GRANT SELECT ON FUTURE VIEWS IN DATABASE AGENT_AUDIT TO ROLE AGENT_AUDIT_VIEWER;

-- Admin permissions
GRANT ALL PRIVILEGES ON DATABASE AGENT_AUDIT TO ROLE AGENT_AUDIT_ADMIN;
GRANT ALL PRIVILEGES ON ALL SCHEMAS IN DATABASE AGENT_AUDIT TO ROLE AGENT_AUDIT_ADMIN;

-- Warehouse permissions
GRANT USAGE ON WAREHOUSE AUDIT_WH TO ROLE AGENT_AUDIT_VIEWER;
GRANT USAGE ON WAREHOUSE AUDIT_WH TO ROLE AGENT_AUDIT_ADMIN;

--------------------------------------------------------------------------------
-- 5. GRANT CORTEX AND OBSERVABILITY PERMISSIONS
--------------------------------------------------------------------------------

-- Required for viewing agent logs
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE AGENT_AUDIT_VIEWER;
GRANT APPLICATION ROLE SNOWFLAKE.AI_OBSERVABILITY_EVENTS_LOOKUP TO ROLE AGENT_AUDIT_VIEWER;

-- Admin can delete observability data
GRANT APPLICATION ROLE SNOWFLAKE.AI_OBSERVABILITY_ADMIN TO ROLE AGENT_AUDIT_ADMIN;

--------------------------------------------------------------------------------
-- 6. GRANT ACCOUNT_USAGE ACCESS
--------------------------------------------------------------------------------

-- Import ACCOUNT_USAGE share for query/access history
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE AGENT_AUDIT_VIEWER;

--------------------------------------------------------------------------------
-- 7. GRANT MONITOR ON AGENTS (Customize for your agents)
--------------------------------------------------------------------------------

-- Example: Grant monitor on a specific agent
-- Uncomment and modify for your agents:

-- GRANT MONITOR ON AGENT YOUR_DB.YOUR_SCHEMA.YOUR_AGENT_NAME 
--     TO ROLE AGENT_AUDIT_VIEWER;

-- Grant monitor on all future agents in a schema:
-- GRANT MONITOR ON FUTURE AGENTS IN SCHEMA YOUR_DB.YOUR_SCHEMA 
--     TO ROLE AGENT_AUDIT_VIEWER;

--------------------------------------------------------------------------------
-- 8. CREATE REFERENCE TABLES
--------------------------------------------------------------------------------

USE SCHEMA REFERENCE;

-- Table for compliance policies (populate with your policies)
CREATE TABLE IF NOT EXISTS COMPLIANCE_POLICIES (
    policy_id VARCHAR(50) PRIMARY KEY,
    policy_name VARCHAR(200) NOT NULL,
    policy_category VARCHAR(100),
    policy_text TEXT,
    effective_date DATE,
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Compliance policies for agent behavior auditing';

-- Table for audit notes (investigators can log findings)
CREATE TABLE IF NOT EXISTS AUDIT_NOTES (
    note_id VARCHAR(50) DEFAULT UUID_STRING() PRIMARY KEY,
    investigation_id VARCHAR(100),
    agent_name VARCHAR(200),
    thread_id VARCHAR(200),
    auditor_name VARCHAR(100),
    note_text TEXT,
    severity VARCHAR(20) DEFAULT 'INFO',  -- INFO, WARNING, CRITICAL
    created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Audit notes and investigation findings';

-- Insert sample compliance policies
INSERT INTO COMPLIANCE_POLICIES (policy_id, policy_name, policy_category, policy_text, effective_date)
VALUES
('POL-001', 'Data Access Boundaries', 'Security', 
 'Agents must only access data within the user''s authorized scope. Row-level security and role-based access control must be enforced at the platform level.', 
 '2024-01-01'),
('POL-002', 'PII Handling', 'Privacy',
 'Protected Health Information (PHI) and Personally Identifiable Information (PII) must be stripped from agent context. Agents must not include SSN, DOB, or patient names in responses.',
 '2024-01-01'),
('POL-003', 'Prompt Injection Response', 'Security',
 'Agents must refuse requests that attempt to override system instructions. All such attempts must be logged for security review.',
 '2024-01-01'),
('POL-004', 'Citation Requirements', 'Accountability',
 'All quantitative claims must cite their data source and freshness date. Agents must not generate statistics without grounding in tool results.',
 '2024-01-01'),
('POL-005', 'Escalation Thresholds', 'Governance',
 'Findings with risk scores above 85 must include a disclaimer requiring human review. Agents must not make definitive fraud determinations.',
 '2024-01-01');

--------------------------------------------------------------------------------
-- 9. VERIFICATION QUERIES
--------------------------------------------------------------------------------

-- Verify setup
SELECT 'Database created' as status, DATABASE_NAME 
FROM INFORMATION_SCHEMA.DATABASES 
WHERE DATABASE_NAME = 'AGENT_AUDIT';

SELECT 'Schemas created' as status, SCHEMA_NAME 
FROM AGENT_AUDIT.INFORMATION_SCHEMA.SCHEMATA;

SELECT 'Roles created' as status, NAME as role_name
FROM SNOWFLAKE.ACCOUNT_USAGE.ROLES 
WHERE NAME IN ('AGENT_AUDIT_VIEWER', 'AGENT_AUDIT_ADMIN')
  AND DELETED_ON IS NULL;

SELECT 'Policies loaded' as status, COUNT(*) as policy_count
FROM AGENT_AUDIT.REFERENCE.COMPLIANCE_POLICIES;

--------------------------------------------------------------------------------
-- NEXT STEPS
--------------------------------------------------------------------------------
/*
1. Run 01_create_audit_views.sql to create views over observability data
2. Grant MONITOR on your specific agents (see section 7)
3. Assign AGENT_AUDIT_VIEWER role to your auditors:
   
   GRANT ROLE AGENT_AUDIT_VIEWER TO USER your_auditor_username;

*/
