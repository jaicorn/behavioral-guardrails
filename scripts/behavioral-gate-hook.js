/**
 * behavioral-gate-hook.js — OpenClaw pre-send hook for behavioral guardrails
 *
 * When OpenClaw supports response pipeline hooks, this intercepts draft responses,
 * runs them through the reply gate, and blocks or flags violations.
 *
 * Hook contract (anticipated):
 *   input:  { draft: string, context: { task?, session?, user? } }
 *   output: { action: "pass" | "block" | "rewrite", violations?: array, rewritten?: string }
 */

const { execSync } = require('child_process');
const path = require('path');

// Resolve reply-gate.sh relative to this script's directory
const SCRIPT_DIR = __dirname;
const REPLY_GATE = path.join(SCRIPT_DIR, 'reply-gate.sh');

/**
 * Run the reply gate on a draft response
 * @param {string} draft - The draft response text
 * @returns {{ pass: boolean, violations: Array<{type: string, evidence: string, suggestion: string}> }}
 */
function runReplyGate(draft) {
  try {
    const result = execSync(`echo "${draft.replace(/"/g, '\\"')}" | bash "${REPLY_GATE}"`, {
      encoding: 'utf-8',
      timeout: 5000,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    return JSON.parse(result.trim());
  } catch (err) {
    // If gate fails, pass through (fail-open to avoid blocking all responses)
    console.error('[behavioral-gate-hook] Reply gate error:', err.message);
    return { pass: true, violations: [] };
  }
}

/**
 * OpenClaw hook entry point
 * @param {{ draft: string, context: object }} input
 * @returns {{ action: string, violations?: array, reason?: string }}
 */
function onPreSend(input) {
  const { draft, context } = input;

  // Skip gate for system messages or non-user-facing responses
  if (context && context.system) {
    return { action: 'pass' };
  }

  const gateResult = runReplyGate(draft);

  if (gateResult.pass) {
    return { action: 'pass' };
  }

  const violationTypes = gateResult.violations.map(v => v.type);
  const suggestions = gateResult.violations.map(v => v.suggestion);

  return {
    action: 'block',
    violations: gateResult.violations,
    reason: `Blocked ${violationTypes.length} violation(s): ${violationTypes.join(', ')}. ` +
            `Fix: ${suggestions.join(' ')}`,
  };
}

// Export for OpenClaw hook system
module.exports = { onPreSend, runReplyGate };

// CLI mode: pipe text in for testing
if (require.main === module) {
  const chunks = [];
  process.stdin.setEncoding('utf-8');
  process.stdin.on('data', chunk => chunks.push(chunk));
  process.stdin.on('end', () => {
    const draft = chunks.join('');
    if (!draft.trim()) {
      console.log(JSON.stringify({ action: 'pass', note: 'empty input' }));
      return;
    }
    const result = onPreSend({ draft, context: {} });
    console.log(JSON.stringify(result, null, 2));
  });
}
