-- OpsSentinel: Cortex Search service over the document corpus.
-- Cortex Search gives the agent semantic retrieval over the unstructured text,
-- so a question like "why is Cedar Valley slipping?" pulls the exact reviews,
-- tickets, and emails that explain it rather than a keyword match.

USE ROLE OPSSENTINEL_ROLE;
USE WAREHOUSE OPSSENTINEL_WH;
USE DATABASE OPSSENTINEL;
USE SCHEMA DOCS;

CREATE OR REPLACE CORTEX SEARCH SERVICE DOCS.OPS_DOC_SEARCH
  ON body
  ATTRIBUTES doc_type, supplier_id, product_id, carrier, created_date
  WAREHOUSE = OPSSENTINEL_WH
  TARGET_LAG = '1 hour'
  COMMENT = 'Semantic search over supplier emails, incidents, reviews, tickets, and news.'
  AS (
    SELECT
      doc_id,
      body,
      doc_type,
      supplier_id,
      product_id,
      carrier,
      created_date
    FROM OPSSENTINEL.DOCS.DOCUMENTS
  );

-- Smoke test the service directly with SEARCH_PREVIEW.
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
  'OPSSENTINEL.DOCS.OPS_DOC_SEARCH',
  '{
     "query": "damaged packaging and quality complaints",
     "columns": ["doc_id", "doc_type", "supplier_id", "body"],
     "limit": 5
   }'
) AS results;
