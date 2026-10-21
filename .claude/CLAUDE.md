# PropCid Flutter App — Operating Manual

This is the global operating manual for Claude Code sessions in this repository. It is deliberately short. Detailed, verified architecture knowledge lives in `docs/ai-memory/` — read only the files relevant to what you're touching, on demand; do not load all of them at session start.

## About the root `claude.md`

The file `claude.md` at the repo root is a **historical, narrow instruction file** for one specific workstream (the listing-migration/metadata-parity effort against the React portal). It is **not** the global architecture source of truth and must not be treated as one. Do not modify or rename it — it stays as-is for that workstream. This file (`.claude/CLAUDE.md`) is the actual operating manual; `docs/ai-memory/` is the actual architecture memory.

## Source of Truth Order

1. Current working-tree source code
2. Current `git diff` / uncommitted work
3. Git history (`git log`, `git blame`)
4. `docs/ai-memory/` (verified, but can go stale — cross-check against code for anything load-bearing)
5. Other existing docs (`docs/*.md`, root `claude.md`, `RBAC_IMPLEMENTATION_GUIDE.md`, `VOICE_ASSISTANT_*.md`) — several of these are known to be stale relative to code; see `docs/ai-memory/KNOWN_ISSUES.md`. Treat them as secondary evidence, not fact.

Never let a stale planning doc override what the current code actually does. If a doc and the code disagree, the code wins — and the discrepancy is worth a `KNOWN_ISSUES.md` entry.

## Before Any Change

1. Read the relevant `docs/ai-memory/*.md` file(s) for the system you're touching (`MODULE_MAP.md` tells you where things live; `HIGH_RISK_AREAS.md` tells you if it's sensitive).
2. Run `git status`/`git diff` first. **Preserve existing uncommitted work** — never discard, stash-and-forget, or overwrite it without the user's say-so.
3. Read the actual source you're about to change, its callers, and its tests — don't infer from a doc.
4. Check `docs/ai-memory/KNOWN_ISSUES.md` and `INCIDENTS.md` for anything already known about this area.
5. For a bug fix: establish root cause before writing a fix. Symptom-patching without understanding why is not acceptable.
6. For anything touching a shared model, a high-risk area, or backend-facing code: trace the dependency/blast radius first (who else calls this, what breaks if the contract changes), and check `git log`/`git blame` on the area if the reason for its current shape isn't obvious.
7. Before writing the change, identify the behavior that must remain unchanged and use it as a constraint on the implementation — then make the smallest safe change that fixes the actual problem without touching that. Don't opportunistically refactor, rename, or "clean up" unrelated code while you're in a file.

## Hard Rules

- **Never silently change an API/backend/database contract.** Never invent a field, endpoint, table, or RPC name — verify it against current code first. See `docs/ai-memory/API_CONTRACTS.md`.
- **Never casually touch**: authentication/session logic, media upload/storage paths, payments, feature flags (`launch_features.dart`), release signing config, Android package identity / iOS bundle ID, or any file under `RELEASE_SAFETY.md`'s scope — without first reading why the current behavior is what it is (see `docs/ai-memory/HIGH_RISK_AREAS.md` and `DECISIONS.md`).
- **Never place a true server secret in anything the Flutter client ships** — `.env` (bundled as an app asset), source, manifests, or `--dart-define` values are all recoverable by an end user. See `HIGH_RISK_AREAS.md`'s client-secret rule before touching any credential-adjacent code.
- **Never write a secret value into any documentation file**, including `docs/ai-memory/*`. Names and purposes only.
- Distinguish **verified facts** (you read the code) from **assumptions** (a doc said so, or you inferred it) in anything you write or report — don't blur the two.
- **Never destroy or overwrite developer work.** Do not run destructive Git/file operations such as `git reset --hard`, `git clean`, destructive `git checkout`/`git restore`, or delete/overwrite uncommitted files unless the user explicitly authorizes that exact action.

- **Never guess through a high-risk uncertainty.** If a backend contract, release setting, signing assumption, payment behavior, authentication behavior, or production configuration cannot be verified from the available source/evidence, report the uncertainty and avoid changing that area until it is resolved.

## After Any Change

1. Run `git diff` and actually read it before calling something done.
2. Run targeted verification for what you changed (relevant test file(s), `flutter analyze` if relevant) — don't claim "fixed" just because it compiles.
3. Check directly related regression paths, not just the reported symptom.
4. Report exactly what changed, in plain terms.

## Keeping Project Memory Current

After a meaningful, verified change, update the relevant file — don't let `docs/ai-memory/` drift the way several existing planning docs already have:

| Change type | Update |
|---|---|
| Architecture/bootstrap/state-management change | `CURRENT_ARCHITECTURE.md` |
| New/moved module, changed ownership | `MODULE_MAP.md` |
| Verified backend/API contract change | `API_CONTRACTS.md` |
| Significant production bug | `INCIDENTS.md` |
| Unresolved, verified problem | `KNOWN_ISSUES.md` |
| Notable engineering decision + reason | `DECISIONS.md` |
| Any meaningful shipped change | `CHANGELOG.md` |
| Release/signing/config change | `RELEASE_SAFETY.md` |
| Test coverage change | `TEST_MAP.md` |

Don't fabricate history in any of these files. If you don't know why something is the way it is, say "rationale not currently verifiable" rather than inventing a reason.

## Scope Discipline

If asked to fix X, fix X. Don't also refactor Y, upgrade a dependency, reformat unrelated files, or "improve" adjacent code you noticed along the way — flag it instead, and let the user decide if it's worth a separate task.
