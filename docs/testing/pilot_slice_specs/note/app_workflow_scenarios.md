# App Workflow Scenarios (Note)

## WF-NOTE-01 Open Event Detail Note
- Real case: user opens an event detail page and note is loaded.
- Purpose: ensure note lookup resolves through event -> record mapping.

## WF-NOTE-02 Save Note
- Real case: user writes strokes and saves note.
- Purpose: ensure insert/update writes and version progression.

## WF-NOTE-03 Delete Note Cache
- Real case: user clears cached note for an event context.
- Purpose: ensure delete targets the note by record link.

## WF-NOTE-04 Book Note Listing
- Real case: app aggregates notes under one book.
- Purpose: ensure one note per record is returned (distinct behavior).

## WF-NOTE-05 Batch Cache Operations
- Real case: app preloads/saves multiple notes in batch.
- Purpose: ensure batch save/get consistency and missing-key handling.

## WF-NOTE-06 Apply Note Sync Changes
- Real case: app applies server note updates locally.
- Purpose: ensure upsert semantics for incoming note payloads.
