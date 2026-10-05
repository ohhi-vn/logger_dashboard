# Containerfile for logger_dashboard
# Compatible with Podman and Docker
# Optimized for production Elixir/Phoenix deployment
#
# Build (Podman):
#   podman build -t logger-dashboard:latest .
# HEALTHCHECK is an OCI/docker-format feature, so add --format docker for podman:
#   podman build --format docker -t logger-dashboard:latest .
#
# Build for AMD64:
#   podman build --platform linux/amd64 -t logger-dashboard:latest .
#
# Build for ARM64:
#   podman build --platform linux/arm64 -t logger-dashboard:latest .
#
# Run:
#   podman run -d --name logger_dashboard -p 4000:4000 logger-dashboard:latest
#
# Configuration the dashboard saves (scheduled retention) is written to
# /app/task_config by default. Pass TASK_CONFIG_DIR to put it elsewhere — on a
# volume, if the saved configuration has to survive recreating the container.

ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=29
ARG DEBIAN_VERSION=trixie-slim

ARG BUILDER_IMAGE="elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION}-slim"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
# nodejs/npm are needed for the assets' own JS dependency (chart.js, declared in
# assets/package.json); assets/node_modules is gitignored, so a clean build
# context has none of it.
RUN apt-get update -y && apt-get install -y build-essential git ca-certificates nodejs npm \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

ENV ERL_FLAGS="+JMsingle true"

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./

# Copy config files properly - create config dir first. runtime.exs is the only
# one evaluated at boot, so it is copied in last.
RUN mkdir -p config
COPY config/config.exs config/
COPY config/prod.exs config/

RUN mix deps.get --only $MIX_ENV

RUN mix deps.compile

COPY priv priv

COPY lib lib

COPY assets assets

# Restore the assets' JS dependencies from the lockfile so esbuild can resolve
# `chart.js/auto`.
RUN npm ci --prefix assets

# Compile the release first (needed for assets.deploy phx.digest)
RUN mix compile

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel

RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates curl lksctp-tools \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Create a symlink for migrations and other release tasks
COPY --from=builder --chown=nobody:root /app/rel/overlays/bin/* /app/bin/

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/logger_dashboard ./

# Where the dashboard keeps configuration an operator saves through it (scheduled
# retention today). Created here and owned by the runtime user so a container started
# with no TASK_CONFIG_DIR can still persist it; TASK_CONFIG_DIR overrides the location,
# which is what the compose stack does so the directory lands on a named volume.
RUN mkdir -p /app/task_config && chown nobody /app/task_config

# Make migration script executable
RUN chmod +x /app/bin/migrate 2>/dev/null || true

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]
ENV PHX_SERVER=true

# Health check for container orchestration.
# Every route sits behind the shared-token gate, and curl sends `Accept: */*`, so an
# unauthenticated probe is redirected to the token page. 302 is therefore the expected
# answer from a running server; what this rejects is a container that is up but no
# longer accepting connections. 401 stays accepted for a client that asks for a
# non-HTML representation, which the gate refuses without a login page.
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -s -o /dev/null -w '%{http_code}' http://localhost:4000/logs | grep -qE '^(200|302|401)$' || exit 1

CMD ["/app/bin/logger_dashboard", "start"]
