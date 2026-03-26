# Behavioral Guardrails

**Pre-send quality gates for AI agents.** Catches 8 failure patterns before they reach the user.

## The Problem

AI agents fail in predictable ways:

1. **Premature surrender** — "I can't do that" after one failed attempt
2. **Answerable questions** — asking the user for info the agent already has
3. **Work handback** — giving instructions instead of doing the work
4. **Narration without action** — describing plans instead of executing
5. **Blocker without recovery** — reporting failure without trying alternatives
6. **False completion** — claiming "done" without evidence
7. **Scope substitution** — doing easier work Y when asked for X
8. **Burden-shifting** — narrating friction to transfer cognitive load

These patterns are consistent, detectable, and fixable — before the message sends.

## How It Works

Every draft response passes through `reply-gate.sh`, which runs deterministic regex checks against all 8 anti-patterns. No LLM call. No latency. Pass/fail with structured JSON output.

```
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

Clean responses pass through:

```
echo "Database migrated. Schema at db/schema.sql, 12 tables created." | bash scripts/reply-gate.sh
```

```json
{
  "verdict": "PASS",
  "violations": [],
  "score": 100
}
```

## Architecture

```
Agent Draft Response
        │
        ▼
┌─────────────────┐     ┌──────────────────┐
│  reply-gate.sh  │────▶│ attempt-tracker   │
│  (8 patterns)   │     │ (state per task)  │
└────────┬────────┘     └──────────────────┘
         │
    PASS │ FAIL
         │
         ▼
┌─────────────────┐     ┌──────────────────┐
│ behavior-audit  │────▶│ daily score JSON  │
│ (trend scoring) │     │ (data/behavior-   │
└─────────────────┘     │  scores/)         │
                        └──────────────────┘
```

- **reply-gate.sh** — Core gate. Deterministic regex detection with whitelists for destructive actions and evidence markers.
- **attempt-tracker.sh** — Tracks failed approaches per task. Blocks surrender until minimum attempts exhausted. Suggests alternatives.
- **behavior-audit.sh** — Scores responses 0-100 for trend tracking. Writes daily JSON to detect behavioral drift.
- **behavioral-gate-hook.js** — Node.js hook skeleton for framework integration. Passes text via stdin (no shell injection).
- **test-behavioral-gate.sh** — 48 tests covering all patterns, edge cases, injection safety, and destructive action whitelists.

## Quick Start

### Prerequisites

- `jq` (`brew install jq` / `apt install jq`)
- `bash` 4+
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
```

### Use

**Gate a response:**
```bash
echo "$AGENT_RESPONSE" | bash scripts/reply-gate.sh
```

**Track attempts before surrendering:**
```bash
# Log a failed approach
bash scripts/attempt-tracker.sh log --task "deploy-api" --method "docker compose" --result "port conflict"

# Check if exhausted (returns suggestions if not)
bash scripts/attempt-tracker.sh status --task "deploy-api"
```

**Score a response for audit:**
```bash
echo "$AGENT_RESPONSE" | bash scripts/behavior-audit.sh --text -
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `OPENCLAW_WORKSPACE` | `~/.openclaw/workspace` or `$(pwd)` | Where behavior score files are written |
| `BEHAVIORAL_GATE_STATE_DIR` | `/tmp/openclaw-attempts` | Attempt tracker state directory |
| `BEHAVIORAL_GATE_MIN_ATTEMPTS` | `3` | Minimum attempts before surrender is allowed |

## Scoring

| Pattern | Penalty | Threshold |
|---|---|---|
| False completion | -30 | Hardest — claiming done without proof |
| Premature surrender | -25 | Giving up before minimum attempts |
| Scope substitution | -20 | Doing Y instead of X |
| Work handback | -20 | Instructions instead of execution |
| Burden-shifting | -15 | Friction narrative without decision |
| Answerable questions | -15 | Asking what you could look up |
| Blocker without recovery | -15 | Failure report without alternatives |
| Narration without action | -10 | Plans instead of execution |

**Score thresholds:** <70 = review needed, <50 = critical, 0 = full behavioral reset.

## Known Limitations

- **Detection is regex-based.** Semantic violations that avoid keyword patterns will not be caught. This is a deliberate trade-off: zero latency, no LLM dependency, deterministic results.
- **Windows:** Native Windows is not supported. Use WSL.
- **False positives:** Patterns like "this doesn't work" could trigger in legitimate technical descriptions. The gate outputs structured feedback for the agent to override with judgment.

## License

MIT. See [LICENSE](LICENSE).
