# Fitz-Net Agent Instructions

## Project Overview

Fitz-Net is a full-stack platform consisting of four independent sibling repositories. This repo (`Fitz-Net`) is the orchestration hub — it holds GitHub Actions workflows and shared agent documentation but contains no application code.

| Repo | Path | Role | Stack |
|---|---|---|---|
| **Fitz-Net** | `../Fitz-Net` | Orchestration hub, GitHub Actions, agentic sandbox | Markdown, YAML |
| **fitz-net-api** | `../fitz-net-api` | REST API backend | Java 21, Spring Boot 3.4, Gradle, MongoDB |
| **fitz-net-website** | `../fitz-net-website` | React SPA frontend | React 19, Vite, React Router v7 |
| **GamerBell** | `../GamerBell` | WebSocket relay + OTA firmware server for ESP32 bells | Java 21, Spring Boot 3.4, Gradle |

Each repo has its own `.github/agents.md` with deep per-repo conventions. The sections below cover cross-repo feature development.

---

## Architecture & Conventions

### Backend (`fitz-net-api`)

| Layer | Location | Pattern |
|---|---|---|
| Controllers | `controller/` | REST endpoints, request validation, maps DTOs ↔ service calls |
| Services | `service/` | Business logic, password hashing, delegates to repositories |
| Repositories | `repository/` | Spring Data MongoDB + custom `MongoTemplate` queries |
| DTOs | `dto/requests/`, `dto/responses/` | Immutable request DTOs (`@Valid`), response DTOs with Lombok `@Data` |
| Model | `model/` | MongoDB `@Document` entities with Lombok `@Builder` |
| Config | `config/` | Spring Security (stateless JWT), CORS, BCrypt |
| Util | `util/` | JWT generation/validation (`JwtUtil`) |

**Key conventions:**
- Endpoints are prefixed with `/user/` (e.g., `/user/create`, `/user/login`)
- Authentication uses JWT Bearer tokens — `JwtAuthenticationFilter` extracts the username from the token into `SecurityContextHolder`
- Authenticated endpoints can get the current user via `SecurityContextHolder.getContext().getAuthentication().getName()`
- Public endpoints: `/user/create`, `/user/login`, `/actuator/health`, `/actuator/info`, `/encrypt`, `/decrypt`
- All other endpoints require a valid JWT token
- Passwords are hashed with BCrypt via `PasswordEncoder`
- Tests use Mockito (`@Mock`, `@InjectMocks`) for unit tests and Flapdoodle embedded MongoDB for integration tests
- Test properties are in `src/test/resources/application.properties`

**Build & Test:**
```bash
cd ../fitz-net-api
./gradlew test                                    # Run all tests
./gradlew test --tests "*.UserControllerTest"     # Run specific test class
```

### Frontend (`fitz-net-website`)

| Layer | Location | Pattern |
|---|---|---|
| Pages/Components | `src/components/` | React functional components with hooks |
| Context | `src/contexts/` | `AuthContext` provides `user`, `token`, `login`, `logout`, `updateProfile`, `isAuthenticated` |
| Services | `src/services/` | `api.js` (real API calls), `mockApi.js` (offline/dev mock) |
| CSS | `src/css/` | Component-scoped CSS files (one per component) |
| Constants | `src/constants.js` | API URLs, config arrays |
| Routing | `src/App.jsx` | React Router v7 `<Routes>` |

**Key conventions:**
- API calls go through `src/services/api.js` which wraps `fetch()` and returns `{ success, message, ...data }`
- Mock API toggled via `VITE_USE_MOCK_API=true` environment variable
- `AuthContext` manages JWT token in `localStorage` (`authToken`, `authUser` keys)
- All authenticated API calls include `Authorization: Bearer <token>` header
- Tests use Vitest + `@testing-library/react` + `@testing-library/user-event`
- Each component `Foo.jsx` has a co-located `Foo.test.jsx`
- Mocking pattern: `vi.mock('../contexts/AuthContext', ...)` to control auth state in tests

**Build & Test:**
```bash
cd ../fitz-net-website
npm install                      # Install dependencies (first time)
npx vitest run                   # Run all tests once
npx vitest run --reporter=verbose  # Verbose output
npm run dev                      # Start dev server
```

### GamerBell (`GamerBell`)

Spring Boot WebSocket relay that bridges ESP32 button devices with the Fitz-Net web UI and handles OTA firmware updates.

| Layer | Location | Pattern |
|---|---|---|
| Handler | `handler/` | `ButtonWebSocketHandler` — routes events, broadcasts to all sessions |
| Services | `service/` | `ButtonService` (session pool + broadcast), `FirmwareService` (GitHub OTA) |
| Controller | `controller/` | `GET /count`, `GET /api/firmware/latest` |
| DTOs | `dto/` | `ButtonEventDto` (WS payload), `BellCountDto`, `GitHubReleaseDto` |
| Config | `config/` | `WebSocketConfig`, `CorsConfig`, `LoggingFilter` |

**Key conventions:**
- WebSocket endpoint: `/ws` — no auth required, accepts ESP32 and browser clients
- `ButtonEventDto` is the shared schema between GamerBell and `fitz-net-website/src/components/WebSocketButton.jsx` — update both sides in sync
- GamerBell is intentionally stateless — no database; session state is in-memory (`CopyOnWriteArrayList`)
- Firmware cached for 60 seconds; downloads from `mattlol85/Esp32FitznetBell` GitHub releases
- All classes use `@Slf4j` with MDC context for structured Loki-compatible logging

**Build & Test:**
```bash
cd ../GamerBell
./gradlew test
./gradlew bootRun --args='--spring.profiles.active=dev'
```

---

## Feature Development Workflow

### 1. Branch Strategy
- Create matching feature branches in **all affected repos**:
  ```bash
  cd ../fitz-net-api && git checkout -b feature/FEATURENAME
  cd ../fitz-net-website && git checkout -b feature/FEATURENAME
  cd ../GamerBell && git checkout -b feature/FEATURENAME  # if WebSocket changes needed
  ```

### 2. API Contract First
- Define the request/response DTOs in the backend **before** implementing frontend calls
- Ensure HTTP method (GET/POST/PUT/PATCH/DELETE) matches between frontend `api.js` and backend controller annotations
- Backend response shape must match what the frontend expects: `{ success, message, ...fields }`

### 3. Backend Implementation Order (`fitz-net-api`)
1. **DTO** — Create request DTO in `dto/requests/` and response DTO in `dto/responses/`
2. **Service** — Add/modify methods in the service layer
3. **Repository** — Add custom queries if needed (extend `UserRepositoryCustom`)
4. **Controller** — Wire up the endpoint, validate with `@Valid`, extract JWT user from `SecurityContextHolder` for authenticated operations
5. **Security** — Update `SecurityConfig` if the new endpoint needs different auth rules
6. **Tests** — Unit test the controller (mock service) and service (mock repository)

### 4. Frontend Implementation Order (`fitz-net-website`)
1. **API service** — Add the call in `src/services/api.js` with matching method/URL/headers
2. **Mock API** — Add mock implementation in `src/services/mockApi.js`
3. **Context** — If auth-related, add the method to `AuthContext` and expose via `useAuth()`
4. **Component** — Build/modify the UI component
5. **CSS** — Add styles in `src/css/`
6. **Routing** — Add route in `App.jsx` if it's a new page
7. **Tests** — Write tests in co-located `*.test.jsx` file, mock `AuthContext` for auth state

### 5. GamerBell / WebSocket Changes
- Update `ButtonEventDto` and corresponding frontend `WebSocketButton.jsx` in the same PR pair
- Never add a database dependency — GamerBell is intentionally stateless
- New CORS origins: add to `cors.allowed-origins` in both `application.properties` and `application-dev.properties`

### 6. Testing Requirements
- **Backend:** All controller endpoints must have Mockito unit tests. Service methods must have unit tests. Run `./gradlew test` and confirm all pass before marking complete.
- **Frontend:** All components must have co-located test files. Run `npx vitest run` and confirm all pass before marking complete.
- **Integration readiness:** Verify the API contract (URL, HTTP method, request body shape, response body shape, headers) is aligned between `api.js` and the backend controller.

### 7. Common Pitfalls
- **HTTP method mismatch:** Frontend `fetch()` method must match backend annotation (`@GetMapping`, `@PostMapping`, `@PutMapping`, `@PatchMapping`, `@DeleteMapping`)
- **DTO field name mismatch:** Java field names (camelCase) must match JSON property names the frontend sends/expects
- **Void endpoints:** If the backend returns `void`, the frontend `response.json()` will fail. Always return a response DTO.
- **CORS:** New origins must be added to both `SecurityConfig.corsConfigurationSource()` and `management.endpoints.web.cors.allowed-origins` in `application.properties`
- **Security:** New public endpoints must be added to the `permitAll()` list in `SecurityConfig`

---

## Commit Convention

All repos use conventional commits with a scope:

```
feat(subject): description
fix(subject): description
chore(subject): description
```

- `feat` — new user-facing behavior
- `fix` — bug fix
- `chore` — maintenance, tooling, dependency updates, documentation

---

## Reference: Existing fitz-net-api Endpoints

| Method | Path | Auth | Request Body | Response |
|---|---|---|---|---|
| POST | `/user/create` | Public | `UserDTO { username, email, password }` | `User` |
| POST | `/user/login` | Public | `LoginRequestDto { username, password }` | `LoginResponseDto { success, message, username, email, token }` |
| POST | `/user/read` | JWT | `String username` | `User` |
| GET | `/user/readAll` | JWT | — | `List<User>` |
| PUT | `/user/update` | JWT | `UpdateProfileRequestDto { username, email, password }` | `UpdateProfileResponseDto { success, message, username, email }` |
| PATCH | `/user/update` | JWT | `UpdateUserRequestDto { username, updatedUsername, email, updatedEmail, updatedPassword }` | `void` |
| DELETE | `/user/delete` | JWT | `DeleteUserRequestDto { username }` | `void` |

## Reference: GamerBell Endpoints

| Type | Path | Auth | Description |
|---|---|---|---|
| WebSocket | `/ws` | None | ESP32 + browser connections; broadcasts `ButtonEventDto` |
| GET | `/count` | None | Returns `{ "count": N }` active sessions |
| GET | `/api/firmware/latest` | None | OTA firmware; 200 = update available, 304 = up to date |
