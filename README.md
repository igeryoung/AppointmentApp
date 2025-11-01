# Schedule Note App

A Flutter appointment scheduling application with handwriting notes capability.

## Overview

This is a cross-platform appointment scheduling app built with Flutter that allows users to:
- Create and manage appointment books
- Schedule events with different views (Day, 3-Day, Week)
- Take handwriting notes for each appointment
- Archive and manage appointment books

## Features

- **Multi-platform support**: Android, iOS, Web, macOS
- **Appointment Books**: Create and organize multiple appointment books
- **Schedule Views**: Day, 3-Day, and Week calendar views
- **Event Management**: Create, edit, and delete appointments
- **Handwriting Notes**: Take handwritten notes for each appointment
- **Archive System**: Archive old appointment books

## Prerequisites

- Flutter SDK (>=3.0.0)
- Dart SDK (>=3.0.0)
- For mobile development:
  - Android Studio with Android SDK
  - Xcode (for iOS development on macOS)

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

### Mobile Platforms

**Android:**
```bash
flutter run -d android
```

**iOS (macOS only):**
```bash
flutter run -d ios
```

**iOS Simulator:**
```bash
flutter run -d apple_ios_simulator
```

### Desktop Platforms

**macOS:**
```bash
flutter run -d macos
```

**Windows:**
```bash
flutter run -d windows
```

**Linux:**
```bash
flutter run -d linux
```

### Web Platform

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

## Project Structure

```
lib/
├── models/                  # Data models (Book, Event, Note, ScheduleDrawing)
├── repositories/            # Data access layer (Repository pattern)
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
├── services/                # Business logic and external services
│   ├── database_service_interface.dart  # Database interface
│   ├── prd_database_service.dart        # SQLite database service
│   ├── web_prd_database_service.dart    # Web database service
│   ├── note_content_service.dart        # Note operations
│   ├── drawing_content_service.dart     # Drawing operations
│   ├── sync_coordinator.dart            # Bulk sync operations
│   ├── api_client.dart                  # Server API client
│   ├── book_backup_service.dart         # Book backup/restore
│   ├── book_order_service.dart          # Book ordering
│   ├── time_service.dart                # Time utilities
│   └── service_locator.dart             # Dependency injection
├── cubits/                  # State management (BLoC pattern)
│   ├── book_list_cubit.dart       # Book list state management
│   ├── book_list_state.dart       # Book list states
│   ├── schedule_cubit.dart        # Schedule state management
│   ├── schedule_state.dart        # Schedule states
│   ├── event_detail_cubit.dart    # Event detail state management
│   └── event_detail_state.dart    # Event detail states
├── screens/                 # UI screens
│   ├── book_list/                 # Book list screen (refactored)
│   │   ├── book_list_screen_bloc.dart  # BLoC version (276 lines)
│   │   ├── book_card.dart              # Book card widget
│   │   ├── create_book_dialog.dart     # Create dialog
│   │   └── rename_book_dialog.dart     # Rename dialog
│   ├── book_list_screen.dart      # Original version (832 lines)
│   ├── schedule_screen.dart       # Schedule view (2500 lines)
│   └── event_detail_screen.dart   # Event details (1000 lines)
├── widgets/                 # Reusable widgets
│   └── handwriting_canvas.dart
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

test/
├── characterization/        # Behavior preservation tests
├── repositories/            # Repository unit tests
├── cubits/                  # Cubit unit tests
├── screens/                 # Screen widget tests
└── widgets/                 # Widget tests
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
│  │  SyncCoordinator                                │        │
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

### Refactoring Progress

This app has undergone a comprehensive refactoring:
- **Phase 1**: Foundation setup (dependency injection, repository interfaces)
- **Phase 2**: Database layer extraction (repository implementations)
- **Phase 3**: Service layer cleanup (focused services)
- **Phase 4**: BLoC/Cubit state management ✅
- **Phase 5**: Screen refactoring (BookListScreen complete) ⏳
- **Phase 6**: Cleanup and standardization (legacy code removed) ✅
- **Phase 7**: Final validation (pending)

**Code Reduction**: ~4,239 lines of legacy code removed

## Legacy Code

The legacy code directory has been removed as part of Phase 6 cleanup. Approximately 4,239 lines of outdated code were deleted, including:
- Old Provider-based state management
- Deprecated service implementations
- Unused screen implementations
- Old Appointment model

All functionality has been replaced with the new Clean Architecture + BLoC implementation.

## Development

This project follows the Product Requirements Document located in `doc/appointmentApp_PRD.md`.

For development guidelines and architecture decisions, refer to the PRD.