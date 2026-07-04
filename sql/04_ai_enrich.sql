-- OpsSentinel: enrich unstructured documents with Cortex AISQL.
-- This is where unstructured text becomes structured signal. We classify each
-- document into an operational topic, score its sentiment, and summarize the
-- daily narrative per topic. The result feeds anomaly detection and the agent.

USE ROLE OPSSENTINEL_ROLE;
USE WAREHOUSE OPSSENTINEL_WH;
USE DATABASE OPSSENTINEL;
USE SCHEMA AI;

-- The topics OpsSentinel cares about. Keeping this list explicit makes the
-- classifier deterministic and the downstream joins simple.
CREATE OR REPLACE TABLE AI.TOPIC_CATALOG (topic STRING) AS
SELECT * FROM VALUES
  ('quality_issue'),
  ('delivery_delay'),
  ('price_change'),
  ('capacity_constraint'),
  ('positive_feedback'),
  ('general_news');

-- DOC_SIGNALS turns each raw document into a labeled, scored row.
-- AI_CLASSIFY assigns the best fitting operational topic and SENTIMENT scores
-- the tone from -1 (very negative) to 1 (very positive).
CREATE OR REPLACE TABLE AI.DOC_SIGNALS AS
SELECT
  d.doc_id,
  d.doc_type,
  d.created_date,
  d.supplier_id,
  d.product_id,
  d.carrier,
  d.body,
  AI_CLASSIFY(
    d.body,
    ['quality_issue', 'delivery_delay', 'price_change',
     'capacity_constraint', 'positive_feedback', 'general_news']
  ):labels[0]::STRING AS topic,
  SNOWFLAKE.CORTEX.SENTIMENT(d.body) AS sentiment_score
FROM OPSSENTINEL.DOCS.DOCUMENTS d;

-- A compact daily rollup of negative signal per supplier. AI_AGG writes a short
-- natural language digest of the underlying complaints, which the agent can
-- quote directly instead of dumping raw rows.
CREATE OR REPLACE TABLE AI.SUPPLIER_SIGNAL_DAILY AS
SELECT
  supplier_id,
  created_date,
  COUNT(*) AS doc_count,
  AVG(sentiment_score) AS avg_sentiment,
  SUM(IFF(topic = 'quality_issue', 1, 0)) AS quality_issue_count,
  AI_AGG(
    body,
    'Summarize the recurring operational problems described in these messages in one short sentence.'
  ) AS daily_digest
FROM AI.DOC_SIGNALS
WHERE supplier_id IS NOT NULL AND supplier_id <> ''
GROUP BY supplier_id, created_date;

-- Sanity check: the failing supplier should surface with negative sentiment.
SELECT supplier_id,
       ROUND(AVG(avg_sentiment), 3) AS mean_sentiment,
       SUM(quality_issue_count) AS quality_issues
FROM AI.SUPPLIER_SIGNAL_DAILY
GROUP BY supplier_id
ORDER BY mean_sentiment ASC;
