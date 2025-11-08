# Person Note Dialog Integration Guide

## Overview
When creating a NEW event, if the user sets a record number and there's existing handwriting in the database for that person (name + record number), show a confirmation dialog to prevent accidental overwriting.

## Implementation

### 1. Add onFocusChange to Record Number TextField

```dart
TextField(
  controller: recordNumberController,
  decoration: InputDecoration(labelText: '病歷號'),
  onChanged: (value) {
    controller.updateRecordNumber(value);
  },
  onEditingComplete: () async {
    // Called when user finishes typing (presses done/enter)
    await _checkForExistingPersonNote();
  },
  onTapOutside: (_) async {
    // Called when user taps outside the field
    await _checkForExistingPersonNote();
  },
)
```

### 2. Implement Check Method

```dart
Future<void> _checkForExistingPersonNote() async {
  // Check if existing person note exists
  final existingNote = await controller.checkExistingPersonNote();

  if (existingNote != null) {
    // Show confirmation dialog
    _showPersonNoteDialog(existingNote);
  }
}
```

### 3. Show Dialog

```dart
Future<void> _showPersonNoteDialog(Note existingNote) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('提示'),
      content: Text('此病歷號已有筆記（${existingNote.strokes.length} 筆畫），要載入現有筆記嗎？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('保留當前'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('載入現有'),
        ),
      ],
    ),
  );

  // Handle user choice
  if (result == true) {
    // User chose "載入現有" - load DB handwriting
    await controller.loadExistingPersonNote(existingNote);
  }
  // If result == false or null, user chose "保留當前" - do nothing
}
```

## Behavior

### Scenario 1: DB has handwriting, canvas is empty
1. User enters record number → Dialog appears
2. User chooses "載入現有" → DB handwriting appears on canvas
3. User chooses "保留當前" → Canvas stays empty

### Scenario 2: DB has handwriting, canvas has drawings
1. User enters record number → Dialog appears
2. User chooses "載入現有" → Canvas replaced with DB handwriting
3. User chooses "保留當前" → Canvas keeps current drawings

### Scenario 3: No DB handwriting exists
1. User enters record number → No dialog
2. Canvas keeps whatever was drawn (if any)

## Triggering the Check

The check is triggered when:
- User finishes editing record number field (onEditingComplete)
- User taps outside the record number field (onTapOutside)

NOT triggered during typing (per requirement).

## Save Behavior

When user saves the event:
- Whatever is on the canvas will be saved to DB
- If record number is set, it will sync to all events with same (name + record number)
- The dialog ensures user makes an informed choice before overwriting

## Important Notes

1. **Only for NEW events**: The check only runs for `isNew == true`
2. **Only when both name and record number exist**: Both fields must have values
3. **Only if DB has actual handwriting**: Empty notes in DB won't trigger dialog
4. **Safety fallback**: If dialog wasn't shown (e.g., user didn't trigger check), the save button has a safety check that auto-loads DB handwriting to prevent data loss
5. **Last-modified-wins**: When saving (and no existing DB note found), the current drawing is saved and syncs to all events in the person group

## Safety Mechanism

The implementation uses **defense-in-depth**:

### Layer 1: UI Dialog (Primary)
- Triggered when user finishes typing record number
- Shows explicit choice to user
- Best UX - user makes informed decision

### Layer 2: Save-Time Check (Fallback)
- Runs during save if new event has record number
- Auto-loads DB handwriting if exists
- **Never loses existing patient data** even if dialog wasn't shown
- Logged with warning: "Found existing person note, loading DB handwriting"

This ensures **100% patient data safety** even if:
- User bypasses the field check somehow
- Dialog fails to show due to timing issues
- UI integration is incomplete
