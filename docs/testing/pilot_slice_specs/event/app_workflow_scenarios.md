# App Workflow Scenarios (Event)

## WF-EVENT-01 View Event List
- Real case: user opens schedule and events are loaded for the selected book/date.
- Purpose: ensure filtering and ordering logic returns correct events.

## WF-EVENT-02 Create Event
- Real case: user creates a new appointment in schedule.
- Purpose: ensure event is persisted with valid lifecycle fields.

## WF-EVENT-03 Update Event
- Real case: user edits event metadata (title/type).
- Purpose: ensure version and persistence behavior are correct.

## WF-EVENT-04 Delete Event
- Real case: user permanently deletes a mistaken event.
- Purpose: ensure event row is removed and missing-target behavior is explicit.

## WF-EVENT-05 Remove Event (Soft Delete)
- Real case: user marks event as removed with a reason.
- Purpose: ensure removal state and reason validation.

## WF-EVENT-06 Change Event Time
- Real case: user reschedules to a new time.
- Purpose: ensure original event is removed, new event is created, and linkage is preserved.

## WF-EVENT-07 Apply Sync Changes
- Real case: app pulls server changes and applies them locally.
- Purpose: ensure upsert behavior for incoming event changes.
