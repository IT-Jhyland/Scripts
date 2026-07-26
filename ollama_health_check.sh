#!/bin/bash
#
# ollama_health_check.sh
# Script 2 - Ollama Health Check
# Host: SierraLab Linux
#
# For each check below, prints PASS or FAIL, then rolls everything up into
# a final summary: HEALTHY / WARNING / CRITICAL
#
#   - Is the Ollama service running?            (systemctl is-active ollama)
#   - Is Ollama bound to 127.0.0.1, not 0.0.0.0? (ss -tuln | grep 11434)
#   - Is the Ollama API responding?              (curl http://localhost:11434/api/tags)
#   - How many models are installed?             (ollama list | tail -n +2 | wc -l)
#   - Is model disk usage below 80% of the partition?
#   - Any ERROR entries in the Ollama journal in the last hour?
#
set -uo pipefail

OLLAMA_PORT=11434
MODELS_DIR="$HOME/.ollama/models"
THRESHOLD=80

# Track failures/warnings for the final rollup.
FAIL_COUNT=0
WARN_COUNT=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
warn() { echo "WARN: $1"; WARN_COUNT=$((WARN_COUNT+1)); }

echo "==================================================="
echo " Ollama Health Check - $(hostname) - $(date '+%Y-%m-%d %H:%M:%S')"
echo "==================================================="

# ---------------------------------------------------------------------------
# 1. Is the Ollama service running?
# ---------------------------------------------------------------------------
echo ""
echo "[1] Service Running"
if systemctl is-active --quiet ollama 2>/dev/null; then
    pass "Ollama service is active."
    SERVICE_UP=true
else
    fail "Ollama service is not active (systemctl is-active ollama)."
    SERVICE_UP=false
fi

# ---------------------------------------------------------------------------
# 2. Bound to 127.0.0.1, not 0.0.0.0?
# ---------------------------------------------------------------------------
echo ""
echo "[2] Bind Address"
BIND_LINE=$(ss -tuln 2>/dev/null | grep ":${OLLAMA_PORT} ")
if [ -z "$BIND_LINE" ]; then
    fail "Ollama is not listening on port ${OLLAMA_PORT} (ss -tuln found nothing)."
elif echo "$BIND_LINE" | grep -q "0.0.0.0:${OLLAMA_PORT}"; then
    fail "Ollama is bound to 0.0.0.0 (all interfaces) - insecure."
elif echo "$BIND_LINE" | grep -q "127.0.0.1:${OLLAMA_PORT}"; then
    pass "Ollama is bound to 127.0.0.1 only."
else
    warn "Ollama is listening but on an unexpected address: $BIND_LINE"
fi

# ---------------------------------------------------------------------------
# 3. Is the Ollama API responding?
# ---------------------------------------------------------------------------
echo ""
echo "[3] API Responding"
API_RESPONSE=$(curl -s -m 5 http://localhost:${OLLAMA_PORT}/api/tags 2>/dev/null)
if [ -n "$API_RESPONSE" ]; then
    pass "Ollama API responded on http://localhost:${OLLAMA_PORT}/api/tags."
else
    fail "Ollama API did not respond (curl returned empty/timed out)."
fi

# ---------------------------------------------------------------------------
# 4. How many models are installed?
# ---------------------------------------------------------------------------
echo ""
echo "[4] Installed Models"
if command -v ollama >/dev/null 2>&1; then
    MODEL_COUNT=$(ollama list 2>/dev/null | tail -n +2 | wc -l)
    if [ "$MODEL_COUNT" -gt 0 ]; then
        pass "${MODEL_COUNT} model(s) installed."
    else
        warn "Ollama CLI is present but no models are installed."
    fi
else
    fail "Ollama CLI ('ollama' command) not found - cannot list models."
    MODEL_COUNT=0
fi

# ---------------------------------------------------------------------------
# 5. Model disk usage below 80% of the partition?
# ---------------------------------------------------------------------------
echo ""
echo "[5] Model Storage Disk Usage"
if [ -d "$MODELS_DIR" ]; then
    USE_PCT=$(df --output=pcent "$MODELS_DIR" 2>/dev/null | tail -1 | tr -d ' %')
    if [ -n "$USE_PCT" ]; then
        if [ "$USE_PCT" -ge "$THRESHOLD" ]; then
            fail "Partition hosting ${MODELS_DIR} is at ${USE_PCT}% (threshold ${THRESHOLD}%)."
        else
            pass "Partition usage is ${USE_PCT}%, below ${THRESHOLD}% threshold."
        fi
    else
        warn "Could not determine partition usage percentage for ${MODELS_DIR}."
    fi
else
    warn "${MODELS_DIR} does not exist - Ollama may not be installed for this user."
fi

# ---------------------------------------------------------------------------
# 6. Any ERROR entries in the Ollama journal in the last hour?
# ---------------------------------------------------------------------------
echo ""
echo "[6] Recent Journal Errors"
if command -v journalctl >/dev/null 2>&1; then
    ERROR_LINES=$(journalctl -u ollama --since "1 hour ago" 2>/dev/null | grep -i "error")
    ERROR_COUNT=$(echo "$ERROR_LINES" | grep -c . || true)
    if [ -z "$ERROR_LINES" ]; then
        pass "No ERROR entries in the Ollama journal in the last hour."
    else
        fail "${ERROR_COUNT} ERROR entr$([ "$ERROR_COUNT" -eq 1 ] && echo y || echo ies) found in the last hour:"
        echo "$ERROR_LINES" | sed 's/^/    /'
    fi
else
    warn "journalctl not available - cannot check Ollama journal."
fi

# ---------------------------------------------------------------------------
# Final Summary
# ---------------------------------------------------------------------------
echo ""
echo "==================================================="
if [ "$FAIL_COUNT" -eq 0 ] && [ "$WARN_COUNT" -eq 0 ]; then
    echo " OVERALL STATUS: HEALTHY"
elif [ "$FAIL_COUNT" -eq 0 ]; then
    echo " OVERALL STATUS: WARNING (${WARN_COUNT} warning(s), 0 failures)"
else
    echo " OVERALL STATUS: CRITICAL (${FAIL_COUNT} failure(s), ${WARN_COUNT} warning(s))"
fi
echo "==================================================="