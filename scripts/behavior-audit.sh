#!/usr/bin/env bash
# behavior-audit.sh — Behavioral scoring for heartbeat cycles
# Samples the last N responses and scores them for failure patterns.
# Output: Score 0-100 + specific callouts. Appends to $WORKSPACE/data/behavior-scores/YYYY-MM-DD.json
set -euo pipefail

# Auto-detect workspace: env var > ~/.openclaw/workspace > current dir
if [[ -n "${OPENCLAW_WORKSPACE:-}" ]]; then
  WORKSPACE="$OPENCLAW_WORKSPACE"
elif [[ -d "$HOME/.openclaw/workspace" ]]; then
  WORKSPACE="$HOME/.openclaw/workspace"
else
  WORKSPACE="$(pwd)"
fi

SCORE_DIR="$WORKSPACE/data/behavior-scores"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPLY_GATE="$SCRIPT_DIR/reply-gate.sh"
TODAY=$(date +"%Y-%m-%d")
SCORE_FILE="$SCORE_DIR/$TODAY.json"
SAMPLE_COUNT=5

mkdir -p "$SCORE_DIR"

# Parse args
INPUT_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) INPUT_FILE="$2"; shift 2 ;;
    --count) SAMPLE_COUNT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Read input into a single string first to detect delimiter mode
RAW_INPUT=""
if [[ -n "$INPUT_FILE" && -f "$INPUT_FILE" ]]; then
  RAW_INPUT="$(cat "$INPUT_FILE")"
else
  RAW_INPUT="$(cat)"
fi

RESPONSES=()
# If input contains "---" on its own line, split on that; otherwise split on newlines
if echo "$RAW_INPUT" | grep -qxF -- '---'; then
  # Split on --- delimiter (supports multiline responses)
  CURRENT=""
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      [[ -n "$CURRENT" ]] && RESPONSES+=("$CURRENT")
      CURRENT=""
    else
      if [[ -n "$CURRENT" ]]; then
        CURRENT="$CURRENT
$line"
      else
        CURRENT="$line"
      fi
    fi
  done <<< "$RAW_INPUT"
  [[ -n "$CURRENT" ]] && RESPONSES+=("$CURRENT")
else
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    RESPONSES+=("$line")
  done <<< "$RAW_INPUT"
fi

# Limit to last N
TOTAL=${#RESPONSES[@]}
if [[ "$TOTAL" -eq 0 ]]; then
  ENTRY=$(jq -n --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{timestamp: $ts, score: 100, samples: 0, violations: [], callouts: ["No responses to audit"]}')

  if [[ -f "$SCORE_FILE" ]]; then
    jq --argjson entry "$ENTRY" '. + [$entry]' "$SCORE_FILE" > "${SCORE_FILE}.tmp" && mv "${SCORE_FILE}.tmp" "$SCORE_FILE"
  else
    echo "[$ENTRY]" > "$SCORE_FILE"
  fi
  echo "$ENTRY"
  exit 0
fi

START=0
if [[ "$TOTAL" -gt "$SAMPLE_COUNT" ]]; then
  START=$((TOTAL - SAMPLE_COUNT))
fi

SCORE=100
ALL_VIOLATIONS="[]"
CALLOUTS="[]"
SAMPLES_CHECKED=0

for ((i=START; i<TOTAL; i++)); do
  RESP="${RESPONSES[$i]}"
  SAMPLES_CHECKED=$((SAMPLES_CHECKED + 1))

  GATE_RESULT=$(echo "$RESP" | bash "$REPLY_GATE" 2>/dev/null || echo '{"pass":true,"violations":[]}')
  PASS=$(echo "$GATE_RESULT" | jq -r '.pass')

  if [[ "$PASS" == "false" ]]; then
    VCOUNT=$(echo "$GATE_RESULT" | jq '.violations | length')

    for ((v=0; v<VCOUNT; v++)); do
      VTYPE=$(echo "$GATE_RESULT" | jq -r ".violations[$v].type")
      EVIDENCE=$(echo "$GATE_RESULT" | jq -r ".violations[$v].evidence")

      case "$VTYPE" in
        premature_surrender)      PENALTY=25 ;;
        answerable_question)      PENALTY=15 ;;
        work_handback)            PENALTY=20 ;;
        narration_without_action) PENALTY=10 ;;
        blocker_without_recovery) PENALTY=20 ;;
        false_completion)         PENALTY=30 ;;
        scope_substitution)       PENALTY=20 ;;
        burden_shifting_update)   PENALTY=15 ;;
        *)                        PENALTY=10 ;;
      esac

      SCORE=$((SCORE - PENALTY))
      [[ "$SCORE" -lt 0 ]] && SCORE=0

      ALL_VIOLATIONS=$(echo "$ALL_VIOLATIONS" | jq --arg t "$VTYPE" --arg e "$EVIDENCE" --argjson s "$((i - START + 1))" \
        '. + [{"type": $t, "evidence": $e, "sample": $s}]')

      CALLOUTS=$(echo "$CALLOUTS" | jq --arg c "Sample $((i - START + 1)): $VTYPE — $EVIDENCE" '. + [$c]')
    done
  fi
done

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

ENTRY=$(jq -n --arg ts "$TIMESTAMP" --argjson score "$SCORE" --argjson samples "$SAMPLES_CHECKED" \
  --argjson violations "$ALL_VIOLATIONS" --argjson callouts "$CALLOUTS" \
  '{timestamp: $ts, score: $score, samples: $samples, violations: $violations, callouts: $callouts}')

if [[ -f "$SCORE_FILE" ]]; then
  jq --argjson entry "$ENTRY" '. + [$entry]' "$SCORE_FILE" > "${SCORE_FILE}.tmp" && mv "${SCORE_FILE}.tmp" "$SCORE_FILE"
else
  echo "[$ENTRY]" > "$SCORE_FILE"
fi

echo "$ENTRY"
