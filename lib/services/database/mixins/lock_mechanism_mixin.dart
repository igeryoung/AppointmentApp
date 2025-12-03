import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'device_info_operations_mixin.dart';

/// Mixin providing Lock Mechanism operations for PRDDatabaseService
mixin LockMechanismMixin {
  /// Subclasses must provide database access
  Future<Database> get database;

  /// Required from DeviceInfoOperationsMixin
  Future<DeviceCredentials?> getDeviceCredentials();

  // ===================
  // Lock Mechanism
  // ===================

  static const int lockTimeoutMinutes = 5;

  /// Try to acquire a lock on a note for editing
  /// Returns true if lock was acquired, false if already locked by another device
  Future<bool> acquireNoteLock(String eventId) async {
    final db = await database;

    // Get current device ID
    final deviceCreds = await getDeviceCredentials();
    if (deviceCreds == null) {
      return false;
    }

    final now = DateTime.now();
    final staleLockCutoff = now.subtract(const Duration(minutes: lockTimeoutMinutes));

    try {
      final updatedRows = await db.rawUpdate('''
        UPDATE notes
        SET locked_by_device_id = ?,
            locked_at = ?
        WHERE event_id = ?
          AND (locked_by_device_id IS NULL
               OR locked_by_device_id = ?
               OR locked_at < ?)
      ''', [
        deviceCreds.deviceId,
        now.millisecondsSinceEpoch ~/ 1000,
        eventId,
        deviceCreds.deviceId,
        staleLockCutoff.millisecondsSinceEpoch ~/ 1000,
      ]);

      if (updatedRows > 0) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Release a lock on a note
  /// Only releases if current device holds the lock
  Future<void> releaseNoteLock(String eventId) async {
    final db = await database;

    // Get current device ID
    final deviceCreds = await getDeviceCredentials();
    if (deviceCreds == null) {
      return;
    }

    try {
      final updatedRows = await db.rawUpdate('''
        UPDATE notes
        SET locked_by_device_id = NULL,
            locked_at = NULL
        WHERE event_id = ?
          AND locked_by_device_id = ?
      ''', [eventId, deviceCreds.deviceId]);

      if (updatedRows > 0) {
      }
    } catch (e) {
    }
  }

  /// Clean up stale locks (older than lockTimeoutMinutes)
  /// Should be called periodically (e.g., every minute)
  Future<int> cleanupStaleLocks() async {
    final db = await database;
    final staleLockCutoff = DateTime.now()
        .subtract(const Duration(minutes: lockTimeoutMinutes))
        .millisecondsSinceEpoch ~/
        1000;

    try {
      final deletedRows = await db.rawUpdate('''
        UPDATE notes
        SET locked_by_device_id = NULL,
            locked_at = NULL
        WHERE locked_at IS NOT NULL
          AND locked_at < ?
      ''', [staleLockCutoff]);

      if (deletedRows > 0) {
      }
      return deletedRows;
    } catch (e) {
      return 0;
    }
  }

  /// Check if a note is currently locked by another device
  /// Returns true if locked by another device, false if unlocked or locked by current device
  Future<bool> isNoteLockedByOther(String eventId) async {
    final db = await database;

    // Get current device ID
    final deviceCreds = await getDeviceCredentials();
    if (deviceCreds == null) {
      return false; // If not registered, can't be locked by us
    }

    final staleLockCutoff = DateTime.now()
        .subtract(const Duration(minutes: lockTimeoutMinutes))
        .millisecondsSinceEpoch ~/
        1000;

    final result = await db.query(
      'notes',
      columns: ['locked_by_device_id', 'locked_at'],
      where: 'event_id = ?',
      whereArgs: [eventId],
      limit: 1,
    );

    if (result.isEmpty) return false;

    final lockedBy = result.first['locked_by_device_id'] as String?;
    final lockedAt = result.first['locked_at'] as int?;

    // Not locked
    if (lockedBy == null || lockedAt == null) return false;

    // Stale lock (expired)
    if (lockedAt < staleLockCutoff) return false;

    // Locked by current device
    if (lockedBy == deviceCreds.deviceId) return false;

    // Locked by another device
    return true;
  }
}
