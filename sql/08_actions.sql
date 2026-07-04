-- OpsSentinel: the action layer that turns detection into decisions.
-- This is what makes OpsSentinel an agent rather than a dashboard. For every
-- open anomaly it retrieves supporting unstructured evidence with Cortex
-- Search, asks a Cortex model to reason about impact, and writes a concrete,
-- prioritized action with a ready to send contextual message.

USE ROLE OPSSENTINEL_ROLE;
USE WAREHOUSE OPSSENTINEL_WH;
USE DATABASE OPSSENTINEL;
USE SCHEMA APP;

-- Every recommendation the agent produces is recorded here. The table doubles
-- as an audit trail and as the queue the dispatcher and UI read from.
CREATE OR REPLACE TABLE APP.ACTION_LOG (
  action_id        STRING DEFAULT UUID_STRING(),
  created_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  anomaly_type     STRING,
  entity_id        STRING,
  entity_name      STRING,
  severity         STRING,
  title            STRING,
  rationale        STRING,
  recommended_action STRING,
  contextual_message STRING,
  priority         NUMBER,
  status           STRING DEFAULT 'proposed',
  dispatched_at    TIMESTAMP_NTZ
);

-- Model used for reasoning. Kept in one place so it is easy to swap.
CREATE OR REPLACE VIEW APP.SENTINEL_CONFIG AS
SELECT 'claude-3-5-sonnet' AS reasoning_model;

-- Core reasoning routine. Given one anomaly, it gathers evidence, prompts the
-- model for a structured action, and returns the parsed fields as an object.
CREATE OR REPLACE FUNCTION APP.REASON_ABOUT_ANOMALY(
  anomaly_type STRING,
  entity_id STRING,
  entity_name STRING,
  severity STRING,
  explanation STRING,
  evidence STRING,
  model STRING
)
RETURNS STRING
LANGUAGE SQL
AS
$$
  SNOWFLAKE.CORTEX.COMPLETE(
    model,
    'You are OpsSentinel, an autonomous operations analyst for a consumer goods '
    || 'company. Given a detected anomaly and supporting evidence, respond with a '
    || 'compact JSON object using exactly these keys: title, rationale, '
    || 'recommended_action, contextual_message, priority. priority is an integer '
    || 'from 1 (most urgent) to 5. contextual_message is a short professional note '
    || 'that could be sent to the responsible team. Do not use em dashes anywhere. '
    || 'Anomaly type: ' || anomaly_type
    || '. Entity: ' || entity_name || ' (' || entity_id || ')'
    || '. Severity: ' || severity
    || '. Detection detail: ' || explanation
    || '. Supporting evidence from documents: ' || evidence
    || '. Return only the JSON object.'
  )
$$;

-- The main scan. It walks every open anomaly, skips ones already actioned in
-- the last day, retrieves matching documents, reasons, and logs an action.
CREATE OR REPLACE PROCEDURE APP.SENTINEL_SCAN()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  model STRING;
  actions_created NUMBER DEFAULT 0;
  evidence STRING;
  raw STRING;
  cur CURSOR FOR
    SELECT anomaly_type, entity_id, entity_name, severity, explanation
    FROM APP.ANOMALY_FEED f
    WHERE severity IN ('high', 'medium')
      AND NOT EXISTS (
        SELECT 1 FROM APP.ACTION_LOG a
        WHERE a.anomaly_type = f.anomaly_type
          AND a.entity_id = f.entity_id
          AND a.created_at > DATEADD('day', -1, CURRENT_TIMESTAMP())
      );
BEGIN
  SELECT reasoning_model INTO :model FROM APP.SENTINEL_CONFIG;
  FOR row IN cur DO
    -- Pull the most relevant supporting documents for this entity.
    evidence := (
      SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'OPSSENTINEL.DOCS.OPS_DOC_SEARCH',
        '{ "query": "' || REPLACE(row.explanation, '"', ' ')
          || '", "columns": ["body", "doc_type"], "limit": 4 }'
      )
    );
    raw := APP.REASON_ABOUT_ANOMALY(
      row.anomaly_type, row.entity_id, row.entity_name,
      row.severity, row.explanation, evidence, :model
    );
    INSERT INTO APP.ACTION_LOG
      (anomaly_type, entity_id, entity_name, severity,
       title, rationale, recommended_action, contextual_message, priority)
    SELECT
      row.anomaly_type, row.entity_id, row.entity_name, row.severity,
      TRY_PARSE_JSON(:raw):title::STRING,
      TRY_PARSE_JSON(:raw):rationale::STRING,
      TRY_PARSE_JSON(:raw):recommended_action::STRING,
      TRY_PARSE_JSON(:raw):contextual_message::STRING,
      COALESCE(TRY_PARSE_JSON(:raw):priority::NUMBER, 3);
    actions_created := actions_created + 1;
  END FOR;
  RETURN 'OpsSentinel scan complete. Actions created: ' || actions_created;
END;
$$;

-- Run one scan now so the demo has fresh actions to show.
CALL APP.SENTINEL_SCAN();

SELECT title, severity, priority, recommended_action
FROM APP.ACTION_LOG
ORDER BY priority ASC, created_at DESC;
