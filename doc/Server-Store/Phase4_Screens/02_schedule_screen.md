# Phase 4-02: ScheduleScreen Smart Preloading

> **优先级**: P1 - Phase 4
> **状态**: 🟡 Not Started
> **估计时间**: 6小时
> **依赖**: Phase 3-01 ContentService完成
> **完成时间**: TBD

---

## 📋 任务描述

### 目标

为ScheduleScreen添加智能预加载，实现：
1. **打开时预加载** - initState时预加载3天窗口的所有notes
2. **切换日期预加载** - 用户切换日期时预加载新窗口
3. **后台执行** - 预加载不阻塞UI，用户立即看到events
4. **缓存优先** - 点击event时优先使用preloaded cache

### 当前问题

**现有代码** (schedule_screen.dart:192):
```dart
Future<void> _loadEvents() async {
  setState(() => _isLoading = true);

  final events = await _dbService.getEventsBy3Days(widget.book.id!, effectiveDate);

  setState(() {
    _events = events;
    _isLoading = false;
  });
}
```

**问题**:
- 只加载events元数据，不加载notes
- 用户点击event时才fetch note（延迟2s）
- 没有预加载机制
- Cache命中率低

---

## 🧠 Linus式根因分析

### 用户体验问题

**当前流程**:
```
用户打开Schedule → 加载events → 显示列表
用户点击event → 加载note (2s延迟) → 显示canvas
                 ^^^^^^^^^^^^^^^^^^^
                 用户等待，体验差
```

**理想流程**:
```
用户打开Schedule → 加载events → 显示列表 → (后台预加载所有notes)
用户点击event → 立即显示note (< 50ms)
                 ^^^^^^^^^^^^^^^^^^
                 cache命中，体验好
```

### 预加载时机

**Good Taste**: 在用户需要之前就准备好数据

**时机分析**:
```
1. initState() - 打开ScheduleScreen时
   → 预加载3天窗口的所有notes

2. onDateChanged() - 用户切换日期时
   → 预加载新3天窗口的notes

3. onEventAdded() - 用户创建新event时
   → 无需预加载（note为空）
```

**不要过度预加载**:
- ❌ 预加载整个月的notes（浪费流量）
- ❌ 预加载历史notes（用户很少回看）
- ✅ 只预加载用户当前查看的3天窗口

---

## ✅ 实施方案

### 方案1: initState预加载

**新增状态**:
```dart
class _ScheduleScreenState extends State<ScheduleScreen> {
  // ... existing fields

  bool _isPreloading = false;  // 后台预加载中
  int _preloadedCount = 0;     // 已预加载的note数量
  int _totalToPreload = 0;     // 总共需要预加载的note数量

  // ContentService实例
  late ContentService _contentService;

  @override
  void initState() {
    super.initState();

    // 初始化ContentService
    _contentService = ContentService(
      apiClient: ApiClient(),
      cacheManager: CacheManager(dbService: _dbService),
      dbService: _dbService,
    );

    // ... existing init code

    _loadEvents();
    _loadDrawing();

    // **新增**: 后台预加载notes
    _preloadNotesInBackground();
  }
}
```

**预加载逻辑**:
```dart
/// 后台预加载3天窗口的所有notes（不阻塞UI）
Future<void> _preloadNotesInBackground() async {
  // 等待_loadEvents()完成
  await Future.delayed(Duration(milliseconds: 100));

  if (_events.isEmpty) {
    debugPrint('📦 ScheduleScreen: No events to preload');
    return;
  }

  setState(() {
    _isPreloading = true;
    _totalToPreload = _events.length;
    _preloadedCount = 0;
  });

  debugPrint('📦 ScheduleScreen: Starting preload for ${_events.length} events');

  // 提取所有event IDs
  final eventIds = _events
      .where((e) => e.id != null)
      .map((e) => e.id!)
      .toList();

  try {
    // 调用ContentService批量预加载
    await _contentService.preloadNotes(
      eventIds,
      onProgress: (loaded, total) {
        // 更新预加载进度（可选，用于调试）
        setState(() {
          _preloadedCount = loaded;
        });
        debugPrint('📦 ScheduleScreen: Preloaded $loaded/$total notes');
      },
    );

    debugPrint('✅ ScheduleScreen: Preload completed (${eventIds.length} notes)');

    setState(() {
      _isPreloading = false;
    });

  } catch (e) {
    // 预加载失败不影响主流程
    debugPrint('⚠️ ScheduleScreen: Preload failed (non-critical): $e');
    setState(() {
      _isPreloading = false;
    });
  }
}
```

**ContentService.preloadNotes()** 实现 (Phase 3补充):
```dart
/// Preload multiple notes in background (non-blocking)
///
/// Strategy:
/// 1. Filter out already-cached notes
/// 2. Batch fetch from server (max 50 per request)
/// 3. Save to cache
Future<void> preloadNotes(
  List<int> eventIds, {
  Function(int loaded, int total)? onProgress,
}) async {
  if (eventIds.isEmpty) return;

  debugPrint('ContentService: Preloading ${eventIds.length} notes');

  // Step 1: Filter out cached notes
  final uncachedIds = <int>[];
  for (final id in eventIds) {
    final cached = await _cacheManager.getNote(id);
    if (cached == null) {
      uncachedIds.add(id);
    }
  }

  if (uncachedIds.isEmpty) {
    debugPrint('ContentService: All notes already cached');
    onProgress?.call(eventIds.length, eventIds.length);
    return;
  }

  debugPrint('ContentService: Need to fetch ${uncachedIds.length} notes from server');

  // Step 2: Batch fetch (max 50 per request to avoid timeout)
  const batchSize = 50;
  int loaded = eventIds.length - uncachedIds.length;  // Already cached

  for (int i = 0; i < uncachedIds.length; i += batchSize) {
    final batch = uncachedIds.skip(i).take(batchSize).toList();

    try {
      // Batch fetch from server
      final notes = await _apiClient.batchFetchNotes(batch);

      // Save to cache
      for (final note in notes) {
        await _cacheManager.saveNote(note.eventId, note, dirty: false);
      }

      loaded += notes.length;
      onProgress?.call(loaded, eventIds.length);

      debugPrint('ContentService: Batch ${i ~/ batchSize + 1} fetched ${notes.length} notes');

    } catch (e) {
      debugPrint('ContentService: Batch fetch failed (skipping): $e');
      // Continue with next batch, don't fail entire preload
    }
  }

  debugPrint('ContentService: Preload completed ($loaded/${eventIds.length})');
}
```

---

### 方案2: 日期切换预加载

**监听日期变化**:
```dart
Future<void> _changeDate(DateTime newDate) async {
  // Save current drawing before switching
  if (_isDrawingMode) {
    await _saveDrawing();
  }

  setState(() {
    _selectedDate = newDate;
  });

  // Reload events for new date
  await _loadEvents();
  await _loadDrawing();

  // **新增**: 预加载新日期的notes
  _preloadNotesInBackground();
}
```

**Good Taste**:
- ✅ 每次切换日期都预加载
- ✅ 不会重复加载（ContentService会跳过cached）
- ✅ 用户无感知（后台执行）

---

### 方案3: Drawing预加载

**预加载Drawings**:
```dart
/// 预加载3天窗口的所有drawings
Future<void> _preloadDrawingsInBackground() async {
  if (widget.book.id == null) return;

  final effectiveDate = _getEffectiveDate();
  final startDate = effectiveDate;
  final endDate = effectiveDate.add(Duration(days: 3));

  debugPrint('📦 ScheduleScreen: Preloading drawings for $startDate to $endDate');

  try {
    await _contentService.preloadDrawings(
      bookId: widget.book.id!,
      startDate: startDate,
      endDate: endDate,
      viewMode: 1,  // 3-day view
    );

    debugPrint('✅ ScheduleScreen: Drawings preloaded');

  } catch (e) {
    debugPrint('⚠️ ScheduleScreen: Drawing preload failed: $e');
  }
}
```

**调用时机**:
```dart
@override
void initState() {
  super.initState();
  // ...

  _loadEvents();
  _loadDrawing();

  // 并行预加载
  Future.wait([
    _preloadNotesInBackground(),
    _preloadDrawingsInBackground(),
  ]);
}
```

---

### 方案4: 预加载进度指示（可选）

**底部Snackbar提示**:
```dart
void _showPreloadingSnackbar() {
  if (!_isPreloading) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          SizedBox(width: 12),
          Text(
            'Preloading notes... $_preloadedCount/$_totalToPreload',
            style: TextStyle(fontSize: 14),
          ),
        ],
      ),
      duration: Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
```

**调用时机**:
```dart
Future<void> _preloadNotesInBackground() async {
  // ...

  setState(() {
    _isPreloading = true;
    _totalToPreload = _events.length;
  });

  // 显示预加载提示（可选）
  _showPreloadingSnackbar();

  // ... preload logic
}
```

---

## 🧪 测试计划

### 功能测试

**测试1: 打开Schedule时预加载**
```dart
testWidgets('Preloads all notes on init', (tester) async {
  // Setup: 10个events
  when(mockDbService.getEventsBy3Days(any, any))
      .thenAnswer((_) async => List.generate(10, (i) => Event(id: i)));

  await tester.pumpWidget(MaterialApp(
    home: ScheduleScreen(book: testBook),
  ));

  // 等待初始化
  await tester.pump(Duration(milliseconds: 200));

  // 验证预加载被调用
  verify(mockContentService.preloadNotes(any, onProgress: any))
      .called(1);

  // 验证预加载了10个event IDs
  final capturedIds = verify(mockContentService.preloadNotes(
    captureAny,
    onProgress: any,
  )).captured.first as List<int>;

  expect(capturedIds.length, 10);
});
```

**测试2: 切换日期时预加载**
```dart
testWidgets('Preloads notes when date changes', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: ScheduleScreen(book: testBook),
  ));

  // 切换到明天
  final tomorrow = DateTime.now().add(Duration(days: 1));
  await tester.runAsync(() async {
    await tester.pumpWidget(ScheduleScreen(book: testBook));
    // Simulate date change
    scheduleScreenState._changeDate(tomorrow);
  });

  await tester.pumpAndSettle();

  // 验证预加载被调用2次（init + date change）
  verify(mockContentService.preloadNotes(any, onProgress: any))
      .called(2);
});
```

**测试3: 预加载失败不影响主流程**
```dart
testWidgets('UI works even if preload fails', (tester) async {
  // Setup: 预加载抛异常
  when(mockContentService.preloadNotes(any, onProgress: any))
      .thenThrow(NetworkException('No internet'));

  await tester.pumpWidget(MaterialApp(
    home: ScheduleScreen(book: testBook),
  ));
  await tester.pumpAndSettle();

  // 验证UI仍然正常显示
  expect(find.byType(ScheduleScreen), findsOneWidget);
  expect(find.text('No internet'), findsNothing);  // 不显示错误
});
```

### 性能测试

**基准测试**:
```dart
void main() {
  test('Preload 100 notes < 10s', () async {
    final stopwatch = Stopwatch()..start();

    final eventIds = List.generate(100, (i) => i);
    await contentService.preloadNotes(eventIds);

    stopwatch.stop();

    expect(stopwatch.elapsedSeconds, lessThan(10));
    print('Preloaded 100 notes in ${stopwatch.elapsedSeconds}s');
  });

  test('Preload doesn\'t block UI', () async {
    // 启动预加载
    final future = contentService.preloadNotes(List.generate(50, (i) => i));

    // 立即检查UI是否响应
    final uiStopwatch = Stopwatch()..start();
    await Future.delayed(Duration(milliseconds: 10));
    uiStopwatch.stop();

    // UI响应时间 < 50ms
    expect(uiStopwatch.elapsedMilliseconds, lessThan(50));

    // 等待预加载完成
    await future;
  });
}
```

### 手动测试场景

**场景1: 正常在线使用**
```
1. 打开ScheduleScreen（今天有10个events）
   ✓ 立即显示10个events列表
   ✓ 底部显示"Preloading notes... 0/10"
   ✓ 2秒后显示"Preloading notes... 10/10"

2. 点击第一个event
   ✓ 立即打开（< 50ms，从cache加载）
   ✓ 无loading延迟

3. 返回，点击第二个event
   ✓ 同样立即打开

4. 切换到明天
   ✓ 立即显示events
   ✓ 后台预加载新notes
```

**场景2: 离线使用**
```
1. 开飞行模式
2. 打开ScheduleScreen
   ✓ 显示events列表
   ✓ 预加载失败（静默，无错误）

3. 点击event（有cache）
   ✓ 立即打开cached note

4. 点击event（无cache）
   ✓ 显示空canvas
   ✓ 顶部显示"离线模式"banner
```

**场景3: 弱网环境**
```
1. 限速到100KB/s
2. 打开ScheduleScreen（50个events）
   ✓ 立即显示列表
   ✓ 后台慢慢预加载

3. 点击第5个event（已预加载）
   ✓ 立即打开

4. 点击第45个event（未预加载）
   ✓ 显示loading 2-3秒
   ✓ 然后显示note
```

---

## 📦 向后兼容性

**迁移策略**:
1. ✅ 预加载是新增功能，不影响现有逻辑
2. ✅ 即使预加载失败，用户仍可点击event后加载
3. ✅ 逐步rollout（可通过feature flag控制）

**性能影响**:
- ✅ 后台执行，不阻塞UI
- ✅ 批量fetch，减少请求数
- ✅ 自动跳过已cached，避免重复

---

## ✅ 验收标准

- [ ] initState时自动预加载3天窗口的notes
- [ ] 切换日期时自动预加载新窗口
- [ ] 预加载不阻塞UI（后台执行）
- [ ] Cache命中率 > 80%（打开event < 50ms）
- [ ] 预加载失败不影响主流程
- [ ] 所有功能测试通过
- [ ] 性能测试：100 notes < 10s
- [ ] 手动测试3个场景全通过

---

## 📝 修复检查清单

### Phase 3补充工作（依赖）
- [ ] ContentService添加`preloadNotes()`方法
- [ ] ContentService添加`preloadDrawings()`方法
- [ ] ApiClient添加`batchFetchNotes()`方法
- [ ] ApiClient添加`batchFetchDrawings()`方法

### ScheduleScreen改造
- [ ] 添加ContentService实例
- [ ] 添加预加载状态变量
- [ ] 实现`_preloadNotesInBackground()`
- [ ] 实现`_preloadDrawingsInBackground()`
- [ ] 在initState中调用预加载
- [ ] 在_changeDate中调用预加载
- [ ] 添加预加载进度提示（可选）

### 测试验证
- [ ] 单元测试：3个测试通过
- [ ] 性能测试：2个基准测试通过
- [ ] 手动测试：3个场景全通过

---

## 🔗 相关任务

- **依赖**: [Phase 3-01: ContentService](../Phase3_ClientServices/01_content_service.md)
- **并行**: [Phase 4-01: EventDetailScreen](01_event_detail_screen.md)
- **下一步**: [Phase 4-03: Offline UX](03_offline_ux.md)

---

**Linus说**: "Preloading is about anticipating user needs. If they're viewing today's schedule, they'll probably click on today's events. Don't make them wait for what you know they'll need."

**性能优化哲学**: "The fastest network request is the one you don't make. Cache aggressively, preload intelligently, but never block the UI."
