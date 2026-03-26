# Behavioral Gate Protocol

## Purpose

AI agents commonly fail by giving up too easily, asking questions they could answer themselves, and handing work back instead of solving problems. This protocol enforces behavioral guardrails that catch these anti-patterns before responses reach the user.

## Components

### 1. Reply Gate (`scripts/reply-gate.sh`)

**When it runs:** Before every response to the user in the main session.

**What it checks:**
- **Premature surrender** — Reporting failure with fewer than 3 documented attempts at different approaches
- **Answerable questions** — Asking the user something that could be looked up (contacts, files, settings, previous conversations)
- **Work handback** — Phrases like "here's how you can..." or "would you like me to..." when the action is within the agent's capability
- **Narration without action** — Describing what it plans to do instead of doing it
- **Blocker escalation without recovery** — Reporting a tool/API failure as a blocker without trying alternatives

**On violation:** The response MUST be rewritten to eliminate the violation before sending. This is not advisory — it is a hard gate.

### 2. Attempt Tracker (`scripts/attempt-tracker.sh`)

**When it runs:** On any tool failure, fetch failure, API error, or approach that doesn't produce the desired result.

**Hard rules:**
- Every failed attempt MUST be logged: `attempt-tracker.sh log --task TASK --method METHOD --result RESULT`
- Before reporting any failure to the user, check status: `attempt-tracker.sh status --task TASK`
- If `exhausted: false`, you MUST try the next suggestion. Do not report failure.
- Minimum 3 materially different approaches before escalation is permitted
- After task completion (success or escalated failure), clear the tracker: `attempt-tracker.sh clear --task TASK`

**State:** Ephemeral, stored in `/tmp/openclaw-attempts/`. Resets on reboot. This is intentional — each session starts fresh.

### 3. Behavior Audit (`scripts/behavior-audit.sh`)

**When it runs:** Every heartbeat cycle. Samples the last N responses.

**Scoring:**
- Starts at 100
- Premature surrender: -25
- Work handback: -20
- Blocker without recovery: -20
- Answerable question: -15
- Narration without action: -10

**Output:** Appends to `data/behavior-scores/YYYY-MM-DD.json`. Scores below 70 should trigger a self-correction review.

### 4. Integration Hook (`scripts/behavioral-gate-hook.js`)

Pre-send hook skeleton. When OpenClaw supports response pipeline hooks, this will intercept draft responses, run them through the reply gate, and block or rewrite violations automatically.

## Hard Rules

1. **Minimum 3 attempts.** You do not get to give up after trying one thing. Log every attempt. Try materially different approaches.
2. **No answerable questions.** If the answer exists in memory, data files, credentials, previous conversations, or system config — look it up. Don't ask.
3. **No premature handback.** If you can do the work, do the work. Don't describe how the user could do it.
4. **Act, don't narrate.** Execute the action. Don't describe your plan to execute it.
5. **Blockers require recovery attempts.** A failed API call is not a blocker — it's attempt #1. Try alternatives before escalating.

## Enforcement

These are not suggestions. The reply-gate is a hard gate. Responses that violate these rules should not reach the user. The behavior-audit provides ongoing accountability. Scores are logged daily and available for review.
