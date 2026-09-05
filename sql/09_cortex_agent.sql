-- OpsSentinel: the Cortex Agent that powers Snowflake Intelligence.
-- The agent is the natural language brain. It orchestrates two Snowflake native
-- tools: Cortex Analyst over the semantic view for structured questions, and
-- Cortex Search over the document corpus for unstructured context. A third
-- custom tool lets a user ask the agent to run a fresh scan on demand.

USE ROLE OPSSENTINEL_ROLE;
USE WAREHOUSE OPSSENTINEL_WH;
USE DATABASE OPSSENTINEL;
USE SCHEMA APP;

-- Wrapper procedure exposed to the agent as a callable tool.
CREATE OR REPLACE PROCEDURE APP.RUN_SENTINEL_SCAN_TOOL()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
  CALL APP.SENTINEL_SCAN();
  RETURN 'OpsSentinel scan triggered. See APP.ACTION_LOG for new actions.';
END;
$$;

CREATE OR REPLACE AGENT APP.OPS_SENTINEL_AGENT
  WITH PROFILE = '{"display_name": "OpsSentinel"}'
  COMMENT = 'Autonomous operations analyst over structured and unstructured data.'
  FROM SPECIFICATION $$
{
  "models": {
    "orchestration": "claude-3-5-sonnet"
  },
  "instructions": {
    "response": "You are OpsSentinel, an operations analyst. Answer concisely, cite whether a number came from structured data or from documents, and always end with a recommended next action. Never use em dashes.",
    "orchestration": "Use the analyst tool for metrics and trends. Use the search tool to explain why something is happening from supplier emails, incident reports, reviews, and tickets. Combine both before concluding. Call the scan tool only when the user explicitly asks to refresh detections.",
    "sample_questions": [
      {"question": "Which supplier has the worst quality signal this month and why?"},
      {"question": "What is driving the late shipments and which carrier is responsible?"},
      {"question": "Which products are at risk of stockout right now?"},
      {"question": "Run a fresh scan and summarize the top three actions."}
    ]
  },
  "tools": [
    {"tool_spec": {"type": "cortex_analyst_text_to_sql", "name": "ops_analyst", "description": "Answer quantitative questions about orders, shipments, inventory, suppliers, and compute spend."}},
    {"tool_spec": {"type": "cortex_search", "name": "ops_docs", "description": "Retrieve supporting text from supplier emails, carrier incidents, customer reviews, support tickets, and market news."}},
    {"tool_spec": {"type": "generic", "name": "run_scan", "description": "Run a fresh OpsSentinel anomaly scan and create prioritized actions."}}
  ],
  "tool_resources": {
    "ops_analyst": {"semantic_view": "OPSSENTINEL.APP.OPS_SEMANTIC"},
    "ops_docs": {"name": "OPSSENTINEL.DOCS.OPS_DOC_SEARCH", "max_results": 5, "id_column": "doc_id"},
    "run_scan": {"identifier": "OPSSENTINEL.APP.RUN_SENTINEL_SCAN_TOOL", "type": "procedure", "execution_environment": {"type": "warehouse", "warehouse": "OPSSENTINEL_WH"}}
  }
}
$$;

SHOW AGENTS LIKE 'OPS_SENTINEL_AGENT' IN SCHEMA APP;
