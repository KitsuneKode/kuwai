#!/bin/bash
# Live-check helpers for the assistant: IPC into the running dev shell.
#   source tests/agent/live/ipc.sh; Q ollama isStreaming; wait_idle 60
Q() { qs ipc -p "${RICE_SHELL:-$HOME/Projects/rice/shell}" call "$@"; }
wait_idle() { for _ in $(seq 1 "${1:-120}"); do sleep 1; [ "$(Q ollama isStreaming)" = "false" ] && return 0; done; return 1; }
