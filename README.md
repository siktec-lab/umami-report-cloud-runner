# umami-report-cloud-runner

A small, self-contained Docker wrapper around
[**Thunderbottom/umami-alerts**](https://github.com/Thunderbottom/umami-alerts) — a Rust CLI that
generates daily/weekly [Umami Analytics](https://umami.is) reports and emails them.

The upstream tool is great but has three rough edges for cloud deployment:

| Upstream | This runner |
| --- | --- |
| Config is a **TOML file only** (no env vars) | Config rendered from **environment variables** at start |
| Sends over **SMTP** (no Resend integration) | Ships pointed at **Resend's SMTP gateway** by default |
| **Runs once and exits** (needs an external cron) | **Self-schedules** with a built-in cron loop (supercronic) |

No fork of the Rust code is needed — the container builds the upstream binary as-is, renders a
`config.toml` from your env vars on startup, and schedules it.

## How it works

1. **Build** (`Dockerfile`, multi-stage): clones upstream pinned to a specific commit and compiles a
   static musl binary (rustls everywhere upstream → no OpenSSL), then assembles a tiny Alpine runtime
   with `tini` + `supercronic`, running as a non-root user.
2. **Start** (`docker/entrypoint.sh`): `render-config.sh` turns your env vars into `/app/config.toml`
   (failing fast with a clear message if anything required is missing).
3. **Schedule**: by default the container stays up and runs the report on `CRON_SCHEDULE` via
   supercronic, logging each run to stdout. Set `RUN_MODE=once` to run a single report and exit.

## Quick start

```bash
cp .env.example .env
# edit .env: RESEND_API_KEY, EMAIL_FROM, UMAMI_* , REPORT_RECIPIENTS, CRON_SCHEDULE
docker compose up -d --build
docker compose logs -f
```

That's it — the container will email the report on your schedule.

### Test without sending

```bash
docker compose run --rm \
  -e RUN_MODE=once -e DRY_RUN=true -e DEBUG=true \
  umami-report-runner
```

`DRY_RUN=true` generates the report but sends no email; `DEBUG=true` prints the rendered config
(SMTP password masked) and verbose logs. Drop `DRY_RUN` to send a real test email.

## Configuration (environment variables)

### Resend / SMTP

| Var | Default | Notes |
| --- | --- | --- |
| `RESEND_API_KEY` | — | **Required** (or `SMTP_PASSWORD`). Used as the SMTP password. |
| `EMAIL_FROM` | — | **Required.** From header, e.g. `Umami Reports <reports@you.com>`. |
| `SMTP_HOST` | `smtp.resend.com` | Override for a non-Resend provider. |
| `SMTP_PORT` | `587` | STARTTLS port. |
| `SMTP_USERNAME` | `resend` | Resend's fixed SMTP username. |
| `SMTP_PASSWORD` | — | Alternative to `RESEND_API_KEY`. |
| `SMTP_TLS` | `true` | STARTTLS (true for 587). |
| `SMTP_SKIP_VERIFY` | `false` | Accept self-signed certs. |
| `SMTP_TIMEOUT` | `30` | Seconds. |

### Umami site (single-site form)

| Var | Default | Notes |
| --- | --- | --- |
| `UMAMI_BASE_URL` | — | **Required.** Your Umami instance URL. |
| `UMAMI_WEBSITE_ID` | — | **Required.** Website UUID (from Umami site settings). |
| `UMAMI_USERNAME` | — | **Required.** Umami login (no API keys in Umami). |
| `UMAMI_PASSWORD` | — | **Required.** |
| `REPORT_RECIPIENTS` | — | **Required.** Comma-separated email list. |
| `SITE_NAME` | site key | Display name in the report. |
| `TIMEZONE` | `UTC` | IANA tz; affects the report's day boundaries. |

### Report / scheduling

| Var | Default | Notes |
| --- | --- | --- |
| `REPORT_TYPE` | `daily` | `daily` or `weekly`. Match it to your cron cadence. |
| `CRON_SCHEDULE` | `0 8 * * *` | supercronic crontab expression. |
| `RUN_MODE` | `cron` | `cron` (stay up + schedule) or `once` (run + exit). |
| `RUN_ON_START` | `false` | Fire one report immediately on container start. |
| `DRY_RUN` | `false` | Generate but don't send. |
| `DEBUG` | `false` | App debug logging + print rendered config. |
| `MAX_CONCURRENT_JOBS` | `4` | Parallel sites processed. |
| `RUST_LOG` | `info` | `trace`/`debug`/`info`/`warn`/`error`. |

### Multiple sites

Set numbered `SITE_N_*` blocks (`SITE_1_BASE_URL`, `SITE_1_WEBSITE_ID`, `SITE_1_USERNAME`,
`SITE_1_PASSWORD`, `SITE_1_RECIPIENTS`, optional `SITE_1_NAME` / `SITE_1_TIMEZONE`). When
`SITE_1_BASE_URL` is present the numbered blocks are used **instead of** the single-site `UMAMI_*`
block. Increment `N` for each additional site.

## Getting credentials

- **Resend SMTP:** create an API key in the Resend dashboard → use it as `RESEND_API_KEY`. Verify
  your sending domain so `EMAIL_FROM` can use it (until then, `onboarding@resend.dev` works for tests).
- **Umami:** there are no API keys — supply a username/password with access to the site. The website
  UUID is shown under the website's settings.

## Scheduling notes

`CRON_SCHEDULE` decides *when* a report runs; `REPORT_TYPE` decides *what window* it covers. Keep them
aligned — e.g. `REPORT_TYPE=weekly` with a once-a-week cron like `0 8 * * 1` (Mondays 08:00). Cron
times follow the container's `TIMEZONE`.

## Pinning upstream

The upstream commit is pinned via the `UMAMI_ALERTS_REF` build arg (default in `Dockerfile` and
`docker-compose.yml`). Bump it deliberately to pick up upstream changes:

```bash
docker build --build-arg UMAMI_ALERTS_REF=<sha> -t umami-report-cloud-runner .
```

> If upstream ever renames its config struct fields, `docker/render-config.sh` is the single place to
> update — that's the only spot coupled to the upstream TOML schema.

## License

MIT — see [LICENSE](LICENSE). Wraps and builds
[Thunderbottom/umami-alerts](https://github.com/Thunderbottom/umami-alerts) (also MIT); all analytics
and email logic is theirs.
