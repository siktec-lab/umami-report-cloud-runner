#!/bin/sh
# entrypoint.sh — render the config from env, then either run the report once
# or hand off to a built-in cron loop (supercronic).
set -eu

CONFIG_PATH="${CONFIG_PATH:-/app/config.toml}"
CRONTAB_PATH="${CRONTAB_PATH:-/app/crontab}"
BIN="/app/umami-alerts"

export CONFIG_PATH

# 1. Build /app/config.toml from environment variables (fails fast on bad input).
/app/render-config.sh

run_once() {
    echo "entrypoint: running report once" >&2
    "$BIN" --config "$CONFIG_PATH"
}

case "${RUN_MODE:-cron}" in
    once)
        # One-shot: render + run + exit. For external schedulers / testing.
        exec "$BIN" --config "$CONFIG_PATH"
        ;;
    cron)
        : "${CRON_SCHEDULE:?set CRON_SCHEDULE (e.g. '0 8 * * *') or use RUN_MODE=once}"

        # supercronic interprets the crontab in the container's local time. Use
        # CRON_TZ if given, otherwise fall back to TIMEZONE so the schedule and
        # the report window share one timezone by default. tzdata is installed
        # in the image, so named zones (e.g. Asia/Jerusalem) resolve.
        TZ="${CRON_TZ:-${TIMEZONE:-UTC}}"
        export TZ

        # Optionally fire one report immediately so a fresh deploy verifies its
        # config without waiting for the first scheduled tick.
        case "$(printf '%s' "${RUN_ON_START:-false}" | tr '[:upper:]' '[:lower:]')" in
            1|true|yes|on) run_once || echo "entrypoint: initial run failed (continuing to cron)" >&2 ;;
        esac

        # supercronic reads a standard crontab and logs each invocation to stdout.
        printf '%s %s --config %s\n' "$CRON_SCHEDULE" "$BIN" "$CONFIG_PATH" > "$CRONTAB_PATH"
        echo "entrypoint: scheduling '$CRON_SCHEDULE' via supercronic" >&2
        exec supercronic "$CRONTAB_PATH"
        ;;
    *)
        echo "entrypoint: ERROR: RUN_MODE must be 'cron' or 'once' (got '${RUN_MODE}')" >&2
        exit 1
        ;;
esac
