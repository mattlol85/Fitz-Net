# End-to-end request tracing

One **correlation id** follows a request from the browser through every backend and into every log line.

| Hop | Where the id comes from / goes | Code |
|---|---|---|
| Browser -> HTTP | `fetch` wrapper adds `X-Correlation-ID: web-xxxxxxxx` to calls to our own origins | `fitz-net-website/src/utils/tracing.js` |
| Browser -> GamerBell WS | `?correlationId=` query param (browsers can't set WS headers) | `WebSocketButton.jsx` |
| Browser -> API STOMP | `X-Correlation-ID` CONNECT header, kept in the session for later frames | `liveBoardService.js`, `LiveBoardChannelInterceptor` |
| HTTP server | reuses inbound `X-Correlation-ID` / `X-Request-ID` or generates one, echoes both on the response | `RequestTracingFilter` (api, Fitz-Bot), `LoggingFilter` (GamerBell) |
| gRPC server | same, via `x-correlation-id` / `x-request-id` metadata; echoed in response headers | `GrpcTracingInterceptor` (api, GamerBell, Fitz-Bot) |
| GamerBell WS | handshake header or `correlationId` query param, else the session id | `ButtonWebSocketHandler` |

- MDC keys: `correlationId`, `requestId`, `transport` (`http`, `grpc`, `stomp`, `websocket`).
- Logs: GamerBell's JSON logs include the keys; api and Fitz-Bot print `[correlationId]` in the console/file pattern.
- Inbound ids must match `[A-Za-z0-9._:-]{1,64}`; anything else is replaced so a caller cannot forge log lines.
- CORS exposes `X-Request-ID` / `X-Correlation-ID` so the browser can read them.
- The ESP32 bell sends no id; GamerBell falls back to the WebSocket session id for it.

To follow a request: grab the `X-Correlation-ID` response header in the browser devtools and grep it in each service's logs.
When adding an endpoint or transport, keep the id in the MDC for the whole call and add a test.
