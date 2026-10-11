# npm (React / Vite)

Applies to `fitz-net-website`.

- **Baseline/verify:** `npm ci`, `npm run lint`, `npm test -- --run`, `npm run build`.
- **Scan:** `npm audit --json` (summarize by severity). Cross-check with `osv-scanner --lockfile package-lock.json` if available.
- **Outdated:** `npm outdated`.
- **Upgrade:** `npm audit fix` (non-forced) first, then `npm update` for in-range bumps; for out-of-range, `npm install pkg@version`. Never `--force`.
- **Verify start:** `npm run build` is the compile gate; optionally `npm run preview` briefly.
- **Pitfalls:** React, React Router, Vite and Vitest majors move together; ask before major bumps. Dev-only vulnerabilities should be reported but are lower priority.
