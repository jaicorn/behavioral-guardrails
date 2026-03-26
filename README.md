# Behavioral Guardrails

**Your agent's last line of defense before it sends something stupid.**

AI agents fail in predictable, repeatable ways. They give up too early, ask questions they could answer, hand you instructions instead of results, and say "done" when nothing happened. These aren't edge cases — they're the default behavior of every foundation model.

Behavioral Guardrails catches all of it. Deterministic regex. Zero latency. No LLM call. Every response gets checked before it reaches you.

---

## The Problem (with receipts)

### "I can't access the database"
Your agent hit one error and surrendered. It didn't try a different connection string, check if the service was running, or use a backup path. It just... quit. And phrased quitting as a status update.

### "Would you like me to check the deployment status?"
You asked it to check the deployment status. It responded by asking if you'd like it to do the thing you just asked it to do. Your agent is wearing politeness as a mask for decision avoidance.

### "Here's how you can update the DNS records"
You didn't ask for instructions. You asked it to update DNS. It gave you a tutorial because doing the work was harder than describing the work. Now *you're* doing *its* job.

### "I'm working on setting up the monitoring pipeline and will be configuring the alert thresholds..."
Your agent just wrote 200 words about what it plans to do. It has done zero of those things. This is narration cosplaying as progress.

### "The API is down, so I couldn't complete the task"
The API was down. Your agent tried once, reported the failure, and moved on. It didn't retry, try a different endpoint, check if the API was actually down or just slow, or attempt any of the twelve other approaches that could have worked.

### "I've completed the deployment"
No artifact. No log. No URL. No verification. The model's context said "deploy" happened, so it declared victory. You find out it failed when a customer emails you.

### "You asked me to fix the CSS but I also refactored the component structure"
You asked for a CSS fix. You got a CSS fix *and* an unsolicited architecture change that broke three other components. The agent substituted your scope with its own because its scope was more interesting.

### "I ran into some issues with the authentication flow and the token refresh logic seems to be..."
This is a cognitive load dump. Your agent hit friction and decided to make it your problem by narrating every obstacle in detail. No recommendation. No decision point. Just a wall of text that transfers the headache from silicon to you.

---

## How It Works

Every response passes through `reply-gate.sh` — 8 pattern detectors, each with regex-based matching, penalty scoring, and structured suggestions.

```bash
# Gate a response
echo "I can't access the database" | bash scripts/reply-gate.sh
```

```json
{
  "verdict": "FAIL",
  "violations": [
    {
      "pattern": "premature_surrender",
      "penalty": -25,
      "evidence": "I can't access the database",
      "suggestion": "Try 2 more approaches before giving up"
    }
  ],
  "score": 75
}
```

Clean responses pass through untouched:

```bash
echo "Database migrated. Schema at db/schema.sql, 12 tables created." | bash scripts/reply-gate.sh
```

```json
{
  "verdict": "PASS",
  "violations": [],
  "score": 100
}
```

Multiple violations stack:

```bash
echo "I couldn't deploy the app. Would you like me to try again? Here's how you could do it manually..." | bash scripts/reply-gate.sh
```

```json
{
  "verdict": "FAIL",
  "violations": [
    { "pattern": "premature_surrender", "penalty": -25 },
    { "pattern": "answerable_question", "penalty": -15 },
    { "pattern": "work_handback", "penalty": -20 }
  ],
  "score": 40
}
```

Score 40 = your agent was about to send a triple-failure response. Guardrails caught it.

---

## The 8 Anti-Patterns

| # | Pattern | Penalty | What It Catches |
|---|---|---|---|
| 1 | **Premature Surrender** | -25 | Giving up before minimum attempts exhausted |
| 2 | **Answerable Questions** | -15 | Asking the user for info the agent already has |
| 3 | **Work Handback** | -20 | Delivering instructions instead of results |
| 4 | **Narration Without Action** | -10 | Describing plans instead of executing them |
| 5 | **Blocker Without Recovery** | -15 | Reporting failure without trying alternatives |
| 6 | **False Completion** | -30 | Claiming "done" with no evidence (hardest penalty) |
| 7 | **Scope Substitution** | -20 | Doing easier work Y when asked for X |
| 8 | **Burden-Shifting** | -15 | Narrating friction to transfer cognitive load |

**Score thresholds:** 100 = clean, <70 = review needed, <50 = critical failure, 0 = full behavioral reset.

---

## Architecture

```
                     Agent Draft Response
                             │
                             ▼
                    ┌─────────────────┐
                    │  reply-gate.sh  │
                    │  8 regex gates  │
                    │  deterministic  │
                    │  zero latency   │
                    └────────┬────────┘
                             │
                  ┌──────────┼──────────┐
                  │          │          │
                PASS       FAIL     MULTI-FAIL
                  │          │          │
                  ▼          ▼          ▼
              Send it    Rework it   Red alert
                             │
                    ┌────────┴────────┐
                    │                 │
                    ▼                 ▼
          ┌──────────────┐  ┌──────────────────┐
          │   attempt-   │  │  behavior-audit  │
          │  tracker.sh  │  │     scoring      │
          │              │  │                  │
          │ "Did you     │  │  0-100 per       │
          │  actually    │  │  response,       │
          │  try 3+      │  │  daily JSON      │
          │  approaches?"│  │  trend files     │
          └──────────────┘  └──────────────────┘
                                    │
                                    ▼
                          data/behavior-scores/
                            YYYY-MM-DD.json
```

---

## What's Different

Most agent quality tools use an LLM to judge another LLM. That means:
- **Extra latency** on every response (1-3 seconds)
- **Extra cost** (another API call per message)
- **Non-deterministic** (the judge hallucinates too)
- **Unjudgeable** (who judges the judge?)

Behavioral Guardrails uses **deterministic regex patterns**. Same input always produces same output. Runs in <50ms. Costs nothing. And because the patterns are hand-tuned from real failure modes (not theoretical ones), they catch the stuff that actually happens.

The trade-off: semantic violations that avoid keyword patterns will slip through. A cleverly-worded surrender will pass. That's the right trade-off — you get reliable, fast, free checks on the 90% of failures that follow predictable language patterns.

---

## Component Deep-Dives

### Reply Gate (`reply-gate.sh`)

The core. Reads a response from stdin, checks all 8 patterns, returns JSON verdict.

**Smart whitelists** prevent false positives:
- Destructive action warnings ("this will delete all data") are exempt from work-handback detection
- Responses with evidence markers (file paths, URLs, code blocks) get lighter false-completion checks
- Minimum-attempt checks integrate with `attempt-tracker.sh` state

```bash
# Pipe any response through it
echo "$RESPONSE" | bash scripts/reply-gate.sh

# Use in a pre-send hook
if ! echo "$RESPONSE" | bash scripts/reply-gate.sh | jq -e '.verdict == "PASS"' > /dev/null; then
  echo "Response blocked — reworking"
fi
```

### Attempt Tracker (`attempt-tracker.sh`)

Tracks what your agent has tried per task. Blocks surrender until minimum attempts are exhausted. Suggests next approaches.

```bash
# Log a failed approach
bash scripts/attempt-tracker.sh log \
  --task "deploy-api" \
  --method "docker compose" \
  --result "port conflict on 8080"

# Check if surrender is justified
bash scripts/attempt-tracker.sh status --task "deploy-api"
# → {"exhausted": false, "attempts": 1, "minimum": 3,
#    "suggestion": "Try different port, direct binary, or systemd"}

# After 3+ attempts
bash scripts/attempt-tracker.sh status --task "deploy-api"
# → {"exhausted": true, "attempts": 3}
# Now surrender is permitted.

# Clear task state
bash scripts/attempt-tracker.sh clear --task "deploy-api"
```

### Behavior Audit (`behavior-audit.sh`)

Scores responses 0-100 for trend tracking. Write daily JSON files to detect behavioral drift over time.

```bash
# Score a single response
echo "$RESPONSE" | bash scripts/behavior-audit.sh --text -

# Score last N responses from a log
bash scripts/behavior-audit.sh --sample 10

# Output goes to data/behavior-scores/YYYY-MM-DD.json
```

Use this in your agent's maintenance loop or heartbeat rotation. A downward trend means your agent is getting sloppier — catch it before your users do.

### Hook (`behavioral-gate-hook.js`)

Node.js skeleton for framework integration. Passes response text via stdin (no shell injection — learned that one the hard way).

```javascript
// Wire into your framework's pre-send pipeline
const { execSync } = require('child_process');
const result = execSync('bash scripts/reply-gate.sh', {
  input: agentResponse,  // stdin, not template string
  encoding: 'utf-8'
});
const verdict = JSON.parse(result);
if (verdict.verdict !== 'PASS') {
  // rework or escalate
}
```

---

## Quick Start

### Prerequisites

- `bash` 4+
- `jq` (`brew install jq` / `apt install jq`)
- `node` (optional — only for the JS hook)

### Install

```bash
git clone https://github.com/jaicorn/behavioral-guardrails.git
cd behavioral-guardrails
chmod +x scripts/*.sh
```

### Test

```bash
bash scripts/test-behavioral-gate.sh
# 48 tests: all patterns, edge cases, injection safety, whitelists
```

### Wire It Up

Add to your agent's system prompt or pre-send hook:

```
Before sending any response, pipe it through reply-gate.sh.
If verdict is FAIL, rework the response addressing each violation.
Log all attempts with attempt-tracker.sh before claiming a task is impossible.
```

---

## Configuration

| Variable | Default | Description |
|---|---|---|
| `OPENCLAW_WORKSPACE` | `~/.openclaw/workspace` or `$(pwd)` | Where behavior score files are written |
| `BEHAVIORAL_GATE_STATE_DIR` | `/tmp/openclaw-attempts` | Attempt tracker state directory |
| `BEHAVIORAL_GATE_MIN_ATTEMPTS` | `3` | Minimum attempts before surrender is allowed |

---

## Known Limitations

- **Regex-based detection.** Semantic violations that avoid keyword patterns will pass. This is a deliberate trade-off: zero latency, no LLM dependency, deterministic results. Catches ~90% of real-world failures.
- **Windows:** Native Windows is not supported. Use WSL.
- **False positives on technical content.** Phrases like "this doesn't work" in a bug report could trigger. The gate outputs structured JSON so your agent can override with judgment when appropriate.
- **State is ephemeral by default.** Attempt tracker uses `/tmp` — customize `BEHAVIORAL_GATE_STATE_DIR` for persistence across reboots.

---

## Why This Exists

Every AI agent you've used has done at least three of these:

- Said "done" when it wasn't
- Asked you a question it could have answered
- Given you instructions instead of doing the work
- Given up after one try
- Narrated its struggle instead of solving the problem

These aren't bugs. They're *default behaviors* that emerge from how language models optimize for response plausibility over response quality. The model doesn't know it's being lazy — it genuinely thinks "here's how you could do it" is a helpful response.

Behavioral Guardrails is the filter between your agent's instincts and your inbox. It doesn't make the model smarter. It stops the dumb stuff from reaching you.

48 tests. 8 patterns. Zero dependencies beyond bash and jq. Every response checked in under 50ms.

Your agent will hate it. You'll love it.

---

## License

MIT. See [LICENSE](LICENSE).
