# Multi-Device Sync Audit (Static Analysis)

Date: 2026-02-18  
Scope: iOS app, device-registration model (no user account), server source of truth, near real-time target (<1 minute), LWW conflict policy.  
Domains requested: schedule/events, event metadata, note sharing by `record_uuid`.

## Executive Summary

Current architecture can support **basic multi-device event viewing and writes**, but it has **critical gaps** that will cause inconsistency in real multi-device use.

- Works now: device auth, server-backed event list refresh (30s while schedule screen is foreground), note version-conflict API + retry path.
- Will fail now: reliable cross-device `record_uuid` identity convergence, record metadata consistency, and some contract/access consistency paths.
- Risk level for production multi-device: **High**.

## Module Verdict Matrix

| Module | Verdict | Why | Evidence |
|---|---|---|---|
| Device registration/auth | Will Work | Device registration/token flow is implemented and checked in server routes. | `/Users/yangping/Studio/side-project/scheduleNote/server/lib/routes/device_routes.dart:20`, `/Users/yangping/Studio/side-project/scheduleNote/server/lib/services/note_service.dart:47` |
| Book sharing/access model | Conditional (works but overly broad) | Access can be granted via `book_device_access`, but list/pull logic is globally permissive (all books visible to any authenticated device). | `/Users/yangping/Studio/side-project/scheduleNote/server/lib/services/book_pull_service.dart:70`, `/Users/yangping/Studio/side-project/scheduleNote/server/lib/services/book_pull_service.dart:121`, `/Users/yangping/Studio/side-project/scheduleNote/server/lib/services/note_service.dart:59` |
| Schedule event list near real-time | Will Work (foreground only) | Screen forces refresh on route/app resume and every 30s timer while active. | `/Users/yangping/Studio/side-project/scheduleNote/lib/screens/schedule_screen.dart:37`, `/Users/yangping/Studio/side-project/scheduleNote/lib/screens/schedule_screen.dart:113`, `/Users/yangping/Studio/side-project/scheduleNote/lib/screens/schedule_screen.dart:118` |
| Event CRUD with LWW | Mostly Works | Server updates increment version without strict optimistic check; effectively last-writer-wins by arrival order. | `/Users/yangping/Studio/side-project/scheduleNote/server/lib/routes/event_routes.dart:564`, `/Users/yangping/Studio/side-project/scheduleNote/server/lib/routes/event_routes.dart:568` |
| Record metadata sync (name/phone/record_number) | Will Fail (consistency) | Event detail loads server event, but name/phone used in UI come from local record row; local record refresh from server is incomplete and can overwrite newer remote data on save. | `/Users/yangping/Studio/side-project/scheduleNote/lib/screens/event_detail/event_detail_controller.dart:140`, `/Users/yangping/Studio/side-project/scheduleNote/lib/screens/event_detail/event_detail_controller.dart:745`, `/Users/yangping/Studio/side-project/scheduleNote/lib/services/database/prd_database_service.dart:277` |
| `record_uuid` identity convergence across devices | Will Fail (core) | Client generates local record UUID; server creates/updates records keyed by UUID, not by canonical `(name, record_number)` uniqueness; cross-device same person can fork into different `record_uuid`s. | `/Users/yangping/Studio/side-project/scheduleNote/lib/services/database/mixins/record_operations_mixin.dart:17`, `/Users/yangping/Studio/side-project/scheduleNote/server/lib/routes/event_routes.dart:351`, `/Users/yangping/Studio/side-project/scheduleNote/server/lib/routes/event_routes.dart:380`, `/Users/yangping/Studio/side-project/scheduleNote/server/schema.sql:136` |
| Note sync by `record_uuid` + conflict handling | Mostly Works | Server supports 409 conflict with version guard; client has retry/merge flow for note conflicts. | `/Users/yangping/Studio/side-project/scheduleNote/server/lib/services/note_service.dart:124`, `/Users/yangping/Studio/side-project/scheduleNote/server/lib/routes/note_routes.dart:463`, `/Users/yangping/Studio/side-project/scheduleNote/lib/screens/event_detail/event_detail_controller.dart:485` |
| Note near real-time freshness while editing | Will Fail (UX freshness) | Note is fetched on load; no periodic pull in event-detail screen, so concurrent remote edits are not reflected within <1 minute unless reopen/reload flow happens. | `/Users/yangping/Studio/side-project/scheduleNote/lib/screens/event_detail/event_detail_controller.dart:193`, `/Users/yangping/Studio/side-project/scheduleNote/lib/screens/event_detail/event_detail_controller.dart:205`, `/Users/yangping/Studio/side-project/scheduleNote/lib/screens/event_detail/event_detail_controller.dart:167` |
| Batch note contract consistency | Will Fail (if enabled) | Client sends `eventIds` but server expects `record_uuids` in `/api/notes/batch`. | `/Users/yangping/Studio/side-project/scheduleNote/lib/services/api_client.dart:601`, `/Users/yangping/Studio/side-project/scheduleNote/server/lib/routes/note_routes.dart:679` |
| Record endpoint safety affecting multi-device trust | Will Fail (security/integrity risk) | `/api/records/*` routes do not enforce device credentials; any caller can mutate record metadata if endpoint is reachable. | `/Users/yangping/Studio/side-project/scheduleNote/server/lib/routes/record_routes.dart:12`, `/Users/yangping/Studio/side-project/scheduleNote/server/lib/routes/record_routes.dart:135` |

## Top Multi-Device Failure Scenarios

1. Same patient created on two devices at similar time can get two different server `record_uuid`s. Notes then split by UUID and stop being truly shared.
2. Device B updates name/phone, Device A opens stale local record view, then save pushes stale metadata back (LWW overwrite with stale base).
3. Event-detail note screen does not auto-refresh frequently; users on two devices see stale note state until manual reopen/refresh path.
4. If batch note path is used, sync breaks due request contract mismatch (`eventIds` vs `record_uuids`).

## Priority Fix Roadmap

### P0 (must do before calling app “multi-device ready”)

1. Enforce canonical record identity on server.
- Add server uniqueness policy for non-empty record identity (at least `(record_number, name)` or a stricter chosen key).
- Replace UUID-only upsert in event-create path with server-side identity resolution that returns canonical `record_uuid`.

2. Make record metadata read/write truly server-authoritative.
- On event-detail load, use server record payload as source for name/phone.
- On save, guard against stale local record overwrite (compare server `updated_at`/version first, then LWW explicitly).

3. Secure record routes with device auth and book-scope authorization.
- Add `x-device-id`/`x-device-token` validation to `/api/records/*` mutation/read routes (or remove direct public record routes and keep book-scoped only).

### P1 (strongly recommended)

1. Fix `/api/notes/batch` contract alignment.
- Choose one payload shape and update client + server + OpenAPI consistently.

2. Add active note freshness polling in event detail (30–60s while screen visible) or push-based refresh.
- Keep your no-offline requirement and near-real-time target aligned for notes, not only schedule list.

3. Add dedicated multi-device tests.
- Two-device integration tests for: same-record concurrent create, concurrent metadata update, concurrent note edit conflict/resolution.

### P2 (hardening)

1. Review global book visibility (`listBooksForDevice` currently unfiltered).
- Decide intended policy and restrict if needed.

2. Align schema artifacts with runtime assumptions.
- Runtime queries use `ON CONFLICT (record_uuid)` and `ON CONFLICT (record_uuid)` patterns; ensure schema/migrations explicitly include required unique constraints and are versioned.

## Final Assessment

For your target (server source-of-truth + near-real-time + multi-device shared record/note), the app is **not yet reliable** due to record identity convergence and metadata consistency gaps.  
After P0 fixes, the core multi-device experience should become stable; P1 completes near-real-time behavior for notes and removes contract fragility.
