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
├── models/          # Data models (Book, Event, Note)
├── services/        # Database services
├── screens/         # UI screens
├── widgets/         # Reusable widgets
├── app.dart         # Main app configuration
└── main.dart        # App entry point

doc/
└── appointmentApp_PRD.md  # Product Requirements Document

test/
└── unit/            # Unit tests
```

## Database

- **Mobile/Desktop**: Uses SQLite with sqflite package
- **Web**: Uses in-memory storage for compatibility

## Architecture

The app follows a hierarchical structure:
- **Books** → **Schedule** → **Events** → **Notes**

Each appointment book contains a schedule with events, and each event can have handwritten notes.

## Development

This project follows the Product Requirements Document located in `doc/appointmentApp_PRD.md`.

For development guidelines and architecture decisions, refer to the PRD.