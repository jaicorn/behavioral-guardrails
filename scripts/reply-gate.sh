#!/usr/bin/env bash
# reply-gate.sh — Pre-reply behavioral gate for AI agents
# Analyzes draft responses and catches failure patterns before they reach the user.
# Input: stdin or --text "..."
# Output: JSON {pass: bool, violations: [{type, evidence, suggestion}]}
set -euo pipefail

TEXT=""

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --text) TEXT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Read from stdin if no --text
if [[ -z "$TEXT" ]]; then
  TEXT="$(cat)"
fi

if [[ -z "$TEXT" ]]; then
  echo '{"pass":true,"violations":[]}'
  exit 0
fi

VIOLATIONS="[]"

add_violation() {
  local type="$1" evidence="$2" suggestion="$3"
  VIOLATIONS=$(echo "$VIOLATIONS" | jq --arg t "$type" --arg e "$evidence" --arg s "$suggestion" \
    '. + [{"type": $t, "evidence": $e, "suggestion": $s}]')
}

# --- Pattern 1: Premature Surrender ---
# Look for failure/inability language without evidence of multiple attempts
SURRENDER_PATTERNS='(unfortunately.*(not able|unable|cannot|couldn.t|failed)|i was unable to|this (doesn.t|does not) (seem to )?work|i (couldn.t|can.t|cannot) (figure out|find|access|complete|do)|giving up|no luck|hit a (wall|dead end)|this approach (failed|doesn.t work)|none of (these|the) (approaches|methods) worked)'
if echo "$TEXT" | grep -iqE "$SURRENDER_PATTERNS"; then
  # Count documented attempts (lines starting with tried/attempt/approach or numbered lists of methods)
  ATTEMPT_COUNT=$(echo "$TEXT" | grep -icE '(^[0-9]+\.|attempt [0-9]|tried [0-9]|approach [0-9]|method [0-9]|try [0-9])' || true)
  if [[ "$ATTEMPT_COUNT" -lt 3 ]]; then
    EVIDENCE=$(echo "$TEXT" | grep -ioE "$SURRENDER_PATTERNS" | head -1)
    add_violation "premature_surrender" \
      "$EVIDENCE" \
      "Document at least 3 materially different approaches before reporting failure. Use attempt-tracker.sh to log attempts."
  fi
fi

# --- Pattern 2: Answerable Questions ---
# Questions the agent should look up itself
ANSWERABLE_PATTERNS='(what is (your|the) (email|phone|address|password|api key|account)|do you (have|know|remember) (a |the )?(password|login|credentials|api|key|token|number|address)|what.s (your|the) (username|login)|where (is|are|did|do) (you|your|the) (keep|store|put|save|find)|can you (remind|tell) me (of |about )?(your|the)|which (file|folder|directory|repo|service|account))'
if echo "$TEXT" | grep -iqE "$ANSWERABLE_PATTERNS"; then
  EVIDENCE=$(echo "$TEXT" | grep -ioE "$ANSWERABLE_PATTERNS" | head -1)
  add_violation "answerable_question" \
    "$EVIDENCE" \
    "Look this up yourself: check memory files, data/, credentials, previous conversations, or system config before asking."
fi

# --- Pattern 3: Work Handback ---
# Phrases that push work back to the user when the agent could do it
HANDBACK_PATTERNS='(here.s how you can|you (could|can|might|should|would need to|may want to) (try|run|do|check|update|install|configure|set up|create|open|go to|navigate|visit|click)|would you like me to|shall i|want me to|i can .* if you.d like|you.ll (need|want|have) to|let me know if you.d like me to|i.d recommend (you|that you))'
if echo "$TEXT" | grep -iqE "$HANDBACK_PATTERNS"; then
  # Whitelist: destructive/irreversible actions legitimately need confirmation
  DESTRUCTIVE_PATTERNS='(delete|destroy|drop|remove permanently|irreversible|production|wipe|purge|truncate|format)'
  DESTRUCTIVE_MATCH=$(echo "$TEXT" | grep -icE "$DESTRUCTIVE_PATTERNS" || true)
  if [[ "$DESTRUCTIVE_MATCH" -lt 1 ]]; then
    EVIDENCE=$(echo "$TEXT" | grep -ioE "$HANDBACK_PATTERNS" | head -1)
    add_violation "work_handback" \
      "$EVIDENCE" \
      "Do the work directly instead of describing it or asking permission. If it's within your capability, execute it."
  fi
fi

# --- Pattern 4: Narration Without Action ---
# Describing plans without executing them
NARRATION_PATTERNS='(i.m going to|i will now|let me (start|begin) by|first.*(i.ll|i will|we.ll|we will)|my plan is to|the (next step|approach) (is|will be|would be) to|here.s (my|the) (plan|approach|strategy)|i.ll (start|begin|proceed) (by|with)|what i.ll do is)'
if echo "$TEXT" | grep -iqE "$NARRATION_PATTERNS"; then
  # Only flag if the response is MOSTLY narration (no tool calls or code blocks)
  ACTION_INDICATORS=$(echo "$TEXT" | grep -cE '(^```|\$ |executed|output:|result:|created |wrote |edited |ran )' || true)
  if [[ "$ACTION_INDICATORS" -lt 1 ]]; then
    EVIDENCE=$(echo "$TEXT" | grep -ioE "$NARRATION_PATTERNS" | head -1)
    add_violation "narration_without_action" \
      "$EVIDENCE" \
      "Stop narrating and start doing. Execute the action directly instead of describing your plan."
  fi
fi

# --- Pattern 5: Blocker Escalation Without Recovery ---
# Reporting a tool/API failure as a blocker without trying alternatives
BLOCKER_PATTERNS='(this (is|appears to be) (a )?block(er|ed|ing)|blocked by|can.t proceed (because|until|without)|need .* (access|permission|credentials|approval) (to|before)|waiting (on|for) .* (to|before)|this requires .* (that|which) (i|we) (don.t|do not) have|unfortunately.*(api|tool|service|endpoint).*(down|unavailable|broken|not working|error|failed))'
if echo "$TEXT" | grep -iqE "$BLOCKER_PATTERNS"; then
  # Check if alternatives were mentioned
  ALT_COUNT=$(echo "$TEXT" | grep -icE '(alternatively|instead|workaround|fallback|another (approach|way|method|option)|plan b|backup plan|as an alternative)' || true)
  if [[ "$ALT_COUNT" -lt 1 ]]; then
    EVIDENCE=$(echo "$TEXT" | grep -ioE "$BLOCKER_PATTERNS" | head -1)
    add_violation "blocker_without_recovery" \
      "$EVIDENCE" \
      "Try at least 2 alternative approaches before escalating a blocker. Use attempt-tracker.sh to find suggestions."
  fi
fi

# --- Pattern 6: False Completion ---
# Claiming done/complete/sent without evidence markers
FALSE_COMPLETION_PATTERNS='(done|complete[d]?|sent|updated|fixed|deployed|finished|shipped|resolved|pushed)'
if echo "$TEXT" | grep -iqE "$FALSE_COMPLETION_PATTERNS"; then
  # Check for evidence markers: code blocks, file paths, URLs, output/confirmed/verified, numbers (specificity), restart/pass indicators, capitalized artifact names
  EVIDENCE_MARKERS=$(echo "$TEXT" | grep -cE '(^```|/[a-zA-Z0-9_./-]+\.[a-z]+|https?://|output:|result:|confirmed|verified|error [0-9]|status [0-9]|"[^"]+\.[a-z]+"|\$ |[0-9]{2,}|restarted|passing|tests? pass|working now|succeeded|workaround|[A-Z]{2,}[A-Z])' || true)
  if [[ "$EVIDENCE_MARKERS" -lt 1 ]]; then
    EVIDENCE=$(echo "$TEXT" | grep -ioE "$FALSE_COMPLETION_PATTERNS" | head -1)
    add_violation "false_completion" \
      "$EVIDENCE" \
      "Include evidence when claiming completion: file paths, URLs, command output, or verification steps."
  fi
fi

# --- Pattern 7: Scope Substitution ---
# Doing something adjacent instead of what was asked
SCOPE_SUB_PATTERNS='(instead,? i|rather than .* i|as an alternative|i went ahead and .* instead|i did .* rather than|a different approach)'
if echo "$TEXT" | grep -iqE "$SCOPE_SUB_PATTERNS"; then
  EVIDENCE=$(echo "$TEXT" | grep -ioE "$SCOPE_SUB_PATTERNS" | head -1)
  add_violation "scope_substitution" \
    "$EVIDENCE" \
    "Complete the originally requested scope. If you pivoted, explain why and confirm the original ask is still addressed."
fi

# --- Pattern 8: Burden-Shifting Update ---
# Friction narration without completion, decision, or risk signal
BURDEN_SHIFT_FRICTION='(ran into|hit a snag|having trouble|struggling with|issue with|problem with|difficulty with|couldn.t get .* to work)'
BURDEN_SHIFT_RESOLUTION='(done|complete|fixed|result:|decision needed|risk:|blocker:|alternatively|workaround|solved|resolved|working now)'
if echo "$TEXT" | grep -iqE "$BURDEN_SHIFT_FRICTION"; then
  RESOLUTION_COUNT=$(echo "$TEXT" | grep -icE "$BURDEN_SHIFT_RESOLUTION" || true)
  if [[ "$RESOLUTION_COUNT" -lt 1 ]]; then
    # Only flag if the message is long enough to be a friction narrative (not a brief mention)
    WORD_COUNT=$(echo "$TEXT" | wc -w | tr -d ' ')
    if [[ "$WORD_COUNT" -gt 15 ]]; then
      EVIDENCE=$(echo "$TEXT" | grep -ioE "$BURDEN_SHIFT_FRICTION" | head -1)
      add_violation "burden_shifting_update" \
        "$EVIDENCE" \
        "Status updates must contain completion, a decision needed, or a risk change. Friction narration without resolution adds cognitive load."
    fi
  fi
fi

# --- Output ---
PASS="true"
VCOUNT=$(echo "$VIOLATIONS" | jq 'length')
if [[ "$VCOUNT" -gt 0 ]]; then
  PASS="false"
fi

jq -n --argjson pass "$PASS" --argjson violations "$VIOLATIONS" \
  '{"pass": $pass, "violations": $violations}'
