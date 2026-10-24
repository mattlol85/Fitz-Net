# gRPC alongside REST

Every REST endpoint in the three Spring backends (`fitz-net-api`, `GamerBell`, `Fitz-Bot`) has an
equivalent gRPC RPC. The two are one implementation: each `@GrpcService` calls the same controller
bean the REST route uses, so validation, `@PreAuthorize`, metrics and logging are shared.

> **Standing rule:** a new or changed REST endpoint ships with its gRPC RPC in the same PR (and the
> reverse). See "Adding an endpoint" below. Not applicable to WebSocket/STOMP, the Thymeleaf pages,
> the `/joenet/**` reverse proxy or actuator endpoints.

## Where things live

| Repo | Proto | Services | Port |
|---|---|---|---|
| `fitz-net-api` | `src/main/proto/fitznet/api/v1/{user,permission,node,info}.proto` | `UserService`, `PermissionService`, `NodeService`, `InfoService` | `GRPC_PORT` (9090) |
| `GamerBell` | `src/main/proto/fitznet/gamerbell/v1/gamerbell.proto` | `GamerBellService` | `GRPC_PORT` (9090) |
| `Fitz-Bot` | `src/main/proto/fitznet/bot/v1/bot.proto` | `BotService`, `LogService` | `GRPC_PORT` (9090) |

The port is plaintext HTTP/2 on the Docker `fitznet` network only. `docker-compose.yml` `expose`s it
but Caddy does not route to it, so it is not reachable from the internet. Server reflection is on,
so `grpcurl -plaintext host:9090 list` works.

## REST → gRPC map

**fitz-net-api**

| REST | RPC |
|---|---|
| `GET /info` | `InfoService/GetInfo` |
| `POST /user/create` | `UserService/CreateUser` |
| `POST /user/login` | `UserService/Login` |
| `POST /user/read` | `UserService/ReadUser` |
| `GET /user/me` | `UserService/GetMe` |
| `GET /user/readAll` | `UserService/ListUsers` |
| `DELETE /user/delete` | `UserService/DeleteMe` |
| `PATCH /user/update` | `UserService/UpdateUser` |
| `PUT /user/update` | `UserService/UpdateProfile` |
| `POST /node/register` | `NodeService/RegisterNode` |
| `POST /node/heartbeat` | `NodeService/Heartbeat` |
| `GET /node/list` | `NodeService/ListNodes` |
| `POST /node/{id}/chat` | `NodeService/Chat` |
| `POST /node/{id}/chat/stream` (SSE) | `NodeService/ChatStream` (server stream of `ChatEvent`) |
| `DELETE /node/{id}` | `NodeService/DeleteNode` |
| `POST /node/enrollment-token` | `NodeService/CreateEnrollmentToken` |
| `GET/POST /admin/permissions`, `DELETE /admin/permissions/{p}` | `PermissionService/{ListPermissions,CreatePermission,DeletePermission}` |
| `GET /admin/users` | `PermissionService/ListUsers` |
| `GET/PUT /admin/users/{u}/permissions` | `PermissionService/{GetUserPermissions,SetUserPermissions}` |
| `POST/DELETE /admin/users/{u}/permissions/{p}` | `PermissionService/{GrantUserPermission,RevokeUserPermission}` |

**GamerBell**: `GET /count` → `GetCount`; `GET /api/firmware/latest` → `GetLatestFirmware` (server
stream: one `FirmwareInfo`, then the `.bin` in 64 KiB chunks; `up_to_date` replaces the 304);
`POST /api/devices/log` → `LogDevice`.

**Fitz-Bot**: `/bot/{startup,force-update-commands,shutdown,status}` and
`/bot/{register-guild-commands,reset-join-counts}/{guildId}` → `BotService/*`;
`/logs/api/{tail,search,level/{level}}` → `LogService/{TailLogs,SearchLogs,GetLogsByLevel}`.

## fitz-net-api auth and errors

Credentials go in call metadata instead of HTTP headers: `authorization: Bearer <jwt>` and
`x-admin-key`. `GrpcAuthInterceptor` reuses `JwtAuthenticationFilter.authenticate` and
`AdminApiKeyFilter.authenticate`, and its `PUBLIC_METHODS` set mirrors `SecurityConfig`'s
`permitAll()` list. `GrpcExceptionMapper` mirrors `GlobalExceptionHandler`:

| HTTP | gRPC code |
|---|---|
| 400 | `INVALID_ARGUMENT` |
| 401 | `UNAUTHENTICATED` |
| 403 | `PERMISSION_DENIED` |
| 404 | `NOT_FOUND` |
| 409 | `ALREADY_EXISTS` |
| 5xx | `INTERNAL` / `UNAVAILABLE` |

The exact REST status is also sent as the `x-http-status` trailer, and the same
`fitznet.api.failures` metric is recorded. GamerBell and Fitz-Bot have no auth, like their REST.

## Adding an endpoint (the rule)

1. Define the REST endpoint as usual and decide request/response shape first.
2. Add the RPC + messages to the repo's `.proto` (same package version, `optional` for nullable
   fields, `repeated` for lists, `Timestamp` for `Instant`). Never renumber or reuse field numbers.
3. Add a method to the repo's `*GrpcService` that maps proto → DTO, calls the **controller** method,
   and maps the result back. Do not duplicate business logic. Controller methods that are shaped
   around the servlet (`HttpServletResponse`, headers) get a plain-Java overload, like
   `NodeController.chatStream(id, request, ChatEventSink)`.
4. fitz-net-api only: if the REST route is public, add the RPC to `GrpcAuthInterceptor.PUBLIC_METHODS`.
5. Add a test next to the existing gRPC one (`GrpcIntegrationTest`, `GamerBellGrpcServiceTest`,
   `GrpcServicesTest`) covering success, auth/permission failure and a validation error.
6. Update the tables above.

## Local testing

```
grpcurl -plaintext localhost:9090 list
grpcurl -plaintext -d '{"username":"alice","password":"..."}' localhost:9090 fitznet.api.v1.UserService/Login
grpcurl -plaintext -H 'authorization: Bearer <jwt>' localhost:9090 fitznet.api.v1.UserService/GetMe
```

Tests set `spring.grpc.server.port=0` (random port) so contexts never collide on 9090.
