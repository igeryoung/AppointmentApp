import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize date formatting for Traditional Chinese
  await initializeDateFormatting('zh_TW', null);

  runApp(const ScheduleNoteApp());
}
