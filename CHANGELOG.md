# Changelog

## [1.0.0] - 2026-03-26

### Added
- 8 anti-pattern detection: premature surrender, answerable questions, work handback, narration without action, blocker without recovery, false completion, scope substitution, burden-shifting
- Attempt tracker with configurable minimum attempts and state directory
- Behavior audit scoring (0-100) with daily JSON trend files
- Node.js hook skeleton for framework integration
- 48-test suite covering all patterns, edge cases, and injection safety
- Destructive action whitelists (delete, wipe, irreversible ops exempt from handback checks)
- Evidence marker detection for completion claims (paths, URLs, code blocks)
- README, LICENSE (MIT), .gitignore, CHANGELOG
- Full env var configuration: `BEHAVIORAL_GATE_STATE_DIR`, `BEHAVIORAL_GATE_MIN_ATTEMPTS`, `OPENCLAW_WORKSPACE`

### Fixed
- SKILL.md description updated to list all 8 anti-patterns (was 5)
- Stale "5 anti-patterns" references updated to "8"
- Node marked as optional prerequisite (only needed for JS hook)
- Clear command uses `jq` for safe JSON output instead of bash interpolation
