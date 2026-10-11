---
name: vulnScan
description: Scan a repo for known CVEs in its dependencies, upgrade vulnerable or outdated packages, and verify the app still compiles and passes tests. Language-agnostic (Gradle, npm, PlatformIO). Use when asked to check vulnerabilities, update packages, or audit dependencies.
argument-hint: "<repo-path> [--report-only]"
---

# vulnScan

Language-agnostic dependency CVE scan, upgrade, and verification. Target: the repo path in `$ARGUMENTS` (default: current directory). With `--report-only`, skip steps 3-5.

## 1. Detect ecosystem
| Marker file | Ecosystem | Reference |
|---|---|---|
| `build.gradle` / `build.gradle.kts` | Gradle (Java) | `references/gradle.md` |
| `package.json` | npm | `references/npm.md` |
| `platformio.ini` | PlatformIO (C++) | `references/platformio.md` |

A repo may match several. Handle each. Read the matching reference before proceeding. Stop and ask if nothing matches.

## 2. Baseline and scan
- Record git status (note any pre-existing uncommitted changes) and run the build and tests *before* changing anything, so failures can be attributed correctly.
- Scan for CVEs using the native tool in the reference. If `osv-scanner` is installed, also run it on the lockfile/manifest as a cross-check.
- Missing tool? Say so and fall back; never invent results.

## 3. Upgrade
- Fix vulnerable packages first, then outdated ones.
- Prefer patch, then minor. **Major upgrades: list them and ask before applying.**
- Upgrade one ecosystem at a time; keep lockfile changes in the same diff.

## 4. Verify
Compile, run tests, and where cheap, confirm the app starts (see reference). If an upgrade breaks the build or tests, revert that package, note it, and continue.

## 5. Re-scan
Run the scan again to confirm CVEs are gone or list what remains (no fixed version, major bump deferred, etc.).

## 6. Report
Output a table: package | old -> new | CVE IDs | severity | build | tests. Then list deferred items and manual follow-ups.

## Rules
- Leave changes **uncommitted** in the working tree. Do not commit, push, or open PRs unless the user asks.
- Never touch secrets, `.env` files, or unrelated code.
- Do not run `npm audit fix --force` or similar blanket force flags.
- If the working tree was already dirty, say so up front and keep your changes separable.
