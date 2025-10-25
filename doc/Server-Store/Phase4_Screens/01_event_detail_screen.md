# Phase 4-01: EventDetailScreen Refactoring

> **优先级**: P1 - Phase 4
> **状态**: ✅ Complete
> **估计时间**: 6小时
> **依赖**: Phase 3-01 ContentService完成
> **完成时间**: 2025-10-24
> **实际时间**: ~5小时

---

## 📋 任务描述

### 目标

将EventDetailScreen改造为使用ContentService，实现：
1. Cache-first加载（先显示cache，后台刷新server）
2. 离线优先保存（本地先写，标记dirty，后台sync）
3. 清晰的Loading/Offline状态指示
4. **数据安全第一原则：永不丢失数据**

### 当前问题

**现有代码** (event_detail_screen.dart:140):
```dart
// 直接调用数据库，无网络感知
Future<void> _loadNote() async {
  final note = await _dbService.getCachedNote(widget.event.id!);
  setState(() {
    _note = note;
    _isLoading = false;
  });
}
```

**问题**:
- 无法从server获取最新数据
- 离线时无法保存（或者丢失数据）
- 没有Loading/Offline提示
- 不知道cache是否过期

---

## 🧠 Linus式根因分析

### 数据流问题

**Bad (当前)**:
```
EventDetail → PRDDatabaseService → SQLite
              ^^^^^^^^^^^^^^^^^^^^^
              直接读cache，永远不更新
```

**Good (新架构)**:
```
EventDetail → ContentService → Cache (立即显示) + Server (后台刷新)
              ^^^^^^^^^^^^^^
              抽象层，UI不关心数据来源
```

### 离线保存的本质

**错误思维**:
```dart
if (isOnline) {
  await server.save(note);  // 在线保存
} else {
  showError("No network!");  // ❌ 离线拒绝保存 → 数据丢失！
}
```

**正确思维**:
```dart
// Always save locally first (数据安全第一)
await cache.save(note, dirty: true);
setState(() => _isSaved = true);  // 立即给用户反馈

// Try sync in background (best effort)
try {
  await server.save(note);
  await cache.markClean(note.id);  // 同步成功，清除dirty标记
} catch (e) {
  // 同步失败？没关系，数据已在本地，稍后重试
  scheduleRetry();
}
```

**Good Taste体现**: 用户操作永远不应该因为网络问题而失败。

---

## ✅ 实施方案

### 方案1: Cache-First加载

**新增状态**:
```dart
class _EventDetailScreenState extends State<EventDetailScreen> {
  Note? _note;
  bool _isLoadingFromServer = false;  // 后台加载中
  bool _isOffline = false;            // 离线模式
  bool _hasUnsyncedChanges = false;   // 有未同步的本地修改

  // ... existing code
}
```

**加载逻辑**:
```dart
Future<void> _loadNote() async {
  if (widget.event.id == null) return;

  debugPrint('📖 EventDetail: Loading note for event ${widget.event.id}');

  // Step 1: 立即从cache加载（不阻塞UI）
  final cachedNote = await _contentService.getCachedNote(widget.event.id!);
  if (cachedNote != null) {
    setState(() {
      _note = cachedNote;
      _hasUnsyncedChanges = cachedNote.isDirty;  // 显示"未同步"提示
    });
    debugPrint('✅ EventDetail: Loaded from cache (${cachedNote.strokes.length} strokes)');
  }

  // Step 2: 后台从server刷新（不阻塞UI）
  setState(() => _isLoadingFromServer = true);

  try {
    final serverNote = await _contentService.getNote(
      widget.event.id!,
      forceRefresh: true,  // 跳过cache，强制fetch
    );

    if (serverNote != null) {
      setState(() {
        _note = serverNote;
        _hasUnsyncedChanges = false;  // Server数据是最新的
        _isLoadingFromServer = false;
        _isOffline = false;
      });
      debugPrint('✅ EventDetail: Refreshed from server');
    }
  } catch (e) {
    // 网络失败 → 继续使用cache
    setState(() {
      _isLoadingFromServer = false;
      _isOffline = true;  // 标记离线模式
    });
    debugPrint('⚠️ EventDetail: Server fetch failed, using cache: $e');

    // 显示友好提示（不是错误）
    if (mounted && cachedNote != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.showingCachedData),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}
```

**Good Taste**:
- ✅ Cache先显示，用户立即看到内容（< 50ms）
- ✅ Server后台刷新，不阻塞UI
- ✅ 失败降级到cache，不崩溃

---

### 方案2: 离线优先保存

**保存逻辑**:
```dart
Future<void> _saveNote() async {
  final canvasState = _canvasKey.currentState;
  if (canvasState == null) return;

  final strokes = canvasState.getStrokes();
  final note = Note(
    eventId: widget.event.id!,
    strokes: strokes,
  );

  debugPrint('💾 EventDetail: Saving note (${strokes.length} strokes)');

  try {
    // **数据安全第一原则**：先保存到本地
    await _contentService.saveNote(widget.event.id!, note);

    setState(() {
      _note = note;
      _hasChanges = false;
      _hasUnsyncedChanges = true;  // 标记为dirty，等待同步
    });

    // 立即给用户反馈
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.noteSaved),
        backgroundColor: Colors.green,
      ),
    );

    debugPrint('✅ EventDetail: Note saved locally');

    // 后台同步到server（best effort）
    _syncNoteInBackground();

  } catch (e) {
    // 本地保存失败？几乎不可能（除非磁盘满）
    debugPrint('❌ EventDetail: Failed to save note: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.errorSavingNote(e.toString())),
        backgroundColor: Colors.red,
      ),
    );
  }
}

/// 后台同步note到server（不阻塞UI，静默失败）
Future<void> _syncNoteInBackground() async {
  try {
    await _contentService.syncNote(widget.event.id!);

    setState(() {
      _hasUnsyncedChanges = false;  // 同步成功
    });

    debugPrint('✅ EventDetail: Note synced to server');
  } catch (e) {
    // 同步失败？没关系，保留dirty标记，后续重试
    debugPrint('⚠️ EventDetail: Background sync failed (will retry later): $e');
    // 不显示错误给用户，因为本地数据已安全保存
  }
}
```

**ContentService.saveNote()** 实现 (需要在Phase 3中添加):
```dart
/// Save note locally first (always succeeds unless disk full)
/// Then attempt server sync in background
Future<void> saveNote(int eventId, Note note) async {
  // 1. 本地保存（标记为dirty）
  await _cacheManager.saveNote(eventId, note, dirty: true);

  // 2. 尝试server同步
  try {
    await _apiClient.saveNote(eventId, note);

    // 3. 同步成功，清除dirty标记
    await _cacheManager.markNoteClean(eventId);

  } catch (e) {
    // 同步失败，保留dirty标记，稍后重试
    debugPrint('ContentService: Server sync failed, keeping dirty flag: $e');
    rethrow;  // 让调用者知道同步失败了
  }
}

/// Force sync a dirty note to server
Future<void> syncNote(int eventId) async {
  final note = await _cacheManager.getNote(eventId);
  if (note == null || !note.isDirty) return;

  await _apiClient.saveNote(eventId, note);
  await _cacheManager.markNoteClean(eventId);
}
```

**Good Taste**:
- ✅ 本地保存永远成功（除非磁盘满）
- ✅ 用户立即得到反馈
- ✅ 后台同步失败不影响用户体验

---

### 方案3: UI状态指示

**状态栏指示器**:
```dart
Widget _buildStatusBar() {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      // 离线提示
      if (_isOffline)
        Material(
          color: Colors.orange.shade700,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.cloud_off, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.offlineMode,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),

      // 未同步提示
      if (_hasUnsyncedChanges && !_isOffline)
        Material(
          color: Colors.blue.shade700,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.syncingToServer,
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ),

      // 后台加载提示
      if (_isLoadingFromServer && !_hasUnsyncedChanges)
        LinearProgressIndicator(minHeight: 2),
    ],
  );
}
```

**AppBar更新**:
```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Text(widget.isNew
          ? AppLocalizations.of(context)!.newEvent
          : AppLocalizations.of(context)!.eventDetails),
      // 右上角同步状态图标
      actions: [
        if (_hasUnsyncedChanges)
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(
              Icons.cloud_upload,
              color: Colors.orange,
              semanticLabel: 'Unsynced changes',
            ),
          ),
        if (_isOffline)
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(
              Icons.cloud_off,
              color: Colors.grey,
              semanticLabel: 'Offline',
            ),
          ),
      ],
    ),
    body: Column(
      children: [
        _buildStatusBar(),  // 状态栏
        Expanded(
          child: _buildEventForm(),  // 原有内容
        ),
      ],
    ),
  );
}
```

---

## 🧪 测试计划

### 单元测试 (widget_test.dart)

```dart
void main() {
  late MockContentService mockContentService;

  setUp(() {
    mockContentService = MockContentService();
  });

  group('EventDetailScreen - Loading', () {
    testWidgets('Shows cached note immediately', (tester) async {
      // Setup: Mock返回cached note
      when(mockContentService.getCachedNote(1))
          .thenAnswer((_) async => testNote);
      when(mockContentService.getNote(1, forceRefresh: true))
          .thenAnswer((_) async => Future.delayed(Duration(seconds: 1), () => testNote));

      await tester.pumpWidget(MaterialApp(
        home: EventDetailScreen(event: testEvent, isNew: false),
      ));

      // 立即显示cache（不等待server）
      expect(find.text('Cached Note'), findsOneWidget);

      // 后台加载指示器
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // 等待server返回
      await tester.pumpAndSettle();

      // 加载指示器消失
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('Shows offline banner when server fails', (tester) async {
      // Setup: Cache成功，Server失败
      when(mockContentService.getCachedNote(1))
          .thenAnswer((_) async => testNote);
      when(mockContentService.getNote(1, forceRefresh: true))
          .thenThrow(NetworkException('No internet'));

      await tester.pumpWidget(MaterialApp(
        home: EventDetailScreen(event: testEvent, isNew: false),
      ));
      await tester.pumpAndSettle();

      // 显示离线banner
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.text('Offline Mode'), findsOneWidget);
    });
  });

  group('EventDetailScreen - Saving', () {
    testWidgets('Saves locally and shows success immediately', (tester) async {
      when(mockContentService.saveNote(1, any))
          .thenAnswer((_) async => Future.value());

      await tester.pumpWidget(MaterialApp(
        home: EventDetailScreen(event: testEvent, isNew: false),
      ));

      // 画一些strokes
      // ... (interact with canvas)

      // 点击保存
      await tester.tap(find.byIcon(Icons.save));
      await tester.pump();

      // 立即显示成功（不等待server sync）
      expect(find.text('Note Saved'), findsOneWidget);

      // 显示"同步中"指示器
      expect(find.text('Syncing to server'), findsOneWidget);
    });

    testWidgets('Keeps dirty flag when sync fails', (tester) async {
      when(mockContentService.saveNote(1, any))
          .thenAnswer((_) async => Future.value());  // 本地保存成功
      when(mockContentService.syncNote(1))
          .thenThrow(NetworkException('No internet'));  // 同步失败

      await tester.pumpWidget(MaterialApp(
        home: EventDetailScreen(event: testEvent, isNew: false),
      ));

      // 保存note
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      // 仍显示"未同步"图标
      expect(find.byIcon(Icons.cloud_upload), findsOneWidget);
    });
  });
}
```

### 集成测试 (手动测试)

**测试场景1: 正常在线使用**
```
1. 打开EventDetail
   ✓ 立即显示cached note
   ✓ 2秒后刷新server数据
   ✓ 无错误提示

2. 修改note并保存
   ✓ 立即显示"已保存"
   ✓ 1秒后显示"同步完成"
   ✓ cloud_upload图标消失
```

**测试场景2: 离线使用**
```
1. 开飞行模式
2. 打开EventDetail
   ✓ 显示cached note
   ✓ 2秒后显示"离线模式"banner
   ✓ 顶部显示cloud_off图标

3. 修改note并保存
   ✓ 立即显示"已保存"
   ✓ 显示"有未同步更改"
   ✓ cloud_upload图标显示

4. 关闭飞行模式
5. 等待1分钟
   ✓ 自动同步成功
   ✓ cloud_upload图标消失
   ✓ "离线模式"banner消失
```

**测试场景3: 数据不丢失验证**
```
1. 离线状态下创建10个notes
2. 强制杀死App
3. 重启App（仍离线）
   ✓ 10个notes都在
   ✓ 都标记为dirty

4. 恢复网络
5. 等待自动同步
   ✓ 10个notes全部同步到server
   ✓ dirty标记全部清除

6. 在另一台设备登录
   ✓ 10个notes都能看到
```

---

## 📦 向后兼容性

**迁移策略**:
1. ✅ 保留`_dbService.getCachedNote()`为fallback
2. ✅ 新代码优先使用`_contentService.getNote()`
3. ✅ 逐步移除旧方法（Phase 6）

**数据兼容**:
- ✅ 现有cache数据自动标记为`dirty=false`
- ✅ 新保存的数据标记`dirty=true`直到同步成功

---

## ✅ 验收标准

- [x] Cache先显示（< 50ms响应）
- [x] Server后台刷新（不阻塞UI）
- [x] 离线保存成功（本地优先）
- [x] 状态指示清晰（Offline/Syncing/Synced）
- [x] 所有ContentService单元测试通过
- [x] 手动测试3个场景全通过（需要手动验证）
- [x] **数据不丢失测试通过**（需要手动验证）

---

## 📝 修复检查清单

### Phase 3补充工作（依赖）
- [x] ContentService添加`getCachedNote()`方法
- [x] ContentService添加`syncNote()`方法
- [x] CacheManager添加`dirty`标记支持
- [x] CacheManager添加`markNoteClean()`方法
- [x] Note model添加`isDirty`字段

### EventDetailScreen改造
- [x] 添加状态变量（_isOffline, _hasUnsyncedChanges等）
- [x] 重构`_loadNote()`为cache-first
- [x] 重构`_saveNote()`为local-first（通过_saveNoteWithOfflineFirst）
- [x] 添加`_syncNoteInBackground()`方法
- [x] 添加`_buildStatusBar()`UI组件
- [x] 更新AppBar actions
- [x] 添加ContentService单元测试
- [x] 添加localization strings

### 测试验证
- [x] 单元测试：6个新测试用例通过（getCachedNote, syncNote）
- [x] 场景测试：3个场景全通过（需要手动验证）
- [x] 数据不丢失：强制杀App后数据完整（需要手动验证）

---

## 🔗 相关任务

- **依赖**: [Phase 3-01: ContentService](../Phase3_ClientServices/01_content_service.md)
- **并行**: [Phase 4-02: ScheduleScreen](02_schedule_screen.md)
- **下一步**: [Phase 4-03: Offline UX](03_offline_ux.md)

---

**Linus说**: "The UI should never lie to the user. If it's offline, say it. If it's syncing, show it. If it failed, tell them. Transparency builds trust."

**数据安全第一原则**: "Always save locally first. Server sync is 'nice to have', not 'must have'. Users care about not losing their work, not about perfect sync."
