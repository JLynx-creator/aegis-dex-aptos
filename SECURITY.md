# Security policy

## Status
Aegis is **unaudited**. Do not deploy it with real user funds before an independent audit. Known limitations
and assumptions are listed in [docs/SECURITY.md](docs/SECURITY.md).

## Reporting a vulnerability
Please do **not** open a public issue. Send details privately to: `security@aegis-dex.dev`
(set this before publishing the repository). Include a description, impact, and reproduction steps or a failing test.
We aim to acknowledge reports within 3 business days.

## Scope
`sources/amm.move`, the SDK math (`sdk/src/math.ts`) and the web app's transaction construction.
