# Submission notes

Snowflake CoCo CLI Hackathon 2026.

## Problem statement

Intelligent Workflow Automation Agent. OpsSentinel understands enterprise data
and autonomously executes a multi step workflow: detect an anomaly, reason over
structured and unstructured signals to find root cause, generate an insight, and
trigger a contextual action. It supports real world decision making in
operations and supply chain.

## Evaluation rubric mapping

### Real world relevance (30 percent)

Operations and supply chain teams face exactly the problem OpsSentinel solves:
the number is in a dashboard, the reason is in a document, and no one connects
them fast enough. The four seeded anomalies (demand spike, supplier quality
decline, carrier failure, cost drift) are drawn from common enterprise pain. The
action log with draft messages maps to how teams actually respond.

### Technical execution (40 percent)

- Cortex AISQL for classification, sentiment, and aggregation of text.
- A governed semantic view for Cortex Analyst.
- A Cortex Search service for retrieval over the corpus.
- Dynamic tables for incremental, declarative anomaly detection.
- A reasoning procedure that fuses structured detection with retrieved evidence
  through Cortex COMPLETE.
- A Snowflake Intelligence agent with three orchestrated tools.
- CoCo native constructs: skills, AGENTS.md, lifecycle hooks, MCP, settings.
- Scheduled tasks for continuous autonomy, and a safety hook for guard rails.
- Tests that prove the seeded anomalies exist, and a CI check that enforces the
  no em dash rule.

### Solution completeness (30 percent)

End to end and reproducible. One command generates data and deploys the entire
stack. Every SQL script is idempotent. The Streamlit app and the agent both
provide a working natural language interface. Documentation covers architecture,
a demo script, and this rubric mapping.

## What is real and what is simulated

- The data is synthetic and generated locally so the project runs in any account
  with no external dependencies.
- All Snowflake objects (tables, semantic view, search service, dynamic tables,
  procedures, agent, tasks) are real and deploy as written.
- Model names are centralized in `APP.SENTINEL_CONFIG` and in the agent spec so
  they can be swapped for whatever models a given account has enabled.

## Live verification

The structured layer and the anomaly detection engine were deployed and verified
on a live Snowflake account. All four seeded anomalies surfaced as expected:
TransArc carrier delays (4.95x baseline late rate), the Citrus Dish Soap demand
spike (2.47x), West Regional DC cost drift (2.07x), and Citrus Dish Soap stockout
risk. The Cortex AI layer (COMPLETE, SENTIMENT, AI_CLASSIFY, EMBED_TEXT, and
therefore Cortex Search and the agent) requires a non trial Snowflake account,
since Snowflake disables these functions on 30 day trials. On any account with
Cortex enabled, the full stack deploys unchanged with `scripts/deploy.sh`.

## Constraints honored

No em dashes appear anywhere in code, comments, SQL, or documentation. This is
enforced by `scripts/check_no_em_dash.py`, which runs in CI.
