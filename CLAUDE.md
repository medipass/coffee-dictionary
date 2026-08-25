# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
pnpm run start   # run locally with nodemon (hot reload)
pnpm run build   # compile TypeScript to dist/
```

There are no tests configured (`test` script exits 1).

## Architecture

The Express app is defined once in `src/server.ts` and shared between two deployment targets:

- **`src/index.ts`** — local / Docker entrypoint; starts a plain HTTP server on `$PORT` (default 3000)
- **`src/lambda.ts`** — AWS Lambda entrypoint; wraps the same app via `aws-serverless-express`

`src/keywords.json` is the data store — imported directly by `src/server.ts` at startup. **`POST /keywords` only mutates the in-memory array; it does not write back to the file.** Added keywords are lost on restart (this is intentional per the `// Danger, Will Robinson!` comment).

CORS is disabled by default and opt-in via the `CORS_HOST` environment variable.

## Deployment

Pushing to `main` or a semver tag (`v*.*.*`) triggers the GitHub Actions workflow (`.github/workflows/docker-publish.yml`), which builds and pushes a Docker image to GitHub Container Registry (`ghcr.io`). PRs only build — they don't push. The Docker image runs the compiled output: `node dist/index.js`.
