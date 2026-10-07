---
name: arch-visualize
description: How the Fitz-Net architecture visualization is built and updated - the 3D graph on the website Status page. Covers where the graph data lives, the Proxmox-node to VM to docker-stack nesting, icon and link conventions, and running a dev server for live preview. Use when adding a service or infra node to the picture.
---

# arch-visualize

The architecture picture is the **3D graph on the Status page** in
`fitz-net-website`, plus the two Mermaid diagrams in `Fitz-Net/README.md`
(Infrastructure and Services). Keep them consistent with each other and with the
real cross-repo contracts.

## Where the graph lives (fitz-net-website)

| File | Role |
|---|---|
| `src/constants/architecture.js` | **Single source of truth** — all nodes, edges, tiers, colors, link kinds. Edit this to change the picture. |
| `src/components/ArchitectureGraph.jsx` | three.js renderer — meshes, icons, labels, hover raycast |
| `src/components/StatusDashboard.jsx` | page that hosts the graph |
| `src/services/architectureStatus.js` | derives each node's live status |
| `src/services/actuatorService.js` | polls `/actuator/health` per service |
| `src/css/ArchitectureGraph.css` | layout/overlay styling |

## Model in `architecture.js`

- **Tiers** (`TIER_Y`): `EDGE` (devices + third parties) -> `APP` (services) ->
  `DATA` (stores) -> `VM` / `CONTAINER` -> `HOST` (physical machines). Reads
  top-to-bottom.
- **Nodes**: `ARCHITECTURE_NODES` (services/devices/externals), `PROXMOX_NODE`,
  `RASPBERRY_PI_NODE`, `VM_NODES`, and container nodes generated per VM by
  `buildContainerNodes`. Final exports: `ALL_NODES`, `ALL_EDGES`.
- **Nesting**: `proxmox` --`hosts`--> each VM; a VM --`runsOn`--> each container
  it runs; a container --`mirror`--> the service it is an instance of. So the
  docker stack shows as containers sitting on the VM deck, the VM sits on the
  Proxmox host, and each container mirrors its app-tier service.
- **Status sources** (`statusSource.kind`): `actuator` (has `configName`),
  `inferred` (from another node + a rule, e.g. ESP32 ota-reachable),
  `external`, `unmonitored`, `nested-health`.
- **Link kinds** (`LINK_KINDS`): line color = protocol
  (`http` blue, `ws` purple, `ota` amber, `db` green, `external` pink), dashed =
  structural (`hosts`, `deployedOn`, `runsOn`, `mirror`). A travelling pulse
  encodes liveness so color and liveness never fight.
- **Icons**: keyed by `NODE_TYPES`; label/status-dot offsets per type live in
  `LABEL_OFFSET_Y` / `DOT_OFFSET_Y` in `ArchitectureGraph.jsx`.

## Adding a node — checklist

1. Scan the repos for the real contract: what talks to what, over which protocol
   (`fitz-net-website/src/services/api.js`, `constants.js`; GamerBell
   `ButtonEventDto` + `WebSocketButton.jsx`; `Fitz-Net/docker-compose.yml` for
   which container runs where; each repo's `.github/agents.md`).
2. Add a `NODE_TYPES` entry if it is a new kind; add its icon in
   `ArchitectureGraph.jsx` and label/dot offsets.
3. Add the node object to `ARCHITECTURE_NODES` (or `VM_NODES` / the container
   builder) with `id`, `label`, `type`, `position` on the right tier, and a
   `statusSource`.
4. Add edges to `ARCHITECTURE_EDGES` with the correct `kind` and a `note`
   describing the real contract (endpoint path, event name).
5. If it is a container, make sure the VM's service list picks it up so the
   `runsOn` / `mirror` edges generate.
6. Update the `README.md` Mermaid diagrams to match.
7. Update/extend `ArchitectureGraph.test.jsx` and `architectureStatus.test.js`.

## Live preview

```bash
cd ../fitz-net-website
npm install          # first time
npm run dev          # Vite dev server, then open the Status page
VITE_USE_MOCK_API=true npm run dev   # offline — mock status data, no backend needed
npx vitest run src/components/ArchitectureGraph.test.jsx
```
