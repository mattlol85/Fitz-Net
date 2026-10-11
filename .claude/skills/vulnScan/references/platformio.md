# PlatformIO (ESP32 C++)

Applies to `Esp32FitznetBell`.

- **Baseline/verify:** `pio run` (compile). `pio test` if tests are runnable without hardware. Never flash or upload.
- **Scan:** there is no native CVE audit. List deps with `pio pkg list`, then run `osv-scanner` if installed, and check each library's GitHub advisories / release notes for the pinned version. State clearly in the report that coverage is best-effort.
- **Outdated:** `pio pkg outdated`.
- **Upgrade:** edit pinned versions in `platformio.ini` `lib_deps` and `platform =`. Platform (espressif32) and Arduino core bumps can change behavior: ask before applying.
- **Pitfalls:** compile success does not prove runtime behavior; recommend an on-device smoke test (WebSocket connect, press/release, OTA check) to the user.
