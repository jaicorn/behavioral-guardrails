#!/usr/bin/env bash
# attempt-tracker.sh — Track failed approaches per task, suggest alternatives, block premature surrender
# State stored in /tmp/openclaw-attempts/ (ephemeral, per-session)
set -euo pipefail

STATE_DIR="/tmp/openclaw-attempts"
MINIMUM_ATTEMPTS=3

mkdir -p "$STATE_DIR"

usage() {
  cat <<'EOF'
Usage:
  attempt-tracker.sh log    --task TASK --method METHOD --result RESULT
  attempt-tracker.sh status --task TASK
  attempt-tracker.sh clear  --task TASK
  attempt-tracker.sh clear-all
EOF
  exit 1
}

[[ $# -lt 1 ]] && usage

COMMAND="$1"; shift
TASK="" METHOD="" RESULT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)   TASK="$2"; shift 2 ;;
    --method) METHOD="$2"; shift 2 ;;
    --result) RESULT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Sanitize task name for filename
task_file() {
  local safe
  safe=$(echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/_/g')
  echo "$STATE_DIR/${safe}.json"
}

# Ranked list of generic alternative approaches
GENERIC_SUGGESTIONS='[
  "Try a different API endpoint or URL pattern",
  "Use a proxy or mirror service",
  "Try browser automation (Playwright/Puppeteer)",
  "Search for the content via a search engine",
  "Check if cached/archived version exists (Wayback Machine, Google Cache)",
  "Try a different authentication method",
  "Parse from a different data source",
  "Use a different tool or library",
  "Try the operation with different parameters",
  "Manual extraction from screenshots or rendered output"
]'

case "$COMMAND" in
  log)
    [[ -z "$TASK" ]] && echo "Error: --task required" && exit 1
    [[ -z "$METHOD" ]] && echo "Error: --method required" && exit 1
    [[ -z "$RESULT" ]] && RESULT="no result recorded"

    FILE=$(task_file "$TASK")
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [[ -f "$FILE" ]]; then
      UPDATED=$(jq --arg m "$METHOD" --arg r "$RESULT" --arg ts "$TIMESTAMP" \
        '.attempts += [{"method": $m, "result": $r, "timestamp": $ts}]' "$FILE")
      echo "$UPDATED" > "$FILE"
    else
      jq -n --arg task "$TASK" --arg m "$METHOD" --arg r "$RESULT" --arg ts "$TIMESTAMP" \
        '{task: $task, attempts: [{"method": $m, "result": $r, "timestamp": $ts}], created: $ts}' > "$FILE"
    fi

    ATTEMPT_COUNT=$(jq '.attempts | length' "$FILE")
    EXHAUSTED="false"
    [[ "$ATTEMPT_COUNT" -ge "$MINIMUM_ATTEMPTS" ]] && EXHAUSTED="true"
    TRIED=$(jq '[.attempts[].method]' "$FILE")

    SUGGESTIONS=$(echo "$GENERIC_SUGGESTIONS" | jq --argjson tried "$TRIED" \
      '[.[] | select(. as $s | ($tried | map(ascii_downcase) | map(. as $t | $s | ascii_downcase | contains($t)) | any) | not)][:4]')

    jq -n --arg task "$TASK" --argjson count "$ATTEMPT_COUNT" --argjson min "$MINIMUM_ATTEMPTS" \
      --argjson exhausted "$EXHAUSTED" --argjson tried "$TRIED" --argjson suggestions "$SUGGESTIONS" \
      '{task: $task, attempts: $count, minimum: $min, exhausted: $exhausted, tried: $tried, suggestions: $suggestions}'
    ;;

  status)
    [[ -z "$TASK" ]] && echo "Error: --task required" && exit 1
    FILE=$(task_file "$TASK")

    if [[ ! -f "$FILE" ]]; then
      jq -n --arg task "$TASK" --argjson min "$MINIMUM_ATTEMPTS" --argjson suggestions "$GENERIC_SUGGESTIONS" \
        '{task: $task, attempts: 0, minimum: $min, exhausted: false, tried: [], suggestions: ($suggestions[:4])}'
      exit 0
    fi

    ATTEMPT_COUNT=$(jq '.attempts | length' "$FILE")
    EXHAUSTED="false"
    [[ "$ATTEMPT_COUNT" -ge "$MINIMUM_ATTEMPTS" ]] && EXHAUSTED="true"
    TRIED=$(jq '[.attempts[].method]' "$FILE")

    SUGGESTIONS=$(echo "$GENERIC_SUGGESTIONS" | jq --argjson tried "$TRIED" \
      '[.[] | select(. as $s | ($tried | map(ascii_downcase) | map(. as $t | $s | ascii_downcase | contains($t)) | any) | not)][:4]')

    jq -n --arg task "$TASK" --argjson count "$ATTEMPT_COUNT" --argjson min "$MINIMUM_ATTEMPTS" \
      --argjson exhausted "$EXHAUSTED" --argjson tried "$TRIED" --argjson suggestions "$SUGGESTIONS" \
      '{task: $task, attempts: $count, minimum: $min, exhausted: $exhausted, tried: $tried, suggestions: $suggestions}'
    ;;

  clear)
    [[ -z "$TASK" ]] && echo "Error: --task required" && exit 1
    FILE=$(task_file "$TASK")
    rm -f "$FILE"
    echo "{\"cleared\": \"$TASK\"}"
    ;;

  clear-all)
    rm -f "$STATE_DIR"/*.json 2>/dev/null || true
    echo '{"cleared": "all"}'
    ;;

  *)
    usage
    ;;
esac
