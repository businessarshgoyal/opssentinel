-- OpsSentinel: account setup.
-- Creates the role, warehouse, database, schemas, stage, and file formats that
-- every later script depends on. Run this once as a role that can create
-- databases and warehouses (ACCOUNTADMIN or an equivalent custom admin role).

USE ROLE ACCOUNTADMIN;

-- Dedicated role so the demo stays isolated and easy to clean up.
CREATE ROLE IF NOT EXISTS OPSSENTINEL_ROLE;
GRANT ROLE OPSSENTINEL_ROLE TO ROLE SYSADMIN;

-- Grants required for Cortex AISQL, Cortex Search, and Cortex Agents.
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE OPSSENTINEL_ROLE;

CREATE WAREHOUSE IF NOT EXISTS OPSSENTINEL_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Compute for the OpsSentinel demo workloads.';

GRANT USAGE ON WAREHOUSE OPSSENTINEL_WH TO ROLE OPSSENTINEL_ROLE;

CREATE DATABASE IF NOT EXISTS OPSSENTINEL;
GRANT OWNERSHIP ON DATABASE OPSSENTINEL TO ROLE OPSSENTINEL_ROLE COPY CURRENT GRANTS;

USE ROLE OPSSENTINEL_ROLE;
USE WAREHOUSE OPSSENTINEL_WH;
USE DATABASE OPSSENTINEL;

-- CORE holds structured operational tables.
-- DOCS holds unstructured documents and the Cortex Search service.
-- AI holds enriched views produced by Cortex AISQL functions.
-- APP holds the semantic view, the agent, and the action layer.
CREATE SCHEMA IF NOT EXISTS CORE;
CREATE SCHEMA IF NOT EXISTS DOCS;
CREATE SCHEMA IF NOT EXISTS AI;
CREATE SCHEMA IF NOT EXISTS APP;

-- Internal stage that receives the generated CSV and JSONL files.
CREATE STAGE IF NOT EXISTS CORE.RAW_STAGE
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Landing zone for generated OpsSentinel data files.';

CREATE FILE FORMAT IF NOT EXISTS CORE.CSV_FORMAT
  TYPE = CSV
  PARSE_HEADER = TRUE
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL')
  ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;

CREATE FILE FORMAT IF NOT EXISTS CORE.JSON_FORMAT
  TYPE = JSON
  STRIP_OUTER_ARRAY = FALSE;
