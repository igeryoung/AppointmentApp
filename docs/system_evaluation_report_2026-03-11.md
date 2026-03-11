# ScheduleNote System Evaluation Report

Date: 2026-03-11  
Evaluator: System design and architecture review (repository-based)

## 1) Executive Summary

Current system quality is mixed: client architecture and local test coverage are solid, but server-side security and production-hardening have multiple critical gaps.

- Overall rating: **4.9 / 10**
- Delivery risk (next 30 days): **High**
- Primary blockers: **auth/authz design, insecure defaults, production-mode ambiguity**

## 2) Scope and Evidence

Reviewed:
- Flutter client (`lib/`)
- Dart Shelf server (`server/`)
- schema and deployment config
- test pipeline status on 2026-03-11

Quality check run:
- `./tool/test_user_pipeline.sh --fast`
- Result: **9 passed / 1 failed**
- Failed step: Pipeline 10 (`test/app/widget/app_bootstrap_setup_test.dart`)

## 3) Rating Matrix

| Dimension | Rating (10) | Notes |
|---|---:|---|
| Security | 2.0 | Multiple critical auth/authz flaws and weak defaults |
| Reliability | 6.0 | Core app paths tested; server has weak guardrails |
| Data Integrity | 5.0 | Version fields exist, but some invariants are unenforced |
| Scalability | 5.0 | Works for small/medium load; limited operational controls |
| Operability | 4.0 | Mode/config mismatch and unsafe runtime defaults |
| Testability | 7.0 client / 3.0 server | Strong client unit pipeline; limited server automated validation |

## 4) Risk Register (Prioritized)

### R1 (Critical): Dashboard authentication is effectively bypassable

Why this is risky:
- Login token is just base64(`username:password`) and middleware only checks header starts with `Bearer `.
- Any bearer string can access dashboard endpoints.
- Defaults are weak and startup logs print credentials.

Evidence:
- `server/lib/routes/dashboard_routes.dart:242-248`
- `server/lib/routes/dashboard_routes.dart:267-278`
- `server/main.dart:92-95`
- `server/main.dart:248`

Recommended fix:
- Replace with signed JWT/session token validation (expiry + signature check).
- Remove default credentials; require env vars in non-dev.
- Never print credentials in logs.

---

### R2 (Critical): Record endpoints have no authentication or authorization checks

Why this is risky:
- `/api/records/*` routes allow create/read/update/delete without device credential validation.
- Exposes sensitive metadata and allows unauthorized mutation.

Evidence:
- Route mount: `server/main.dart:61-63`
- No auth checks in handlers: `server/lib/routes/record_routes.dart:16-25`, `49-112`, `114-146`, `184-240`

Recommended fix:
- Add centralized auth middleware.
- Require book/record-level authorization per request context.

---

### R3 (Critical): Test fixture endpoints are mounted in main server runtime

Why this is risky:
- Fixture provisioning/cleanup endpoints are available by default.
- Protection falls back to default password `"password"` if env is missing.

Evidence:
- Mount in runtime: `server/main.dart:103-104`
- Password default: `server/lib/routes/test_fixture_routes.dart:46-49`

Recommended fix:
- Gate fixture routes behind explicit `ENABLE_TEST_FIXTURES=true` and non-production mode.
- Separate them into test-only binary or dev-only router.

---

### R4 (High): Production mode detection conflicts with docs and weakens safeguards

Why this is risky:
- Code treats empty args as development mode.
- Docs say `dart run main.dart` is production.
- This can bypass production-only checks and misapply SSL behavior.

Evidence:
- Mode detection: `server/main.dart:33`
- Production command in docs: `server/README.md:33-35`

Recommended fix:
- Make dev mode explicit (`--dev` only).
- Treat default as production.
- Add startup banner showing effective mode and config source.

---

### R5 (High): Book read/bundle paths can auto-grant membership

Why this is risky:
- If a device can pass password gate (or for legacy books without password), server silently inserts membership.
- Converts read access flow into implicit ACL mutation.

Evidence:
- Membership grant helper: `server/lib/routes/book_routes.dart:84-99`
- Invocation on read paths: `server/lib/routes/book_routes.dart:414-423`, `664-673`

Recommended fix:
- Remove implicit ACL grants from read endpoints.
- Use explicit share/invite endpoint with audit trail.

---

### R6 (High): “Atomic” batch save is not actually transactional

Why this is risky:
- API contract claims all-or-nothing with commit/rollback.
- Implementation performs iterative writes without DB transaction boundaries.
- Partial writes are possible on mid-batch failure.

Evidence:
- Atomic claim: `server/lib/routes/batch_routes.dart:32-37`
- Iterative write loops: `server/lib/services/batch_service.dart:207-274`
- Transaction helper is no-op: `server/lib/database/connection.dart:58-61`

Recommended fix:
- Implement true transactional batch (DB transaction/RPC stored procedure).
- Return per-item status only if atomic mode is disabled by design.

---

### R7 (Medium): Note 1:1 invariant is declared in comments but not enforced in schema

Why this is risky:
- Notes are conceptually one-per-record, but no unique constraint on `notes.record_uuid`.
- Code reads/updates with `limit(1)`, so duplicates can create non-deterministic behavior.

Evidence:
- Schema without unique constraint: `server/schema.sql:120-133`
- One-to-one intent comment: `server/schema.sql:138-139`
- Query pattern assumes single row: `server/lib/services/note_service.dart:183-217`

Recommended fix:
- Add unique index on active notes per `record_uuid` (e.g., partial unique where `is_deleted=false`).
- Add migration + duplicate resolution script.

---

### R8 (Medium): Book password hashing uses plain SHA-256 without adaptive hashing

Why this is risky:
- Fast hash is weaker against offline brute-force if hashes leak.

Evidence:
- Hashing call: `server/lib/routes/book_routes.dart:174-176`

Recommended fix:
- Migrate to Argon2id or bcrypt with per-book salt and cost factor.

---

### R9 (Medium): Server-side automated safety net is thin

Why this is risky:
- Rich client test pipeline exists, but no comparable server test suite and no repo CI workflows detected.

Evidence:
- Fast pipeline result on 2026-03-11: 9/10 passing.
- No `.github/workflows` directory in repo.
- No `server/test` suite found.

Recommended fix:
- Add server integration tests for auth/authz and critical endpoints.
- Add CI gates (analyze + tests for client/server on PR).

---

### R10 (Low): Current client pipeline has one failing widget test

Why this is risky:
- Indicates drift in setup error messaging/expectations.
- Not a production blocker, but it reduces confidence in setup UX regression detection.

Evidence:
- Failed assertion text: `test/app/widget/app_bootstrap_setup_test.dart:58`
- Pipeline report: `docs/testing/reports/user_pipeline_report_20260311_221123.md`

Recommended fix:
- Align localization/error text assertion with current UI behavior.

## 5) Strengths Observed

- Clear separation of concerns in Flutter app (repositories/services/cubits/screens).
- Consistent use of version fields and soft-delete flags in core server tables.
- Well-structured local pipeline for core app flows (books/events/notes/drawings/controller paths).

## 6) Improvement Plan

### Phase 0 (0-72 hours)

1. Fix dashboard auth (real token verification) and remove printed credentials.
2. Add auth middleware for `/api/records/*`.
3. Disable fixture routes by default in production.
4. Correct runtime mode selection (`args.isEmpty` must not imply dev).

### Phase 1 (Week 1-2)

1. Remove implicit ACL grant from read endpoints.
2. Implement true transactional batch write path.
3. Add schema constraint for single active note per record.
4. Upgrade password hashing strategy (Argon2id/bcrypt migration).

### Phase 2 (Week 3-4)

1. Add server integration tests (auth/authz, batch atomicity, ACL behavior).
2. Add CI workflows for client + server quality gates.
3. Add security regression checks (config validation, forbidden defaults).

## 7) Final Assessment

The product is functionally mature on the client side, but server trust boundaries are currently under-protected. Fixing the critical auth/authz and deployment-mode issues should be treated as a release-gating priority before wider production exposure.
