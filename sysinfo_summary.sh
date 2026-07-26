#!/bin/bash
#
# sysinfo_summary.sh
# Script 1 - System Info Summary
# Host: SierraLab Linux
#
# Purpose:
#   Collects and reports:
#     - Hostname, IP, OS version, kernel, uptime
#     - Disk usage - flags any filesystem above 80%
#     - Memory and CPU model
#   Writes output to ~/sysinfo_[date].txt
#
set -uo pipefail

THRESHOLD=80
OUTFILE="$HOME/sysinfo_$(date '+%Y-%m-%d').txt"

{
    echo "==================================================="
    echo " System Info Summary - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "==================================================="

    echo ""
    echo "[Hostname]"
    hostname

    echo ""
    echo "[IP Address(es)]"
    # Prefer 'ip' (modern), fall back to hostname -I, then ifconfig
    if command -v ip >/dev/null 2>&1; then
        ip -4 addr show scope global | awk '/inet /{print $2, "on", $NF}'
    elif command -v hostname >/dev/null 2>&1; then
        hostname -I
    elif command -v ifconfig >/dev/null 2>&1; then
        ifconfig | awk '/inet /{print $2}'
    else
        echo "Could not determine IP address (no ip/hostname/ifconfig available)."
    fi

    echo ""
    echo "[OS Version]"
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "${PRETTY_NAME:-Unknown OS}"
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -d | cut -f2
    else
        echo "Unknown (no /etc/os-release or lsb_release found)"
    fi

    echo ""
    echo "[Kernel]"
    uname -r

    echo ""
    echo "[Uptime]"
    uptime -p 2>/dev/null || uptime

    echo ""
    echo "[Disk Usage] (flagging any filesystem >= ${THRESHOLD}%)"
    echo "-----------------------------------------------------"
    # Print header once, then each real filesystem line, flagging >=80%
    df -hP -x tmpfs -x devtmpfs -x squashfs | awk -v thresh="$THRESHOLD" '
        NR==1 {print; next}
        {
            pct = $5
            gsub("%","",pct)
            line = $0
            if (pct+0 >= thresh) {
                print line "   <-- WARNING: " pct "% used"
            } else {
                print line
            }
        }'

    echo ""
    echo "[Memory]"
    free -h

    echo ""
    echo "[CPU Model]"
    if [ -f /proc/cpuinfo ]; then
        grep -m1 "model name" /proc/cpuinfo | sed 's/model name[[:space:]]*: //'
    else
        echo "Could not read /proc/cpuinfo"
    fi

    echo ""
    echo "==================================================="
    echo " End of report"
    echo "==================================================="
} | tee "$OUTFILE"

echo ""
echo "Report saved to: $OUTFILE"