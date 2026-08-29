---
name: sync-siblings
description: Runs the mandatory six-repo git pull from .github/agents.md Before You Start, then prints a per-repo summary of branch, ahead/behind, and dirty files. Use before any Fitz-Net cross-repo work.
---

# sync-siblings

The Fitz-Net repos move independently. Working against stale checkouts breaks
cross-repo contracts. Run this before any task.

## 1. Pull every repo

```bash
git -C ../Fitz-Net pull
git -C ../fitz-net-api pull
git -C ../fitz-net-website pull
git -C ../GamerBell pull
git -C ../Esp32FitznetBell pull
git -C ../Fitz-Bot pull
```

If a pull fails because the tree is dirty or on a feature branch with no
upstream, do not stash or reset — record it and move on.

## 2. Print a per-repo summary

For each of the six paths, run:

```bash
for d in ../Fitz-Net ../fitz-net-api ../fitz-net-website ../GamerBell ../Esp32FitznetBell ../Fitz-Bot; do
  echo "=== $d ==="
  git -C "$d" fetch --quiet
  git -C "$d" status -sb | head -1
  echo "dirty files: $(git -C "$d" status --porcelain | wc -l)"
  git -C "$d" status --porcelain
  git -C "$d" log -1 --format='HEAD: %h %s (%cr)'
done
```

## 3. Report

A table: `Repo | Branch | Ahead/Behind | Dirty files | Last commit`. Call out
any repo that is not on `main`, is behind its upstream after the pull, or has
uncommitted changes — those need attention before cross-repo work starts.
