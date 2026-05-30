# umami-report-cloud-runner

[![CI](https://github.com/siktec-lab/umami-report-cloud-runner/actions/workflows/ci.yml/badge.svg)](https://github.com/siktec-lab/umami-report-cloud-runner/actions/workflows/ci.yml)

A containerized, environment-driven deployment of
[Thunderbottom/umami-alerts](https://github.com/Thunderbottom/umami-alerts) — a tool that generates
daily or weekly [Umami Analytics](https://umami.is) reports and emails them.

The upstream tool is configured through a TOML file, sends over generic SMTP, and runs once per
invocation (intended to be driven by an external cron). This project wraps it so that:

- All configuration is supplied through **environment variables** (no config file to mount or template).
- Email is sent through **[Resend](https://resend.com)** by default, via Resend's SMTP gateway.
- The container **schedules itself** with a built-in cron loop, or runs once and exits.

The upstream source is built unmodified; an entrypoint renders its TOML config from the environment
at container start.

## Contents

- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Configuration reference](#configuration-reference)
- [Obtaining credentials](#obtaining-credentials)
- [Testing](#testing)
- [Deployment](#deployment)
- [Scheduling and timezones](#scheduling-and-timezones)
- [Multiple sites](#multiple-sites)
- [Operations](#operations)
- [How it works](#how-it-works)
- [Upstream pinning](#upstream-pinning)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Requirements

- Docker 20.10+ with Compose v2 (`docker compose`).
- A reachable [Umami](https://umami.is) instance (v3+) and a login with access to the website(s) you
  want to report on.
- A [Resend](https://resend.com) account with an API key, and a verified sending domain (or use
  `onboarding@resend.dev` for testing).

No local toolchain is required — the Rust binary is compiled inside the image during the build.

## Quick start

```bash
cp .env.example .env
# Edit .env and set, at minimum:
#   RESEND_API_KEY, EMAIL_FROM
#   UMAMI_BASE_URL, UMAMI_WEBSITE_ID, UMAMI_USERNAME, UMAMI_PASSWORD
#   REPORT_RECIPIENTS

# Verify configuration and send one report immediately, then exit:
docker compose run --rm -e RUN_MODE=once umami-report-runner

# Once verified, start the scheduled service:
docker compose up -d --build
docker compose logs -f
```

The first build compiles the upstream binary and takes a few minutes; subsequent builds are cached.

## Configuration reference

All settings are environment variables. `.env` is read by Compose and is gitignored. Required values
have no default and the container exits with a clear error at startup if any are missing.

### Email (Resend / SMTP)

| Variable | Required | Default | Description |
| --- | :---: | --- | --- |
| `RESEND_API_KEY` | yes¹ | — | Resend API key. Used as the SMTP password. |
| `EMAIL_FROM` | yes | — | `From` header. May include a display name: `Umami Reports <reports@example.com>`. The address must be on a domain verified in Resend. |
| `SMTP_HOST` | no | `smtp.resend.com` | Override to use a different SMTP provider. |
| `SMTP_PORT` | no | `587` | STARTTLS submission port. |
| `SMTP_USERNAME` | no | `resend` | Resend's fixed SMTP username. |
| `SMTP_PASSWORD` | no | — | Alternative to `RESEND_API_KEY` for non-Resend providers. |
| `SMTP_TLS` | no | `true` | Use STARTTLS (correct for port 587). |
| `SMTP_SKIP_VERIFY` | no | `false` | Accept self-signed certificates. |
| `SMTP_TIMEOUT` | no | `30` | SMTP timeout in seconds. |

¹ Either `RESEND_API_KEY` or `SMTP_PASSWORD` must be set.

### Umami site (single-site form)

| Variable | Required | Default | Description |
| --- | :---: | --- | --- |
| `UMAMI_BASE_URL` | yes | — | Base URL of the Umami instance, e.g. `https://analytics.example.com`. |
| `UMAMI_WEBSITE_ID` | yes | — | Website UUID, found in the website's settings in Umami. |
| `UMAMI_USERNAME` | yes | — | Umami login username (Umami has no API keys). |
| `UMAMI_PASSWORD` | yes | — | Umami login password. |
| `REPORT_RECIPIENTS` | yes | — | Comma-separated list of recipient email addresses. |
| `SITE_NAME` | no | `site` | Display name shown in the report. |
| `TIMEZONE` | no | `UTC` | IANA timezone for the report's day boundaries (e.g. `Asia/Jerusalem`). |

For more than one site, see [Multiple sites](#multiple-sites).

### Report and scheduling

| Variable | Required | Default | Description |
| --- | :---: | --- | --- |
| `REPORT_TYPE` | no | `daily` | `daily` or `weekly`. Determines the reporting window. |
| `RUN_MODE` | no | `cron` | `cron` (stay running and schedule) or `once` (run a single report and exit). |
| `CRON_SCHEDULE` | cron mode | `0 8 * * *` | Crontab expression. Required when `RUN_MODE=cron`. |
| `CRON_TZ` | no | `TIMEZONE` | Timezone in which `CRON_SCHEDULE` is interpreted. Defaults to `TIMEZONE`, then `UTC`. |
| `RUN_ON_START` | no | `false` | In cron mode, also run one report immediately at container start. |
| `DRY_RUN` | no | `false` | Generate the report but do not send the email. |
| `DEBUG` | no | `false` | Enable verbose application logging and print the rendered config (password masked). |
| `MAX_CONCURRENT_JOBS` | no | `4` | Number of sites processed in parallel. |
| `RUST_LOG` | no | `info` | Log level: `trace`, `debug`, `info`, `warn`, or `error`. |

## Obtaining credentials

**Resend.** Create an API key in the Resend dashboard and set it as `RESEND_API_KEY`. To send from
your own domain, add and verify the domain in Resend, then use an address on it for `EMAIL_FROM`.
Before a domain is verified, `onboarding@resend.dev` can be used as the `From` address for testing.

**Umami.** Umami does not issue API keys; the tool authenticates with a username and password that has
access to the website. Use a dedicated low-privilege account where possible. The `UMAMI_WEBSITE_ID` is
the UUID shown in the website's settings page in the Umami dashboard.

## Testing

Run a single report without starting the scheduler. `--rm` removes the container on exit.

**Dry run (no email).** Confirms Umami authentication and report generation, prints the rendered
config with the password masked, and sends nothing:

```bash
docker compose run --rm \
  -e RUN_MODE=once -e DRY_RUN=true -e DEBUG=true \
  umami-report-runner
```

**Live test (sends one email).** Same as above but actually delivers via Resend:

```bash
docker compose run --rm -e RUN_MODE=once umami-report-runner
```

A successful live run ends with a log line similar to:

```
INFO Successfully sent report for website: <SITE_NAME>
INFO Processing complete. 1 succeeded, 0 failed
```

and exits with status `0`. A new or low-traffic site may produce a sparse report for `REPORT_TYPE=daily`;
set `REPORT_TYPE=weekly` to cover a larger window.

## Deployment

### Docker Compose (recommended)

```bash
docker compose up -d --build
```

The service runs in cron mode and emails the report on `CRON_SCHEDULE`. It is a background worker and
exposes no ports. `restart: unless-stopped` keeps it running across reboots and crashes.

Update after changing `.env`:

```bash
docker compose up -d
```

Rebuild after changing the Dockerfile or bumping the upstream pin:

```bash
docker compose up -d --build
```

### Plain Docker

```bash
docker build -t umami-report-cloud-runner .
docker run -d --name umami-report-runner --restart unless-stopped \
  --env-file .env umami-report-cloud-runner
```

### Platform notes (Coolify / Dokploy / Portainer)

Point the platform at this repository and use the provided `Dockerfile`. Supply the variables from
[Configuration reference](#configuration-reference) through the platform's environment/secrets UI
rather than committing a `.env`. No ports, volumes, or healthcheck endpoints are required — the
container is a scheduled worker and logs each run to stdout.

## Scheduling and timezones

`CRON_SCHEDULE` controls *when* a report runs; `REPORT_TYPE` controls *what window* it covers. Keep
the two consistent:

| Cadence | `REPORT_TYPE` | Example `CRON_SCHEDULE` | Meaning |
| --- | --- | --- | --- |
| Daily | `daily` | `0 8 * * *` | 08:00 every day |
| Weekly | `weekly` | `0 8 * * 1` | 08:00 every Monday |

The schedule is interpreted in `CRON_TZ`, which defaults to `TIMEZONE`, which defaults to `UTC`. Named
zones such as `Asia/Jerusalem` are supported (tzdata is bundled in the image). Set `CRON_TZ` separately
only if you need the firing time and the report window in different timezones.

## Multiple sites

To report on several websites from one container, define numbered `SITE_N_*` blocks. When
`SITE_1_BASE_URL` is present, the numbered blocks are used **instead of** the single-site `UMAMI_*`
variables.

| Variable (per N) | Required | Description |
| --- | :---: | --- |
| `SITE_N_BASE_URL` | yes | Umami base URL for this site. |
| `SITE_N_WEBSITE_ID` | yes | Website UUID. |
| `SITE_N_USERNAME` | yes | Umami username. |
| `SITE_N_PASSWORD` | yes | Umami password. |
| `SITE_N_RECIPIENTS` | yes | Comma-separated recipients. |
| `SITE_N_NAME` | no | Display name (defaults to `siteN`). |
| `SITE_N_TIMEZONE` | no | IANA timezone (defaults to `TIMEZONE`). |

```bash
SITE_1_BASE_URL=https://analytics.example.com
SITE_1_WEBSITE_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
SITE_1_USERNAME=user1
SITE_1_PASSWORD=pass1
SITE_1_RECIPIENTS=a@example.com,b@example.com
SITE_1_NAME=Site One

SITE_2_BASE_URL=https://umami.other.com
SITE_2_WEBSITE_ID=...
SITE_2_USERNAME=user2
SITE_2_PASSWORD=pass2
SITE_2_RECIPIENTS=c@example.com
SITE_2_TIMEZONE=Asia/Kolkata
```

A single email is generated and sent per site. `MAX_CONCURRENT_JOBS` bounds how many are processed at
once.

## Operations

**Logs.** Each scheduled run, including the report summary and any errors, is written to stdout:

```bash
docker compose logs -f
```

**Trigger an ad-hoc report** without disturbing the running service:

```bash
docker compose run --rm -e RUN_MODE=once umami-report-runner
```

**Stop / start:**

```bash
docker compose stop
docker compose up -d
```

The container runs as a non-root user and `tini` handles signal forwarding, so `docker stop` shuts it
down promptly.

## How it works

The image is built in stages:

1. **Build** — clones the upstream repository pinned to a specific commit and compiles a statically
   linked `musl` binary. The upstream uses `rustls` throughout, so no OpenSSL is required.
2. **Cron** — fetches `supercronic`, a container-oriented cron implementation, and verifies its checksum.
3. **Runtime** — a minimal Alpine image containing the binary, `supercronic`, `tini`, CA certificates,
   and `tzdata`, running as a non-root user.

At startup, `docker/entrypoint.sh` invokes `docker/render-config.sh`, which translates the environment
variables into the TOML file the upstream binary expects (`/app/config.toml`) and validates required
values. The entrypoint then either runs the binary once (`RUN_MODE=once`) or writes a crontab and hands
off to `supercronic` (`RUN_MODE=cron`). The upstream report HTML template is compiled into the binary,
so no template files are present at runtime.

`docker/render-config.sh` is the only component coupled to the upstream config schema. If upstream
renames a config field, that script is the single place to update.

## Upstream pinning

The upstream commit is pinned through the `UMAMI_ALERTS_REF` build argument, with the default set in
both the `Dockerfile` and `docker-compose.yml`. Update it deliberately to adopt upstream changes:

```bash
docker build --build-arg UMAMI_ALERTS_REF=<commit-sha> -t umami-report-cloud-runner .
```

or change `UMAMI_ALERTS_REF` under `build.args` in `docker-compose.yml` and rebuild.

## Troubleshooting

| Symptom | Likely cause | Resolution |
| --- | --- | --- |
| Container exits immediately with `render-config: ERROR: ...` | A required variable is missing or invalid | Set the named variable; check `REPORT_TYPE` is `daily`/`weekly`. |
| `Processing complete. 0 succeeded, 1 failed` | Umami authentication or connectivity failure | Verify `UMAMI_BASE_URL`, credentials, and that the instance is reachable from the container. Run with `DEBUG=true` for detail. |
| Email never arrives | Resend rejected the message | Confirm `RESEND_API_KEY` is valid and `EMAIL_FROM` uses a verified domain (or `onboarding@resend.dev` for tests). Check the Resend dashboard logs. |
| Report appears empty | No traffic in the window | Use `REPORT_TYPE=weekly`, or confirm the window with `DEBUG=true`. |
| Scheduled run fires at the wrong local time | `CRON_SCHEDULE` interpreted in the default timezone | Set `CRON_TZ` (or `TIMEZONE`) to your zone. |

## Contributing

The `main` branch is protected; all changes land through pull requests that pass CI. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the development setup, the local checks to run before opening a
PR, and the branch workflow.

## License

MIT — see [LICENSE](LICENSE). This project builds and wraps
[Thunderbottom/umami-alerts](https://github.com/Thunderbottom/umami-alerts) (MIT); the analytics
querying, report rendering, and email logic are upstream's.
