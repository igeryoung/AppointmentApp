# Simplified Appointment App Specification

## Linus Review Status: ✅ APPROVED (after major simplification)

**原则：先让它工作，再让它完美。复杂性是万恶之源。**

## 1. Core Problem Statement

**Real Problem:** Medical professionals need to schedule appointments and take handwritten notes.

**NOT solving:** Theoretical scheduling perfection, enterprise integration fantasies.

## 2. Data Structure (The Only Thing That Matters)

```sql
-- 两张表，完成
CREATE TABLE books (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE TABLE appointments (
  id INTEGER PRIMARY KEY,
  book_id INTEGER NOT NULL REFERENCES books(id),
  start_time INTEGER NOT NULL,  -- Unix timestamp
  duration INTEGER DEFAULT 0,   -- 分钟，0 = 开放式
  name TEXT,
  record_number TEXT,
  type TEXT,
  note_strokes BLOB,            -- 手写数据直接存储
  created_at INTEGER DEFAULT (strftime('%s', 'now')),
  updated_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX idx_appointments_time ON appointments(book_id, start_time);
```

## 3. UI Structure (3 Screens, Done)

### Screen 1: Book List
- 显示所有books
- 点击进入book的日历
- 新建/删除book

### Screen 2: Daily Calendar
- 显示今天的appointments
- 点击时间槽创建appointment
- 点击appointment编辑/删除

### Screen 3: Appointment Detail
- 基本信息编辑
- 手写笔记区域（90%的屏幕）

## 4. Implementation Phases

### Phase 1: MVP (2周)
- [x] **Task:** SQLite schema setup
- [ ] **Task:** Book CRUD operations
- [ ] **Task:** Basic appointment CRUD
- [ ] **Task:** Simple daily view
- [ ] **Task:** Basic handwriting canvas

**Definition of Done:** 能创建book，添加appointment，手写笔记

### Phase 2: Polish (1周)
- [ ] **Task:** Handwriting optimization (<30ms latency)
- [ ] **Task:** Auto-save implementation
- [ ] **Task:** Basic error handling

**Definition of Done:** 手写流畅，数据不丢失

### Phase 3: Future (Maybe)
- Search appointments
- Export功能
- 云同步 (单独项目)

## 5. Rejected Features (Linus Says No)

### ❌ Schedule抽象层
**Why:** 不是数据，只是appointments的视图。过度设计。

### ❌ 多种日历视图
**Why:** Day/Week/Month都是相同查询，不同WHERE条件。先做一个。

### ❌ "可选"云同步
**Why:** 要么有要么没有。"可选"增加复杂性和测试负担。

### ❌ 复杂加密
**Why:** 先能用，安全性后面迭代。

### ❌ 独立Note实体
**Why:** 1:1关系应该嵌入，不要单独表。

## 6. Technical Constraints

### Platform
- Flutter (Skia渲染，手写性能好)
- 本地SQLite存储
- 离线优先

### Performance Targets
- App启动 < 2秒
- 手写延迟 < 30ms
- 日历切换 < 200ms

### Data Limits
- 每个book最多10,000 appointments（索引优化）
- 手写笔记最大1MB per appointment

## 7. File Structure

```
lib/
├── main.dart
├── models/
│   ├── book.dart
│   └── appointment.dart
├── screens/
│   ├── book_list_screen.dart
│   ├── calendar_screen.dart
│   └── appointment_detail_screen.dart
├── widgets/
│   └── handwriting_canvas.dart
└── database/
    └── database.dart
```

## 8. Success Metrics

- **Primary:** 用户能成功创建appointment并手写笔记
- **Secondary:** 手写延迟确实 < 30ms
- **Tertiary:** 无数据丢失事故

---

**Linus Note:** 这个spec从277行减少到了150行，删除了70%的复杂性，但仍然解决核心问题。现在去实现它，别再加功能了。