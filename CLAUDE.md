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

## Terraform (Lambda)

```bash
pnpm run build                       # compile TypeScript first — OpenTofu zips dist/ + node_modules/
rm -rf node_modules && pnpm install --prod   # drop devDependencies before packaging — see note below
cd terraform
tofu init
tofu apply                # outputs the API Gateway URL
pnpm install               # back at repo root: restore devDependencies for local dev
```

**A clean prod-only `node_modules` before every apply is required, not optional.** The Lambda zip is the whole `node_modules/`; with devDependencies included (`typescript` alone is ~65MB) it exceeds Lambda's direct-upload size limit and `UpdateFunctionCode` fails with `RequestEntityTooLargeException`. It has to be `rm -rf node_modules && pnpm install --prod`, not a plain `pnpm install --prod` over the existing install — pruning in place can leave dangling `node_modules/.bin` symlinks pointing at now-removed dev packages, which breaks `archive_file` (`error creating archive: ... lstat ... no such file or directory`). Re-run a plain `pnpm install` afterwards to get `nodemon`/`ts-node`/`typescript` back for local dev.

`pnpm-workspace.yaml` sets `nodeLinker: hoisted`. This isn't optional either: pnpm's default symlinked layout is incompatible with how OpenTofu's `archive_file` zips the directory (it copies symlinked files' content without preserving the sibling directory they resolve against), which silently breaks `aws-serverless-express`'s runtime dependency on `@vendia/serverless-express`.

The OpenTofu config (`terraform/`) packages the built app, creates a Lambda function (`dist/lambda.handler`, Node 22), and wires it to an API Gateway v2 HTTP API. `CORS_HOST` and `function_name` are overridable via variables. State lives in the `coffee-dictionary-tfstate-699799608914` S3 bucket (`terraform/main.tf` backend block), not locally — this is required for `.github/workflows/deploy.yml` (below) and local runs to share the same state.

### CI: plan on PR, apply on merge

- `.github/workflows/plan.yml` — every PR targeting `main` runs build → prune → `tofu plan`, posting the result as a PR comment (updated in place on new pushes). Uses `aws_iam_role.github_actions_plan`, a **read-only** role.
- `.github/workflows/deploy.yml` — every push to `main` (i.e. after merge) runs build → prune → `tofu apply -auto-approve`. Uses `aws_iam_role.github_actions`, the read/write role, and requires manual approval via the `production` GitHub Environment (repo Settings > Environments) since this repo is public. Runs are serialized (`concurrency: terraform-deploy`) so back-to-back merges don't race on the state lock.

Both roles are defined in `terraform/github_oidc.tf` and assumed via GitHub OIDC — no AWS keys stored in GitHub. The plan role is intentionally read-only rather than reusing the apply role: `pull_request` runs execute the workflow file *as committed in the PR*, so a PR that edited the workflow to call `apply` instead of `plan` still couldn't mutate anything — the IAM policy itself blocks it, not just the workflow's own logic.

## Docker

The `Dockerfile` builds and runs the compiled output (`node dist/index.js`) locally — there's no CI workflow publishing it anywhere.
