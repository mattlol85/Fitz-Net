---
name: prod-handoff
description: Template and checklist for the handoff docs that live on the prod Proxmox Docker VM. Mirrors the structure of the existing docs/*-handoff.md files - what to run on the box, verification steps, and rollback. Use when writing or updating a docs/*-handoff.md.
---

# prod-handoff

Handoff docs in `docs/` are runbooks that get copied **onto the machine they
describe** (the Proxmox Docker VM `192.168.1.59` / `proxmoxvm`, the OpenVPN Pi,
etc.). Study `docs/openvpn-ai-node-handoff.md` and
`docs/proxmox-self-hosted-runner-handoff.md` before writing — match their voice:
second person, "put a copy of this file on that machine", a "## Why" section,
numbered steps with exact copy-pasteable commands, and an explicit revert path.

## Structure to follow

1. **Title** — `# Handoff: <what this enables> on <which box>`
2. **Why** — one short paragraph: what changed and why this runbook exists.
   Note what does *not* depend on this (e.g. "heartbeats still go over public
   HTTPS regardless").
3. **Primary path** — the automated / normal route (a workflow, a script).
4. **One-time setup** — numbered, with exact commands, secrets handled via
   `gh secret set` (never pasted into chat or committed).
5. **Verification** — commands run *on the box itself* that prove it works,
   with expected output.
6. **Rollback / revoke** — the exact steps to undo, and what else must change.
7. **Fallback / manual path** — what the automation does, by hand.

## Fill-in template

```markdown
# Handoff: <capability> on <box name / IP / alias>

This is the runbook for <box> — <one line on its role>. Put a copy of this file
directly on that machine.

## Why

<What changed. What this doc covers. What is out of scope / unaffected.>

## Primary path: <the workflow or script>

<How it is normally triggered, e.g. `gh workflow run <file>.yml -R mattlol85/<repo> -f <input>=<value>`.>

### One-time setup

1. **<step>**
   ```bash
   <command>
   ```
2. **<step>**
   ```bash
   <command>
   ```
3. **Store secrets in GitHub, never in the repo**
   ```bash
   gh secret set <NAME> -R mattlol85/<repo> < <file>
   ```

## Verify

Run on <box>:

```bash
<verification command>      # expect: <expected output>
curl -fsS https://<service>.fitznet.org/actuator/health   # expect: {"status":"UP"}
```

## Rollback

```bash
<revert command — e.g. redeploy the previous image tag>
```

Then: <anything else that must be reverted — secrets, authorized_keys lines,
pushed routes>.

## Fallback / manual path

<Step-by-step of what the automation does, for doing it by hand.>
```

## Checklist before you commit the doc

- [ ] Every command is copy-pasteable and uses real hostnames/paths from this platform.
- [ ] Secrets go through `gh secret set` / env; none are in the doc.
- [ ] There is a verification section with expected output.
- [ ] There is a rollback section.
- [ ] Filename is `docs/<subject>-handoff.md` (or `-prod-handoff.md`).
- [ ] Linked from `README.md` or the relevant `docs/` file if it is a first-class runbook.
