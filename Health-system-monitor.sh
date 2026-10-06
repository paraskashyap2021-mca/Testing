#!/bin/bash
#
# health-monitor.sh — System Health Monitor (Capstone)
# Collects CPU/memory/disk, compares to thresholds, logs, alerts,
# and prunes its own old logs. Schedule via cron.
# git cong
set -euo pipefail
# ---------------- CONFIG (tune these) ----------------
LOGFILE="${LOGFILE:-$HOME/health.log}"
CPU_MAX="${CPU_MAX:-80}"
MEM_MAX="${MEM_MAX:-80}"
DISK_MAX="${DISK_MAX:-80}"
RETAIN_DAYS="${RETAIN_DAYS:-7}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}" # optional; empty = skip webhook
# ---------------- SAFETY: cleanup on exit ----------------
trap 'rc=$?; [ $rc -ne 0 ] && log ERROR "monitor exited with code $rc"; exit $rc' EXIT
# ---------------- LOGGING ----------------
log() {
local level="$1"; shift
echo "$(date '+%F %T') [$level] $*" | tee -a "$LOGFILE"
}
# ---------------- ALERTING ----------------
alert() {
local msg="$1"
log ERROR "ALERT: $msg"
# optional Slack webhook (only if a URL is configured and curl exists)
if [ -n "$SLACK_WEBHOOK_URL" ] && command -v curl >/dev/null; then
curl -s -X POST -H 'Content-type: application/json' \
-d "{\"text\":\"[$(hostname)] $msg\"}" "$SLACK_WEBHOOK_URL" >/dev/null || \
log WARN "failed to post to Slack webhook"
fi
}
# ---------------- ONE REUSABLE CHECKER ----------------
check() { # $1=name $2=value $3=limit
local name="$1" value="$2" limit="$3"
if [ "$value" -gt "$limit" ]; then
alert "$name at ${value}% (limit ${limit}%)"
else
log INFO "$name ok at ${value}%"
fi
}
# ---------------- COLLECT METRICS ----------------
collect() {
DISK=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
MEM=$(free | awk '/Mem/ {printf "%.0f", $3/$2*100}')
# CPU% from 1-min load average / cores (robust, no top dependency)
local load cores
load=$(awk '{print $1}' /proc/loadavg)
cores=$(nproc)
CPU=$(awk -v l="$load" -v c="$cores" 'BEGIN {printf "%.0f", (l/c)*100}')
}
# ---------------- FILESYSTEM AUTOMATION: prune old logs ----------------
prune_logs() {
local dir; dir=$(dirname "$LOGFILE")
find "$dir" -maxdepth 1 -name '*.log' -mtime +"$RETAIN_DAYS" -delete 2>/dev/null || true
log INFO "pruned logs older than ${RETAIN_DAYS} days in $dir"
}
# ---------------- MAIN ----------------
main() {
log INFO "----- health check start -----"
collect
check CPU "$CPU" "$CPU_MAX"
check MEM "$MEM" "$MEM_MAX"
check DISK "$DISK" "$DISK_MAX"
prune_logs
log INFO "----- health check done -----"
}
main "$@"
