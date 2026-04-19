# Fitz-Net Agent Instructions

## Project Overview

Fitz-Net is a full-stack web application consisting of two independent repositories within a single workspace:

- **`fitz-net-api/`** — Spring Boot 3.4 REST API (Java 21, Gradle, MongoDB, Spring Security + JWT)
- **`fitz-net-website/`** — React 19 SPA (Vite, React Router v7, Vitest + Testing Library)

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
- Endpoints are prefixed with `/user/` (e.g., `/user/create`, `/user/login`, `/user/update`)
- Authentication uses JWT Bearer tokens — `JwtAuthenticationFilter` extracts the username from the token into `SecurityContextHolder`
- Authenticated endpoints can get the current user via `SecurityContextHolder.getContext().getAuthentication().getName()`
- Public endpoints: `/user/create`, `/user/login`, `/actuator/health`, `/actuator/info`, `/encrypt`, `/decrypt`
- All other endpoints require a valid JWT token
- Passwords are hashed with BCrypt via `PasswordEncoder`
- Tests use Mockito (`@Mock`, `@InjectMocks`) for unit tests and Flapdoodle embedded MongoDB for integration tests
- Test properties are in `src/test/resources/application.properties`

**Build & Test:**
```bash
cd fitz-net-api
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
cd fitz-net-website
npm install                      # Install dependencies (first time)
npx vitest run                   # Run all tests once
npx vitest run --reporter=verbose  # Verbose output
npm run dev                      # Start dev server
```

---

## Feature Development Workflow

### 1. Branch Strategy
- Create matching feature branches in **both** repos:
  ```bash
  cd fitz-net-api && git checkout -b feature/FEATURENAME
  cd fitz-net-website && git checkout -b feature/FEATURENAME
  ```

### 2. API Contract First
- Define the request/response DTOs in the backend **before** implementing frontend calls
- Ensure HTTP method (GET/POST/PUT/PATCH/DELETE) matches between frontend `api.js` and backend controller annotations
- Backend response shape must match what the frontend expects: `{ success, message, ...fields }`

### 3. Backend Implementation Order
1. **DTO** — Create request DTO in `dto/requests/` and response DTO in `dto/responses/`
2. **Service** — Add/modify methods in the service layer
3. **Repository** — Add custom queries if needed (extend `UserRepositoryCustom`)
4. **Controller** — Wire up the endpoint, validate with `@Valid`, extract JWT user from `SecurityContextHolder` for authenticated operations
5. **Security** — Update `SecurityConfig` if the new endpoint needs different auth rules
6. **Tests** — Unit test the controller (mock service) and service (mock repository)

### 4. Frontend Implementation Order
1. **API service** — Add the call in `src/services/api.js` with matching method/URL/headers
2. **Mock API** — Add mock implementation in `src/services/mockApi.js`
3. **Context** — If auth-related, add the method to `AuthContext` and expose via `useAuth()`
4. **Component** — Build/modify the UI component
5. **CSS** — Add styles in `src/css/`
6. **Routing** — Add route in `App.jsx` if it's a new page
7. **Tests** — Write tests in co-located `*.test.jsx` file, mock `AuthContext` for auth state

### 5. Testing Requirements
- **Backend:** All controller endpoints must have Mockito unit tests. Service methods must have unit tests. Run `./gradlew test` and confirm all pass before marking complete.
- **Frontend:** All components must have co-located test files. Run `npx vitest run` and confirm all pass before marking complete.
- **Integration readiness:** Verify the API contract (URL, HTTP method, request body shape, response body shape, headers) is aligned between `api.js` and the backend controller.

### 6. Common Pitfalls
- **HTTP method mismatch:** Frontend `fetch()` method must match backend annotation (`@GetMapping`, `@PostMapping`, `@PutMapping`, `@PatchMapping`, `@DeleteMapping`)
- **DTO field name mismatch:** Java field names (camelCase) must match JSON property names the frontend sends/expects
- **Void endpoints:** If the backend returns `void`, the frontend `response.json()` will fail. Always return a response DTO.
- **CORS:** New origins must be added to both `SecurityConfig.corsConfigurationSource()` and `management.endpoints.web.cors.allowed-origins` in `application.properties`
- **Security:** New public endpoints must be added to the `permitAll()` list in `SecurityConfig`

---

## Reference: Existing API Endpoints

| Method | Path | Auth | Request Body | Response |
|---|---|---|---|---|
| POST | `/user/create` | Public | `UserDTO { username, email, password }` | `User` |
| POST | `/user/login` | Public | `LoginRequestDto { username, password }` | `LoginResponseDto { success, message, username, email, token }` |
| POST | `/user/read` | JWT | `String username` | `User` |
| GET | `/user/readAll` | JWT | — | `List<User>` |
| PUT | `/user/update` | JWT | `UpdateProfileRequestDto { username, email, password }` | `UpdateProfileResponseDto { success, message, username, email }` |
| PATCH | `/user/update` | JWT | `UpdateUserRequestDto { username, updatedUsername, email, updatedEmail, updatedPassword }` | `void` |
| DELETE | `/user/delete` | JWT | `DeleteUserRequestDto { username }` | `void` |

