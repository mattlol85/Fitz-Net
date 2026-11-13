# Matt-GPT v2 — AI chat contract

The contract between `fitz-net-api` and `fitz-net-website` for the `/ai` tab: server-side
conversations, one model picker across nodes, switching node and model mid-conversation, warm-up,
thinking, presets, image attachments and per-reply stats.

Tools/MCP, RAG and web search are **out of scope**; the message schema and the stream leave room
for them (see [Deferred](#17-deferred)).

Decisions taken with the owner before this was written:

| Topic | Decision |
|---|---|
| History model | **Linear.** Regenerate replaces the answer, edit truncates what follows. Messages store `parentId` so branching can be added later without a migration. |
| Context overflow | **Trim, then offer a summary.** Oldest turns are left out of the prompt (never deleted) with a visible warning; "Summarise older turns" is an explicit action. |
| Model metadata | **The API fetches it from each node's Ollama** (short cache). The heartbeat only gains two optional VRAM fields. |
| `ollama.keep-alive` | Folded into this work (same property name and default as the unmerged `feature/ollama-keep-alive` edits). |

---

## 1. Conventions

- **Base path** `/ai` on `fitz-net-api` (the browser calls `${FITZ_NET_API}/ai/...`).
- **Auth.** Every `/ai/**` endpoint and every `AiChatService` RPC requires
  `hasAnyAuthority('PERM_AI_USER','PERM_ADMIN')`. None is public, so nothing is added to
  `GrpcAuthInterceptor.PUBLIC_METHODS`.
- **Owner.** The owner of a conversation, attachment, private preset and preference document is
  `Authentication.getName()` (the canonical lowercase username). A resource owned by someone else
  answers **404**, never 403, so existence is not leaked. `ADMIN` gets no access to other users'
  conversations.
- **IDs** are Mongo ObjectId hex strings. **Timestamps** are ISO-8601 instants in JSON and
  `google.protobuf.Timestamp` in proto.
- **Errors outside a stream** use the existing `GlobalExceptionHandler` body and status codes
  (400 validation, 401, 403, 404, 409). gRPC maps them through `GrpcExceptionMapper` as today.
- **No void responses.** Deletes return `{ "deleted": true }`.
- **Tracing.** Requests pass through `RequestTracingFilter` / `GrpcTracingInterceptor` unchanged.
  Work moved to another thread (catalogue fetches, warm-up, the keep-alive ticker) must carry the
  MDC `correlationId` with it. The browser uses `fetch` only (never `EventSource` or XHR) so
  `installFetchTracing()` adds `X-Correlation-ID`.
- **Logging.** Never log message content, thinking, system prompts, titles, summaries or image
  data. Log ids, node, model, token counts and durations.
- **Limits** (all configurable, see [Configuration](#15-configuration)): message ≤ 32 000 chars,
  ≤ 4 attachments per message, attachment ≤ 3 MB decoded, system prompt ≤ 8 000 chars, title ≤ 120
  chars.

## 2. Nodes and model metadata

### 2.1 Source of model metadata (decision)

The API reads model details and the loaded set **directly from each node's Ollama** and caches them:

| Call | Gives | Cache |
|---|---|---|
| `GET http://{address}/api/tags` | installed models: `name`, `size`, `digest`, `details.family`, `details.parameter_size`, `details.quantization_level` | `ai.catalog.models-ttl` (60 s) |
| `POST http://{address}/api/show` | `model_info.*.context_length`, `capabilities[]` (`completion`, `vision`, `thinking`, `tools`) | existing `ollama.model-info-ttl` (10 m), keyed by address + model + digest |
| `GET http://{address}/api/ps` | loaded models: `name`, `size_vram`, `expires_at` | `ai.catalog.loaded-ttl` (5 s) |

Why not the heartbeat:

1. Loaded/warm state changes within seconds; the heartbeat runs every 2 minutes, so a
   heartbeat-fed "loaded" badge would be wrong most of the time.
2. It needs **no installer redistribution** — the picker works against every node already enrolled.
3. The API already has to reach each node's Ollama over the LAN/VPN to chat, so this adds no new
   network path or credential.
4. Cost is bounded: fetches are lazy (only when someone asks for the catalogue or sends a turn),
   run in parallel across nodes, and use short timeouts (`ai.catalog.connect-timeout` 2 s,
   `ai.catalog.read-timeout` 4 s).

Failure handling: if a node's Ollama cannot be reached, the last good snapshot is served with
`catalogStale: true`; with no snapshot, the node's models fall back to the heartbeat's names with
all detail fields `null`. A node whose effective status is `OFFLINE` is not contacted. A model whose
`capabilities` are known and do not include `completion` (embedding models) is left out. The node
`address` is never sent to clients.

### 2.2 Effective node status

Today a node's status is whatever the last heartbeat stored, forever. From now on **every** place
that exposes or uses a status (`/node/list`, `NodeService/ListNodes`, the catalogue, routing) uses
the effective status:

```
OFFLINE  stored status is OFFLINE, or lastHeartbeatAt is null or older than ai.node.stale-after (5m)
BUSY     otherwise, if stored status is BUSY or the API has ≥ 1 generation in flight on the node
ONLINE   otherwise
```

`activeGenerations` is an in-memory count of chat streams the API currently has open against the
node (legacy and v2 endpoints both count). The wire shape of `/node/list` does not change.

### 2.3 Heartbeat: optional VRAM (the only installer change)

`POST /node/heartbeat` and `NodeService/Heartbeat` accept two new **optional** fields:

| JSON | proto (`HeartbeatRequest`) | Meaning |
|---|---|---|
| `vramTotalMb` (int) | `optional int32 vram_total_mb = 6` | GPU memory total, MiB (`nvidia-smi memory.total`) |
| `vramUsedMb` (int) | `optional int32 vram_used_mb = 7` | GPU memory in use by **everything** (games included), MiB |

They are stored on `AiNode` with `vramReportedAt` and used only while that timestamp is within
`ai.node.stale-after`, so a node that stops reporting never shows frozen numbers. Nodes on the old
installer simply omit them and keep working; the picker then shows only what Ollama itself has
loaded against the registered `vramGb`. Shipping this to nodes means redistributing
`scripts/ai-node-installer`.

## 3. Picker catalogue

`GET /ai/models[?refresh=true]` → `AiChatService/ListModels`

`refresh=true` bypasses the caches (the server still rate-limits to one forced fetch per node per
2 s).

```jsonc
{
  "generatedAt": "2026-11-12T18:04:11Z",
  "nodes": [
    {
      "id": "6741…",
      "name": "Matt-PC",
      "status": "ONLINE",              // effective status: ONLINE | BUSY | OFFLINE
      "os": "Windows 11",
      "lastHeartbeatAt": "2026-11-12T18:03:02Z",
      "activeGenerations": 0,
      "catalogStale": false,           // true: Ollama unreachable, data is cached or heartbeat-only
      "vram": {
        "totalMb": 16384,              // heartbeat vramTotalMb, else registered vramGb × 1024, else null
        "usedMb": 9216,                // heartbeat vramUsedMb, else sum of loaded models' vramMb, else null
        "source": "heartbeat"          // "heartbeat" | "ollama" | null — what usedMb is based on
      },
      "models": [
        {
          "name": "llama3.1:8b",
          "family": "llama",           // nullable
          "parameterSize": "8.0B",     // nullable
          "quantization": "Q4_K_M",    // nullable
          "sizeBytes": 4920753328,     // nullable
          "contextLength": 8192,       // effective window: min(native, ollama.max-num-ctx); null if the node could not report it
          "maxContextLength": 131072,  // native window, nullable
          "capabilities": ["completion", "vision"],   // [] when unknown
          "loaded": true,              // in /api/ps, or a warm-up for it is in flight
          "loadedUntil": "2026-11-12T18:33:00Z",      // expires_at, nullable
          "vramMb": 5300               // size_vram when loaded, nullable
        }
      ]
    }
  ],
  // One row per distinct model name on nodes that are not OFFLINE — the "Auto" entries.
  "models": [
    {
      "name": "llama3.1:8b",
      "nodeIds": ["6741…", "6742…"],   // nodes (not OFFLINE) that have it
      "loadedOn": ["6741…"],
      "autoNodeId": "6741…",           // where Auto would route right now (section 4)
      // Details below are the autoNodeId node's copy of the model.
      "parameterSize": "8.0B",
      "quantization": "Q4_K_M",
      "contextLength": 8192,
      "capabilities": ["completion", "vision"]
    }
  ]
}
```

`nodes` lists every registered node, OFFLINE ones included (the picker greys them out and lists them
last), sorted by name. An OFFLINE node's `models` come from its last snapshot or heartbeat names and
may be empty; a node that never sent a heartbeat is OFFLINE. `autoNodeId` may be a BUSY node.

## 4. Routing

A **target** is `{ "model": string, "nodeId": string | null }`. `nodeId: null` means **Auto**.
Model names are matched exactly (`llama3.1:8b`).

### 4.1 Auto

Candidates are nodes whose effective status is not `OFFLINE`, that have an address, and that list
the model (live catalogue names; heartbeat names if the catalogue is unavailable). Nodes already
tried in the current turn are excluded. Candidates are ordered by:

1. **Warm first** — the model is loaded on the node, or a warm-up for it is in flight.
2. **Least busy** — fewest `activeGenerations`; then heartbeat status `ONLINE` before `BUSY`.
3. **Fits** — the model's `sizeBytes` ≤ free VRAM (`totalMb − usedMb`); unknown counts as fits.
4. **Most free VRAM** (unknown last).
5. Node name, then id (stable tie-break).

No candidate → error `NO_NODE_AVAILABLE`.

If the chosen node fails **before the first upstream chunk** (connect error, HTTP error), the server
moves to the next candidate, at most 2 times, emitting `status {phase:"failover"}` and a fresh
`meta`. After the first chunk there is no transparent failover (output would duplicate); the turn
ends with an `error` that lists alternatives.

### 4.2 Explicit node

The server never substitutes silently:

| Situation | Error code |
|---|---|
| Node unknown, effective status `OFFLINE`, or no address | `NODE_OFFLINE` |
| Node does not have the model | `MODEL_NOT_ON_NODE` |
| Connect/read failure while generating | `NODE_UNREACHABLE` |

Each of these carries `alternatives`: the other nodes that have the same model, in Auto order.
One-click failover is "regenerate the failed message with `target` set to an alternative" (or to
`{model, nodeId: null}` for Auto).

## 5. Warm-up

`POST /ai/warmup` → `AiChatService/WarmUp`

```jsonc
// request
{ "model": "llama3.1:8b", "nodeId": null }
// response (200)
{ "state": "loading", "nodeId": "6741…", "nodeName": "Matt-PC", "model": "llama3.1:8b", "message": null }
```

`state`: `loaded` (already in memory), `loading` (a preload was started, or one is already in
flight), `unavailable` (no node can serve it right now; `message` says why, `nodeId` may be null).

The server resolves the target with the routing rules, returns immediately, and — when the model is
not loaded — preloads it on a background thread with Ollama's empty request
(`POST /api/generate {"model": …, "keep_alive": ollama.keep-alive}`). Concurrent warm-ups for the
same node + model share one in-flight request. Every chat request also sends
`keep_alive: ollama.keep-alive` (default `30m`).

The client calls this when a model is **selected** (not hovered), debounced.

## 6. Conversations

| REST | gRPC | Body → response |
|---|---|---|
| `GET /ai/conversations?q=&limit=&offset=` | `ListConversations` | → `{ items: ConversationSummary[], hasMore }` |
| `POST /ai/conversations` | `CreateConversation` | `{ title?, target?, settings? }` → `Conversation` |
| `GET /ai/conversations/{id}` | `GetConversation` | → `ConversationDetail` |
| `PATCH /ai/conversations/{id}` | `UpdateConversation` | `{ title?, pinned?, target?, settings? }` → `Conversation` |
| `DELETE /ai/conversations/{id}` | `DeleteConversation` | → `{ deleted: true }` (messages and attachments go too) |
| `POST /ai/conversations/{id}/title` | `GenerateTitle` | → `Conversation` |

```jsonc
// Conversation (ConversationSummary is the same plus an optional "matchSnippet")
{
  "id": "6750…",
  "title": "Tuning the bell debounce",
  "titleSource": "auto",               // "default" | "auto" | "user"
  "pinned": false,
  "target": { "model": "llama3.1:8b", "nodeId": null },   // nullable until first chosen
  "settings": { "presetId": null, "systemPrompt": null },
  "messageCount": 6,
  "createdAt": "…",
  "updatedAt": "…"
}

// ConversationDetail = Conversation +
{
  "summary": null,                     // or { text, coversThroughSeq, model, partial, createdAt }
  "context": { /* ContextUsage for the current target, section 8; null if it can't be resolved */ },
  "messages": [ /* Message[], ascending seq */ ]
}

// Message
{
  "id": "6751…",
  "seq": 4,
  "parentId": "6751…",                 // previous message; null for the first
  "role": "assistant",                 // "user" | "assistant" ("system" and "tool" are reserved)
  "content": "…",
  "thinking": null,                    // assistant reasoning text, never replayed to a model
  "attachments": [ { "id": "…", "kind": "image", "mimeType": "image/jpeg", "sizeBytes": 412345, "name": "bell.jpg" } ],
  "toolCalls": [],                     // reserved, always []
  "status": "complete",                // "complete" | "streaming" | "cancelled" | "error"
  "error": null,                       // or { "code": "NODE_OFFLINE", "message": "…" }
  "generation": {                      // assistant only, else null
    "nodeId": "6741…", "nodeName": "Matt-PC", "model": "llama3.1:8b",
    "auto": true,                      // routed by Auto
    "presetId": null, "presetName": null,
    "contextLength": 8192,
    "promptTokens": 812, "completionTokens": 240,
    "ttftMs": 420, "totalMs": 5210, "loadMs": 0, "thinkingMs": null,
    "tokensPerSecond": 48.2,
    "finishReason": "stop",            // "stop" | "length" | "cancelled" | "error"
    "contextOverflow": false           // the model's window was full (same flag as the done event)
  },
  "createdAt": "…",
  "editedAt": null
}
```

Rules:

- **List** is the caller's conversations, pinned first, then `updatedAt` descending. `limit`
  defaults to 50 (max 200). `q` is a case-insensitive substring match on the title **or** any
  message content (escape the term; it is not a regex); a content hit fills `matchSnippet` (≤ 160
  chars around the match).
- `updatedAt` moves on a new turn, rename or settings change — not on pin.
- **PATCH** fields are independent; an absent field is left alone. `target` and `settings` are
  replaced whole when present, so `settings: { "presetId": null, "systemPrompt": null }` clears
  both. A user-supplied `title` sets `titleSource: "user"`.
- Setting `settings.presetId` (on create or PATCH) without a `target` in the same request copies
  the preset's pinned model into `target`, if the preset pins one.
- A `target` change also updates the user's `lastTarget` preference.
- **Titles.** A new conversation is `"New chat"` (`default`). The first user message sets a
  provisional title (its first line, ≤ 60 chars, still `default`). `POST …/title` asks the model of
  the last assistant message for a ≤ 6-word title (non-streaming call, `num_predict` 32, thinking
  off where the model allows, 20 s timeout) and stores it as `auto`. It is best-effort: on any
  failure, or when `titleSource` is `user`, the conversation is returned unchanged with 200. The
  client calls it once, after the first reply completes.
- A message found in `streaming` state when no generation is in flight for that conversation is
  returned as `status: "error"`, `error.code: "INTERRUPTED"`.
- `DELETE` and `…/summarize` answer **409** while a generation is in flight for the conversation.
- An assistant message that failed before a node was chosen (routing, vision check) still has a
  minimal `generation`: the **requested** `model` and `nodeId` (null for Auto), `nodeName` when
  known, `auto`, `finishReason: "error"`; everything else null.

## 7. Turns (streaming)

| REST (response is `text/event-stream`) | gRPC (server stream of `TurnEvent`) |
|---|---|
| `POST /ai/conversations/{id}/messages` | `SendMessage` |
| `POST /ai/conversations/{id}/messages/{messageId}/regenerate` | `RegenerateMessage` |
| `POST /ai/conversations/{id}/messages/{messageId}/edit` | `EditMessage` |

```jsonc
// send
{ "content": "…", "attachmentIds": ["…"], "target": { "model": "…", "nodeId": null } }
// regenerate (body optional)
{ "target": { "model": "…", "nodeId": "6742…" } }
// edit
{ "content": "…", "attachmentIds": ["…"], "target": { "model": "…", "nodeId": null } }
```

- **send** appends a user message and answers it. `content` may be empty only if there is at least
  one attachment.
- **regenerate** — `messageId` must be an **assistant** message. It and everything after it are
  deleted, then a new answer is generated for the same history. This is also "Regenerate with…" and
  the failover action.
- **edit** — `messageId` must be a **user** message. Its content is replaced in place (same id and
  `seq`, `editedAt` set), everything after it is deleted, then it is answered. `attachmentIds`
  absent keeps the existing attachments; present replaces them.
- `target` is optional everywhere. When present it **becomes the conversation's target** (and the
  user's `lastTarget`) before generating. When absent the conversation's target is used.
- The browser sends only the new content. The server builds the prompt from stored history.
- Deleting messages also deletes their attachments, and drops the conversation's `summary` if the
  deletion reaches into the summarised range.

Pre-stream HTTP errors (nothing is persisted, the response is normal JSON):

| Status | When |
|---|---|
| 400 | empty/oversized content, too many attachments, unknown or foreign attachment id, `messageId` has the wrong role, no target on the request and none on the conversation |
| 404 | conversation or message not found, or not the caller's |
| 409 | a generation is already in flight for this conversation |

### 7.1 Pipeline

1. Validate and apply the action (persist the user message / truncate). Create the assistant
   message with `status: "streaming"`. Open the stream.
2. Resolve the target (section 4). Failure → `error` event; the assistant message is saved with
   `status: "error"`.
3. Vision check: if the **new** user message has images and the model lacks `vision` →
   `error MODEL_NOT_VISION`.
4. Build the prompt (section 8) and emit `meta`.
5. If the model is not loaded on the node, emit `status {phase:"loading_model"}`.
6. Open `/api/chat` with `stream: true`, `keep_alive`, `options.num_ctx` (and `temperature` from the
   preset), and `think: true` only when the model reports the `thinking` capability.
7. On the first upstream chunk emit `status {phase:"generating"}`, then relay `thinking` and `token`
   deltas.
8. Finish with exactly one `done` or `error`. In a `finally`, persist the assistant message:
   content and thinking so far, final status, generation stats.

**Cancel.** Closing the HTTP response (browser `AbortController`) or cancelling the gRPC call stops
the generation on the GPU by disconnecting the upstream `HttpURLConnection` — the existing
behaviour, which must be kept. It must take effect at **any** point, including while the model is
still loading and no upstream bytes have arrived: while a turn is open the server writes an SSE
comment frame (`:\n\n`) whenever nothing else was written for `ai.chat.cancel-poll-interval` (1 s),
and a failed write (REST) or `isCancelled()` / `onCancel` (gRPC) disconnects the upstream. A closed
HTTP connection is only noticed on the second write after it closes, so a cancel during loading
lands within about two intervals (≈ 2 s); a cancel while tokens are flowing is immediate. The partial reply is kept with `status: "cancelled"`, `finishReason: "cancelled"`.

**History replay.** Sent to the model in `seq` order: assistant messages with non-empty content and
status `complete` or `cancelled`, and all user messages. `thinking` is never replayed. Messages with
status `error` are skipped. Images from older messages are sent only if the target model has
`vision`; otherwise they are dropped from the prompt and counted in `context.imagesOmitted`.

### 7.2 Events

Grammar: `meta? (status | thinking | token | meta)* (done | error)`. `meta` is missing only when
routing fails; it repeats only after an Auto failover (the latest wins, with the same
`conversationId`, `userMessageId` and `assistantMessageId`). Comment frames (`:\n\n`)
may appear anywhere. **Clients must ignore unknown event names and unknown fields.**

```jsonc
// event: meta
{
  "conversationId": "6750…", "userMessageId": "6751…", "assistantMessageId": "6752…",
  "nodeId": "6741…", "nodeName": "Matt-PC", "model": "llama3.1:8b",
  "auto": true, "presetId": null,
  "contextLength": 8192,
  "context": { "promptTokensEstimate": 3110, "trimmedCount": 0, "summaryActive": false, "imagesOmitted": 0 }
}

// event: status
{ "phase": "loading_model", "nodeId": "6741…", "model": "llama3.1:8b", "message": "Loading llama3.1:8b on Matt-PC…" }
{ "phase": "generating" }
{ "phase": "failover", "fromNodeId": "6741…", "toNodeId": "6742…", "message": "Matt-PC did not answer, trying Rig-2…" }

// event: thinking   (reasoning delta, from Ollama message.thinking)
{ "content": "The user wants…" }

// event: token      (answer delta, unchanged from v1)
{ "content": "Sure" }

// event: done
{
  "messageId": "6752…", "userMessageId": "6751…",
  "promptTokens": 812, "completionTokens": 240, "contextLength": 8192,
  "finishReason": "stop",              // "stop" | "length"
  "contextOverflow": false,            // true when promptTokens reached contextLength (the model truncated)
  "stats": { "ttftMs": 420, "totalMs": 5210, "loadMs": 0, "thinkingMs": null, "tokensPerSecond": 48.2 }
}

// event: error
{
  "messageId": "6752…", "userMessageId": "6751…",
  "code": "NODE_OFFLINE", "message": "Matt-PC is offline.", "retryable": true,
  "alternatives": [ { "nodeId": "6742…", "nodeName": "Rig-2", "model": "llama3.1:8b", "loaded": true, "status": "ONLINE" } ]
}
```

Stats: `ttftMs` is request received → first `thinking` or `token` written; `totalMs` is request
received → `done`; `loadMs` is Ollama's `load_duration`; `thinkingMs` is first `thinking` → first
`token` (null without thinking); `tokensPerSecond` is `eval_count / eval_duration` (1 decimal, null
if unavailable).

Error codes: `NODE_OFFLINE`, `MODEL_NOT_ON_NODE`, `NO_NODE_AVAILABLE`, `NODE_UNREACHABLE`,
`NODE_ERROR` (Ollama returned an error), `TIMEOUT` (node silent for `ollama.read-timeout`, or
`ollama.max-stream-duration` exceeded), `MODEL_NOT_VISION`, `CONTEXT_TOO_SMALL` (the newest message
alone does not fit), `INTERNAL`. `alternatives` is present (possibly empty) for the first four.

Reserved for later, not emitted in v2: `tool_call { id, name, arguments }`,
`tool_result { toolCallId, content }`.

## 8. Context window

`contextLength` is the model's effective window on the resolved node:
`min(native context_length, preset numCtx if set, ollama.max-num-ctx)`. It is sent to Ollama as
`options.num_ctx`.

The server has no tokenizer, so it estimates conservatively:
`tokens(text) = ceil(codePoints / 3) + 4` per message, **768 per image**. The estimate is stored on
each message (`tokenEstimate`).

Prompt building, newest first:

```
budget = contextLength − replyReserve − tokens(system prompt)
replyReserve = min(max(contextLength / 4, 256), 2048)
```

1. If the whole history fits the budget, send it all (a stored summary is ignored but kept).
2. Otherwise, if a summary exists: send it as a system message (`"Summary of the earlier
   conversation:\n…"`) plus the messages after `coversThroughSeq`, newest first, as many as fit.
3. Otherwise send the newest messages that fit.
4. The newest user message is always included; if it alone does not fit → `CONTEXT_TOO_SMALL`.

`trimmedCount` is the number of stored messages that were neither sent nor covered by the summary
in use. Nothing is ever deleted by trimming.

**Preflight** — `GET /ai/conversations/{id}/context?model=&nodeId=` → `GetContextUsage`.
Without `model` it uses the conversation's target. The client calls it when the user switches model
so the ring and the warning update before anything is sent. When the target cannot be resolved right
now (no target, node offline, model gone) it answers 503, and `ConversationDetail.context` is `null`.

```jsonc
// ContextUsage
{
  "model": "phi3:mini", "nodeId": "6741…",        // the node it resolved to
  "contextLength": 4096,
  "usedTokens": 2890,          // estimate of what would be sent next turn (system + summary + included history)
  "totalTokens": 7420,         // estimate of the whole stored history
  "fits": false,               // trimmedCount == 0
  "trimmedCount": 9,
  "summaryActive": false
}
```

**Summarise** — `POST /ai/conversations/{id}/summarize` → `SummarizeConversation`, no body,
blocking. Using the conversation's current target, the server asks the model to summarise the
messages that are currently trimmed (folding in any earlier summary), stores it on the conversation
and returns `{ "conversation": Conversation, "summary": {…}, "context": ContextUsage }`. If the
trimmed range does not fit the window either, the most recent part of it is summarised and
`partial: true` is set. `409` when nothing is trimmed. Routing failures use the normal HTTP codes
(503 for no node).

## 9. Presets

| REST | gRPC | |
|---|---|---|
| `GET /ai/presets` | `ListPresets` | → `{ items: Preset[] }` visible to the caller |
| `POST /ai/presets` | `CreatePreset` | → `Preset` |
| `PUT /ai/presets/{id}` | `UpdatePreset` | → `Preset` |
| `DELETE /ai/presets/{id}` | `DeletePreset` | → `{ deleted: true }` |

```jsonc
{
  "id": "6760…",
  "name": "Code reviewer",                 // 1–60 chars
  "description": "Blunt, cites line numbers",   // ≤ 200 chars, nullable
  "model": "qwen2.5-coder:14b",            // nullable = "whatever model is selected"
  "nodeId": null,                          // nullable = Auto; only meaningful with a model
  "systemPrompt": "You are…",              // ≤ 8000 chars, nullable
  "temperature": 0.2,                      // 0–2, nullable = model default
  "numCtx": 8192,                          // 512–131072, nullable = model default; capped at run time
  "visibility": "private",                 // "private" | "shared"
  "requiredPermission": null,              // shared only: null = everyone with AI access
  "ownerUsername": "matt",
  "editable": true,                        // computed for the caller
  "createdAt": "…", "updatedAt": "…"
}
```

- **Visibility by permission.** `private` presets are visible to and editable by their owner only.
  `shared` presets are visible to callers who hold `requiredPermission` (or to everyone with AI
  access when it is null) and to `ADMIN`; only `ADMIN` can create, edit or delete them (403).
- A conversation references a preset by `settings.presetId`. Values are read **at generation
  time**, not snapshotted: system prompt = `settings.systemPrompt` (the per-conversation override)
  if set, else the preset's; `temperature` and `numCtx` from the preset. A deleted or no longer
  visible preset is treated as none.
- Each assistant message records `presetId` and `presetName` as they were when it was generated.

## 10. Attachments

| REST | gRPC | |
|---|---|---|
| `POST /ai/attachments` | `UploadAttachment` | `{ name, mimeType, dataBase64 }` (proto: `bytes data`) → `Attachment` |
| `GET /ai/attachments/{id}` | `GetAttachment` | REST: the raw bytes with their `Content-Type` and `Cache-Control: private, max-age=31536000, immutable`. gRPC: `{ mime_type, data }` |

- Images only: `image/png`, `image/jpeg`, `image/webp`. ≤ 3 MB decoded, ≤ 4 per message.
- Upload first, then reference the ids in `attachmentIds`. An upload not attached to a message
  within `ai.chat.attachment-orphan-ttl` (24 h) is removed by a Mongo TTL index.
- Images go to Ollama in the message's `images` array (base64).
- The client downsizes before upload (longest side ≤ 1568 px, JPEG, aiming for ≤ 700 KB) so the
  request also passes proxies with a 1 MB body limit, and enables attaching **only** when the
  selected model's `capabilities` include `vision`.
- `<img>` cannot send the bearer token, so the client fetches the bytes with `fetch` and shows them
  through an object URL.

## 11. Preferences

`GET /ai/preferences` → `GetPreferences`, `PUT /ai/preferences` → `UpdatePreferences`

```jsonc
{ "lastTarget": { "model": "llama3.1:8b", "nodeId": null }, "lastPresetId": null, "updatedAt": "…" }
```

One document per user. `PUT` is presence-based: an absent field is kept, an explicit `null` clears
it, a value replaces it (gRPC: an unset field is kept; an empty `ModelTarget` or empty string
clears). The server updates `lastTarget` itself whenever a turn or a conversation PATCH carries a
target; the client `PUT`s when the picker changes before a conversation exists. A
new chat starts on `lastTarget` if the catalogue still has that model; each conversation remembers
its own `target`.

## 12. Mongo schemas

Auto index creation is off in this API: create indexes with `MongoTemplate.indexOps` in an
initializer, like `UsernameIndexInitializer`. No auditing — set timestamps by hand.

**`ai_conversations`**

| Field | Type | |
|---|---|---|
| `_id` | ObjectId | |
| `ownerUsername` | string | |
| `title`, `titleSource` | string | |
| `pinned` | bool | |
| `target` | `{ model, nodeId }` | nullable |
| `presetId`, `systemPrompt` | string | nullable |
| `summary` | `{ text, coversThroughSeq, tokenEstimate, model, nodeId, partial, createdAt }` | nullable |
| `nextSeq` | int | next message sequence number |
| `activeLeafId` | string | always the last message in v2; the hook for branching later |
| `messageCount` | int | |
| `schemaVersion` | int | `1` |
| `createdAt`, `updatedAt` | Instant | |

Index: `{ ownerUsername: 1, pinned: -1, updatedAt: -1 }`.

**`ai_messages`**

| Field | Type | |
|---|---|---|
| `_id` | ObjectId | |
| `conversationId`, `ownerUsername` | string | owner is denormalised for owner-scoped search |
| `seq` | int | order within the conversation |
| `parentId` | string | nullable |
| `role` | string | `user`, `assistant`; `system`, `tool` reserved |
| `content`, `thinking` | string | |
| `attachments` | `[{ id, kind, mimeType, sizeBytes, name }]` | |
| `toolCalls` | `[{ id, name, arguments }]` | reserved, empty |
| `toolCallId` | string | reserved, null |
| `status` | string | `complete`, `streaming`, `cancelled`, `error` |
| `error` | `{ code, message }` | nullable |
| `generation` | object | the `generation` block of section 6 |
| `tokenEstimate` | int | |
| `schemaVersion` | int | `1` |
| `createdAt`, `editedAt`, `completedAt` | Instant | |

Indexes: `{ conversationId: 1, seq: 1 }` unique; `{ ownerUsername: 1 }`.

**`ai_attachments`** — `_id`, `ownerUsername`, `conversationId` (null until attached), `messageId`
(null until attached), `kind`, `mimeType`, `name`, `sizeBytes`, `data` (Binary), `createdAt`,
`expiresAt` (set on upload, **unset when attached**). Indexes: TTL on `expiresAt`
(expireAfter 0); `{ conversationId: 1 }`.

**`ai_presets`** — the fields of section 9 except `editable`. Indexes: `{ ownerUsername: 1 }`,
`{ visibility: 1 }`.

**`ai_user_prefs`** — `_id` = username, `lastTarget`, `lastPresetId`, `updatedAt`.

**`ai_nodes`** (existing) gains `vramTotalMb`, `vramUsedMb`, `vramReportedAt`. Model metadata is
**not** stored in Mongo; it lives in the in-memory catalogue cache.

Adding tools or new attachment kinds later needs no migration: `role`, `attachments[].kind`,
`toolCalls`, `toolCallId` and `schemaVersion` are already there.

## 13. gRPC

New file `src/main/proto/fitznet/api/v1/ai_chat.proto`, package `fitznet.api.v1`, same options as
`node.proto`. `AiChatGrpcService` (`@GrpcService`) delegates every RPC to the **same controller
bean** as the REST route; the streaming controller methods get a plain-Java overload taking an
event sink, like `NodeController.chatStream(id, request, ChatEventSink)`.

```proto
service AiChatService {
  rpc ListModels(ListModelsRequest) returns (ModelCatalog);
  rpc WarmUp(WarmUpRequest) returns (WarmUpResponse);
  rpc GetPreferences(GetPreferencesRequest) returns (ChatPreferences);
  rpc UpdatePreferences(UpdatePreferencesRequest) returns (ChatPreferences);

  rpc ListConversations(ListConversationsRequest) returns (ListConversationsResponse);
  rpc CreateConversation(CreateConversationRequest) returns (Conversation);
  rpc GetConversation(GetConversationRequest) returns (ConversationDetail);
  rpc UpdateConversation(UpdateConversationRequest) returns (Conversation);
  rpc DeleteConversation(DeleteConversationRequest) returns (DeleteResponse);
  rpc GenerateTitle(GenerateTitleRequest) returns (Conversation);
  rpc GetContextUsage(GetContextUsageRequest) returns (ContextUsage);
  rpc SummarizeConversation(SummarizeConversationRequest) returns (SummarizeConversationResponse);

  rpc SendMessage(SendMessageRequest) returns (stream TurnEvent);
  rpc RegenerateMessage(RegenerateMessageRequest) returns (stream TurnEvent);
  rpc EditMessage(EditMessageRequest) returns (stream TurnEvent);

  rpc UploadAttachment(UploadAttachmentRequest) returns (Attachment);
  rpc GetAttachment(GetAttachmentRequest) returns (AttachmentContent);

  rpc ListPresets(ListPresetsRequest) returns (ListPresetsResponse);
  rpc CreatePreset(CreatePresetRequest) returns (Preset);
  rpc UpdatePreset(UpdatePresetRequest) returns (Preset);
  rpc DeletePreset(DeletePresetRequest) returns (DeleteResponse);
}

message TurnEvent {
  reserved 7, 8;              // tool_call, tool_result
  oneof event {
    TurnMeta meta = 1;
    TurnStatus status = 2;
    TurnDelta thinking = 3;
    TurnDelta token = 4;
    TurnDone done = 5;
    TurnError error = 6;
  }
}
```

Message rules: every proto message mirrors its JSON shape field for field in `snake_case`; nullable
JSON fields are `optional`; lists are `repeated`; instants are `Timestamp`; path parameters become
request fields (`conversation_id`, `message_id`, `preset_id`, `attachment_id`); enumerated strings
(`status`, `phase`, `code`, `visibility`, `role`) stay **strings** so new values need no proto
change. In `UpdateConversationRequest`, `target` and `settings` are message fields (presence =
replace whole). Never renumber fields.

`node.proto`: `HeartbeatRequest` gains `optional int32 vram_total_mb = 6` and
`optional int32 vram_used_mb = 7`. Nothing else in it changes.

## 14. Legacy endpoints

`POST /node/{id}/chat`, `POST /node/{id}/chat/stream`, `NodeService/Chat` and
`NodeService/ChatStream` stay, stateless, with the **same wire format** (`meta`, `token`, `done`,
`error`; reasoning chunks still become keep-alive comments). They gain `keep_alive` and count
toward `activeGenerations`. They are deprecated: the website stops calling them.

## 15. Configuration

```properties
ollama.keep-alive=${OLLAMA_KEEP_ALIVE:30m}
ai.node.stale-after=${AI_NODE_STALE_AFTER:5m}
ai.catalog.models-ttl=${AI_CATALOG_MODELS_TTL:60s}
ai.catalog.loaded-ttl=${AI_CATALOG_LOADED_TTL:5s}
ai.catalog.connect-timeout=${AI_CATALOG_CONNECT_TIMEOUT:2s}
ai.catalog.read-timeout=${AI_CATALOG_READ_TIMEOUT:4s}
ai.catalog.force-refresh-interval=${AI_CATALOG_FORCE_REFRESH_INTERVAL:2s}
ai.chat.cancel-poll-interval=${AI_CHAT_CANCEL_POLL_INTERVAL:1s}
ai.chat.max-message-chars=${AI_CHAT_MAX_MESSAGE_CHARS:32000}
ai.chat.max-attachments-per-message=${AI_CHAT_MAX_ATTACHMENTS:4}
ai.chat.max-attachment-bytes=${AI_CHAT_MAX_ATTACHMENT_BYTES:3145728}
ai.chat.attachment-orphan-ttl=${AI_CHAT_ATTACHMENT_ORPHAN_TTL:24h}
```

Existing `ollama.connect-timeout`, `ollama.read-timeout`, `ollama.max-stream-duration`,
`ollama.max-num-ctx` and `ollama.model-info-ttl` keep their meaning.

## 16. Client behaviour the server relies on

- One picker replaces the node and model selects: an **Auto** group (one row per model in
  `models[]`) and one group per node. Rows show name, parameter size, quantization, context length
  and a loaded badge; node headers show status and VRAM; OFFLINE nodes are greyed out and not
  selectable. Opens on click or Ctrl/Cmd+K, with search.
- Selecting an entry: warm-up call, context preflight (if a conversation exists), then PATCH the
  conversation target (or `PUT /ai/preferences` when there is no conversation yet).
- A conversation is created lazily on the first send, then `POST …/messages`.
- Stop = abort the `fetch`. No separate stop endpoint.
- After the first `done` of a conversation, call `POST …/title` once.
- When `context.trimmedCount > 0` (preflight or `meta`), show the warning with a
  "Summarise older turns" action.
- When the selected node is OFFLINE in the catalogue, or a turn ends with an `error` carrying
  `alternatives`, offer each alternative and Auto as one-click actions (regenerate with `target`).
- Every assistant message shows a tag built from `generation` (model, node, "auto", preset) and its
  stats.
- The mock "Preview" mode is retired; `aiChatService.sendMessage` and the legacy
  `streamChatWithNode` are removed from the website.

## 17. Deferred

Tools/MCP, RAG, web search, answer versions (branching), a thinking on/off toggle, non-image
attachments, shared conversations.
