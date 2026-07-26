#!/bin/bash
#
# ollama_check.sh
# Host: SierraLab Linux
#
# Purpose:
#   1. Check if Ollama is running; restart it if stopped.
#   2. Check if Ollama is bound to 127.0.0.1 (not 0.0.0.0); warn if insecure.
#   3. Check disk usage of ~/.ollama/models; warn if above 80%.
#   4. Output the last 5 failed SSH login attempts.
#
# ---------------------------------------------------------------------------
# CHANGES MADE FROM THE AI'S ORIGINAL DRAFT (documented per assignment):
#   1. Original draft used `ps aux | grep ollama` to detect the running
#      process. Changed to `systemctl is-active ollama` because SierraLab
#      runs Ollama as a systemd service — grepping ps is unreliable (matches
#      grep's own process, doesn't confirm systemd's view of the unit) and
#      doesn't let us cleanly restart via systemctl.
#   2. Original draft parsed `netstat -tuln`. Changed to `ss -tuln` since
#      netstat is deprecated/not installed by default on current SierraLab
#      image; ss is the modern replacement and is already used elsewhere in
#      the course's lab scripts.
#   3. Original draft used `du -sh` for the models directory and eyeballed
#      the output. Changed to `df` against the filesystem the directory
#      lives on, so the 80% threshold is checked against actual partition
#      capacity, not just the size of the folder in isolation (a folder can
#      be "small" while the partition it sits on is nearly full).
#   4. Original draft grepped /var/log/auth.log directly. Added a fallback
#      to `journalctl` for systemd-journal-only systems (no flat auth.log),
#      since SierraLab's minimal install doesn't guarantee rsyslog is
#      writing to a flat file.
#   5. Added set -uo pipefail and quoting throughout for safer execution;
#      the AI draft did not guard against unset variables.
#   6. Added timestamped section headers to output for easier reading when
#      run interactively or piped to a log file.
# ---------------------------------------------------------------------------

set -uo pipefail

OLLAMA_PORT=11434
MODELS_DIR="$HOME/.ollama/models"
THRESHOLD=80

echo "==================================================="
echo " Ollama Check - $(hostname) - $(date '+%Y-%m-%d %H:%M:%S')"
echo "==================================================="

# ---------------------------------------------------------------------------
# 1. Is Ollama running? Restart if not.
# ---------------------------------------------------------------------------
echo ""
echo "[1] Service Status"
echo "-------------------"
if systemctl is-active --quiet ollama; then
    echo "OK: Ollama service is running."
else
    echo "WARN: Ollama service is NOT running. Attempting restart..."
    if sudo systemctl restart ollama; then
        sleep 2
        if systemctl is-active --quiet ollama; then
            echo "OK: Ollama service restarted successfully."
        else
            echo "FAIL: Ollama service failed to start after restart attempt."
        fi
    else
        echo "FAIL: Could not issue restart command (check sudo/systemd permissions)."
    fi
fi

# ---------------------------------------------------------------------------
# 2. Bound to 127.0.0.1, not 0.0.0.0?
# ---------------------------------------------------------------------------
echo ""
echo "[2] Bind Address Security Check"
echo "--------------------------------"
BIND_LINE=$(ss -tuln 2>/dev/null | grep ":${OLLAMA_PORT} ")
if [ -z "$BIND_LINE" ]; then
    echo "WARN: Could not find Ollama listening on port ${OLLAMA_PORT}. Is it running?"
elif echo "$BIND_LINE" | grep -q "0.0.0.0:${OLLAMA_PORT}"; then
    echo "WARN: Ollama is bound to 0.0.0.0 (all interfaces) - INSECURE."
    echo "      Recommend setting OLLAMA_HOST=127.0.0.1 in the service config."
elif echo "$BIND_LINE" | grep -q "127.0.0.1:${OLLAMA_PORT}"; then
    echo "OK: Ollama is bound to 127.0.0.1 (localhost only)."
else
    echo "INFO: Unexpected bind address:"
    echo "$BIND_LINE"
fi

# ---------------------------------------------------------------------------
# 3. Disk usage of ~/.ollama/models - warn if partition above 80%.
# ---------------------------------------------------------------------------
echo ""
echo "[3] Model Storage Disk Usage"
echo "-----------------------------"
if [ -d "$MODELS_DIR" ]; then
    FOLDER_SIZE=$(du -sh "$MODELS_DIR" 2>/dev/null | cut -f1)
    USE_PCT=$(df --output=pcent "$MODELS_DIR" 2>/dev/null | tail -1 | tr -d ' %')
    echo "Models folder size: ${FOLDER_SIZE}"
    if [ -n "$USE_PCT" ]; then
        echo "Partition usage: ${USE_PCT}%"
        if [ "$USE_PCT" -ge "$THRESHOLD" ]; then
            echo "WARN: Partition hosting ${MODELS_DIR} is at ${USE_PCT}% (threshold ${THRESHOLD}%)."
        else
            echo "OK: Partition usage is below ${THRESHOLD}% threshold."
        fi
    else
        echo "WARN: Could not determine partition usage percentage."
    fi
else
    echo "WARN: ${MODELS_DIR} does not exist. Is Ollama installed for this user?"
fi

# ---------------------------------------------------------------------------
# 4. Last 5 failed SSH login attempts.
# ---------------------------------------------------------------------------
echo ""
echo "[4] Last 5 Failed SSH Login Attempts"
echo "-------------------------------------"
if [ -f /var/log/auth.log ]; then
    grep "Failed password" /var/log/auth.log 2>/dev/null | tail -n 5
elif command -v journalctl >/dev/null 2>&1; then
    journalctl -u ssh -u sshd 2>/dev/null | grep "Failed password" | tail -n 5
else
    echo "INFO: No auth.log found and journalctl unavailable."
fi
echo ""
echo "==================================================="
echo " Check complete."
echo "==================================================="