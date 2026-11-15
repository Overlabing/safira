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
- Test windows: tests create windows only through `TestWindow` (`Packages/SafiraKit/Tests/TestSupport`), which keeps them off every display and never key; `check.sh` guards it with `scripts/test-window-patterns.txt`, proved by `scripts/test-guard-test-windows.sh`. `swift scripts/test-windows-offscreen.swift <command>` runs a command (for example `swift test --package-path Packages/SafiraKit`) and fails if one of its windows reaches a display or one of its processes becomes frontmost.
- `scripts/check-attribution.sh <base> <head>`: rejects a Claude attribution line or a personal email address in the commits and in `PR_TITLE`/`PR_BODY`; CI runs it on every pull request (`hygiene` workflow).
- String Catalogs: one per module that shows text (`Packages/SafiraKit/Sources/<Module>/Resources/<Module>.xcstrings`, looked up with `table: "<Module>", bundle: .module`) and `App/macOS/Localizable.xcstrings`; keys are English, French is the translation. After adding a string, build, run `"$(scripts/tools.sh)"/bin/sync-strings --config scripts/sync-strings.json .build/dd` to merge it, then translate it. `check.sh` runs the same with `--check` and fails on a lost, unreachable or untranslated string; `StringCatalogTests` fails on a missing French value or a French key.
- `scripts/keychain-gate.sh [Verrou extension folder]`: operator-run only, never by an agent or in CI. Signs a small app that runs SafiraKit's extension host with Developer ID under a throwaway bundle id, stores a `CryptoKey` from an extension service worker, relaunches and reads it back, then deletes the keychain item it created (ADR 0006).
- `scripts/keychain-gate.sh --load-only [folder]`: the same app signed ad hoc, touching no keychain: it only loads Verrou and the probe into a Profile kept in memory and expects `RESULT: loaded`. Anyone may run it.
- `scripts/keychain-gate.sh --native-check <host manifest> '<message JSON>' [folder]`: the sandboxed gate app, signed ad hoc, starts the native messaging host the manifest registers (copied into `~/Library/Application Support/Safira/NativeMessagingHosts/` for that run only, removed after) as an extension carrying the `key` of `[folder]`, and prints the host's first answer. No keychain.
- Native messaging follows Chrome's host manifests, with no per-extension code (ADR 0007, `docs/native-messaging.md`). `NativeMessagingTests` use an echo host in a temporary folder; with Verrou installed and running, one test also talks to Verrou's host through a temporary manifest, and `SAFIRA_PAIRING_CHECK=1 SAFIRA_CAPTURE_DIR=<folder>` adds the popup's pairing check, which shows Verrou's own Link window in front, so only with someone at the Mac, who answers Decline.
- UI checks: `ui-lock take <unit>`, then `ui-lock app <unit> <pid of the Safira copy>` once it runs, `ui-lock release <unit>` (lock `/tmp/overlabing-ui.lock`; `ui-lock` is in `"$(scripts/tools.sh)"/bin`).
