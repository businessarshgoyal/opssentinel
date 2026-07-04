# AGENTS.md

Project instructions for Cortex Code (CoCo) when working in the OpsSentinel repo.

## What this project is

OpsSentinel is an autonomous operations analyst built on Snowflake. It watches a
consumer goods company's structured operations data (orders, shipments,
inventory, supplier master, compute spend) together with unstructured text
(supplier emails, carrier incident reports, customer reviews, support tickets,
market news). It detects anomalies, reasons about root cause using both data
types, and writes prioritized actions with ready to send messages.

## Golden rules

1. Never use em dashes in code, comments, SQL, or generated text. Use commas,
   periods, colons, or parentheses instead.
2. Treat everything under the `OPSSENTINEL` database as demo data you may
   rebuild, but never run `DROP DATABASE`, `DROP SCHEMA`, `TRUNCATE`, or
   unfiltered `DELETE` without an explicit instruction. The PreToolUse hook will
   block these by default.
3. Prefer the semantic view `OPSSENTINEL.APP.OPS_SEMANTIC` for metrics. Prefer
   the Cortex Search service `OPSSENTINEL.DOCS.OPS_DOC_SEARCH` for explanations.
4. Keep SQL idempotent. Use `CREATE OR REPLACE` and `IF NOT EXISTS`.

## Layout

- `data/generate.py` builds the deterministic demo dataset.
- `sql/00` through `sql/10` build the full stack in order.
- `.cortex/skills/` holds the project skills. Invoke them with `$name`.
- `cortex/` holds connection, MCP, settings, and hook templates.
- `app/streamlit_app.py` is the Streamlit in Snowflake interface.
- `scripts/deploy.sh` runs the end to end deploy through the Snowflake CLI.

## How to run things

- Regenerate data: `python3 data/generate.py`.
- Deploy everything: `bash scripts/deploy.sh <connection_name>`.
- Run a scan by hand: `$anomaly-scan` or `CALL OPSSENTINEL.APP.SENTINEL_SCAN();`.
- Ask questions in natural language through the `OPS_SENTINEL_AGENT` agent.

## Connections

Set the active connection before running SQL: `cortex connections set <name>`.
The connection needs a role that holds `OPSSENTINEL_ROLE` and the
`SNOWFLAKE.CORTEX_USER` database role.
