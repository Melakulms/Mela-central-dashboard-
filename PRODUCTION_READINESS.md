# MELA Central Admin — Production Readiness

This document records the remaining non-live verification work. It deliberately does not claim live deployment, browser QA, or end-to-end production payment verification.

## Verified architecture
- Separate Vite/React admin application.
- Fail-closed admin authorization.
- MFA/AAL2 enforcement for privileged access.
- Privileged operations routed through `mela-admin-api`.
- Private admin schema and audit trail.
- GitHub Actions build workflow runs `npm install` and `npm run build` on `main`.
- Production environment variables required by the application are documented.

## Release gates
- [ ] Live Netlify deployment reachable.
- [ ] Latest commit confirmed live.
- [ ] Browser QA on mobile/tablet/desktop.
- [ ] Full RBAC negative-test matrix with separate role identities.
- [ ] Complete live registration-to-admin lifecycle test.

## Security rule
Never mark a release gate green based solely on source-code presence. Live gates require live evidence.
