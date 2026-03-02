# Event Create/Update Latency Audit

Date: March 2, 2026

Scope: Event create/update flow in the Flutter client and Dart server.

Method: Static code-path audit only. This document does not include fresh live benchmark numbers because no active benchmark environment was provided during this pass. The repo does include a benchmark harness at `tool/benchmark_event_500_strokes.dart`.

## Architecture Decision Update

Confirmed direction for follow-up work:

- The app should support server-only behavior for event/record content.
- Offline behavior for event/record content is no longer required.
- Local event/record cache should be removed or minimized rather than preserved.
- Drawing behavior should keep local in-memory buffering and debounced/queued server sync.
- Drawing must not regress into per-stroke server uploads.

Implication:

- `PRDDatabaseService` should not remain the local content store for events/records/notes.
- A minimal local store may still be needed for server URL, device credentials, and similar app configuration.
- Drawing can keep its current UX without `PRDDatabaseService` because its anti-chattiness comes from in-memory canvas state plus debounced/queued saves, not from SQLite event/record cache.

## Executive Summary

The event create/update path is not a single write. In the common "save event with note" case it is a pipeline:

1. Local record resolution and local event write.
2. Optional local existing-note lookup by record number.
3. Async remote note sync.
4. Async remote event metadata sync.
5. Async remote record sync.
6. Sometimes an extra remote fetch to recover from record UUID remap.
7. Sometimes an extra local event rewrite after the server remaps `record_uuid`.

The largest latency contributors are:

- A serial remote sync order that does note save first, then event update, then record update.
- Read-before-write note saving on the client.
- Server note saving that decodes the full note payload and recomputes `has_note` for every event tied to the record.
- Recovery paths that add extra network round-trips on new events or record remaps.

If the user perceives save latency during create/update, the primary fix is not local SQLite work. The dominant cost is the remote write pipeline around note persistence.

## Current Processing

### 1. Client local save path

`saveEvent()` first writes locally through `PRDDatabaseService`, then kicks off async server sync instead of waiting for remote completion.

Relevant code:

- `lib/screens/event_detail/event_detail_controller.dart:373`
- `lib/screens/event_detail/event_detail_controller.dart:424`
- `lib/screens/event_detail/event_detail_controller.dart:494`
- `lib/services/database/prd_database_service.dart:556`
- `lib/services/database/prd_database_service.dart:594`

Current local steps for create:

1. Resolve or create a record with `getOrCreateRecord()`.
2. Create the local event row.
3. If record number is present, look up an existing note for that record.
4. Start async server sync.

Current local steps for update:

1. Possibly resolve a different record when record number changes.
2. Possibly update the existing record name/phone.
3. Update the local event row.
4. If a record number was newly added, look up an existing note for that record.
5. Start async server sync.

Local DB cost exists, but it is small compared with the remote pipeline. The main local inefficiency is that the helper methods use multiple independent queries instead of a transaction-based save bundle.

### 2. Client async remote sync order

The remote sync order is explicitly serial:

1. Save note if the note changed.
2. Sync event metadata.
3. Sync record metadata.

Relevant code:

- `lib/screens/event_detail/event_detail_controller.dart:647`
- `lib/screens/event_detail/event_detail_controller.dart:663`
- `lib/screens/event_detail/event_detail_controller.dart:674`
- `lib/screens/event_detail/event_detail_controller.dart:892`

This means note latency sits directly on the critical path of the remote write pipeline. Even though the UI returns earlier, the overall save completion and any "unsynced" state stay open until the slowest step finishes.

### 3. Client note save path

Before sending a note write, the client does more work than necessary:

1. Reload the local event by ID.
2. Fetch the current note from the server by `record_uuid`.
3. Merge erase maps and compute the next version.
4. POST the full serialized `pagesData`.
5. On conflict, fetch the note again and retry up to two times.

Relevant code:

- `lib/screens/event_detail/event_detail_controller.dart:521`
- `lib/screens/event_detail/event_detail_controller.dart:537`
- `lib/screens/event_detail/event_detail_controller.dart:542`
- `lib/screens/event_detail/event_detail_controller.dart:706`
- `lib/services/content_service.dart:241`
- `lib/services/api_client.dart:496`

This makes every note save at least one read plus one write, even when there is no conflict.

### 4. Server note save path

The note endpoint is the heaviest part of the pipeline.

Relevant code:

- `server/lib/routes/note_routes.dart:485`
- `server/lib/services/note_service.dart:204`

Current server steps for `POST /api/books/:bookUuid/events/:eventId/note`:

1. Parse the full request body.
2. Verify device credentials.
3. Verify book access.
4. Look up the event to find `record_uuid`.
5. If event is missing and `eventData` is present, create the record and event first.
6. Read existing note row by `record_uuid`.
7. Insert or update note row.
8. Decode the full `pagesData` JSON.
9. Walk every page and every stroke to rebuild event-to-stroke ownership.
10. Query every event tied to the same `record_uuid`.
11. Issue one `UPDATE events SET has_note = ...` per related event.

The expensive part is not only the note write itself. The endpoint also performs derived-state recomputation by reprocessing the entire note payload.

### 5. Server event metadata path

The event update route is simpler than note save, but it still has extra round-trips:

1. Authorize book access.
2. Read request JSON.
3. Fetch current event row for version.
4. Update event row.
5. Re-read joined event row for response.

Relevant code:

- `server/lib/routes/event_routes.dart:760`

On the client side, metadata sync may add more calls:

1. `PATCH /events/:id`
2. Fallback to `POST /events` on 404 for new events
3. `PATCH /records/:recordUuid`
4. Fallback `GET /events/:id` and second `PATCH /records/:recordUuid` when server remaps the record UUID

Relevant code:

- `lib/screens/event_detail/event_detail_controller.dart:928`
- `lib/screens/event_detail/event_detail_controller.dart:947`
- `lib/screens/event_detail/event_detail_controller.dart:980`
- `lib/screens/event_detail/event_detail_controller.dart:998`

## Bottlenecks

### A. Read-before-write note sync

Impact: High

Evidence:

- `lib/screens/event_detail/event_detail_controller.dart:542`
- `lib/services/content_service.dart:204`

Every note save fetches the current server note before attempting the write. That guarantees an extra network round-trip even when there is no conflict. For large note payloads or higher latency networks, this becomes one of the most visible costs.

### B. Serial remote sync chain

Impact: High

Evidence:

- `lib/screens/event_detail/event_detail_controller.dart:663`
- `lib/screens/event_detail/event_detail_controller.dart:674`

Note save, event sync, and record sync are serialized. A slow note upload delays the entire remote completion path. Event metadata and record metadata are not being used to hide note latency.

### C. Full note reparse plus per-event updates on every note save

Impact: High

Evidence:

- `server/lib/services/note_service.dart:280`
- `server/lib/services/note_service.dart:295`
- `server/lib/services/note_service.dart:310`
- `server/lib/services/note_service.dart:325`

The server decodes the full note payload, scans all strokes, fetches all events for the record, and updates each event individually. This scales with note size and with the number of events tied to the same record.

### D. New-event fallback and record remap retries

Impact: Medium to High

Evidence:

- `lib/screens/event_detail/event_detail_controller.dart:937`
- `lib/screens/event_detail/event_detail_controller.dart:988`

New-event sync can hit `PATCH -> 404 -> POST`. Record sync can hit `PATCH -> 404 -> GET event -> PATCH again`. These are avoidable extra network hops.

### E. Duplicate auth/access lookups on the server

Impact: Medium

Evidence:

- `server/lib/routes/note_routes.dart:538`
- `server/lib/routes/note_routes.dart:549`
- `server/lib/services/book_access_service.dart:17`
- `server/lib/services/book_access_service.dart:32`

The note path verifies device access, verifies book access, and may check device role again. Individually these are cheap; together they add extra database lookups to the hottest write endpoint.

### F. Local save bundle is not transactional

Impact: Low to Medium

Evidence:

- `lib/services/database/mixins/record_operations_mixin.dart:80`
- `lib/services/database/prd_database_service.dart:556`
- `lib/services/database/prd_database_service.dart:594`
- `lib/services/database/mixins/event_operations_mixin.dart:78`
- `lib/services/database/mixins/event_operations_mixin.dart:90`

Local save is spread across separate queries and helper calls. This is not likely the dominant user-visible latency, but it adds overhead and makes the pipeline harder to reason about.

## Recommended Optimizations

### Priority 1: Stop doing a preflight note read on every save

Change:

- Send the note write immediately using the current local version.
- Only fetch and merge on `409 conflict`.

Why:

- Removes one network round-trip from the common case.
- Keeps conflict handling behavior without paying the cost every time.

Expected effect:

- Best immediate win for note-heavy saves.

Implementation targets:

- `lib/screens/event_detail/event_detail_controller.dart:521`
- `lib/services/content_service.dart:241`
- `server/lib/routes/note_routes.dart:620`

### Priority 2: Collapse event + note + record into one server mutation for save

Change:

- Add a dedicated endpoint or RPC for "save event detail" that accepts event metadata, record metadata, and optional note payload in one request.
- Return authoritative event, record, and note state in one response.

Why:

- Replaces a multi-call client orchestration with one server transaction boundary.
- Eliminates `PATCH -> 404 -> POST` fallback behavior.
- Eliminates the `GET event` retry path for record remaps.

Expected effect:

- Largest structural latency reduction.
- Also reduces sync consistency bugs.
- Matches the target architecture of server-only event/record content.

Implementation targets:

- `lib/screens/event_detail/event_detail_controller.dart:647`
- `server/lib/routes/event_routes.dart`
- `server/lib/routes/note_routes.dart`

### Priority 3: Stop recomputing `has_note` by rescanning the full note blob

Change:

- Track per-event note contribution incrementally.
- Send `changedEventIds` or per-event stroke counts in the note payload.
- Update only affected events.

Why:

- Current implementation scales with total note size, not with the size of the actual change.
- It also performs one database update per related event.

Expected effect:

- Major reduction in server CPU and write amplification for large or long-lived notes.

Implementation targets:

- `server/lib/services/note_service.dart:280`

### Priority 4: Parallelize event metadata update and record update where safe

Change:

- Once the server has authoritative event identity, update event and record in parallel, or let the unified save endpoint handle both inside one transaction.

Why:

- Current client path waits for each network step in sequence.

Expected effect:

- Moderate latency reduction for metadata-only edits.

Implementation targets:

- `lib/screens/event_detail/event_detail_controller.dart:928`
- `lib/screens/event_detail/event_detail_controller.dart:980`

### Priority 5: Cache or fuse auth/access checks on the write endpoints

Change:

- Resolve device validity, role, and book access once per request.
- Pass the result through the request context instead of re-querying.

Why:

- Reduces database chatter on the hottest endpoints.

Expected effect:

- Small to moderate gain, but easy to stack with larger fixes.

Implementation targets:

- `server/lib/routes/note_routes.dart:538`
- `server/lib/services/book_access_service.dart:32`

### Priority 6: Wrap local create/update save bundles in a transaction

Change:

- Bundle record lookup/create/update and event write in one SQLite transaction.

Why:

- Reduces local round-trips and removes partial-write edge cases.

Expected effect:

- Smaller user-visible latency improvement than the network fixes, but worthwhile cleanup.

Implementation targets:

- `lib/services/database/prd_database_service.dart:556`
- `lib/services/database/prd_database_service.dart:594`

Note:

- If server-only event/record content is adopted, this should be treated as a temporary bridge only, not a long-term optimization target.

### Priority 7: Replace local event/record cache with minimal local config storage

Change:

- Remove `PRDDatabaseService` from event/record/note content flows.
- Keep only a minimal local store for server URL, device credentials, and app/session settings.
- Move event detail load/save to server-backed repositories and server-authoritative responses.

Why:

- The local content cache no longer aligns with the desired architecture.
- It preserves hybrid complexity without delivering needed offline value.

Expected effect:

- Simplifies the write path.
- Removes stale local content as a source of truth.
- Keeps drawing behavior intact if drawing remains in-memory buffered with debounced saves.

## Suggested Rollout Order

1. Remove note preflight read and rely on optimistic write with conflict fallback.
2. Add timing instrumentation around local save, note POST, event PATCH/POST, record PATCH, and retry paths.
3. Redesign server note save so `has_note` updates are incremental rather than full-note rescans.
4. Replace the multi-call event detail save with one server mutation.

## Measurement Gaps

This repo already has a useful starting benchmark:

- `tool/benchmark_event_500_strokes.dart:165`

It measures:

- Event create time
- Note save time for a 500-stroke payload
- Combined event create plus note save time

What is still missing:

- Separate timing for client local save vs remote sync
- Timing for metadata-only update without note changes
- Timing for note saves when a record has many linked events
- Timing for conflict retry cases
- P50/P95 numbers captured from the real target deployment

## Bottom Line

The current latency is mainly a pipeline design issue, not a single slow function.

The highest-value fixes are:

1. Remove the note read-before-write preflight.
2. Stop rescanning the whole note payload on every save to compute `has_note`.
3. Replace the multi-request client orchestration with one server-side save mutation.
