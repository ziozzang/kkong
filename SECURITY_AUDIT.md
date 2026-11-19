# Security Audit – kkong (Kong 1.31.x fork)

## 1. Scope and Methodology

### Scope
This audit focused on **fork-introduced deltas** between `ziozzang/kkong` and upstream `Kong/kong` (master), with priority on the areas requested in the issue:

- TLS yield retry patch (`build/openresty/patches/nginx-1.27.1_12-ssl-lua-yield-retry.patch`)
- OpenResty source override and supply-chain controls (`build/openresty/repositories.bzl`, vendored tarball)
- Nginx template changes for SSL directives
- Metadata/version signaling (`kong/meta.lua`, `.requirements`)
- Status of `ngx_lua-0.10.28_02-fix-invalid-hostname.patch`
- Smoke script safety (`scripts/run-ssl-yield-regression.sh`)
- GitHub Actions workflow risk patterns (`.github/workflows`)
- Build-system download/integrity controls (`Makefile`, `BUILD.bazel`, `MODULE.bazel`, `WORKSPACE`, `build/**/*.bzl`)
- High-risk Lua/shell pattern checks in changed areas
- Default config delta check (`kong.conf.default`)

### Methods used
1. **Fork delta identification**
   - `git fetch upstream master`
   - `git diff --name-status upstream/master..HEAD`
   - `git log --oneline -- <file>` on high-risk files
2. **Targeted static review**
   - Direct hunk-level review of `.patch` files
   - Direct review of changed templates/workflows/build rules
3. **Pattern-driven search**
   - `pull_request_target`, secret usage, `permissions`, shell interpolation patterns
   - `loadstring`, `load(`, `os.execute`, `io.popen`, `ngx.exec`
   - integrity indicators: `sha256`, `integrity`, `urls`, `http://`
4. **Artifact/source cross-check**
   - Inspected vendored OpenResty tarball contents (`tar -tzf`, `tar -xOf`) including:
     - nginx source path and version macros (`NGINX_VERSION "1.31.0"`)
     - pre-patch OpenSSL handshake code context
5. **CI signal check**
   - Listed recent workflow runs and inspected failed job logs (Dependabot failure)

### Constraints / limits
- Full runtime regression execution was attempted but blocked by sandbox DNS/network failure while downloading Bazel (`releases.bazel.build` lookup failure), so dynamic reproduction for TLS-loop edge cases is marked as suspected/not reproduced where applicable.

## 2. Threat Model

### Assets
- TLS handshake correctness and certificate verification behavior
- Build-time dependency integrity (OpenResty, Kong Manager, toolchains)
- CI secrets and workflow execution context
- Operational trust in exposed version metadata

### Trust boundaries
- Untrusted network clients (TLS handshake inputs, SNI values)
- Untrusted PR authors/forks in GitHub Actions context
- External or prebuilt artifacts (vendored tarballs, release archives)
- Local build environment variables and repository content

### Attacker models
1. Remote network attacker attempting handshake abuse/DoS.
2. Supply-chain attacker tampering with runtime artifacts before vendoring.
3. PR-based attacker attempting CI privilege/secret escalation.
4. Operator-level confusion attacker relying on inaccurate documentation/version cues.

## 3. Findings

### KKONG-AUDIT-001
- **Title:** Vendored OpenResty archive bypasses explicit cryptographic verification in repository rule
- **Severity:** Medium
- **Status:** Confirmed
- **Location:**
  - `build/openresty/repositories.bzl:43-51,107-142`
  - `vendor/openresty/BUILD.bazel:1`
  - `.requirements:3-4`
- **Description:**
  The fork replaced upstream `http_archive(urls + sha256)` with local archive extraction (`archive = "//vendor/openresty:...tar.gz"` + custom repository_rule extraction). The build rule no longer enforces a per-fetch `sha256` check for OpenResty in `openresty_repositories`, while `.requirements` still exposes `OPENRESTY_SHA256` that is not used by this code path.
- **Impact:**
  If the vendored artifact is tampered with before commit (or artifact generation pipeline is compromised), consumers rely mainly on Git commit trust, not independent artifact integrity/provenance checks at fetch/extract time. This increases supply-chain blast radius.
- **Reproduction / Reasoning:**
  `git diff upstream/master -- build/openresty/repositories.bzl` shows removal of `sha256`/`urls` and replacement with local `archive` extraction. No digest validation logic exists in `_openresty_vendor_archive_impl`.
- **Recommendation:**
  Add explicit digest verification for vendored archive (or store and verify SLSA-style provenance/signature), and align `.requirements` hash with an enforced check in Bazel rule logic.
- **References:**
  `git diff upstream/master -- build/openresty/repositories.bzl`; file lines above.

### KKONG-AUDIT-002
- **Title:** TLS retry patch may permit event-loop spin (CPU DoS) for WANT_* retry classes
- **Severity:** Medium
- **Status:** Suspected
- **Location:** `build/openresty/patches/nginx-1.27.1_12-ssl-lua-yield-retry.patch:8-34,43-109`
- **Description:**
  Newly added branches for `SSL_ERROR_WANT_X509_LOOKUP`, `SSL_ERROR_PENDING_SESSION`, `SSL_ERROR_WANT_CLIENT_HELLO_CB`, `SSL_ERROR_WANT_RETRY_VERIFY` set handshake handlers and return `NGX_AGAIN`, but unlike existing WANT_READ/WANT_WRITE branches they do not clear `c->read->ready` or `c->write->ready`.
- **Impact:**
  Under crafted handshake timing/state, this may cause tight re-dispatch/retry behavior and worker CPU exhaustion (availability impact).
- **Reproduction / Reasoning:**
  Pre-patch source in vendored nginx (`.../ngx_event_openssl.c`) clears ready flags for WANT_READ/WANT_WRITE before `NGX_AGAIN`. New WANT_* branches do not. Dynamic reproduction was not completed due build/runtime setup limits in this sandbox.
- **Recommendation:**
  Validate with stress/regression test that repeatedly triggers each WANT_* class and monitor event-loop behavior. Consider mirroring ready-flag handling semantics used in WANT_READ/WANT_WRITE if consistent with upstream nginx/OpenResty behavior.
- **References:**
  Patch hunk lines above; pre-patch context from vendored `ngx_event_openssl.c` around `ngx_ssl_handshake` and `ngx_ssl_try_early_data`.

### KKONG-AUDIT-003
- **Title:** Documentation claim about removed invalid-hostname patch conflicts with repository state
- **Severity:** Low
- **Status:** Confirmed
- **Location:**
  - `PORTING_1_31_0.md:17-18`
  - `build/openresty/patches/ngx_lua-0.10.28_02-fix-invalid-hostname.patch:1-23`
  - `build/kong_bindings.bzl:55-60`
- **Description:**
  Porting notes state the old invalid-hostname patch was removed because upstream includes the fix. However the patch file exists and is still included by the dynamic patch list assembly.
- **Impact:**
  Audit and maintenance confusion: reviewers may assume a patch is not in effect when it is still part of patch set resolution logic.
- **Reproduction / Reasoning:**
  File is present; patch list is computed by directory enumeration in `build/kong_bindings.bzl`, which includes this file.
- **Recommendation:**
  Reconcile docs and actual patch policy. If patch is intentionally retained for compatibility/fuzzing, document rationale explicitly.
- **References:**
  Files/lines above.

### KKONG-AUDIT-004
- **Title:** GitHub Actions `pull_request_target` + PR checkout + secret exposure pattern
- **Severity:** Informational
- **Status:** Cleared
- **Location:** `.github/workflows/*.yml`
- **Description:**
  Checked for classic high-risk pattern (`pull_request_target` with untrusted PR code checkout and secrets).
- **Impact:**
  None observed for this pattern.
- **Reproduction / Reasoning:**
  Repository-wide workflow search found no `pull_request_target` trigger.
- **Recommendation:**
  Keep `pull_request` for untrusted code paths; if `pull_request_target` is introduced later, isolate privileged steps and avoid checking out attacker-controlled refs before secret use.
- **References:**
  Pattern search output on `.github/workflows`.

### KKONG-AUDIT-005
- **Title:** `lua_ssl_verify_depth` guard change does not itself force weaker TLS verification
- **Severity:** Informational
- **Status:** Cleared
- **Location:**
  - `kong/templates/nginx_kong_inject.lua:2-4`
  - `kong/templates/nginx_kong_stream_inject.lua:2-4`
  - `git diff upstream/master -- kong/templates/nginx_kong.lua kong/templates/nginx_kong_stream.lua kong/templates/nginx.lua kong/templates/kong_defaults.lua` (no fork delta in core SSL policy directives)
- **Description:**
  Guard now emits `lua_ssl_verify_depth` only when configured and not equal to default `1` to avoid duplicate directive emission.
- **Impact:**
  No direct downgrade found in fork delta for `ssl_verify_client`, `ssl_protocols`, `ssl_ciphers` in main templates/defaults.
- **Reproduction / Reasoning:**
  Diff confirms inject-only change; core SSL directives remain upstream-equivalent in reviewed templates.
- **Recommendation:**
  Keep regression tests for config render edge cases (`LUA_SSL_VERIFY_DEPTH` unset/0/1/large).
- **References:**
  Files/diffs above.

### KKONG-AUDIT-006
- **Title:** SSL yield smoke script temp-file and shell-injection posture
- **Severity:** Informational
- **Status:** Cleared (with caveat)
- **Location:** `scripts/run-ssl-yield-regression.sh:1-315`
- **Description:**
  Script uses `mktemp -d`, quoted variables, no `eval`, and deterministic cleanup. This is strong baseline hygiene.
- **Impact:**
  No direct command-injection or predictable `/tmp` filename issue observed.
- **Reproduction / Reasoning:**
  Static review plus pattern checks (`mktemp`, `/tmp`, `eval`, variable quoting). Caveat: key-file permissions rely on defaults (`openssl` output), not explicit chmod in script.
- **Recommendation:**
  Optionally enforce explicit `umask 077` before key generation for defense-in-depth.
- **References:**
  Script lines above.

### KKONG-AUDIT-007
- **Title:** Version signaling consistency check for nginx/OpenResty metadata
- **Severity:** Informational
- **Status:** Cleared
- **Location:**
  - `.requirements:3-4`
  - `kong/meta.lua:27`
  - vendored source `.../bundle/nginx-1.29.2/src/core/nginx.h` (`NGINX_VERSION "1.31.0"`)
- **Description:**
  Although source directory path remains `nginx-1.29.2`, nginx version macros in vendored source indicate `1.31.0`, matching fork intent and metadata.
- **Impact:**
  No immediate evidence of version string spoofing for user-visible runtime version in reviewed source.
- **Reproduction / Reasoning:**
  Extracted `nginx.h` from vendored tarball and checked version macros.
- **Recommendation:**
  Keep an explicit provenance note documenting why directory naming differs from reported nginx version.
- **References:**
  Files and extracted source noted above.

### KKONG-AUDIT-008
- **Title:** `kong.conf.default` risky default delta from upstream
- **Severity:** Informational
- **Status:** Cleared
- **Location:** `kong.conf.default`
- **Description:**
  Checked for fork-specific risky default changes (admin listen, trusted_ips, ssl-related defaults).
- **Impact:**
  No fork delta detected in `kong.conf.default` vs upstream master.
- **Reproduction / Reasoning:**
  `git diff upstream/master -- kong.conf.default` returns no changes.
- **Recommendation:**
  Continue auditing defaults whenever fork rebases/ports runtime lines.
- **References:**
  Diff command above.

## 4. Test Cases Executed

### Executed commands / checks
- Repository and history:
  - `git status`, `git log --oneline`, `git fetch --unshallow origin`
  - `git fetch upstream master:refs/remotes/upstream/master --tags`
  - `git diff --name-status upstream/master..HEAD`
  - `git diff upstream/master -- <scoped files>`
  - `git log --oneline -- <scoped files>`
- CI/workflow inspection:
  - Listed workflows/runs via GitHub Actions API
  - Retrieved failed Dependabot job logs (run `26074552768`)
- Pattern searches:
  - `pull_request_target`, `write-all`, `permissions`, secret usage
  - risky code patterns (`loadstring`, `load(`, `os.execute`, `io.popen`, `ngx.exec`)
  - integrity patterns (`sha256`, `integrity`, `urls`, `http://`)
  - shell safety patterns in smoke script (`mktemp`, `eval`, `/tmp` usage)
- Artifact cross-check:
  - `tar -tzf vendor/openresty/...tar.gz` path enumeration
  - `tar -xOf ... nginx.h` version macro check
  - `tar -xOf ... ngx_event_openssl.c` hunk context review

### Runtime test attempts
- Attempted baseline targeted test:
  - `make test-custom test_spec=spec/02-integration/05-proxy/35-ssl-yield-regression_spec.lua`
- Result:
  - Failed before execution due Bazel download DNS/network error (`releases.bazel.build` lookup failure in sandbox).

### Hypotheses not fully executed (explicit)
- Full dynamic reproduction of potential busy-loop behavior for each WANT_* TLS retry class under load.
- End-to-end runtime validation of patched nginx event behavior in this sandbox.

## 5. Residual Risk / Not Covered

- **Dynamic verification gap:** TLS retry edge behavior (`WANT_X509_LOOKUP`, `PENDING_SESSION`, etc.) remains partially unverified at runtime due environment constraints.
- **Opaque vendored artifact provenance:** Review covered code and archive contents, but did not validate external signed provenance/attestation for how tarball was produced.
- **Workflow runtime behavior:** Static workflow review was performed; not all privileged jobs were executed in controlled fork/PR threat simulations.

## 6. Tracking

- [ ] Add enforced integrity/provenance validation for vendored OpenResty archive in Bazel rule path.
- [ ] Add/extend regression tests that intentionally trigger each TLS WANT_* retry class and assert no event-loop spin.
- [ ] Reconcile `PORTING_1_31_0.md` statement about `ngx_lua-...-invalid-hostname.patch` with actual patch set behavior.
- [ ] Add a short provenance note for `openresty-1.29.2.3-nginx-1.31.0-as1292.tar.gz` (build recipe, source commits, checksum workflow).
- [ ] Re-audit workflows whenever introducing new secret-consuming jobs or trigger changes.
