import 'dart:io';

const _checklistPath = 'docs/testing/physical_device_test_checklist.md';
const _reportDir = 'docs/testing/reports';

const Map<String, List<String>> _operationToPipelineSteps = {
  'Install app fresh (clear old app data), then open app': [
    'Pipeline 10 - App Bootstrap & Setup Widget Paths',
  ],
  'Enter invalid server URL / unreachable server and continue': [
    'Pipeline 10 - App Bootstrap & Setup Widget Paths',
  ],
  'Register device with valid server config': [
    'Pipeline 12 - Live Event Metadata Roundtrip',
  ],
  'Force close app and reopen': [
    'Pipeline 10 - App Bootstrap & Setup Widget Paths',
  ],
  'Create a new book with valid name': [
    'Pipeline 02 - Create Book (server UUID source of truth)',
  ],
  'Try to create book with blank name': [
    'Pipeline 02 - Create Book (server UUID source of truth)',
  ],
  'Rename a book (with extra spaces before/after name)': [
    'Pipeline 04 - Rename/Reorder/Server Import Guards',
  ],
  'Archive a book': ['Pipeline 03 - Read/Archive/Delete Book'],
  'Delete a book': ['Pipeline 03 - Read/Archive/Delete Book'],
  'Reorder books by drag/drop, then relaunch app': [
    'Pipeline 04 - Rename/Reorder/Server Import Guards',
  ],
  'Open import-from-server flow, search by keyword, pull one book': [
    'Pipeline 04 - Rename/Reorder/Server Import Guards',
  ],
  'Try pulling a book that already exists locally': [
    'Pipeline 04 - Rename/Reorder/Server Import Guards',
  ],
  'In a selected book, create an event in schedule': [
    'Pipeline 05 - Create/Update/Delete/Reschedule Event',
  ],
  'Edit event title/type and save': [
    'Pipeline 05 - Create/Update/Delete/Reschedule Event',
  ],
  'Remove event with reason': [
    'Pipeline 05 - Create/Update/Delete/Reschedule Event',
  ],
  'Change event time (reschedule)': [
    'Pipeline 05 - Create/Update/Delete/Reschedule Event',
  ],
  'Delete event permanently': [
    'Pipeline 05 - Create/Update/Delete/Reschedule Event',
  ],
  'Navigate across day range/week and return': [],
  'Open Event Detail note and write strokes, then save': [
    'Pipeline 07 - Note Save/Load/Sync Apply',
    'Pipeline 09 - Event Detail Trigger -> Server -> Return -> Update',
  ],
  'Open another event with same record/person': [
    'Pipeline 07 - Note Save/Load/Sync Apply',
  ],
  'Create event for record that already has note, but do not write/update note and save':
      [
        'Pipeline 09 - Event Detail Trigger -> Server -> Return -> Update',
        'Pipeline 12 - Live Event Metadata Roundtrip',
      ],
  'Create no-record-number event with handwriting note, then reschedule time and open old/new events':
      ['Pipeline 12 - Live Event Metadata Roundtrip'],
  'Create no-record-number event, draw note and auto-save, then reenter and fill record number':
      ['Pipeline 12 - Live Event Metadata Roundtrip'],
  'Edit note again and save': ['Pipeline 07 - Note Save/Load/Sync Apply'],
  '(If note clear/delete action exists) clear note cache/content': [
    'Pipeline 07 - Note Save/Load/Sync Apply',
  ],
  'Draw on schedule overlay, leave screen, return to same date': [
    'Pipeline 08 - Drawing Save/Load/Update/Clear',
  ],
  'Update existing drawing on same date': [
    'Pipeline 08 - Drawing Save/Load/Update/Clear',
  ],
  'Switch date and return': ['Pipeline 08 - Drawing Save/Load/Update/Clear'],
  'In 2-day mode, draw on one page, navigate to previous page, then return': [
    'Pipeline 08 - Drawing Save/Load/Update/Clear',
  ],
  '(If clear action exists) clear drawing for date': [
    'Pipeline 08 - Drawing Save/Load/Update/Clear',
  ],
  'Complete setup once, then relaunch app multiple times': [
    'Pipeline 01 - Device Registration Gate',
    'Pipeline 10 - App Bootstrap & Setup Widget Paths',
  ],
  'Re-register / update device setup (if flow exists)': [
    'Pipeline 01 - Device Registration Gate',
  ],
  'Turn on airplane mode, try create/edit book/event/note': [
    'Pipeline 09 - Event Detail Trigger -> Server -> Return -> Update',
  ],
  'Re-enable network and retry same operation': [
    'Pipeline 09 - Event Detail Trigger -> Server -> Return -> Update',
  ],
  'Pull server data after reconnect': [
    'Pipeline 12 - Live Event Metadata Roundtrip',
  ],
  'Cold launch app on physical device': [],
  'Open book with dense schedule and scroll/navigate': [],
  'Open note/drawing-heavy screen and edit': [],
};

void main(List<String> args) {
  final explicitReportPath = _readArg(args, '--report');
  final reportFile = explicitReportPath == null
      ? _findLatestReportFile()
      : File(explicitReportPath);
  if (reportFile == null || !reportFile.existsSync()) {
    stderr.writeln('No report file found. Skip checklist auto-status update.');
    exitCode = 0;
    return;
  }

  final pipelineStatus = _parsePipelineStatus(reportFile.readAsLinesSync());
  final checklistFile = File(_checklistPath);
  if (!checklistFile.existsSync()) {
    stderr.writeln('Checklist not found: $_checklistPath');
    exitCode = 1;
    return;
  }

  final updated = _updateChecklist(
    lines: checklistFile.readAsLinesSync(),
    pipelineStatus: pipelineStatus,
  );
  checklistFile.writeAsStringSync('${updated.join('\n')}\n');
  stdout.writeln('Updated checklist auto-test column from ${reportFile.path}');
}

String? _readArg(List<String> args, String key) {
  final idx = args.indexOf(key);
  if (idx == -1 || idx + 1 >= args.length) return null;
  return args[idx + 1];
}

File? _findLatestReportFile() {
  final dir = Directory(_reportDir);
  if (!dir.existsSync()) return null;
  final candidates = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('user_pipeline_report_'))
      .toList();
  if (candidates.isEmpty) return null;
  candidates.sort(
    (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
  );
  return candidates.first;
}

Map<String, String> _parsePipelineStatus(List<String> lines) {
  final result = <String, String>{};
  final regex = RegExp(r'^\|\s*(Pipeline [^|]+?)\s*\|\s*(PASS|FAIL|SKIP)\s*\|');
  for (final line in lines) {
    final match = regex.firstMatch(line);
    if (match == null) continue;
    final step = match.group(1)!.trim();
    final status = match.group(2)!.trim();
    result[step] = status;
  }
  return result;
}

List<String> _updateChecklist({
  required List<String> lines,
  required Map<String, String> pipelineStatus,
}) {
  final output = <String>[];
  for (final line in lines) {
    if (line.trim() == '| Done | Operation | Expected Behavior |') {
      output.add('| Done | Auto Test | Operation | Expected Behavior |');
      continue;
    }
    if (line.trim() == '|---|---|---|') {
      output.add('|---|---|---|---|');
      continue;
    }

    if (!line.trimLeft().startsWith('|')) {
      output.add(line);
      continue;
    }

    final cells = _extractCells(line);
    if (cells == null) {
      output.add(line);
      continue;
    }

    if (cells.length == 3 && _isDoneCell(cells[0])) {
      final done = cells[0];
      final operation = cells[1];
      final expected = cells[2];
      final auto = _autoCell(operation, pipelineStatus);
      output.add('| $done | $auto | $operation | $expected |');
      continue;
    }

    if (cells.length == 4 && _isDoneCell(cells[0])) {
      final done = cells[0];
      final operation = cells[2];
      final expected = cells[3];
      final auto = _autoCell(operation, pipelineStatus);
      output.add('| $done | $auto | $operation | $expected |');
      continue;
    }

    output.add(line);
  }
  return output;
}

List<String>? _extractCells(String line) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('|') || !trimmed.endsWith('|')) return null;
  final raw = trimmed.split('|');
  if (raw.length < 4) return null;
  return raw.sublist(1, raw.length - 1).map((c) => c.trim()).toList();
}

bool _isDoneCell(String value) => value.startsWith('[') && value.endsWith(']');

String _autoCell(String operation, Map<String, String> pipelineStatus) {
  final steps = _operationToPipelineSteps[operation];
  if (steps == null || steps.isEmpty) return '[ ]';
  final allPass = steps.every((s) => pipelineStatus[s] == 'PASS');
  return allPass ? '[V]' : '[ ]';
}
