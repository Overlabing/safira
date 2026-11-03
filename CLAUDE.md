# Safira

## Agent skills

### Issue tracker

Issues live in GitHub Issues (`Overlabing/safira`), via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Commands

- `scripts/check.sh`: the gate before every commit (generate, singleton guard, `swift test`, Debug build into `.build/dd`, signature and sandbox check). One `OK:`/`FAILED:` line per step.
- `xcodegen generate`: regenerate `Safira.xcodeproj` from `project.yml` (never commit the project).
- `swift test --package-path Packages/SafiraKit`: the package tests alone.
- `scripts/guard-singletons.sh <allowed file> <paths>...`: the shared-singleton guard; `scripts/test-guard-singletons.sh` proves it against `scripts/fixtures/singleton-guard`.
