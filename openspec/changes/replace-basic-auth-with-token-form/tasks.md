# Tasks

## 1. Token digest

- [x] 1.1 Add `DashboardAuth.digest/0` returning the SHA-256 hex digest of the current
  token, and verify `test/logger_dashboard/dashboard_auth_test.exs` covers that it is
  stable for an unchanged token, changes when the token changes, and is `nil` when no
  token is configured
- [x] 1.2 Delete `DashboardAuth.extract_token/1`, `authenticated?/1`, and the `Basic`
  and `Bearer` clauses of `parse_authorization/1`; verify `rg 'Basic |Bearer
  |extract_token|authenticated\?' lib` finds nothing and `mix compile
  --warnings-as-errors` succeeds
- [x] 1.3 Confirm `valid?/1` is untouched and still the comparison used everywhere;
  verify its existing tests in `dashboard_auth_test.exs` pass unchanged

## 2. Token page

- [x] 2.1 Create `LoggerDashboardWeb.AuthSessionController` with `new/2` rendering the
  page and `create/2` handling the submitted token, redirecting to the originally
  requested path on success and re-rendering with an error on failure; verify a wrong
  token leaves `Plug.Conn.get_session(conn, :dashboard_auth_digest)` unset
- [x] 2.2 Create `LoggerDashboardWeb.AuthSessionHTML` and its template: a password
  field, a submit control, and no navigation or flash group; verify the rendered page
  contains `#login-form` and a `type="password"` input and does not contain
  `#dashboard-nav`
- [x] 2.3 Add `GET /login` and `POST /login` to a public scope, and verify
  `mix phx.routes` lists both and neither appears behind the gate
- [x] 2.4 Verify the CSRF hidden field is present in the rendered form and that a POST
  without it is rejected; add a test asserting the rejection

## 3. The gate

- [x] 3.1 Rewrite `Plugs.DashboardAuth.call/2` to read the session digest, redirect to
  the token page for requests that accept HTML, and answer `401` with no
  `WWW-Authenticate` header otherwise; verify with a request sending `Accept: text/html`
  and with one sending none
- [x] 3.2 Verify no response carries a `WWW-Authenticate` header; add a test asserting
  its absence on both the redirect and the `401`
- [x] 3.3 Verify a token in an `Authorization` header does not authenticate; add a test
  covering both `Basic` and `Bearer` forms
- [x] 3.4 Replace `on_mount(:default, ...)`'s `redirect(socket, to: "/")` with a
  redirect to the token page, delete the dead `on_mount(:ensure_authenticated, ...)`
  clause, and update `test/logger_dashboard_web/plugs/dashboard_auth_test.exs` to drop
  the tests of the deleted clause and the `401` + challenge contract; verify the file
  passes

## 4. Router ordering

- [x] 4.1 Add a `:browser_unauthenticated` pipeline carrying `accepts`, `fetch_session`,
  `fetch_live_flash`, `put_root_layout`, `protect_from_forgery`, and
  `put_secure_browser_headers`, and make `:browser` extend it with the auth plug and
  `load_csrf_protection`; verify `mix compile` succeeds and the login page renders
  inside the root layout
- [x] 4.2 Add `DELETE /logout` to the authenticated scope, clearing the session and
  redirecting to the token page; verify a subsequent request to `/logs` is
  unauthenticated and that no log row was deleted and no retention policy changed
- [x] 4.3 Confirm every gated route — `/`, `/logs`, `/analysis`, `/prune`, and `/dev/*`
  — still sits behind the plug; verify with a table of unauthenticated requests each
  redirecting and each authenticated request rendering

## 5. Sign-out control

- [x] 5.1 Render the sign-out control in `Layouts.app/1` beside the theme toggle, as a
  form posting to the logout route with an accessible name; verify the control appears
  on `/`, `/logs`, `/analysis`, and `/prune`
- [x] 5.2 Verify the control is absent from the token page; add a test asserting
  `#logout-button` is not present there

## 6. Sessions

- [x] 6.1 Add an explicit `max_age` to `@session_options` in the endpoint and verify it
  reaches the cookie; assert on the `set-cookie` header in a test
- [x] 6.2 Verify a session established with the current token keeps working across
  requests and LiveView mounts without re-prompting; add a test covering a mount over
  the socket
- [x] 6.3 Verify rotating the token ends outstanding sessions — both a changed
  configured token and a regenerated ephemeral one — with a test for each; confirm the
  operator lands on the token page and that the old digest no longer authenticates
- [x] 6.4 Verify the session cookie contains no usable token; add a test asserting the
  cookie value does not contain the token and does contain the digest

## 7. Test harness

- [x] 7.1 Rewrite `test/support/conn_case.ex` to authenticate by posting to the token
  page instead of injecting an `Authorization` header, and verify all eight test files
  that use it still pass with no per-file changes
- [x] 7.2 Rewrite `test/logger_dashboard_web/controllers/dashboard_auth_test.exs`: drop
  the `WWW-Authenticate` and `401`-for-browser assertions, and add cases for the
  redirect, the form round trip, and header credentials being ignored
- [x] 7.3 Update `test/logger_dashboard_web/live/dashboard_auth_test.exs`, whose
  unauthenticated assertion expects `401` on a headerless conn, to expect the redirect;
  verify it passes
- [x] 7.4 Run the full suite and verify no test still reaches authentication through an
  `Authorization` header

## 8. Deployment and documentation

- [x] 8.1 Update the `Containerfile` and `compose.yaml` health checks to accept `302`
  alongside `200`, with a comment saying an unauthenticated request is now redirected;
  verified against a live `MIX_ENV=prod` instance (curl `/logs` → `302`, probe regex
  passes). A full `podman build` in this environment is slow on the git-sourced Tailwind
  fetch and was still running when the task list completed
- [x] 8.2 Rewrite the README authentication section: remove the two `curl` recipes,
  describe the token page and the form, and give a login-then-use recipe for scripted
  access; verify the documented commands work as written against a running instance
- [x] 8.3 Update the README to state that a restart with an ephemeral token signs
  existing sessions out, and that a pinned `DASHBOARD_AUTH_TOKEN` is what keeps a
  session alive across restarts
- [x] 8.4 Run `mix precommit` with a ClickHouse available and fix any failures