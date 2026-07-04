# Architecture

OpsSentinel is organized as a set of layers that each do one job. Data flows up
from raw tables to a single anomaly feed, then to reasoned actions, and out
through an agent and an app.

## Layers

### 1. Ingest and store (schemas CORE and DOCS)

`data/generate.py` produces seven structured CSV files and one JSONL document
file. The CSV files load into `CORE` tables. The documents load into
`DOCS.DOCUMENTS`, one row per message with light attributes (doc type, source,
supplier, product, carrier, date) plus the raw body.

### 2. Enrich unstructured text (schema AI)

`AI.DOC_SIGNALS` runs Cortex AISQL over every document:

- `AI_CLASSIFY` assigns one operational topic from a fixed catalog.
- `SNOWFLAKE.CORTEX.SENTIMENT` scores tone from -1 to 1.

`AI.SUPPLIER_SIGNAL_DAILY` rolls signals up per supplier per day and uses
`AI_AGG` to write a one sentence digest of the day's complaints. This turns free
text into numbers and short summaries the rest of the system can join on.

### 3. Detect (schema APP, dynamic tables)

Four dynamic tables each compare a recent window against a trailing baseline:

| Table | Signal | Recent vs baseline |
| --- | --- | --- |
| `DEMAND_ANOMALIES` | avg daily units per product | 7 days vs prior 6 weeks |
| `CARRIER_ANOMALIES` | late shipment rate per carrier | 14 days vs prior quarter |
| `INVENTORY_ANOMALIES` | on hand vs reorder point | latest snapshot |
| `COST_ANOMALIES` | compute credits per DC | 10 days vs prior baseline |

`ANOMALY_FEED` unions them into one normalized shape with a severity label and a
plain language explanation. Dynamic tables refresh incrementally, which is what
makes monitoring continuous with no orchestration code.

### 4. Reason and act (schema APP, procedures)

`SENTINEL_SCAN` walks every open high or medium anomaly, skips ones already
actioned in the last day, retrieves supporting documents with
`SNOWFLAKE.CORTEX.SEARCH_PREVIEW`, and calls a Cortex model to produce a
structured action (title, rationale, recommended action, draft message,
priority). Actions are written to `ACTION_LOG`, which is both the work queue and
the audit trail.

### 5. Interface (schema APP, agent and app)

`OPS_SENTINEL_AGENT` is a Snowflake Intelligence agent with three tools: Cortex
Analyst over the semantic view for metrics, Cortex Search over the corpus for
context, and a custom procedure tool to run a scan on request. The Streamlit in
Snowflake app exposes the anomaly feed, the action queue with a dispatch
control, and a natural language console.

### 6. Automate (schema APP, tasks)

`ENRICH_REFRESH_TASK` rebuilds enrichment daily. `SENTINEL_SCAN_TASK` runs the
scan hourly. Together with the dynamic tables, the system keeps itself current.

## Safety

The `cortex/hooks/pre_tool_use.py` hook blocks destructive statements against the
OpsSentinel database from inside CoCo unless an explicit override flag is set.
This models the guard rails a real deployment would need before letting an agent
touch production.

## Why dynamic tables and not one big query

Dynamic tables give incremental refresh, a clear dependency graph, and a natural
place to set freshness targets. Detection logic stays declarative, and the scan
procedure only has to read a clean feed, which keeps the reasoning step simple.
