#!/usr/bin/env bash
#
# End to end deploy for OpsSentinel.
# Usage: bash scripts/deploy.sh <connection_name>
#
# Requires the Snowflake CLI (snow) on the path and a connection that can
# create databases and warehouses. The connection is passed as the first
# argument and defaults to "opssentinel".

set -euo pipefail

CONN="${1:-opssentinel}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="${ROOT}/data/generated"
STAGE="@OPSSENTINEL.CORE.RAW_STAGE"

echo "OpsSentinel deploy starting with connection: ${CONN}"

run_sql() {
  echo ">> running $1"
  snow sql --connection "${CONN}" --filename "${ROOT}/sql/$1"
}

put_file() {
  echo ">> uploading $1"
  snow sql --connection "${CONN}" \
    --query "PUT file://${GEN}/$1 ${STAGE} AUTO_COMPRESS=TRUE OVERWRITE=TRUE"
}

echo "== Step 1: generate demo data =="
python3 "${ROOT}/data/generate.py" --out "${GEN}"

echo "== Step 2: account setup and tables =="
run_sql 00_setup.sql
run_sql 01_tables.sql

echo "== Step 3: stage the files =="
for f in suppliers.csv products.csv warehouses.csv inventory.csv \
         orders.csv shipments.csv warehouse_spend.csv documents.jsonl; do
  put_file "${f}"
done

echo "== Step 4: load, enrich, and build the intelligence layer =="
run_sql 02_load_structured.sql
run_sql 03_documents.sql
run_sql 04_ai_enrich.sql
run_sql 05_semantic_view.sql
run_sql 06_cortex_search.sql
run_sql 07_dynamic_tables.sql
run_sql 08_actions.sql
run_sql 09_cortex_agent.sql
run_sql 10_scheduled_tasks.sql

echo "OpsSentinel deploy complete."
echo "Ask the agent OPSSENTINEL.APP.OPS_SENTINEL_AGENT a question, or open the Streamlit app."
