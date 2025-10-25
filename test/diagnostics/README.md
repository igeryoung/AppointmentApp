# Diagnostics Directory

此目录包含用于诊断和调试特定问题的测试文件。这些不是常规的单元测试或集成测试，而是用于验证特定 bug 修复或诊断问题的临时测试。

## 文件说明

- `canvas_state_diagnosis.dart` - 诊断 Canvas 状态管理问题
- `event_flow_diagnosis.dart` - 诊断事件流程问题
- `note_persistence_diagnosis.dart` - 诊断笔记持久化问题
- `bug_fix_verification.dart` - 验证 bug 修复
- `verify_time_change_fix.dart` - 验证时间变更功能修复

## 使用方法

这些诊断文件通常包含特定的测试场景和详细的日志输出，用于：
1. 重现特定 bug
2. 验证修复是否有效
3. 理解复杂的状态流转

## 维护

- ✅ 问题解决后应保留诊断文件作为回归测试
- ✅ 添加注释说明诊断的具体问题
- ⚠️ 这些文件可能包含大量调试日志，不适合 CI/CD 流程
