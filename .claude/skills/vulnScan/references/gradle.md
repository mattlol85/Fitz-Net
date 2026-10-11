# Gradle (Java / Spring Boot)

Applies to `fitz-net-api`, `GamerBell`, `Fitz-Bot`. Always use the wrapper (`./gradlew`).

- **Baseline/verify:** `./gradlew build` (compiles + tests). Optional start check: `./gradlew bootRun` briefly, then stop.
- **Scan:** OWASP Dependency-Check. If the plugin is not configured, run it without editing the build file permanently, e.g. via an init script in the scratchpad applying `org.owasp.dependency-check` and `./gradlew dependencyCheckAnalyze`. An NVD API key (`NVD_API_KEY`) speeds this up; without it, expect slow first runs. Cross-check with `osv-scanner --lockfile` if available.
- **Outdated:** `./gradlew dependencies --configuration runtimeClasspath` to inspect; check Spring Boot plugin version first, since most transitive CVEs are fixed by a Boot patch bump (e.g. 3.4.x -> latest 3.4.y).
- **Upgrade:** edit versions in `build.gradle(.kts)` / `gradle/libs.versions.toml`. Prefer bumping the Spring Boot plugin/BOM over pinning transitive libs; if pinning, add a comment with the CVE ID.
- **Pitfalls:** Boot minor bumps (3.4 -> 3.5) count as major-ish: ask first. Gradle wrapper itself can be updated with `./gradlew wrapper --gradle-version <v>`.
