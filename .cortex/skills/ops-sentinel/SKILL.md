---
name: ops-sentinel
id: ops-sentinel
title: OpsSentinel Operations Analyst
summary: Investigate operational anomalies over structured and unstructured Snowflake data and propose prioritized actions.
description: "Use to investigate operations questions and incidents for the OpsSentinel demo: demand spikes, late shipments, carrier reliability, supplier quality, inventory stockout risk, and compute cost drift. Combines Cortex Analyst metrics with Cortex Search evidence and writes actions. Triggers: anomaly, root cause, why is, late shipments, carrier, supplier quality, stockout, reorder, cost drift, action plan, operations."
type: community
status: stable
categories:
  - operations
  - agents
tools:
  - sql
  - cortex_search
---

# OpsSentinel Operations Analyst

Investigate an operational question end to end, then recommend an action. This
is a router skill that combines quantitative and qualitative evidence before
concluding.

## When to use

Load this skill for any operations question about the OpsSentinel dataset:
trends, anomalies, root cause, or what to do next.

## Workflow

1. Restate the question and decide which signals matter (demand, delivery,
   quality, inventory, or cost).
2. Get the numbers. Query the semantic view through Cortex Analyst, or run SQL
   against `OPSSENTINEL.APP.ANOMALY_FEED` for the current anomalies.
3. Get the story. Search `OPSSENTINEL.DOCS.OPS_DOC_SEARCH` for documents that
   explain the numbers. Always pull evidence before asserting a cause.
4. Reason across both. State clearly which facts came from structured data and
   which came from documents.
5. Recommend one concrete next action and, when useful, a short message the
   responsible team could send. Keep it specific.

## Example

```
$ops-sentinel why did on time delivery drop this month?
```

The skill checks `late_rate` by carrier through Cortex Analyst, finds TransArc
is the outlier, then searches incident reports to explain the cause, and
recommends rerouting critical lanes to a backup carrier.

## Common mistakes

- Concluding a root cause without retrieving supporting documents.
- Mixing structured and document facts without saying which is which.
- Using em dashes. Do not use them.
