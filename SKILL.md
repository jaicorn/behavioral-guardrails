---
name: behavioral-guardrails
description: Enforce behavioral guardrails on AI agent responses. Blocks 8 anti-patterns — premature surrender, answerable questions, work handback, narration without action, blocker without recovery, false completion, scope substitution, and burden-shifting updates. Use for reply quality gates and agent self-correction.
version: 1.0.0
---

# Behavioral Guardrails

Enforces 8 behavioral rules that prevent AI agents from falling into common failure patterns. Every draft response is checked before it reaches the user. Violations are blocked, not advised on.

## Anti-Patterns Detected

| # | Pattern | What It Catches | Penalty |
|---|---------|----------------|---------|
| 1 | **Premature Surrender** | Giving up with fewer than 3 documented attempts | -25 |
| 2 | **Answerable Questions** | Asking the user for info the agent can look up | -15 |
| 3 | **Work Handback** | "Here's how you can..." instead of doing it (whitelists destructive actions) | -20 |
| 4 | **Narration Without Action** | Describing plans instead of executing them | -10 |
| 5 | **Blocker Without Recovery** | Reporting blockers without trying alternatives | -20 |
| 6 | **False Completion** | Claiming done/sent/deployed without evidence (file paths, URLs, output) | -30 |
| 7 | **Scope Substitution** | Doing adjacent work instead of what was actually asked | -20 |
| 8 | **Burden-Shifting Update** | Narrating friction without completion, decision, or risk signal | -15 |

## Setup

### Prerequisites

- `jq` installed (`brew install jq` / `apt install jq`)
- `bash` 4+
- `node` (optional — only needed for the JS hook integration)

### Install

1. Copy or install the skill into your OpenClaw skills directory
2. Make scripts executable (they should already be):

```bash
chmod +x scripts/*.sh
```

3. Set your workspace (optional — auto-detects `~/.openclaw/workspace`):

```bash
export OPENCLAW_WORKSPACE="$HOME/.openclaw/workspace"
```

### Verify

```bash
bash scripts/test-behavioral-gate.sh
```

All tests should pass.

## Scripts

### `scripts/reply-gate.sh` — Pre-Reply Gate

The core enforcement script. Analyzes text for all 8 anti-patterns and returns a pass/fail verdict with violation details.

**Usage:**

```bash
# Pipe text in
echo "Unfortunately I was unable to complete the task." | bash scripts/reply-gate.sh

# Or pass as argument
bash scripts/reply-gate.sh --text "Would you like me to check that?"
```

**Output:**

```json
{
  "pass": false,
  "violations": [
    {
      "type": "premature_surrender",
      "evidence": "unfortunately I was unable",
      "suggestion": "Document at least 3 materially different approaches before reporting failure."
    }
  ]
}
```

**Integration:** Run this on every draft response before sending. If `pass` is `false`, rewrite the response to eliminate the violation. This is a hard gate, not advisory.

### `scripts/attempt-tracker.sh` — Attempt Tracking

Tracks failed approaches per task and enforces the 3-attempt minimum before the agent is allowed to report failure.

**Commands:**

```bash
# Log a failed attempt
bash scripts/attempt-tracker.sh log --task "fetch-data" --method "direct API" --result "403 forbidden"

# Check if enough attempts have been made
bash scripts/attempt-tracker.sh status --task "fetch-data"
# Returns: {attempts: 1, minimum: 3, exhausted: false, suggestions: [...]}

# Clear after task completion
bash scripts/attempt-tracker.sh clear --task "fetch-data"

# Reset all tracking
bash scripts/attempt-tracker.sh clear-all
```

**State:** Stored in `/tmp/openclaw-attempts/` (ephemeral). Each reboot starts fresh — this is intentional. Tasks within a session accumulate attempts; across sessions, the slate is clean.

**Key field:** `exhausted` — when `false`, the agent MUST try the next suggestion before reporting failure.

### `scripts/behavior-audit.sh` — Behavioral Scoring

Scores a batch of responses (0-100) by running each through the reply gate. Designed for periodic audits (heartbeat cycles, cron jobs).

**Usage:**

```bash
# Audit responses from a file (one response per line)
bash scripts/behavior-audit.sh --file responses.txt --count 5

# Pipe responses (one per line)
echo -e "Done. Updated the config.\nUnfortunately I failed." | bash scripts/behavior-audit.sh
```

**Output:**

```json
{
  "timestamp": "2026-03-25T12:00:00Z",
  "score": 75,
  "samples": 5,
  "violations": [{"type": "premature_surrender", "evidence": "...", "sample": 2}],
  "callouts": ["Sample 2: premature_surrender — unfortunately I failed"]
}
```

**Score storage:** Appends to `$WORKSPACE/data/behavior-scores/YYYY-MM-DD.json`. Scores below 70 should trigger self-correction.

### `scripts/behavioral-gate-hook.js` — Pre-Send Hook (Skeleton)

Node.js module for future OpenClaw response pipeline integration. Can also be used standalone:

```bash
# CLI mode — pipe draft responses
echo "Would you like me to do that?" | node scripts/behavioral-gate-hook.js
# Returns: {"action": "block", "violations": [...], "reason": "..."}

echo "Done. Config updated." | node scripts/behavioral-gate-hook.js
# Returns: {"action": "pass"}
```

**Exports:** `onPreSend(input)` and `runReplyGate(draft)` for programmatic use.

### `scripts/test-behavioral-gate.sh` — Test Suite

Comprehensive test suite covering all 8 anti-patterns, attempt tracking, behavior audit scoring, and the JS hook. Run to verify everything works:

```bash
bash scripts/test-behavioral-gate.sh
```

## Integration Guide

### Option 1: Agent Instructions (Simplest)

Add to your `AGENTS.md` or system prompt:

```markdown
## Behavioral Gate (MANDATORY)

Before sending any response, run it through the reply gate:
  bash /path/to/scripts/reply-gate.sh --text "<draft>"

If pass is false, rewrite the response to eliminate violations.

On any tool/API failure, log the attempt:
  bash /path/to/scripts/attempt-tracker.sh log --task "TASK" --method "METHOD" --result "RESULT"

Check status before reporting failure:
  bash /path/to/scripts/attempt-tracker.sh status --task "TASK"
If exhausted is false, try the next suggestion. Do not report failure.
```

### Option 2: Cron Audit (Ongoing Accountability)

Schedule `behavior-audit.sh` to run periodically and review scores:

```bash
# Every 30 minutes, audit the last 5 responses
*/30 * * * * bash /path/to/scripts/behavior-audit.sh --file /path/to/recent-responses.txt --count 5
```

Review daily scores:

```bash
cat $WORKSPACE/data/behavior-scores/$(date +%Y-%m-%d).json | jq '.[].score'
```

### Option 3: Pre-Send Hook (When Supported)

When OpenClaw adds response pipeline hooks, register the JS module:

```javascript
const { onPreSend } = require('./scripts/behavioral-gate-hook.js');
// Register with OpenClaw's hook system
```

## Protocol Reference

For the full enforcement protocol and philosophy, see `references/behavioral-gate-protocol.md`.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCLAW_WORKSPACE` | `~/.openclaw/workspace` | Workspace root for score storage |

## Scoring Reference

| Violation | Penalty | Threshold |
|-----------|---------|-----------|
| False completion | -30 | Score < 70 = review needed |
| Premature surrender | -25 | Score < 50 = critical |
| Work handback | -20 | Score = 0 = full reset needed |
| Blocker without recovery | -20 | |
| Scope substitution | -20 | |
| Answerable question | -15 | |
| Burden-shifting update | -15 | |
| Narration without action | -10 | |
