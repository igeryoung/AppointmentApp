# Development Guide

## Getting Started (Linus Style)

**规则1:** 按顺序实施，不要跳跃
**规则2:** 每个功能先能用，再优化
**规则3:** 出现3级以上缩进立即重构

## Implementation Order

### Week 1: Foundation
```bash
# Day 1-2: Project Setup
flutter create schedule_note_app
cd schedule_note_app

# Add dependencies
flutter pub add sqflite path provider
flutter pub add flutter_test --dev

# Day 3-4: Database Layer
# 实施 models/ 和 services/database_service.dart
# 写单元测试确保CRUD操作正确

# Day 5: Basic UI Structure
# 实施 3个空白screen和导航
```

### Week 2: Core Features
```bash
# Day 1-2: Book Management
# BookListScreen + BookService
# 能创建、删除book

# Day 3-4: Appointment Management
# CalendarScreen + AppointmentService
# 能创建、编辑、删除appointment

# Day 5: Basic Handwriting
# HandwritingCanvas基础版本
# 能画线条并保存
```

## Code Quality Standards (Linus审查标准)

### 🟢 Good Code
```dart
// 清晰、简单、直接
class BookService {
  Future<Book> createBook(String name) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Book name cannot be empty');
    }
    return await _database.createBook(name.trim());
  }
}
```

### 🔴 Bad Code
```dart
// 过度抽象、特殊情况太多
class BookServiceFactory {
  static BookService createBookService({
    DatabaseType type = DatabaseType.sqlite,
    bool enableCaching = false,
    CacheStrategy strategy = CacheStrategy.lru,
  }) {
    // 30行配置代码...
  }
}
```

### Function Length Rule
```dart
// ✅ Good: 一个函数做一件事
Future<void> saveAppointment(Appointment appointment) async {
  await _validateAppointment(appointment);
  await _database.saveAppointment(appointment);
  notifyListeners();
}

// ❌ Bad: 超过20行，做太多事情
Future<void> handleAppointmentCreation(...) async {
  // 50行混杂验证、保存、UI更新、错误处理...
}
```

## Database Implementation

### Setup Script
```dart
// database_service.dart
class DatabaseService {
  static const String _databaseName = 'schedule_note.db';
  static const int _databaseVersion = 1;

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _createTables,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE appointments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        start_time INTEGER NOT NULL,
        duration INTEGER NOT NULL DEFAULT 0,
        name TEXT,
        record_number TEXT,
        type TEXT,
        note_strokes TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        FOREIGN KEY (book_id) REFERENCES books (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_appointments_book_time
      ON appointments(book_id, start_time)
    ''');
  }
}
```

## Handwriting Implementation

### Canvas Setup
```dart
class HandwritingCanvas extends StatefulWidget {
  @override
  _HandwritingCanvasState createState() => _HandwritingCanvasState();
}

class _HandwritingCanvasState extends State<HandwritingCanvas> {
  List<Stroke> strokes = [];
  Stroke? currentStroke;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: CustomPaint(
        painter: StrokePainter(strokes),
        child: Container(),
      ),
    );
  }

  void _onPanStart(DragStartDetails details) {
    currentStroke = Stroke(
      points: [details.localPosition],
      color: Colors.black,
      width: 2.0,
    );
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      currentStroke?.points.add(details.localPosition);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (currentStroke != null) {
      setState(() {
        strokes.add(currentStroke!);
        currentStroke = null;
      });
    }
  }
}
```

## Testing Strategy

### Unit Tests Example
```dart
// test/services/book_service_test.dart
void main() {
  group('BookService', () {
    test('should create book with valid name', () async {
      final bookService = BookService();
      final book = await bookService.createBook('Doctor A');

      expect(book.name, 'Doctor A');
      expect(book.id, isNotNull);
    });

    test('should throw error for empty name', () async {
      final bookService = BookService();

      expect(
        () => bookService.createBook(''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
```

### Widget Tests Example
```dart
// test/screens/book_list_screen_test.dart
void main() {
  testWidgets('should display list of books', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp());

    expect(find.text('Books'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
  });
}
```

## Performance Optimization Checklist

### 手写性能
- [ ] 使用RepaintBoundary包装canvas
- [ ] 实施stroke简化算法（减少points数量）
- [ ] 避免每次onPanUpdate都setState
- [ ] 实施渲染缓存

### 数据库性能
- [ ] 使用事务批量操作
- [ ] 只查询需要的字段
- [ ] 实施合理的分页
- [ ] 监控查询执行时间

### 内存优化
- [ ] 及时dispose controllers
- [ ] 使用WeakReference缓存
- [ ] 监控内存使用
- [ ] 避免circular references

## Debugging Guide

### 常见问题
1. **手写延迟过高**
   - 检查CustomPainter的paint方法
   - 减少不必要的setState调用
   - 使用Flutter Inspector分析rebuild

2. **数据库锁定**
   - 确保所有database操作在同一个isolate
   - 避免并发写操作
   - 使用事务管理

3. **内存泄漏**
   - 检查是否正确dispose controllers
   - 使用Memory Inspector
   - 监控Stream subscription

### 性能分析工具
```bash
# 性能分析
flutter run --profile
flutter drive --target=test_driver/app.dart --profile

# 内存分析
flutter run --profile --enable-checked-mode
```

---

**Linus Final Notes:**

这个开发指南遵循"先让它工作"的原则。不要试图一开始就完美，先实现基本功能，然后迭代改进。

记住：**简单的代码容易调试，复杂的代码容易出错。**

开始编码吧！