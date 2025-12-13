import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'screens/book_list/book_list_screen.dart';
import 'screens/server_setup_screen.dart';
import 'services/database/prd_database_service.dart';
import 'services/service_locator.dart';

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
      home: const _AppInitializer(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Widget that checks server configuration and initializes services
class _AppInitializer extends StatefulWidget {
  const _AppInitializer();

  @override
  State<_AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<_AppInitializer> {
  bool _isLoading = true;
  bool _isServerConfigured = false;
  String? _serverUrl;

  @override
  void initState() {
    super.initState();
    _checkServerConfiguration();
  }

  Future<void> _checkServerConfiguration() async {
    try {
      final dbService = PRDDatabaseService();
      final db = await dbService.database;

      // Check if server URL exists in device_info
      final rows = await db.query('device_info', limit: 1);

      if (rows.isNotEmpty && rows.first['server_url'] != null) {
        final serverUrl = rows.first['server_url'] as String;
        // Server is configured, initialize services
        await setupServices(serverUrl: serverUrl);
        setState(() {
          _isServerConfigured = true;
          _serverUrl = serverUrl;
          _isLoading = false;
        });
      } else {
        // Server not configured, show setup screen
        setState(() {
          _isServerConfigured = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      // On error, show setup screen
      setState(() {
        _isServerConfigured = false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_isServerConfigured) {
      return const BookListScreen();
    } else {
      return const ServerSetupScreen();
    }
  }
}