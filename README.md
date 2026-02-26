# Schedule Note App

A Flutter appointment scheduling application with handwriting notes capability.

**Version:** 2.1.0
**Total Dart Files:** 98 (58 in lib/, 18 tests)
**Architecture:** Clean Architecture + BLoC Pattern

## Overview

This is a cross-platform appointment scheduling app built with Flutter that allows users to:
- Create and manage appointment books
- Schedule events with different views (Day, 3-Day, Week)
- Take handwriting notes for each appointment
- Archive and manage appointment books

## Features

- **Multi-platform support**: Web
- **Appointment Books**: Create and organize multiple appointment books
- **Schedule Views**: Day, 3-Day, and Week calendar views
- **Event Management**: Create, edit, and delete appointments
- **Handwriting Notes**: Take handwritten notes for each appointment
- **Archive System**: Archive old appointment books

## Prerequisites

- Flutter SDK (>=3.0.0)
- Dart SDK (>=3.0.0)

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd scheduleNote
```

2. Get Flutter dependencies:
```bash
flutter pub get
```

## Running the App

### Web

**Default web port (auto-assigned):**
```bash
flutter run -d chrome
```

**Custom web port:**
```bash
flutter run -d chrome --web-port=8080
```

## Testing

Run unit tests:
```bash
flutter test
```

Run integration tests:
```bash
flutter test integration_test/
```

Use Supabase as backend database (recommended architecture):
```bash
# in /Users/yangping/Studio/side-project/scheduleNote/.env
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_KEY=<service-role-or-secret-key>
```

Then run the API server from `/Users/yangping/Studio/side-project/scheduleNote/server`
and connect the app to your server URL via the setup screen.

Before starting server, run in Supabase SQL editor:
- `/Users/yangping/Studio/side-project/scheduleNote/server/schema.sql`

Run live server metadata smoke test (auto-create fixture IDs):
```bash
SN_TEST_BASE_URL=https://<your-server-base-url> \
SN_TEST_DEVICE_ID=<device-id> \
SN_TEST_DEVICE_TOKEN=<device-token> \
dart run tool/create_event_metadata_fixture.dart

flutter test test/app/integration/event_metadata_server_smoke_test.dart
```

## Project Structure

```
lib/
├── models/                  # Data models (8 files - Book, Event, Note, ScheduleDrawing)
├── repositories/            # Data access layer (12 files - Repository pattern)
│   ├── book_repository.dart           # Book repository interface
│   ├── book_repository_impl.dart      # SQLite implementation
│   ├── event_repository.dart          # Event repository interface
│   ├── event_repository_impl.dart     # SQLite implementation
│   ├── note_repository.dart           # Note repository interface
│   ├── note_repository_impl.dart      # SQLite implementation
│   ├── drawing_repository.dart        # Drawing repository interface
│   ├── drawing_repository_impl.dart   # SQLite implementation
│   ├── device_repository.dart         # Device credentials interface
│   └── device_repository_impl.dart    # SQLite implementation
├── services/                # Business logic and external services (17 files, 216 KB)
│   ├── database_service_interface.dart  # Database interface
│   ├── prd_database_service.dart        # SQLite database service
│   ├── web_prd_database_service.dart    # Web database service
│   ├── note_content_service.dart        # Note operations
│   ├── drawing_content_service.dart     # Drawing operations
│   ├── api_client.dart                  # Server API client
│   ├── content_service.dart             # Legacy compatibility facade (deprecated)
│   ├── book_order_service.dart          # Book ordering
│   ├── time_service.dart                # Time utilities
│   └── service_locator.dart             # Dependency injection
├── cubits/                  # State management (8 files - BLoC pattern)
│   ├── book_list_cubit.dart       # Book list state management
│   ├── book_list_state.dart       # Book list states
│   ├── schedule_cubit.dart        # Schedule state management
│   ├── schedule_state.dart        # Schedule states
│   ├── event_detail_cubit.dart    # Event detail state management
│   └── event_detail_state.dart    # Event detail states
├── screens/                 # UI screens
│   ├── book_list/                 # Book list feature (provider-based controller + dialogs/widgets)
│   ├── schedule/                  # Schedule subcomponents and services
│   ├── event_detail/              # Event detail feature (modularized)
│   ├── book_list_screen.dart      # Book list entry point
│   ├── schedule_screen.dart       # Schedule view (controller + services)
│   └── event_detail_screen.dart   # Exports refactored event detail
├── widgets/                 # Reusable widgets
│   ├── handwriting_canvas.dart    # Core handwriting widget
│   └── schedule/                  # Schedule-specific widgets
├── painters/                # Custom painters
│   └── schedule_painters.dart    # Custom paint operations for schedule
├── utils/                   # Utilities
│   └── schedule/                 # Schedule-specific utilities (layout, cache, tests)
├── l10n/                    # Localization files
├── app.dart                 # Main app configuration
└── main.dart                # App entry point

doc/
├── appointmentApp_PRD.md    # Product Requirements Document
└── refactor/                # Refactoring documentation
    ├── 00_overview.md       # Refactoring overview
    ├── phase1_foundation.md
    ├── phase2_database_layer.md
    ├── phase3_service_layer.md
    ├── phase4_state_management.md
    ├── phase5_screen_refactor.md
    ├── phase6_cleanup.md
    └── phase7_validation.md

test/                        # 18 test files
├── characterization/        # Behavior preservation tests
│   ├── database_operations_test.dart
│   └── cache_behavior_test.dart
├── diagnostics/             # Diagnostic tools (6 files)
│   ├── note_persistence_diagnosis.dart
│   ├── canvas_state_diagnosis.dart
│   ├── event_flow_diagnosis.dart
│   ├── bug_fix_verification.dart
│   ├── verify_time_change_fix.dart
│   └── update_server_url.dart
├── repositories/            # Repository unit tests
│   └── book_repository_test.dart
├── cubits/                  # Cubit unit tests
│   ├── book_list_cubit_test.dart
│   └── book_list_cubit_test.mocks.dart
├── services/                # Service tests (4 files)
│   ├── prd_database_service_test.dart
│   ├── cache_manager_test.dart
│   ├── content_service_test.dart
│   └── cache_policy_db_test.dart
├── screens/                 # Screen widget tests
│   ├── schedule_screen_behavior_test.dart
│   └── schedule_screen_preload_test.dart
└── models/                  # Model tests
    └── cache_policy_test.dart
```

## Database

### Active Implementation
- **Mobile/Desktop**: SQLite with sqflite package (`PRDDatabaseService`)
- **Web**: In-memory storage (`WebPRDDatabaseService`)
- **Interface**: Both implement `IDatabaseService` for type safety

### Schema
```sql
books (id, name, created_at, archived_at)
events (id, book_id, name, record_number, event_type, start_time, end_time, ...)
notes (id, event_id, strokes_data, ...)
schedule_drawings (id, book_id, date, view_mode, strokes_data, ...)
```

## Architecture

### Current Architecture (Clean Architecture + BLoC Pattern)

```
┌─────────────────────────────────────────────────────────────┐
│                     Presentation Layer                      │
│  ┌────────────┐  ┌────────────┐  ┌────────────────┐        │
│  │ BookList   │  │ Schedule   │  │ EventDetail    │        │
│  │ Screen     │  │ Screen     │  │ Screen         │        │
│  └─────┬──────┘  └─────┬──────┘  └────────┬───────┘        │
│        │                │                  │                 │
│        v                v                  v                 │
│  ┌────────────┐  ┌────────────┐  ┌────────────────┐        │
│  │ BookList   │  │ Schedule   │  │ EventDetail    │        │
│  │ Cubit      │  │ Cubit      │  │ Cubit          │        │
│  └─────┬──────┘  └─────┬──────┘  └────────┬───────┘        │
└────────┼────────────────┼───────────────────┼────────────────┘
         │                │                   │
┌────────┼────────────────┼───────────────────┼────────────────┐
│        │    Business Logic Layer            │                │
│        v                v                   v                │
│  ┌─────────────────────────────────────────────────┐        │
│  │  NoteContentService                             │        │
│  │  DrawingContentService                          │        │
│  │  ApiClient + Server APIs                        │        │
│  │  BookOrderService                               │        │
│  └─────────┬───────────────────────────────────────┘        │
└────────────┼──────────────────────────────────────────────────┘
             │
┌────────────┼──────────────────────────────────────────────────┐
│            │       Data Access Layer (Repository Pattern)     │
│            v                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │ Book         │  │ Event        │  │ Note         │        │
│  │ Repository   │  │ Repository   │  │ Repository   │        │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘        │
│         │                  │                  │                │
│         v                  v                  v                │
│  ┌────────────────────────────────────────────────────┐       │
│  │         PRDDatabaseService / IDatabaseService      │       │
│  └────────────────────────┬───────────────────────────┘       │
└───────────────────────────┼─────────────────────────────────────┘
                            │
┌───────────────────────────┼─────────────────────────────────────┐
│                           │        Infrastructure Layer         │
│                           v                                     │
│  ┌──────────────────┐  ┌──────────────────┐                   │
│  │ SQLite           │  │ Web Storage      │                   │
│  │ (Mobile/Desktop) │  │ (Browser)        │                   │
│  └──────────────────┘  └──────────────────┘                   │
└─────────────────────────────────────────────────────────────────┘
```

### Data Hierarchy
**Books** → **Events** → **Notes**
- Each Book contains multiple Events
- Each Event can have one Note (handwriting)
- Schedule Drawings are overlay annotations on schedule views

### Key Principles

1. **Separation of Concerns**: Clear boundaries between presentation, business logic, and data access
2. **Dependency Injection**: Using `get_it` for service locator pattern
3. **State Management**: BLoC/Cubit pattern for predictable state handling
4. **Repository Pattern**: Abstract data access behind repository interfaces
5. **Type Safety**: Interfaces for all major components (repositories, services)
6. **Testability**: All layers can be tested independently with mocks
7. **Platform Adaptation**: Automatic selection of appropriate implementations

### Refactoring Progress (v2.1.0)

This app has undergone a comprehensive refactoring:
- **Phase 1**: Foundation setup (dependency injection, repository interfaces) ✅
- **Phase 2**: Database layer extraction (repository implementations) ✅
- **Phase 3**: Service layer cleanup (focused services) ✅
- **Phase 4**: BLoC/Cubit state management ✅
- **Phase 5**: Screen refactoring 🔄
  - BookListScreen: ✅ Complete (BLoC version in `screens/book_list/`)
  - ScheduleScreen: 🔄 **In Progress** (extracting widgets to `lib/widgets/schedule/`, painters to `lib/painters/`)
  - EventDetailScreen: ⏳ Pending
- **Phase 6**: Cleanup and standardization (legacy code removed) ✅
- **Phase 7**: Final validation ⏳

**Code Reduction**: ~4,239 lines of legacy code removed
**Documentation Cleanup**: 12 guide files consolidated

## Legacy Code

The legacy code directory has been removed as part of Phase 6 cleanup. Approximately 4,239 lines of outdated code were deleted, including:
- Old Provider-based state management
- Deprecated service implementations
- Unused screen implementations
- Old Appointment model

All functionality has been replaced with the new Clean Architecture + BLoC implementation.

## Current Development Status

### Active Work: ScheduleScreen Refactoring
The `schedule_screen.dart` (2,004 lines) is currently being refactored using a component extraction strategy:

**Strategy:**
1. Extract reusable widgets to `lib/widgets/schedule/`
2. Extract custom painters to `lib/painters/`
3. Extract utility functions to `lib/utils/schedule/`
4. Keep core screen logic with Cubit state management

**Progress Indicators:**
- Multiple temporary refactor snapshots exist for `schedule_screen.dart`
- New directories created: `lib/widgets/schedule/`, `lib/painters/`
- Widget extraction in progress: `event_tile.dart`, `fab_menu.dart`, `drawing_toolbar.dart`, `test_menu.dart`

**Next Steps:**
1. Complete widget extraction from schedule_screen.dart
2. Integrate extracted components with ScheduleCubit
3. Remove temporary snapshots once refactoring is stable
4. Apply same pattern to EventDetailScreen

## Development

This project follows the Product Requirements Document located in `doc/appointmentApp_PRD.md`.

For development guidelines and architecture decisions, refer to the PRD.
