import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize date formatting for Traditional Chinese
  await initializeDateFormatting('zh_TW', null);

  // Note: setupServices() is called after checking server configuration
  // See ScheduleNoteApp for the initialization flow

  runApp(const ScheduleNoteApp());
}
