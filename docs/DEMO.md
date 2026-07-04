# Demo script

A five minute walkthrough that shows detection, reasoning, action, and natural
language, in that order.

## Setup (once)

```shell
python3 data/generate.py
bash scripts/deploy.sh opssentinel
```

## 1. Show the anomaly feed (detection)

Open the Streamlit app, Overview tab. Point out that four anomalies surface with
no manual query: a demand spike, a carrier delay, a stockout risk, and a cost
drift. Note the severity and the ratio against baseline.

Or in SQL:

```sql
SELECT anomaly_type, entity_name, severity, ratio, explanation
FROM OPSSENTINEL.APP.ANOMALY_FEED
ORDER BY severity;
```

## 2. Show the reasoned actions (agentic step)

Action queue tab. Click into the top action. Show the rationale that references
both the metric and the documents, the recommended action, and the draft
message. Emphasize that this was written by combining structured detection with
retrieved unstructured evidence.

Run a fresh scan live with the button, or:

```sql
CALL OPSSENTINEL.APP.SENTINEL_SCAN();
SELECT title, severity, priority, recommended_action
FROM OPSSENTINEL.APP.ACTION_LOG
ORDER BY priority ASC, created_at DESC;
```

## 3. Ask in plain language (Snowflake Intelligence)

Ask OpsSentinel tab, or the agent in Snowsight:

- "Which supplier has the worst quality signal this month and why?"
- "What is driving the late shipments and which carrier is responsible?"
- "Which products are at risk of stockout right now?"

Show that the answer cites whether a fact came from data or from documents and
ends with a recommended action.

## 4. Show CoCo native operation

From Cortex Code inside the repo:

```
$anomaly-scan
$ops-sentinel connect the demand spike to any supplier risk
```

Point out the SessionStart banner, and try a blocked destructive statement to
show the PreToolUse safety hook in action.

## The story to tell

Start with the demand spike on the dish soap product. It is sourced from the
supplier whose reviews and tickets are turning negative, and the same product is
below its reorder point. OpsSentinel connects all three into one action:
expedite a reorder from a backup source and open a quality review with the
supplier. That is the kind of cross signal reasoning a dashboard cannot do.
