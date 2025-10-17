# Technical Architecture Specification

## Linus Approval: ✅ "Keep it simple, stupid"

## 1. Architecture Overview

```
┌─────────────────────────────────────┐
│              UI Layer               │
│  BookList → Calendar → Appointment  │
└─────────────────┬───────────────────┘
                  │
┌─────────────────┴───────────────────┐
│            Business Logic           │
│     BookService, AppointmentService │
└─────────────────┬───────────────────┘
                  │
┌─────────────────┴───────────────────┐
│            Data Layer               │
│        SQLite + 2 Tables            │
└─────────────────────────────────────┘
```

**原则：每层职责清晰，无跨层调用，无魔法抽象。**

## 2. Directory Structure

```
lib/
├── main.dart                    # App entry point
├── app.dart                     # MaterialApp setup
│
├── models/                      # Data models (Plain Dart classes)
│   ├── book.dart
│   └── appointment.dart
│
├── services/                    # Business logic
│   ├── database_service.dart    # SQLite operations
│   ├── book_service.dart        # Book CRUD
│   └── appointment_service.dart # Appointment CRUD
│
├── screens/                     # UI screens
│   ├── book_list_screen.dart
│   ├── calendar_screen.dart
│   └── appointment_detail_screen.dart
│
├── widgets/                     # Reusable UI components
│   ├── handwriting_canvas.dart
│   ├── appointment_card.dart
│   └── time_slot_widget.dart
│
└── utils/                       # Utilities
    ├── date_utils.dart
    └── handwriting_utils.dart
```

## 3. Data Layer

### Database Schema (SQLite)
```sql
-- 简单，直接，有效
PRAGMA foreign_keys = ON;

CREATE TABLE books (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);

CREATE TABLE appointments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER NOT NULL,
  start_time INTEGER NOT NULL,     -- Unix timestamp
  duration INTEGER NOT NULL DEFAULT 0,  -- 分钟，0表示开放式
  name TEXT,
  record_number TEXT,
  type TEXT,
  note_strokes BLOB,               -- JSON encoded strokes
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),

  FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
);

-- 唯一必需的索引
CREATE INDEX idx_appointments_book_time ON appointments(book_id, start_time);
```

### Model Classes
```dart
// 纯数据容器，无业务逻辑
class Book {
  final int? id;
  final String name;
  final DateTime createdAt;

  const Book({this.id, required this.name, required this.createdAt});
}

class Appointment {
  final int? id;
  final int bookId;
  final DateTime startTime;
  final int duration;  // 分钟
  final String? name;
  final String? recordNumber;
  final String? type;
  final List<Stroke>? noteStrokes;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

## 4. Service Layer

### DatabaseService
```dart
// 单例，懒加载，简单粗暴
class DatabaseService {
  static DatabaseService? _instance;
  static Database? _database;

  // CRUD operations only, no business logic
  Future<List<Book>> getAllBooks();
  Future<Book> createBook(String name);
  Future<void> deleteBook(int id);

  Future<List<Appointment>> getAppointmentsByBookAndDate(int bookId, DateTime date);
  Future<Appointment> createAppointment(Appointment appointment);
  Future<Appointment> updateAppointment(Appointment appointment);
  Future<void> deleteAppointment(int id);
}
```

### Business Services
```dart
// 薄薄一层业务逻辑，主要是验证和格式化
class BookService {
  Future<List<Book>> getBooks();
  Future<Book> createBook(String name);
  Future<void> deleteBook(int id);
}

class AppointmentService {
  Future<List<Appointment>> getTodayAppointments(int bookId);
  Future<Appointment> createAppointment({...});
  Future<void> updateAppointment(Appointment appointment);
  Future<void> deleteAppointment(int id);
}
```

## 5. UI Layer

### State Management: Provider (Simple)
```dart
// 不用复杂的状态管理，Provider就够了
class BookProvider extends ChangeNotifier {
  List<Book> _books = [];
  List<Book> get books => _books;

  Future<void> loadBooks();
  Future<void> createBook(String name);
  Future<void> deleteBook(int id);
}

class AppointmentProvider extends ChangeNotifier {
  List<Appointment> _appointments = [];
  DateTime _selectedDate = DateTime.now();

  // 简单的状态管理，不要花里胡哨
}
```

### Screen Structure
```dart
// 每个screen都是StatefulWidget，简单直接
class BookListScreen extends StatefulWidget {
  // 显示books列表
  // 新建book
  // 点击进入日历
}

class CalendarScreen extends StatefulWidget {
  // 显示一天的appointments
  // 创建新appointment
  // 点击appointment进入详情
}

class AppointmentDetailScreen extends StatefulWidget {
  // 基本信息编辑
  // 手写笔记区域
  // 保存/删除操作
}
```

## 6. Handwriting Implementation

### Canvas Widget
```dart
class HandwritingCanvas extends StatefulWidget {
  // CustomPainter for stroke rendering
  // GestureDetector for input capture
  // Stroke data as List<Offset> per stroke
}

// 手写数据结构
class Stroke {
  final List<Offset> points;
  final Color color;
  final double width;
  final DateTime timestamp;
}
```

### Storage Strategy
- 手写数据存储为JSON BLOB
- 每次保存整个stroke列表（简单）
- 不做增量更新（复杂）

## 7. Error Handling Strategy

### Database Errors
- 所有database操作用try-catch包装
- 错误日志 + 用户友好消息
- 简单重试机制

### UI Errors
- 全局ErrorWidget重写
- SnackBar显示错误信息
- 崩溃恢复到主页面

## 8. Performance Considerations

### 手写性能
- 使用CustomPainter直接绘制
- 避免频繁rebuild
- Stroke缓存策略

### 数据库性能
- 只查询需要的日期范围
- 合理使用索引
- 避免N+1查询问题

### 内存管理
- 及时dispose controllers
- 图片/笔记数据懒加载
- 避免内存泄漏

## 9. Testing Strategy

### Unit Tests
- Model类序列化/反序列化
- Service层业务逻辑
- Utils函数

### Widget Tests
- 各screen的基本功能
- 手写canvas的交互

### Integration Tests
- 完整的用户流程
- 数据持久化验证

---

**Linus Notes:**
- 架构图一页纸能画完 ✅
- 没有过度抽象 ✅
- 每个类职责单一 ✅
- 可以3个人并行开发 ✅
- 出问题时能快速定位 ✅

**复杂度评估:** 🟢 简单 （Linus标准）