#!/usr/bin/env bash
#
# Sierra Valley USD - Ollama AI Server Health Monitor (Script B)
#
# Checks:
#   1. Ollama service is running
#   2. Ollama API is responsive
#   3. Installed models are compared against the approved model list
#      (model governance policy - Deliverable 3) -> alerts on any unauthorized model
#   4. Whether the API is exposed on 0.0.0.0 (all interfaces) instead of
#      bound to localhost only -> alerts if so, since this is a direct
#      violation of the "API binding: 127.0.0.1 only" security design
#
# Usage:
#   ./ollama-health-monitor.sh
#   Recommended: run via cron every 15 minutes
#     */15 * * * * /opt/scripts/ollama-health-monitor.sh >> /var/log/ollama-health.log 2>&1
#
# Author: Jon - IT0100 Final Project, Part D
#
set -uo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
OLLAMA_API_URL="http://127.0.0.1:11434"
OLLAMA_PORT=11434
LOG_FILE="/var/log/ollama-health.log"

# Approved model list - must match the model governance policy in Deliverable 3.
# Any model installed on this server that is NOT in this list triggers an alert.
APPROVED_MODELS=(
    "llama3.1:8b"
    "mistral:7b"
    "phi3:mini"
)

ALERT_COUNT=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() {
    local level="$1"; shift
    local msg="$*"
    local line
    line="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${msg}"
    echo "${line}"
}

alert() {
    # Central alert function - currently logs at ALERT level.
    # Swap/extend this to call a webhook, send mail, or push to a SIEM
    # once the district has a monitoring platform in place.
    log "ALERT" "$*"
    ALERT_COUNT=$((ALERT_COUNT + 1))
}

is_model_approved() {
    local model="$1"
    for approved in "${APPROVED_MODELS[@]}"; do
        if [[ "$model" == "$approved" ]]; then
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# 1. Is the Ollama service running?
# ---------------------------------------------------------------------------
log "INFO" "=== Ollama health check starting ==="

if systemctl is-active --quiet ollama 2>/dev/null; then
    log "OK" "Ollama systemd service is active."
else
    alert "Ollama service is NOT running (systemctl is-active failed)."
fi

# ---------------------------------------------------------------------------
# 2. Is the API responsive?
# ---------------------------------------------------------------------------
if curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${OLLAMA_API_URL}/api/tags" | grep -q "200"; then
    log "OK" "Ollama API responded successfully at ${OLLAMA_API_URL}."
else
    alert "Ollama API did not respond at ${OLLAMA_API_URL} (service may be down or hung)."
fi

# ---------------------------------------------------------------------------
# 3. Unauthorized model detection
# ---------------------------------------------------------------------------
MODEL_LIST_JSON="$(curl -s --max-time 5 "${OLLAMA_API_URL}/api/tags" 2>/dev/null)"

if [[ -n "${MODEL_LIST_JSON}" ]]; then
    # Extract model names from the JSON response without requiring jq,
    # falling back to jq if it's available for more reliable parsing.
    if command -v jq >/dev/null 2>&1; then
        INSTALLED_MODELS=$(echo "${MODEL_LIST_JSON}" | jq -r '.models[].name' 2>/dev/null)
    else
        INSTALLED_MODELS=$(echo "${MODEL_LIST_JSON}" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//')
    fi

    if [[ -z "${INSTALLED_MODELS}" ]]; then
        log "WARN" "Could not parse installed model list from API response."
    else
        while IFS= read -r model; do
            [[ -z "$model" ]] && continue
            if is_model_approved "$model"; then
                log "OK" "Model '${model}' is on the approved list."
            else
                alert "Unauthorized model detected: '${model}' is NOT on the approved model list. Investigate immediately - possible policy violation or unauthorized deployment."
            fi
        done <<< "${INSTALLED_MODELS}"
    fi
else
    log "WARN" "Could not retrieve model list from API - skipping model governance check."
fi

# ---------------------------------------------------------------------------
# 4. Check whether API is exposed on 0.0.0.0 instead of localhost only
# ---------------------------------------------------------------------------
# This directly checks the security design requirement from Deliverable 3:
# the Ollama API must bind to 127.0.0.1 only, never all interfaces.
LISTEN_INFO=""
if command -v ss >/dev/null 2>&1; then
    LISTEN_INFO=$(ss -tlnp 2>/dev/null | grep ":${OLLAMA_PORT} ")
elif command -v netstat >/dev/null 2>&1; then
    LISTEN_INFO=$(netstat -tlnp 2>/dev/null | grep ":${OLLAMA_PORT} ")
fi

if [[ -n "${LISTEN_INFO}" ]]; then
    if echo "${LISTEN_INFO}" | grep -qE '0\.0\.0\.0:'"${OLLAMA_PORT}"'|\*:'"${OLLAMA_PORT}"; then
        alert "Ollama API is bound to 0.0.0.0 (ALL interfaces) on port ${OLLAMA_PORT} - this exposes the AI server API district-wide, violating the 127.0.0.1-only binding policy. Fix OLLAMA_HOST setting immediately."
    elif echo "${LISTEN_INFO}" | grep -qE '127\.0\.0\.1:'"${OLLAMA_PORT}"; then
        log "OK" "Ollama API is correctly bound to 127.0.0.1 only."
    else
        log "WARN" "Ollama is listening on port ${OLLAMA_PORT} but binding address could not be confirmed as localhost-only: ${LISTEN_INFO}"
    fi
else
    log "WARN" "Could not determine listening state for port ${OLLAMA_PORT} (ss/netstat unavailable or port not found)."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log "INFO" "=== Ollama health check complete: ${ALERT_COUNT} alert(s) raised ==="

if [[ "${ALERT_COUNT}" -gt 0 ]]; then
    exit 1
else
    exit 0
fi
