import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../lib/services/prd_database_service.dart';

/// Utility to update server URL from HTTP to HTTPS
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize FFI for desktop testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Create database service
  final dbService = PRDDatabaseService();

  print('📋 Checking current server URL...');
  final db = await dbService.database;

  // Check current URL
  final rows = await db.query('device_info', limit: 1);
  if (rows.isEmpty) {
    print('❌ No device_info found. Please register device first.');
    return;
  }

  final currentUrl = rows.first['server_url'] as String?;
  print('Current URL: $currentUrl');

  if (currentUrl == null) {
    print('❌ No server URL configured.');
    return;
  }

  // Update HTTP to HTTPS
  if (currentUrl.startsWith('http://')) {
    final newUrl = currentUrl.replaceFirst('http://', 'https://');
    print('\n🔄 Updating URL...');
    print('   From: $currentUrl');
    print('   To:   $newUrl');

    await db.update(
      'device_info',
      {'server_url': newUrl},
      where: 'id = 1',
    );

    // Verify update
    final updatedRows = await db.query('device_info', limit: 1);
    final verifyUrl = updatedRows.first['server_url'] as String?;

    if (verifyUrl == newUrl) {
      print('✅ Server URL updated successfully!');
      print('   New URL: $verifyUrl');
    } else {
      print('❌ Update failed. URL: $verifyUrl');
    }
  } else if (currentUrl.startsWith('https://')) {
    print('✅ URL already uses HTTPS: $currentUrl');
  } else {
    print('⚠️  Unexpected URL format: $currentUrl');
  }

  await db.close();
}
