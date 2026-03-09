#!/usr/bin/env bash
# idle_monitor.sh — ashigaru/gunshi idle detection daemon
# Checks panes every 60s, notifies karo after 2min idle

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$REPO_DIR/logs/idle_monitor.log"
SESSION="multiagent"
# pane_index -> agent_id mapping (cmd_173: 殿最終指示 管理層先・実行層後)
# karo=0.0, komadukai=0.1 は監視対象外（管理層）
# gunshi=0.2, ashigaru1-7=0.3-0.9
declare -A PANE_AGENT=(
  ["0.2"]="gunshi"
  ["0.3"]="ashigaru1" ["0.4"]="ashigaru2" ["0.5"]="ashigaru3"
  ["0.6"]="ashigaru4" ["0.7"]="ashigaru5" ["0.8"]="ashigaru6"
  ["0.9"]="ashigaru7"
)
mkdir -p "$REPO_DIR/logs" /tmp/idle_monitor_state

log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

check_idle() {
  local pane="$1" agent="$2"
  local content
  content=$(tmux capture-pane -t "${SESSION}:${pane}" -p 2>/dev/null | tail -3) || return 1
  # Idle = ends with ❯ or $ prompt with no running process
  if echo "$content" | grep -qE '❯\s*$|^\s*\$\s*$'; then
    echo "idle"
  else
    echo "busy"
  fi
}

notify_karo() {
  local agent="$1"
  bash "$REPO_DIR/scripts/inbox_write.sh" karo \
    "【idle検知】${agent}がアイドル状態2分超。タスク割り当てまたは報告回収を確認せよ。" \
    idle_alert idle_monitor
}

# PIDファイル管理
PID_FILE="/tmp/idle_monitor.pid"
echo $$ > "$PID_FILE"

log "idle_monitor started (PID=$$)"
declare -A IDLE_COUNT=()

while true; do
  for pane in "${!PANE_AGENT[@]}"; do
    agent="${PANE_AGENT[$pane]}"
    state_file="/tmp/idle_monitor_state/${agent}"
    status=$(check_idle "$pane" "$agent" 2>/dev/null || echo "unknown")

    if [[ "$status" == "idle" ]]; then
      IDLE_COUNT[$agent]=$(( ${IDLE_COUNT[$agent]:-0} + 1 ))
      if [[ ${IDLE_COUNT[$agent]} -ge 2 ]] && [[ ! -f "$state_file" ]]; then
        log "IDLE ALERT: $agent idle for 2+ min"
        notify_karo "$agent"
        touch "$state_file"
      fi
    else
      IDLE_COUNT[$agent]=0
      rm -f "$state_file"
    fi
  done
  sleep 60
done
