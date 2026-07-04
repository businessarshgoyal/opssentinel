-- OpsSentinel: load the unstructured document corpus.
-- Documents arrive as newline delimited JSON. Each line becomes one row that
-- keeps the raw text plus light structured attributes for filtering.

USE ROLE OPSSENTINEL_ROLE;
USE WAREHOUSE OPSSENTINEL_WH;
USE DATABASE OPSSENTINEL;
USE SCHEMA DOCS;

CREATE OR REPLACE TABLE DOCUMENTS (
  doc_id        STRING,
  doc_type      STRING,
  source        STRING,
  created_date  DATE,
  supplier_id   STRING,
  product_id    STRING,
  carrier       STRING,
  body          STRING
);

-- Load the JSONL file that was staged by the deploy script. Each record is a
-- single JSON object, so we read the VARIANT column and project the fields.
COPY INTO DOCUMENTS
  FROM (
    SELECT
      $1:doc_id::STRING,
      $1:doc_type::STRING,
      $1:source::STRING,
      $1:created_date::DATE,
      $1:supplier_id::STRING,
      $1:product_id::STRING,
      $1:carrier::STRING,
      $1:body::STRING
    FROM @OPSSENTINEL.CORE.RAW_STAGE/documents.jsonl.gz
    (FILE_FORMAT => 'OPSSENTINEL.CORE.JSON_FORMAT')
  )
  ON_ERROR = ABORT_STATEMENT;

SELECT doc_type, COUNT(*) AS row_count
FROM DOCUMENTS
GROUP BY doc_type
ORDER BY row_count DESC;
