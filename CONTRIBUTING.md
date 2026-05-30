# Contributing

Thanks for your interest in improving **umami-report-cloud-runner**. This document explains how to
propose changes.

## Ground rules

- The `main` branch is protected. **All changes land through pull requests** — direct pushes to `main`
  are rejected.
- Every PR must pass CI (shellcheck, config rendering, and the Docker build smoke test) before it can
  be merged.
- Keep PRs focused. One logical change per pull request makes review faster.

## Development setup

You only need Docker (with Compose v2). The Rust binary is compiled inside the image, so no local Rust
toolchain is required.

```bash
git clone https://github.com/siktec-lab/umami-report-cloud-runner.git
cd umami-report-cloud-runner
cp .env.example .env   # fill in for local testing; .env is gitignored
```

## Workflow

1. **Fork** the repository (external contributors) or create a branch (maintainers).
2. Create a topic branch off `main`:
   ```bash
   git checkout -b feat/short-description
   ```
3. Make your change. Match the existing style; keep shell scripts POSIX `sh` compatible.
4. **Run the checks locally** (see below).
5. Commit using [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`,
   `docs:`, `ci:`, `chore:`, …).
6. Push and open a pull request against `main`. Fill in the PR template.

## Local checks

Run the same checks CI runs before opening a PR.

**Lint the shell scripts** (requires Docker):

```bash
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable \
  --shell=sh docker/entrypoint.sh docker/render-config.sh
```

**Render the config from env** (no containers, just `sh`):

```bash
CONFIG_PATH=/tmp/config.toml \
RESEND_API_KEY=re_test EMAIL_FROM=reports@example.com \
UMAMI_BASE_URL=https://analytics.example.com \
UMAMI_WEBSITE_ID=00000000-0000-0000-0000-000000000000 \
UMAMI_USERNAME=u UMAMI_PASSWORD=p REPORT_RECIPIENTS=you@example.com \
sh docker/render-config.sh && cat /tmp/config.toml
```

**Build and smoke-test the image:**

```bash
docker build -t umami-report-cloud-runner:dev .
docker run --rm --entrypoint /app/umami-alerts umami-report-cloud-runner:dev --help
```

See [README.md](README.md) for a full dry-run / live-send test.

## Coupling to upstream

This project builds [Thunderbottom/umami-alerts](https://github.com/Thunderbottom/umami-alerts)
unmodified and renders its TOML config from environment variables. The **only** file coupled to the
upstream config schema is [`docker/render-config.sh`](docker/render-config.sh). If you bump the pinned
upstream commit (`UMAMI_ALERTS_REF`) and a config field was renamed, update that script and the env
reference in the README together.

## Reporting bugs and requesting features

Use the issue templates. Include enough detail to reproduce: relevant env vars (redact secrets), the
command you ran, and the container logs (run with `DEBUG=true` for detail).
