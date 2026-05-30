# syntax=docker/dockerfile:1

###############################################################################
# umami-report-cloud-runner
#
# Containerizes Thunderbottom/umami-alerts (a Rust CLI that emails Umami
# Analytics reports) and wraps it so the whole thing is configured purely from
# environment variables, sends through Resend's SMTP gateway, and schedules
# itself with a built-in cron loop (supercronic).
#
# No fork of the upstream Rust is required:
#   - config.toml is rendered from env at container start (render-config.sh)
#   - Resend works via its SMTP interface, which upstream's lettre supports
###############################################################################

# ---- Stage 1: build the upstream binary (static musl) -----------------------
# rustls everywhere upstream (reqwest rustls-tls + lettre tokio1-rustls-tls)
# means no OpenSSL is needed, so we can build a fully static musl binary and
# ship a tiny runtime image.
FROM rust:1.83-alpine AS builder

# Pin upstream to a specific commit for reproducible builds. Override at build
# time with: --build-arg UMAMI_ALERTS_REF=<sha|tag|branch>
ARG UMAMI_ALERTS_REPO=https://github.com/Thunderbottom/umami-alerts.git
ARG UMAMI_ALERTS_REF=8dc96e406d016bc1c6c68b828ac58f87492460ee

RUN apk add --no-cache git musl-dev openssl-dev pkgconfig \
    && rustup target add x86_64-unknown-linux-musl

WORKDIR /build
RUN git clone "${UMAMI_ALERTS_REPO}" . \
    && git checkout "${UMAMI_ALERTS_REF}"

# Build the release binary against musl. Templates are embedded via include_str!
# at this point, so the resulting binary is self-contained.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    cargo build --release --target x86_64-unknown-linux-musl \
    && cp target/x86_64-unknown-linux-musl/release/umami-alerts /umami-alerts \
    && strip /umami-alerts

# ---- Stage 2: fetch supercronic (container-friendly cron) -------------------
FROM alpine:3.21 AS cron
ARG SUPERCRONIC_VERSION=v0.2.33
ARG SUPERCRONIC_SHA1SUM=71b0d58cc53f6bd72cf2f293e09e294b79c666d8
RUN apk add --no-cache curl \
    && curl -fsSLo /usr/local/bin/supercronic \
       "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64" \
    && echo "${SUPERCRONIC_SHA1SUM}  /usr/local/bin/supercronic" | sha1sum -c - \
    && chmod +x /usr/local/bin/supercronic

# ---- Stage 3: minimal runtime ----------------------------------------------
FROM alpine:3.21 AS runtime

# tini = proper PID 1 / signal reaping; ca-certificates for outbound TLS
# (Umami API over HTTPS + Resend SMTP STARTTLS); tzdata so per-site timezones
# resolve correctly.
RUN apk add --no-cache tini ca-certificates tzdata \
    && addgroup -S runner \
    && adduser -S -G runner -h /app runner

COPY --from=builder /umami-alerts /app/umami-alerts
COPY --from=cron /usr/local/bin/supercronic /usr/local/bin/supercronic
COPY docker/entrypoint.sh docker/render-config.sh /app/

RUN chmod +x /app/entrypoint.sh /app/render-config.sh /app/umami-alerts \
    && chown -R runner:runner /app

USER runner
WORKDIR /app

# Sensible defaults; override any via `docker run -e` / compose env_file.
ENV RUN_MODE=cron \
    CRON_SCHEDULE="0 8 * * *" \
    RUN_ON_START=false \
    REPORT_TYPE=daily \
    DRY_RUN=false \
    DEBUG=false \
    MAX_CONCURRENT_JOBS=4 \
    TIMEZONE=UTC \
    SMTP_HOST=smtp.resend.com \
    SMTP_PORT=587 \
    SMTP_USERNAME=resend \
    SMTP_TLS=true \
    SMTP_SKIP_VERIFY=false \
    SMTP_TIMEOUT=30 \
    RUST_LOG=info

ENTRYPOINT ["/sbin/tini", "--", "/app/entrypoint.sh"]
