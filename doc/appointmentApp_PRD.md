Product Requirements Document (PRD)

Appointment Registration App

1. Overview

The Appointment Registration App is a cross-platform mobile application (Android & iOS) designed to help a Registrant create, manage, and annotate appointments. It provides a Google Calendar–like scheduling system combined with a handwriting-only note-taking interface, structured in a clear hierarchy: Book → Schedule → Event → Note.

2. Objectives

The system is designed to provide a focused, lightweight, and intuitive registration workflow.

Hierarchy of Data

Book – Top-level container, representing an independent schedule (e.g., Doctor A, Doctor B).

Schedule – Calendar-like view within a Book to manage time slots and events.

Event – Individual appointment entry with minimal metadata.

Note – Handwriting-only note page linked to a single event.

Key Objectives

Support multiple independent Books, each with its own Schedule and Events.

Provide calendar-style scheduling per Book for creating and managing events.

Restrict Event metadata to Name, Record Number, and Event Type for simplicity.

Link each Event to a handwriting-only Note page (stylus/finger input, no text/images).

Ensure the app works offline-first, with optional PostgreSQL sync.

3. Key Features
3.1 Book Management

Create multiple Books (e.g., Doctor A, Doctor B).

Rename, archive, or delete Books.

Switch seamlessly between Books, with full data isolation.

3.2 Schedule (within each Book)

Views:

Day View

3-Day View (starting from today)

Week View

Tap/drag to create Events.

Select to edit or delete Events.

Visual indicators for event density per time slot.

3.3 Event Metadata

Each Event contains only:

Name

Record Number

Event Type

Default behavior:

Start time is required.

End time is optional (open-ended by default).

3.4 Notes (linked to Event)

Each Event has one dedicated Note page.

Handwriting features:

Stylus/finger input.

Eraser, undo/redo.

Auto-save.

Notes remain permanently linked to their Event.

No typed text, image insertion, or attachments.

4. Non-Functional Requirements
4.1 Cross-Platform

Built with Flutter (preferred) or React Native.

Adaptive UI for phones and tablets.

4.2 Performance

Handwriting latency <30ms.

Calendar view switching <200ms.

Support up to 500,000 Events per Book with proper indexing.

4.3 Offline-First

Full functionality offline:

Create/edit/delete Events.

Write and store Notes.

Switch between Books.

Cloud sync is optional.

4.4 Data Separation & Integrity

Each Book is fully isolated.

Integrity rules:

Events require a start time.

End time optional.

Notes cannot exist without an Event.

4.5 Security & Privacy

Local: Encrypted SQLite (SQLCipher).

Cloud: PostgreSQL for sync backend.

TLS encryption in transit.

Row-Level Security (RLS) per Book.

No third-party data sharing.

4.6 Reliability

Auto-save for Notes and Events.

Crash recovery with journaled writes.

Local backups per Book.

5. User Stories
Book Management

As a Registrant, I want to create separate Books (e.g., “Doctor A” and “Doctor B”) so I can keep schedules independent.

As a Registrant, I want to switch between Books easily to manage different contexts.

As a Registrant, I want to archive or delete a Book when no longer needed.

Schedule Management

As a Registrant, I want to view appointments in Day, 3-Day, or Week views.

As a Registrant, I want to quickly create an Event with only a start time required.

As a Registrant, I want the option to add an end time if needed.

As a Registrant, I want to edit or delete Events directly from the schedule.

Event Metadata

As a Registrant, I want each Event to store only Name, Record Number, and Event Type.

As a Registrant, I want to quickly see Event metadata at a glance.

Notes (Handwriting Only)

As a Registrant, I want to handwrite notes for each Event naturally with finger/stylus.

As a Registrant, I want handwriting to feel smooth with <30ms latency.

As a Registrant, I want undo/redo and eraser tools when writing.

As a Registrant, I want notes to auto-save and remain linked to the Event.

Data & Reliability

As a Registrant, I want all data to be stored locally first for offline use.

As a Registrant, I want data to optionally sync to a PostgreSQL backend for multi-device access.

As a Registrant, I want Book-level isolation so no data leaks across Books.

As a Registrant, I want my data to survive app restarts and crashes.

6. Technical Considerations
Platform & Framework

Flutter (Skia rendering, better handwriting support).

Target iOS 15+ and Android 8+.

Data Model

Book → multiple Events → each Event has Note.

Event metadata: Name, Record Number, Event Type, Start Time, optional End Time.

Notes stored as vector strokes (JSON/Protobuf) with optional raster snapshot for previews.

Local Storage

SQLite (encrypted).

Drift/Moor for schema migrations.

Indexed queries for fast Day/3-Day/Week lookups.

Cloud Sync (Optional)

PostgreSQL with RLS per Book.

Sync strategy: last-write-wins for Events; stroke-based incremental sync for Notes.

Incremental pull by updated_at.

Deletes tracked via tombstones.

Handwriting Engine

Flutter CustomPainter for stroke rendering.

Pressure-sensitive width mapping.

Undo/redo via stroke history stack.

Auto-save after idle debounce.

Security

Local encryption via SQLCipher.

Cloud sync: TLS + JWT auth.

Reliability

Auto-save + crash recovery.

Daily local backups per Book.

7. Risks & Constraints

Performance challenges at 500k Events per Book if indexes/queries are poorly optimized.

Achieving <30ms handwriting latency consistently across low-end devices may be difficult.

Large Note storage may cause device space issues; compression required.

Limiting metadata to 3 fields may reduce flexibility for broader use cases.

Conflict resolution during sync could cause occasional overwrites without careful versioning.

8. Future Enhancements

Search/filter for Events by metadata.

Shared Books (multi-Registrant collaboration).

OCR/handwriting recognition for searchable notes.

Recurring events support.

Google Calendar / iCal integration.

Desktop & Web clients.

AI assistance for auto-tagging notes and suggesting Event Types.