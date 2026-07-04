# OpsSentinel

**An autonomous operations analyst that reasons over your enterprise data and acts on it, built with Snowflake Cortex Code (CoCo).**

Submission for the Snowflake CoCo CLI Hackathon 2026. Problem statement: **Intelligent Workflow Automation Agent**.

OpsSentinel goes beyond querying. It continuously watches a company's structured
operations data and its unstructured text, detects anomalies, explains root
cause by combining both, and writes prioritized actions with ready to send
messages. A human stays in the loop to approve and dispatch.

---

## Why this matters

Every operations team lives in two worlds that rarely meet. Dashboards show that
on time delivery dropped, but the reason sits in a carrier incident email nobody
read. Revenue for a product spiked, but the stockout risk hides in a weekly
inventory snapshot. OpsSentinel joins those worlds. It treats supplier emails,
incident reports, reviews, and tickets as first class signals alongside orders,
shipments, inventory, and spend, then reasons across all of it the way a good
analyst would.

## What it does

1. **Detects.** Dynamic tables compare a recent window against a trailing
   baseline across four operational domains: demand, delivery, inventory, and
   compute cost. Anomalies land in one normalized feed.
2. **Explains.** For each anomaly, Cortex Search retrieves the documents that
   explain it, and a Cortex model reasons about impact and root cause.
3. **Acts.** The agent writes a concrete, prioritized action with a draft
   message for the responsible team into an auditable action log.
4. **Answers.** A Snowflake Intelligence agent and a Streamlit in Snowflake app
   let anyone ask questions in plain language and get answers grounded in both
   structured metrics and document evidence.

## The scenario

A consumer goods company. The seeded dataset contains four intertwined problems
that a real operator would need to connect:

- A demand spike on one product that inventory is not keeping up with.
- A supplier whose quality is slipping, visible in reviews and support tickets.
- A carrier whose on time performance is collapsing, backed by incident reports.
- A distribution center whose compute spend is drifting up without more work.

OpsSentinel finds all four, connects the demand spike to the failing supplier
and the stockout risk, and proposes what to do.

---

## Architecture

```
                 Structured                        Unstructured
        orders, shipments, inventory,       supplier emails, incidents,
        suppliers, warehouse spend          reviews, tickets, market news
                 |                                     |
                 v                                     v
          CORE tables                          DOCS.DOCUMENTS
                 |                                     |
                 |                          Cortex AISQL enrichment
                 |                        (AI_CLASSIFY, SENTIMENT, AI_AGG)
                 |                                     |
                 |                                     v
                 |                          AI.DOC_SIGNALS + rollups
                 |                                     |
                 +------------------+------------------+
                                    v
                    Dynamic tables: APP.ANOMALY_FEED
                                    |
                    APP.SENTINEL_SCAN  (Cortex Search + Cortex COMPLETE)
                                    |
                                    v
                           APP.ACTION_LOG
                                    ^
        Semantic view  ------------ | ------------  Cortex Search service
     APP.OPS_SEMANTIC               |               DOCS.OPS_DOC_SEARCH
        (Cortex Analyst)            |
                                    v
                 Snowflake Intelligence agent: APP.OPS_SENTINEL_AGENT
                 Streamlit in Snowflake app:   app/streamlit_app.py
```

## How the mandates are met

| Mandate | Where |
| --- | --- |
| Snowflake CoCo CLI | Project skills in `.cortex/skills`, `AGENTS.md`, hooks in `cortex/hooks`, MCP and settings in `cortex/`. Deploy and operate the whole stack from CoCo. |
| Agentic workflows | `APP.SENTINEL_SCAN` reasons over anomalies and writes actions. Scheduled tasks make it continuous. A safety hook guards production objects. |
| Snowflake Intelligence | `APP.OPS_SENTINEL_AGENT` orchestrates Cortex Analyst over the semantic view and Cortex Search over the corpus, plus a custom scan tool. |
| Structured plus unstructured | CORE tables joined with DOCS documents through Cortex AISQL and the search service, reasoned together in every action. |
| Natural language interaction | The agent and the Streamlit app both answer plain language questions. |
| No em dashes | Enforced by `scripts/check_no_em_dash.py` in CI. |

## Repository layout

```
data/generate.py          deterministic synthetic data (structured + unstructured)
sql/00 .. sql/10          the full stack, idempotent, run in order
.cortex/skills/           CoCo skills: ops-sentinel, anomaly-scan, deploy-opssentinel
cortex/                   connection, MCP, settings, and lifecycle hook templates
app/streamlit_app.py      Streamlit in Snowflake command center
scripts/deploy.sh         one command end to end deploy through the Snowflake CLI
tests/                    tests that prove the seeded anomalies exist
docs/                     architecture, demo script, and rubric mapping
```

## Quick start

Prerequisites: a Snowflake account with Cortex enabled, the Snowflake CLI
(`snow`), and Python 3.9 or newer. Cortex Code (CoCo) is recommended for the
full experience but not required to deploy.

```shell
# 1. generate the demo data
python3 data/generate.py

# 2. add a connection named opssentinel (see cortex/connections.example.toml)

# 3. deploy the full stack
bash scripts/deploy.sh opssentinel
```

Then ask the agent a question, or launch the Streamlit app in Snowsight against
the `OPSSENTINEL_WH` warehouse.

## Using it from CoCo

```
$deploy-opssentinel        build or rebuild the stack
$anomaly-scan              run a fresh scan and list the top actions
$ops-sentinel why did on time delivery drop this month?
```

## Tests

```shell
python3 -m pytest
python3 scripts/check_no_em_dash.py
```

## Notes on scope

The dataset is synthetic and generated locally so the project runs in any
Snowflake account with no external dependencies. Every SQL script is idempotent.
Model names are set in one place (`APP.SENTINEL_CONFIG`) so they are easy to swap
for whatever your account has available.

## License

MIT. See [LICENSE](LICENSE).
