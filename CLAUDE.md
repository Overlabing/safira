# Safira

## Agent skills

### Issue tracker

Issues live in GitHub Issues (`Overlabing/safira`), via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Commands

- `scripts/check.sh`: the gate before every commit (leak scan, generate, singleton guard, `swift test`, Debug build into `.build/dd`, signature and sandbox check). One `OK:`/`FAILED:` line per step. Its `step` and scanners come from AppTooling.
- `scripts/tools.sh`: fetches AppTooling at the version and checksum in `scripts/apptooling.pin` into `.build/tools/` and prints its directory (`tools=$(scripts/tools.sh)`). Bump version and checksum together.
- `scripts/tools.sh install-hooks`: once per clone, installs the `pre-commit` (leak scan of the staged files) and `commit-msg` (strips Claude attribution, scans the message) hooks for every worktree. They read the private terms from `$OVERLABING_PRIVATE_TERMS` (default `~/.config/overlabing/private-terms`, outside every repository; never copy it into one). A missing file blocks the commit.
- `"$(scripts/tools.sh)"/bin/leak-scan history`: scans every commit of every ref against the private terms; `scripts/leak-scan-public.sh tree|history` is the same with the committed public patterns, which is what CI runs.
- `xcodegen generate`: regenerate `Safira.xcodeproj` from `project.yml` (never commit the project).
- `swift test --package-path Packages/SafiraKit`: the package tests alone.
- `scripts/test-guard-singletons.sh` proves the shared-singleton guard (`guard-pattern.sh` with `scripts/singleton-patterns.txt`) against `scripts/fixtures/singleton-guard`; `scripts/test-step.sh` proves a failing step prints `FAILED:`.
- `scripts/check-attribution.sh <base> <head>`: rejects a Claude attribution line or a personal email address in the commits and in `PR_TITLE`/`PR_BODY`; CI runs it on every pull request (`hygiene` workflow).
- String Catalogs: one per module that shows text (`Packages/SafiraKit/Sources/<Module>/Resources/<Module>.xcstrings`, looked up with `table: "<Module>", bundle: .module`) and `App/macOS/Localizable.xcstrings`; keys are English, French is the translation. After adding a string, build, run `"$(scripts/tools.sh)"/bin/sync-strings --config scripts/sync-strings.json .build/dd` to merge it, then translate it. `check.sh` runs the same with `--check` and fails on a lost, unreachable or untranslated string; `StringCatalogTests` fails on a missing French value or a French key.
- UI checks: `ui-lock take <unit>`, then `ui-lock app <unit> <pid of the Safira copy>` once it runs, `ui-lock release <unit>` (lock `/tmp/overlabing-ui.lock`; `ui-lock` is in `"$(scripts/tools.sh)"/bin`).
