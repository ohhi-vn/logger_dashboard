# Proposal

## Why

Every route currently answers an unauthenticated request with `401` and a
`WWW-Authenticate: Basic` challenge, so a browser opens its own modal asking for a
username and password. The username is ignored and discarded, the password is the
token, and the dialog is not this application's — it cannot say what the token is, why
the attempt failed, or where to get one. For a tool whose whole purpose is being usable
at 3am during an incident, that is the wrong front door. The project already rejected
this once, on the grounds that a login form needed "session store, CSRF, LiveView form
work for zero benefit at this scale" — the session store, CSRF, and form components
have since all arrived anyway, so the reason no longer holds and the cost is now small.

The token itself is unchanged and should stay unchanged. What changes is how an
operator presents it.

## What Changes

- **BREAKING**: Remove HTTP Basic and `Authorization: Bearer` as ways in. The session
  cookie becomes the only credential. The `WWW-Authenticate` challenge is gone.
- **BREAKING**: An unauthenticated request is redirected (`302`) to a dedicated token
  page instead of receiving `401`. A request that does not accept HTML still receives
  `401`, so a scripted client is not handed a login page.
- Add a token page with a single password field. Submitting a correct token starts a
  session and returns the operator to where they were going; submitting a wrong one
  re-renders the page with an error and no distinction between "wrong token" and
  "unknown token".
- **BREAKING**: An authenticated session records a digest of the token rather than a
  bare `true`. Rotating the token — including the default ephemeral token regenerating
  on every restart — now invalidates outstanding sessions.
- Add a sign-out control to the shell that ends the session and returns to the token
  page.
- **BREAKING**: The documented `curl -u operator:$TOKEN` and
  `curl -H "Authorization: Bearer $TOKEN"` workflows no longer authenticate. Scripted
  access now logs in once and carries the session cookie.
- The container and compose health checks accept the new unauthenticated status
  (`302`) instead of `401`.
- Retire the dead `on_mount(:ensure_authenticated, ...)` clause, which exists only for
  a test and duplicates `:default`.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `dashboard-auth`: the gate no longer challenges with `401`/`WWW-Authenticate`;
  requests are redirected to a token page, authenticated access is carried by a
  session bound to the token, the header schemes are removed, and signing out is a
  supported action. The environment-token, ephemeral-token, constant-time-comparison,
  and offline-generator requirements are unchanged in substance.
- `dashboard-shell`: the navigation frame gains a sign-out control, present on every
  page.

## Impact

- **New modules**: `LoggerDashboardWeb.AuthSessionController` (render the token page,
  accept the token, sign out) and `LoggerDashboardWeb.AuthSessionHTML` plus its
  template.
- **Changed modules**:
  - `LoggerDashboardWeb.Plugs.DashboardAuth` — reads the session instead of the
    `Authorization` header; redirects to the token page for HTML requests and answers
    `401` otherwise; `on_mount` verifies the session's digest against the current token
    and redirects to the token page rather than to `/`.
  - `LoggerDashboard.DashboardAuth` — drops `extract_token/1`, `authenticated?/1`, and
    the `Basic`/`Bearer` header parsing; gains a token digest for the session to bind
    to. `valid?/1`, `get_token/0`, and `generate_token/1` are unchanged and are what
    the controller and the mount hook use.
  - `LoggerDashboardWeb.Router` — the auth plug moves below `put_root_layout` and
    `protect_from_forgery` so a redirected response can be a real page with a real
    form; a public scope is added for the token page and the sign-out route.
  - `LoggerDashboardWeb.Layouts` — renders the sign-out control.
  - `LoggerDashboardWeb.Endpoint` — session options gain an explicit `max_age`, and
    the signing salt is left alone.
- **Configuration**: no new variables. `SECRET_KEY_BASE` and `DASHBOARD_AUTH_TOKEN`
  keep their meanings.
- **Deployment**: `Containerfile` and `compose.yaml` health checks accept `302`
  alongside `200`.
- **Documentation**: the README authentication section is rewritten — the two `curl`
  recipes are replaced by a login-then-use recipe, and the "browser gets a 401 prompt"
  paragraph with the form's behaviour.
- **Tests**: `test/support/conn_case.ex` stops injecting an `Authorization` header and
  logs in through the token page instead; the two test files that assert the
  `WWW-Authenticate` contract are rewritten; new coverage for the form, the session
  digest, rotation invalidating a session, and sign-out.
- **Not changed**: the token itself, its sources, its entropy, its generation task,
  and the constant-time comparison. `LoggerDashboardWeb.CoreComponents` already
  supports `type="password"`, so the form reuses the existing `<.input>` and `<.button>`
  with no new UI primitive.