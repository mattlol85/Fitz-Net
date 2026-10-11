---
name: ship-it
description: Raise a PR for the current changes in a Fitz-Net repo, wait for CI, and only if it passes merge, tag a release, and deploy to prod. Args - optional repo path, bump type (patch|minor|major), and commit/PR title. Use when asked to ship, release, or "PR, merge, tag and deploy" a change.
---

# ship-it

End-to-end: **branch -> PR -> CI green -> squash-merge -> release tag -> deploy -> verify.**
Stop and report at the first failure; never merge on red or pending CI.

## 0. Inputs

- **Repo**: the sibling repo holding the changes (default: infer from the files
  the user just worked on; confirm if ambiguous). Call it `$REPO` (GitHub slug
  `mattlol85/$REPO`).
- **Bump**: `patch` for fixes/UI polish, `minor` for features, `major` only if
  the user says so. Default: infer from the commit type (`fix`/`chore` -> patch,
  `feat` -> minor).
- **Title**: conventional commit, `type(subject): description`.

## 1. Branch and commit (only the intended changes)

```bash
cd ../$REPO
git fetch origin && git status --short && git branch --show-current
```

- Stage **only files that belong to this change** by name. Leave unrelated
  modified/untracked files alone and mention them in the summary.
- If the current branch is `main`, or is a different feature branch with its own
  unmerged commits, create a fresh branch from `origin/main`
  (`git switch -c <type>/<slug> origin/main` carries the working-tree changes
  across). Never commit to `main` directly.
- Commit with the conventional message and the attribution trailer from the
  session's system reminder.

## 2. Local checks before pushing

Run the repo's own tests/lint (website: `npx vitest run` + `npx eslint <files>`;
Gradle repos: `./gradlew test`). If they fail, fix or stop - don't push red.

## 3. Raise the PR

```bash
git push -u origin HEAD
gh pr create -R mattlol85/$REPO --base main --title "<title>" --body "<summary + test plan + PR attribution line>"
```

## 4. Gate on CI

```bash
gh pr checks <PR#> -R mattlol85/$REPO --watch --fail-fast
```

- **All pass** -> continue.
- **Any fail / cancelled / no checks reported** -> STOP. Show the failing
  job's log (`gh run view --log-failed`) and ask the user. Do not merge.

## 5. Merge

```bash
gh pr merge <PR#> -R mattlol85/$REPO --squash --delete-branch
git switch main && git pull
```

If merging is blocked (required reviews, conflicts), stop and report.

## 6. Tag / release

Check which mechanism the repo has:

```bash
ls ../$REPO/.github/workflows
```

- **`publish.yml` exists** (fitz-net-website, fitz-net-api): it runs tests,
  bumps the version, tags `vX.Y.Z`, and creates the GitHub Release.
  ```bash
  gh workflow run publish.yml -R mattlol85/$REPO -f increment-type=<patch|minor|major>
  gh run watch -R mattlol85/$REPO "$(gh run list -R mattlol85/$REPO -w publish.yml -L1 --json databaseId -q '.[0].databaseId')" --exit-status
  git pull --tags && git tag --sort=-v:refname | head -1   # new tag = $TAG
  ```
- **No `publish.yml`** (GamerBell, Fitz-Bot): compute the next semver from
  `git tag --sort=-v:refname | head -1`, then
  `git tag -a $TAG -m "<emoji> Auto <bump> release $TAG" && git push origin $TAG`
  and `gh release create $TAG --generate-notes -R mattlol85/$REPO`.
  Confirm the new tag with the user first if the repo has no prior tags.

## 7. Deploy

The release-published event does **not** reliably trigger the deploy (releases
made with `GITHUB_TOKEN` don't cascade), so always dispatch explicitly. See the
`deploy-to-proxmox` skill for details.

```bash
# fitz-net-api / fitz-net-website / GamerBell: input is `tag`
gh workflow run deploy-to-proxmox.yml -R mattlol85/$REPO -f tag=$TAG
# Fitz-Bot: workflow is Deployment.yml, input is `version`
```

- Check first whether a deploy run was already started by the release
  (`gh run list -w deploy-to-proxmox.yml -L3`); don't double-dispatch.
- **Never run api + website deploys concurrently** - they race on
  `docker image prune`. Deploy one at a time; if one fails with "a prune
  operation is already running", re-run it solo.
- Watch with `gh run watch ... --exit-status`. If it sits queued > ~30s the
  self-hosted runner on the VM is probably down - report it.

## 8. Verify and report

```bash
curl -fsS https://api.fitznet.doomdns.org/actuator/info
curl -fsS https://gamerbell.fitznet.doomdns.org/actuator/info
curl -fsS -o /dev/null -w '%{http_code}\n' https://fitznet.org/   # website: 200
```

Confirm the live version matches `$TAG` where an info endpoint exists. Final
report: PR link, merged commit, tag, deploy run link, live check result, and any
files deliberately left out of the commit. On a bad deploy, roll back by
re-dispatching with the previous tag.

## Guardrails

- Merge, tag, and deploy are outward-facing: only proceed when the user invoked
  this skill (that is the authorization). Don't extend it to other repos.
- Never `--no-verify`, never force-push, never merge with failing/pending checks.
