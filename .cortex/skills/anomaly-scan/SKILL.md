---
name: anomaly-scan
id: anomaly-scan
title: OpsSentinel Anomaly Scan
summary: Run the OpsSentinel detection and action pipeline and summarize the results.
description: "Use to run a fresh OpsSentinel anomaly scan and produce prioritized actions. Triggers: run a scan, refresh anomalies, check for issues, sentinel scan, what needs attention, top actions, action queue."
type: community
status: stable
categories:
  - operations
  - automation
tools:
  - sql
---

# OpsSentinel Anomaly Scan

Trigger a detection pass, then report the actions the agent created.

## When to use

Load this skill when the user asks to check for new problems, refresh the
anomaly feed, or see what needs attention right now.

## Workflow

1. Refresh detection inputs if documents changed:
   `CALL OPSSENTINEL.APP.REFRESH_ENRICHMENT();`
2. Run the scan: `CALL OPSSENTINEL.APP.SENTINEL_SCAN();`
3. Read the queue and summarize the top items:

   ```sql
   SELECT title, severity, priority, recommended_action
   FROM OPSSENTINEL.APP.ACTION_LOG
   WHERE status = 'proposed'
   ORDER BY priority ASC, created_at DESC
   LIMIT 5;
   ```
4. Present the actions grouped by severity. For each, give the one line
   rationale and the recommended action.

## Common mistakes

- Forgetting to refresh enrichment when new documents were loaded.
- Reporting raw anomaly rows instead of the reasoned actions in ACTION_LOG.
- Using em dashes. Do not use them.
