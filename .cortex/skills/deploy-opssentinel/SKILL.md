---
name: deploy-opssentinel
id: deploy-opssentinel
title: Deploy OpsSentinel
summary: Build or rebuild the full OpsSentinel stack on Snowflake in the correct order.
description: "Use to deploy or rebuild the OpsSentinel stack: setup, tables, data load, AI enrichment, semantic view, Cortex Search, dynamic tables, actions, agent, and tasks. Triggers: deploy, set up, rebuild, install opssentinel, provision, run the sql scripts."
type: community
status: stable
categories:
  - operations
  - deployment
tools:
  - sql
  - bash
---

# Deploy OpsSentinel

Stand up the entire stack from a clean account.

## When to use

Load this skill to provision OpsSentinel for the first time or to rebuild it.

## Workflow

1. Confirm the active connection points at the target account:
   `!cortex connections list`.
2. Generate data locally: `!python3 data/generate.py`.
3. Run the deploy script, which uploads files and runs every SQL script in
   order: `!bash scripts/deploy.sh <connection_name>`.
4. Verify the agent exists: `SHOW AGENTS LIKE 'OPS_SENTINEL_AGENT' IN SCHEMA OPSSENTINEL.APP;`.
5. Run a first scan: `CALL OPSSENTINEL.APP.SENTINEL_SCAN();`.
6. Report the object counts and the first set of proposed actions.

## Order matters

The SQL scripts are numbered `00` through `10` and must run in that order. Later
scripts depend on tables, the semantic view, and the search service created
earlier. Each script is idempotent, so a partial run is safe to repeat.

## Common mistakes

- Running enrichment or the agent before data is loaded.
- Skipping the PUT step, which leaves the stage empty and the COPY commands with
  nothing to load. The deploy script handles PUT for you.
- Using em dashes. Do not use them.
