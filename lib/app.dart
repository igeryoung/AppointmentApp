import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'screens/book_list_screen.dart';

/// PRD-compliant Appointment Registration App
/// Hierarchy: Book → Schedule → Event → Note
class ScheduleNoteApp extends StatelessWidget {
  const ScheduleNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', ''), // Chinese (general)
        Locale('zh', 'TW'), // Traditional Chinese (Taiwan)
      ],
      locale: const Locale('zh', 'TW'), // Set Traditional Chinese as default
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        // Mobile-optimized theme
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const BookListScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}