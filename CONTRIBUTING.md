# Contributing

1. Install: Aptos CLI 9.6.x (pin the same version as CI), Node 22, git.
2. `make test` must pass before opening a pull request (Move tests, SDK tests, app tests and builds).
3. Contract changes (`sources/amm.move`) require: a new or updated test for every changed behaviour, an update to
   `docs/ARCHITECTURE.md` / `docs/SECURITY.md` if assumptions change, and a matching change in `sdk/src/math.ts`
   (the SDK mirrors the on-chain math; its tests share vectors with the Move tests).
4. Never relax a check or an abort condition without a written justification in the pull request.
5. Keep dependencies pinned (`Move.toml` framework `rev`, committed lockfiles).
