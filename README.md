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
├── services/                # Database services
│   ├── database_service_interface.dart  # Interface for type safety
│   ├── prd_database_service.dart        # SQLite implementation
│   └── web_prd_database_service.dart    # Web in-memory implementation
├── screens/                 # UI screens
│   ├── book_list_screen.dart
│   ├── schedule_screen.dart
│   └── event_detail_screen.dart
├── widgets/                 # Reusable widgets
│   └── handwriting_canvas.dart
├── legacy/                  # ⚠️ Legacy code (not in use)
│   ├── README_LEGACY.md     # Legacy code documentation
│   ├── screens/             # Old screen implementations
│   ├── providers/           # Old Provider-based state management
│   ├── services/            # Old service layer
│   └── models/              # Old Appointment model
├── app.dart                 # Main app configuration
└── main.dart                # App entry point

doc/
└── appointmentApp_PRD.md    # Product Requirements Document

test/
├── diagnostics/             # Debugging and diagnosis tests
├── models/                  # Model tests
├── screens/                 # Screen tests
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

### Data Flow (Current Implementation)
```
BookListScreen → ScheduleScreen → EventDetailScreen
       ↓                ↓                ↓
   IDatabaseService (interface)
       ↓                ↓
PRDDatabaseService ← (mobile/desktop)
WebPRDDatabaseService ← (web)
```

### Hierarchy
**Books** → **Events** → **Notes**
- Each Book contains multiple Events
- Each Event can have one Note (handwriting)
- Schedule Drawings are overlay annotations on schedule views

### Key Principles
1. **Direct Data Access**: Screens directly use database services (no intermediate service layer)
2. **Type Safety**: All services implement `IDatabaseService` interface
3. **Platform Adaptation**: Automatic selection of appropriate database implementation
4. **Simplicity**: Minimal abstraction layers for maintainability

## Legacy Code

The `lib/legacy/` directory contains an older implementation that is **not currently in use**. This code is preserved for:
- Historical reference
- Potential future feature extraction
- Understanding project evolution

⚠️ **Do not use code from `lib/legacy/`** - it is not maintained and may contain bugs.

See `lib/legacy/README_LEGACY.md` for details.

## Development

This project follows the Product Requirements Document located in `doc/appointmentApp_PRD.md`.

For development guidelines and architecture decisions, refer to the PRD.