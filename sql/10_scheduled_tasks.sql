-- OpsSentinel: scheduled autonomy.
-- Dynamic tables keep the anomaly feed fresh on their own. These tasks close
-- the loop: one rebuilds the AI enrichment from new documents, the other runs
-- the scan so new actions appear without anyone pressing a button.

USE ROLE OPSSENTINEL_ROLE;
USE WAREHOUSE OPSSENTINEL_WH;
USE DATABASE OPSSENTINEL;
USE SCHEMA APP;

-- Rebuild the document enrichment so newly arrived text is classified and
-- scored. Kept as a procedure so both the task and manual runs share one path.
CREATE OR REPLACE PROCEDURE APP.REFRESH_ENRICHMENT()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
  CREATE OR REPLACE TABLE OPSSENTINEL.AI.DOC_SIGNALS AS
  SELECT
    d.doc_id, d.doc_type, d.created_date, d.supplier_id, d.product_id, d.carrier, d.body,
    AI_CLASSIFY(
      d.body,
      ['quality_issue', 'delivery_delay', 'price_change',
       'capacity_constraint', 'positive_feedback', 'general_news']
    ):labels[0]::STRING AS topic,
    SNOWFLAKE.CORTEX.SENTIMENT(d.body) AS sentiment_score
  FROM OPSSENTINEL.DOCS.DOCUMENTS d;
  RETURN 'Enrichment refreshed.';
END;
$$;

CREATE OR REPLACE TASK APP.ENRICH_REFRESH_TASK
  WAREHOUSE = OPSSENTINEL_WH
  SCHEDULE = 'USING CRON 0 6 * * * UTC'
  COMMENT = 'Daily rebuild of document enrichment.'
AS
  CALL APP.REFRESH_ENRICHMENT();

CREATE OR REPLACE TASK APP.SENTINEL_SCAN_TASK
  WAREHOUSE = OPSSENTINEL_WH
  SCHEDULE = '60 MINUTE'
  COMMENT = 'Hourly OpsSentinel anomaly scan and action creation.'
AS
  CALL APP.SENTINEL_SCAN();

-- Tasks are created suspended. Resume them to make monitoring continuous.
ALTER TASK APP.ENRICH_REFRESH_TASK RESUME;
ALTER TASK APP.SENTINEL_SCAN_TASK RESUME;

SHOW TASKS IN SCHEMA APP;
