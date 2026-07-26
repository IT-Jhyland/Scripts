#!/bin/bash
#
# user_audit.sh
# Script 3 - User Audit
# Host: SierraLab Linux
#
# Purpose:
#   - List all users with login shells (not /sbin/nologin, /bin/false, etc.)
#   - Check which of those users have sudo rights
#   - Flag any user with UID 0 other than root
#
set -uo pipefail

echo "==================================================="
echo " User Audit - $(hostname) - $(date '+%Y-%m-%d %H:%M:%S')"
echo "==================================================="

# ---------------------------------------------------------------------------
# 1. Users with login shells
# ---------------------------------------------------------------------------
echo ""
echo "[1] Users With Login Shells"
echo "-----------------------------"
# Treat /sbin/nologin, /bin/false, /usr/sbin/nologin as "no login" shells.
# Everything else in /etc/passwd's shell field counts as a login shell.
LOGIN_USERS=$(awk -F: '
    $7 !~ /(nologin|false)$/ { print $1 ":" $3 ":" $7 }
' /etc/passwd)

if [ -z "$LOGIN_USERS" ]; then
    echo "No users with login shells found."
else
    printf "%-20s %-8s %s\n" "USERNAME" "UID" "SHELL"
    echo "$LOGIN_USERS" | while IFS=: read -r uname uid shell; do
        printf "%-20s %-8s %s\n" "$uname" "$uid" "$shell"
    done
fi

# ---------------------------------------------------------------------------
# 2. Which of those users have sudo rights?
# ---------------------------------------------------------------------------
echo ""
echo "[2] Sudo Rights"
echo "-----------------"
# A user has sudo rights if they're in the 'sudo' or 'wheel' group
# (covers both Debian/Ubuntu-style and RHEL-style admin groups),
# or if they have an explicit entry in /etc/sudoers / /etc/sudoers.d/.
SUDO_GROUP_MEMBERS=""
for grp in sudo wheel admin; do
    if getent group "$grp" >/dev/null 2>&1; then
        members=$(getent group "$grp" | awk -F: '{print $4}')
        if [ -n "$members" ]; then
            SUDO_GROUP_MEMBERS="${SUDO_GROUP_MEMBERS},${members}"
        fi
    fi
done
SUDO_GROUP_MEMBERS=$(echo "$SUDO_GROUP_MEMBERS" | tr ',' '\n' | tr ',' '\n' | sed '/^$/d' | tr '\n' ',' )

echo "$LOGIN_USERS" | while IFS=: read -r uname uid shell; do
    # root always has full rights by definition (UID 0) - it doesn't need
    # to be in the sudo/wheel group, so calling that out separately avoids
    # a misleading "no sudo rights" line for the root account itself.
    if [ "$uid" = "0" ]; then
        echo "  ${uname}: N/A - root account (UID 0, inherently has full rights)"
        continue
    fi

    IN_GROUP="no"
    echo ",$SUDO_GROUP_MEMBERS," | grep -q ",$uname," && IN_GROUP="yes"

    IN_SUDOERS="no"
    if [ -r /etc/sudoers ] && sudo -n true 2>/dev/null; then
        # Only works if we actually have passwordless sudo ourselves;
        # otherwise we silently skip this deeper check.
        sudo grep -Eq "^[[:space:]]*${uname}[[:space:]]" /etc/sudoers 2>/dev/null && IN_SUDOERS="yes"
    fi

    if [ "$IN_GROUP" = "yes" ] || [ "$IN_SUDOERS" = "yes" ]; then
        echo "  ${uname}: HAS sudo rights"
    else
        echo "  ${uname}: no sudo rights"
    fi
done

# ---------------------------------------------------------------------------
# 3. Flag any user with UID 0 other than root
# ---------------------------------------------------------------------------
echo ""
echo "[3] UID 0 Check"
echo "------------------"
UID0_OTHERS=$(awk -F: '$3 == 0 && $1 != "root" {print $1}' /etc/passwd)
if [ -z "$UID0_OTHERS" ]; then
    echo "OK: No users other than 'root' have UID 0."
else
    echo "WARNING: The following non-root users have UID 0 (this is a serious security issue):"
    echo "$UID0_OTHERS" | sed 's/^/  - /'
fi

echo ""
echo "==================================================="
echo " Audit complete."
echo "==================================================="