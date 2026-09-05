#!/usr/bin/env python3
"""PreToolUse safety hook for OpsSentinel.

Cortex Code invokes this before every tool call and passes a JSON payload on
stdin. The hook inspects SQL that CoCo is about to run and blocks destructive
statements against the OpsSentinel database unless the user has clearly opted
in with an OPSSENTINEL_ALLOW_DESTRUCTIVE environment flag.

Blocking is done by printing a JSON object with a block decision and exiting
with a non zero status, which is the contract Cortex Code expects.
"""

import json
import os
import re
import sys

# Statements that can destroy or wipe demo objects. Matched case insensitively.
DESTRUCTIVE = re.compile(
    r"\b(drop\s+database|drop\s+schema|drop\s+table|truncate\s+table"
    r"|delete\s+from)\b",
    re.IGNORECASE,
)

# Only guard statements that actually touch the OpsSentinel objects.
GUARDED_SCOPE = re.compile(r"opssentinel", re.IGNORECASE)


def read_payload() -> dict:
    """Read and parse the JSON payload from stdin, tolerating empty input."""
    raw = sys.stdin.read().strip()
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def extract_sql(payload: dict) -> str:
    """Pull any SQL text out of the tool input regardless of exact key name."""
    tool_input = payload.get("tool_input", {})
    if isinstance(tool_input, str):
        return tool_input
    parts = []
    for key in ("sql", "query", "statement", "command", "code"):
        value = tool_input.get(key)
        if isinstance(value, str):
            parts.append(value)
    return "\n".join(parts)


def block(reason: str) -> None:
    """Emit a block decision and exit non zero so the tool call is stopped."""
    print(json.dumps({"decision": "block", "reason": reason}))
    sys.exit(2)


def main() -> None:
    if os.environ.get("OPSSENTINEL_ALLOW_DESTRUCTIVE") == "1":
        return
    payload = read_payload()
    sql = extract_sql(payload)
    if not sql:
        return
    if DESTRUCTIVE.search(sql) and GUARDED_SCOPE.search(sql):
        block(
            "Blocked a destructive statement against the OpsSentinel database. "
            "Set OPSSENTINEL_ALLOW_DESTRUCTIVE=1 to override intentionally."
        )


if __name__ == "__main__":
    main()
