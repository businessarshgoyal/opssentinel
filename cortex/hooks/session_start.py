#!/usr/bin/env python3
"""SessionStart hook for OpsSentinel.

Prints a short orientation banner when a Cortex Code session begins inside the
repo, so the operator immediately knows the key commands. Cortex Code shows the
stdout of a SessionStart hook as a context note.
"""

import sys

BANNER = """
OpsSentinel session ready.

Common moves:
  $ops-sentinel    investigate an operations question end to end
  $anomaly-scan    run a fresh detection pass and list top actions
  $deploy-opssentinel  build or rebuild the full stack

Data:  OPSSENTINEL.CORE, OPSSENTINEL.DOCS
Brain: agent OPSSENTINEL.APP.OPS_SENTINEL_AGENT
Reminder: never use em dashes in code, SQL, or generated text.
"""


def main() -> None:
    sys.stdout.write(BANNER)


if __name__ == "__main__":
    main()
