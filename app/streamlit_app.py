"""OpsSentinel Streamlit in Snowflake app.

A lightweight operations command center. It surfaces the live anomaly feed, the
prioritized action queue, and a natural language console that answers questions
by combining structured metrics with unstructured evidence through Cortex.

Deploy this as a Streamlit in Snowflake app with the OPSSENTINEL_ROLE and the
OPSSENTINEL_WH warehouse. It uses the active Snowpark session, so no connection
details are stored in the file.
"""

import json

import streamlit as st
from snowflake.snowpark.context import get_active_session

session = get_active_session()

st.set_page_config(page_title="OpsSentinel", page_icon="warning", layout="wide")
st.title("OpsSentinel")
st.caption("Autonomous operations analyst over structured and unstructured Snowflake data.")

SEVERITY_ORDER = {"high": 0, "medium": 1, "low": 2}


def run_df(query: str):
    """Run a query and return a pandas DataFrame."""
    return session.sql(query).to_pandas()


def sql_quote(text: str) -> str:
    """Escape single quotes so a value can be embedded in a SQL literal."""
    return text.replace("'", "''")


tab_overview, tab_actions, tab_ask = st.tabs(["Overview", "Action queue", "Ask OpsSentinel"])

with tab_overview:
    st.subheader("Live anomaly feed")
    st.write(
        "Anomalies are detected by dynamic tables that compare a recent window "
        "against a trailing baseline across demand, delivery, inventory, and cost."
    )
    feed = run_df(
        "SELECT anomaly_type, entity_name, severity, ratio, explanation "
        "FROM OPSSENTINEL.APP.ANOMALY_FEED"
    )
    if not feed.empty:
        feed["order"] = feed["SEVERITY"].str.lower().map(SEVERITY_ORDER).fillna(3)
        feed = feed.sort_values("order").drop(columns="order")
        high = int((feed["SEVERITY"].str.lower() == "high").sum())
        medium = int((feed["SEVERITY"].str.lower() == "medium").sum())
        col_a, col_b, col_c = st.columns(3)
        col_a.metric("Open anomalies", len(feed))
        col_b.metric("High severity", high)
        col_c.metric("Medium severity", medium)
        st.dataframe(feed, use_container_width=True, hide_index=True)
    else:
        st.info("No anomalies detected in the current window.")

with tab_actions:
    st.subheader("Prioritized actions")
    st.write("Each action is reasoned from an anomaly plus supporting documents.")
    if st.button("Run a fresh scan now"):
        with st.spinner("Scanning..."):
            result = session.sql("CALL OPSSENTINEL.APP.SENTINEL_SCAN()").collect()
        st.success(result[0][0] if result else "Scan complete.")

    actions = run_df(
        "SELECT action_id, created_at, entity_name, severity, priority, title, "
        "rationale, recommended_action, contextual_message, status "
        "FROM OPSSENTINEL.APP.ACTION_LOG "
        "ORDER BY priority ASC, created_at DESC LIMIT 25"
    )
    if actions.empty:
        st.info("No actions yet. Run a scan to generate the queue.")
    for _, row in actions.iterrows():
        header = "Priority %s  |  %s  |  %s" % (row["PRIORITY"], row["SEVERITY"], row["TITLE"])
        with st.expander(header):
            st.markdown("**Why:** %s" % row["RATIONALE"])
            st.markdown("**Recommended action:** %s" % row["RECOMMENDED_ACTION"])
            st.markdown("**Draft message:**")
            st.code(row["CONTEXTUAL_MESSAGE"] or "", language="text")
            st.caption("Status: %s" % row["STATUS"])
            if row["STATUS"] == "proposed":
                if st.button("Mark dispatched", key="dispatch_%s" % row["ACTION_ID"]):
                    session.sql(
                        "UPDATE OPSSENTINEL.APP.ACTION_LOG "
                        "SET status = 'dispatched', dispatched_at = CURRENT_TIMESTAMP() "
                        "WHERE action_id = '%s'" % sql_quote(row["ACTION_ID"])
                    ).collect()
                    st.rerun()

with tab_ask:
    st.subheader("Ask in plain language")
    st.write(
        "OpsSentinel gathers document evidence with Cortex Search and answers "
        "with a Cortex model. For full text to SQL, connect the Cortex Analyst "
        "semantic view through the OPS_SENTINEL_AGENT agent."
    )
    question = st.text_input(
        "Your question",
        placeholder="Why did on time delivery drop this month?",
    )
    if st.button("Ask") and question:
        with st.spinner("Thinking..."):
            search_payload = json.dumps(
                {"query": question, "columns": ["body", "doc_type"], "limit": 6}
            )
            evidence_rows = session.sql(
                "SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW("
                "'OPSSENTINEL.DOCS.OPS_DOC_SEARCH', '%s') AS r" % sql_quote(search_payload)
            ).collect()
            evidence = evidence_rows[0][0] if evidence_rows else "{}"

            anomalies = run_df(
                "SELECT anomaly_type, entity_name, severity, explanation "
                "FROM OPSSENTINEL.APP.ANOMALY_FEED"
            ).to_json(orient="records")

            prompt = (
                "You are OpsSentinel, an operations analyst. Answer the question "
                "using the current anomalies and the document evidence below. Say "
                "which facts came from data and which from documents, and end with "
                "a recommended action. Never use em dashes. Question: "
                + question
                + " Current anomalies: "
                + anomalies
                + " Document evidence: "
                + str(evidence)
            )
            answer = session.sql(
                "SELECT SNOWFLAKE.CORTEX.COMPLETE('claude-3-5-sonnet', '%s') AS a"
                % sql_quote(prompt)
            ).collect()
        st.markdown(answer[0][0] if answer else "No answer produced.")
