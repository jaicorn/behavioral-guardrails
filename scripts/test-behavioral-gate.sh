#!/usr/bin/env bash
# test-behavioral-gate.sh — Test suite for the behavioral guardrail system
set -euo pipefail

# Auto-detect script directory for portable test execution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR"

# Use a temp dir for audit output to avoid polluting any workspace
export OPENCLAW_WORKSPACE="$(mktemp -d)"
mkdir -p "$OPENCLAW_WORKSPACE/data/behavior-scores"

TODAY=$(date +"%Y-%m-%d")
PASS_COUNT=0
FAIL_COUNT=0

green() { printf "\033[32m%s\033[0m\n" "$1"; }
red()   { printf "\033[31m%s\033[0m\n" "$1"; }

assert_pass() {
  local name="$1" result="$2"
  local pass
  pass=$(echo "$result" | jq -r '.pass')
  if [[ "$pass" == "true" ]]; then
    green "  PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    red "  FAIL: $name (expected pass, got fail)"
    echo "  Result: $result"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_fail() {
  local name="$1" result="$2" expected_type="${3:-}"
  local pass
  pass=$(echo "$result" | jq -r '.pass')
  if [[ "$pass" == "false" ]]; then
    if [[ -n "$expected_type" ]]; then
      local found
      found=$(echo "$result" | jq -r --arg t "$expected_type" '[.violations[].type] | map(select(. == $t)) | length')
      if [[ "$found" -gt 0 ]]; then
        green "  PASS: $name (caught $expected_type)"
        PASS_COUNT=$((PASS_COUNT + 1))
      else
        red "  FAIL: $name (expected $expected_type violation, got different type)"
        echo "  Result: $result"
        FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
    else
      green "  PASS: $name (caught violation)"
      PASS_COUNT=$((PASS_COUNT + 1))
    fi
  else
    red "  FAIL: $name (expected fail, got pass)"
    echo "  Result: $result"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

echo "=== Reply Gate Tests ==="

# Pattern 1: Premature Surrender
echo "--- Premature Surrender ---"

R=$(echo "Unfortunately I was unable to fetch the tweet. The API returned an error." | bash "$SCRIPTS/reply-gate.sh")
assert_fail "surrender after 1 attempt" "$R" "premature_surrender"

R=$(echo "I tried three different approaches:
1. Direct API call - returned 403
2. Using fxtwitter proxy - timeout
3. Browser automation with Playwright - stopped by captcha
Alternatively I could try a search engine, but unfortunately none of these approaches worked." | bash "$SCRIPTS/reply-gate.sh")
assert_pass "surrender after 3 documented attempts" "$R"

R=$(echo "I couldn't figure out how to parse that file." | bash "$SCRIPTS/reply-gate.sh")
assert_fail "giving up without attempts" "$R" "premature_surrender"

# Pattern 2: Answerable Questions
echo "--- Answerable Questions ---"

R=$(echo "What is your email address? I need it to send the report." | bash "$SCRIPTS/reply-gate.sh")
assert_fail "asking for email" "$R" "answerable_question"

R=$(echo "Do you have the API key for this service?" | bash "$SCRIPTS/reply-gate.sh")
assert_fail "asking for API key" "$R" "answerable_question"

R=$(echo "I found the API key in data/credentials and used it to authenticate." | bash "$SCRIPTS/reply-gate.sh")
assert_pass "looked up credentials self" "$R"

# Pattern 3: Work Handback
echo "--- Work Handback ---"

R=$(echo "Here's how you can fix this: open the config file and change the port to 3000." | bash "$SCRIPTS/reply-gate.sh")
assert_fail "handback with instructions" "$R" "work_handback"

R=$(echo "You could try running npm install to fix the dependency issue." | bash "$SCRIPTS/reply-gate.sh")
assert_fail "suggesting user run command" "$R" "work_handback"

R=$(echo "Would you like me to update the configuration?" | bash "$SCRIPTS/reply-gate.sh")
assert_fail "asking permission to act" "$R" "work_handback"

R=$(echo "I updated /etc/app/config.yml to use port 3000 and restarted the server." | bash "$SCRIPTS/reply-gate.sh")
assert_pass "did the work directly" "$R"

# Pattern 4: Narration Without Action
echo "--- Narration Without Action ---"

R=$(echo "I'm going to start by reading the config file, then I'll update the port setting, and finally restart the service." | bash "$SCRIPTS/reply-gate.sh")
assert_fail "pure narration" "$R" "narration_without_action"

R=$(echo "Let me begin by analyzing the error logs to find the root cause." | bash "$SCRIPTS/reply-gate.sh")
assert_fail "narrating plan" "$R" "narration_without_action"

R=$(echo "I read the config file and here is the output:
\`\`\`
port=8080
\`\`\`
The port is set to 8080." | bash "$SCRIPTS/reply-gate.sh")
assert_pass "narration with action evidence" "$R"

# Pattern 5: Blocker Without Recovery
echo "--- Blocker Without Recovery ---"

R=$(echo "This is blocked by the API being down. I can't proceed without it." | bash "$SCRIPTS/reply-gate.sh")
assert_fail "blocker without alternatives" "$R" "blocker_without_recovery"

R=$(echo "The API is currently unavailable. Alternatively, I can try the cached version or use a different endpoint." | bash "$SCRIPTS/reply-gate.sh")
assert_pass "blocker with alternatives" "$R"

# Pattern 6: False Completion
echo "--- False Completion ---"

R=$(echo "Done. I updated the file." | bash "$SCRIPTS/reply-gate.sh")
assert_fail "claim done without evidence" "$R" "false_completion"

R=$(echo "Fixed the issue. Should be good now." | bash "$SCRIPTS/reply-gate.sh")
assert_fail "claim fixed without evidence" "$R" "false_completion"

R=$(echo "Deployed the new version. All set." | bash "$SCRIPTS/reply-gate.sh")
assert_fail "claim deployed without evidence" "$R" "false_completion"

R=$(echo "Done. Updated /etc/nginx/nginx.conf and restarted.
output:
\`\`\`
nginx: configuration file /etc/nginx/nginx.conf test is successful
\`\`\`" | bash "$SCRIPTS/reply-gate.sh")
assert_pass "completion with evidence (code block + path)" "$R"

R=$(echo "Deployed to https://app.example.com — verified the homepage loads." | bash "$SCRIPTS/reply-gate.sh")
assert_pass "completion with URL evidence" "$R"

# Pattern 7: Scope Substitution
echo "--- Scope Substitution ---"

R=$(echo "Instead, I went ahead and updated the README rather than fixing the tests." | bash "$SCRIPTS/reply-gate.sh")
assert_fail "did different work instead" "$R" "scope_substitution"

R=$(echo "Rather than building the API endpoint, I took a different approach and wrote documentation." | bash "$SCRIPTS/reply-gate.sh")
assert_fail "substituted scope with docs" "$R" "scope_substitution"

R=$(echo "As an alternative, I refactored the module instead of adding the feature." | bash "$SCRIPTS/reply-gate.sh")
assert_fail "alternative instead of asked work" "$R" "scope_substitution"

R=$(echo "I completed the API endpoint at /api/v2/users and also updated README.md. Tests passing (12/12)." | bash "$SCRIPTS/reply-gate.sh")
assert_pass "did the work plus extras" "$R"

# Pattern 8: Burden-Shifting Update
echo "--- Burden-Shifting Update ---"

R=$(echo "I ran into some issues with the deployment pipeline. The Docker build is having trouble with the node modules and I'm struggling with the network configuration. It seems like there might be an issue with the firewall rules as well." | bash "$SCRIPTS/reply-gate.sh")
assert_fail "friction narration without resolution" "$R" "burden_shifting_update"

R=$(echo "Hit a snag with the SSL certificate renewal. Having trouble getting certbot to validate the domain. The DNS propagation is slow and I'm struggling with the provider's API." | bash "$SCRIPTS/reply-gate.sh")
assert_fail "all friction no resolution" "$R" "burden_shifting_update"

R=$(echo "I ran into an issue with the API rate limit but found a workaround using batch requests at /api/v2/batch. The timeout issue is fixed and the pipeline is working now — 47 records processed." | bash "$SCRIPTS/reply-gate.sh")
assert_pass "friction with resolution" "$R"

R=$(echo "Ran into a snag. Decision needed: the API requires a paid tier for this endpoint. Risk: we'd need to upgrade." | bash "$SCRIPTS/reply-gate.sh")
assert_pass "friction with decision/risk signal" "$R"

# Command injection safety (hook)
echo "--- Command Injection Safety ---"

R=$(echo '$(echo PWNED > /tmp/pwned)' | node "$SCRIPTS/behavioral-gate-hook.js")
if [[ ! -f "/tmp/pwned" ]]; then
  green "  PASS: \$() injection did not execute"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  red "  FAIL: \$() injection executed!"
  rm -f /tmp/pwned
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

R=$(echo '`echo PWNED2 > /tmp/pwned2`' | node "$SCRIPTS/behavioral-gate-hook.js")
if [[ ! -f "/tmp/pwned2" ]]; then
  green "  PASS: backtick injection did not execute"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  red "  FAIL: backtick injection executed!"
  rm -f /tmp/pwned2
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Destructive action whitelist
echo "--- Destructive Action Whitelist ---"

R=$(echo "Would you like me to delete the production database?" | bash "$SCRIPTS/reply-gate.sh")
assert_pass "destructive confirmation is legitimate" "$R"

R=$(echo "Would you like me to wipe the server and start fresh?" | bash "$SCRIPTS/reply-gate.sh")
assert_pass "wipe confirmation is legitimate" "$R"

R=$(echo "Shall I drop the users table? This is irreversible." | bash "$SCRIPTS/reply-gate.sh")
assert_pass "irreversible action confirmation is legitimate" "$R"

R=$(echo "Would you like me to update the config?" | bash "$SCRIPTS/reply-gate.sh")
assert_fail "non-destructive permission ask is handback" "$R" "work_handback"

# Clean response
echo "--- Clean Responses ---"

R=$(echo "Done. Updated /app/config.json and the tests pass (15/15)." | bash "$SCRIPTS/reply-gate.sh")
assert_pass "clean action response" "$R"

R=$(echo "The deployment completed successfully at https://app.example.com. All 47 tests passing." | bash "$SCRIPTS/reply-gate.sh")
assert_pass "clean status report" "$R"

echo ""
echo "=== Attempt Tracker Tests ==="

# Clean state
bash "$SCRIPTS/attempt-tracker.sh" clear-all > /dev/null 2>&1

echo "--- Log and Status ---"
R=$(bash "$SCRIPTS/attempt-tracker.sh" log --task "test-fetch" --method "direct API" --result "403 forbidden")
EXHAUSTED=$(echo "$R" | jq -r '.exhausted')
ATTEMPTS=$(echo "$R" | jq -r '.attempts')
if [[ "$EXHAUSTED" == "false" && "$ATTEMPTS" == "1" ]]; then
  green "  PASS: first attempt logged, not exhausted"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  red "  FAIL: first attempt state wrong"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

R=$(bash "$SCRIPTS/attempt-tracker.sh" log --task "test-fetch" --method "proxy service" --result "timeout")
EXHAUSTED=$(echo "$R" | jq -r '.exhausted')
ATTEMPTS=$(echo "$R" | jq -r '.attempts')
if [[ "$EXHAUSTED" == "false" && "$ATTEMPTS" == "2" ]]; then
  green "  PASS: second attempt logged, still not exhausted"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  red "  FAIL: second attempt state wrong"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

R=$(bash "$SCRIPTS/attempt-tracker.sh" log --task "test-fetch" --method "browser automation" --result "captcha blocked")
EXHAUSTED=$(echo "$R" | jq -r '.exhausted')
ATTEMPTS=$(echo "$R" | jq -r '.attempts')
if [[ "$EXHAUSTED" == "true" && "$ATTEMPTS" == "3" ]]; then
  green "  PASS: third attempt logged, now exhausted"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  red "  FAIL: third attempt state wrong (exhausted=$EXHAUSTED, attempts=$ATTEMPTS)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

R=$(bash "$SCRIPTS/attempt-tracker.sh" status --task "test-fetch")
TRIED_COUNT=$(echo "$R" | jq '.tried | length')
if [[ "$TRIED_COUNT" == "3" ]]; then
  green "  PASS: status shows 3 tried methods"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  red "  FAIL: status tried count wrong ($TRIED_COUNT)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

HAS_SUGGESTIONS=$(echo "$R" | jq '.suggestions | length > 0')
if [[ "$HAS_SUGGESTIONS" == "true" ]]; then
  green "  PASS: suggestions provided"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  red "  FAIL: no suggestions provided"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

R=$(bash "$SCRIPTS/attempt-tracker.sh" clear --task "test-fetch")
CLEARED=$(echo "$R" | jq -r '.cleared')
if [[ "$CLEARED" == "test-fetch" ]]; then
  green "  PASS: task cleared"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  red "  FAIL: clear failed"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

R=$(bash "$SCRIPTS/attempt-tracker.sh" status --task "test-fetch")
ATTEMPTS=$(echo "$R" | jq -r '.attempts')
if [[ "$ATTEMPTS" == "0" ]]; then
  green "  PASS: status clean after clear"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  red "  FAIL: status not clean after clear ($ATTEMPTS)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""
echo "=== Behavior Audit Tests ==="

TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'RESPONSES'
Done. I updated the file.
Unfortunately I was unable to complete the task.
Here's how you can fix this: open the config and change the value.
The deployment completed successfully.
I'm going to start by reading the logs, then I'll check the config.
RESPONSES

R=$(bash "$SCRIPTS/behavior-audit.sh" --file "$TMPFILE" --count 5)
SCORE=$(echo "$R" | jq '.score')
VCOUNT=$(echo "$R" | jq '.violations | length')
rm -f "$TMPFILE"

if [[ "$SCORE" -lt 100 && "$SCORE" -ge 0 && "$VCOUNT" -gt 0 ]]; then
  green "  PASS: audit scored $SCORE with $VCOUNT violations (expected <100 with violations)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  red "  FAIL: audit score unexpected (score=$SCORE, violations=$VCOUNT)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

TMPFILE=$(mktemp)
cat > "$TMPFILE" <<'RESPONSES'
Done. Updated /etc/app/config.json and verified.
Tests all passing — 47/47 green.
Deployed to https://app.example.com — confirmed live.
RESPONSES

R=$(bash "$SCRIPTS/behavior-audit.sh" --file "$TMPFILE" --count 5)
SCORE=$(echo "$R" | jq '.score')
rm -f "$TMPFILE"

if [[ "$SCORE" == "100" ]]; then
  green "  PASS: clean responses scored 100"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  red "  FAIL: clean responses scored $SCORE (expected 100)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

if [[ -f "$OPENCLAW_WORKSPACE/data/behavior-scores/$TODAY.json" ]]; then
  green "  PASS: daily score file created"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  red "  FAIL: daily score file not created"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""
echo "=== Hook Tests ==="

R=$(echo "Would you like me to check that for you?" | node "$SCRIPTS/behavioral-gate-hook.js")
ACTION=$(echo "$R" | jq -r '.action')
if [[ "$ACTION" == "block" ]]; then
  green "  PASS: hook blocks violation"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  red "  FAIL: hook did not block (action=$ACTION)"
  echo "  Result: $R"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

R=$(echo "Done. Updated /etc/app/config.yml and restarted the service." | node "$SCRIPTS/behavioral-gate-hook.js")
ACTION=$(echo "$R" | jq -r '.action')
if [[ "$ACTION" == "pass" ]]; then
  green "  PASS: hook passes clean response"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  red "  FAIL: hook did not pass clean response (action=$ACTION)"
  echo "  Result: $R"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Cleanup temp workspace
rm -rf "$OPENCLAW_WORKSPACE"

echo ""
echo "================================"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "Results: $PASS_COUNT/$TOTAL passed"
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  red "$FAIL_COUNT FAILURES"
  exit 1
else
  green "ALL TESTS PASSED"
  exit 0
fi
