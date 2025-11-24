import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/event.dart';
import '../../models/event_type.dart';
import '../../models/note.dart';
import '../../services/database_service_interface.dart';
import '../../services/time_service.dart';

/// Utility class for heavy load testing in ScheduleScreen
class ScheduleTestUtils {
  /// Clear all events in the specified book
  static Future<void> clearAllEventsInBook(
    IDatabaseService dbService,
    String bookUuid,
  ) async {
    // Get all events in the book
    final allEvents = await dbService.getAllEventsByBook(bookUuid);

    if (allEvents.isEmpty) return;

    // Delete all events
    for (final event in allEvents) {
      if (event.id != null) {
        try {
          await dbService.deleteEvent(event.id!);
        } catch (e) {
          debugPrint('Error deleting event ${event.id}: $e');
        }
      }
    }
  }

  /// Show Clear All Events confirmation dialog
  static Future<void> showClearAllEventsDialog(
    BuildContext context,
    IDatabaseService dbService,
    String bookUuid,
  ) async {
    final l10n = AppLocalizations.of(context)!;

    // Get event count for confirmation
    final allEvents = await dbService.getAllEventsByBook(bookUuid);
    final eventCount = allEvents.length;

    if (eventCount == 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('目前沒有任何活動'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除所有活動'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              '確定要刪除本子中的所有 $eventCount 個活動嗎？',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '此操作無法復原！所有活動及其筆記將被永久刪除。',
              style: TextStyle(
                fontSize: 14,
                color: Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('確定刪除'),
          ),
        ],
      ),
    );

    if (result == true) {
      await clearAllEventsInBook(dbService, bookUuid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已刪除 $eventCount 個活動'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Show heavy load test confirmation dialog
  static Future<void> showHeavyLoadTestDialog(
    BuildContext context,
    IDatabaseService dbService,
    String bookUuid,
    StreamController<Map<String, dynamic>> progressController,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    bool clearAll = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.heavyLoadTest),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.heavyLoadTestWarning),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: Text(l10n.clearExistingEvents),
                value: clearAll,
                onChanged: (value) => setState(() => clearAll = value ?? false),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
              ),
              child: Text(l10n.heavyLoadTestConfirm),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await generateHeavyLoadTest(
        context: context,
        dbService: dbService,
        bookUuid: bookUuid,
        progressController: progressController,
        clearAll: clearAll,
      );
    }
  }

  /// Show Stage 1 Only confirmation dialog
  static Future<void> showHeavyLoadStage1Dialog(
    BuildContext context,
    IDatabaseService dbService,
    String bookUuid,
    StreamController<Map<String, dynamic>> progressController,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    bool clearAll = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.heavyLoadStage1Only),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.stage1OnlyWarning),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: Text(l10n.clearExistingEvents),
                value: clearAll,
                onChanged: (value) => setState(() => clearAll = value ?? false),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: Text(l10n.heavyLoadTestConfirm),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await generateHeavyLoadStage1(
        context: context,
        dbService: dbService,
        bookUuid: bookUuid,
        progressController: progressController,
        clearAll: clearAll,
      );
    }
  }

  /// Show Stage 2 Only confirmation dialog
  static Future<void> showHeavyLoadStage2Dialog(
    BuildContext context,
    IDatabaseService dbService,
    String bookUuid,
    StreamController<Map<String, dynamic>> progressController,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final stage2EventCountController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.heavyLoadStage2Only),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.stage2OnlyWarning),
            const SizedBox(height: 8),
            const Text(
              '提示：此功能將查詢所有記錄編號以 HEAVY- 開頭的活動，並為其添加筆畫。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: stage2EventCountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '事件數量 (留空=全部)',
                hintText: '輸入要處理的事件數量',
                border: OutlineInputBorder(),
                helperText: '留空將處理所有 HEAVY- 事件',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
            ),
            child: Text(l10n.heavyLoadTestConfirm),
          ),
        ],
      ),
    );

    if (result == true) {
      // Parse event count
      int? maxEvents;
      final inputText = stage2EventCountController.text.trim();
      if (inputText.isNotEmpty) {
        maxEvents = int.tryParse(inputText);
        if (maxEvents == null || maxEvents <= 0) {
          // Show error message
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('請輸入有效的正整數'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return;
        }
      }

      await generateHeavyLoadStage2(
        context: context,
        dbService: dbService,
        bookUuid: bookUuid,
        progressController: progressController,
        maxEvents: maxEvents,
      );
    }
  }

  /// Generate heavy load test data using two-stage approach
  static Future<void> generateHeavyLoadTest({
    required BuildContext context,
    required IDatabaseService dbService,
    required String bookUuid,
    required StreamController<Map<String, dynamic>> progressController,
    bool clearAll = false,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final startTime = DateTime.now();

    // Clear existing events if requested
    if (clearAll) {
      await clearAllEventsInBook(dbService, bookUuid);
    }

    // Constants
    const daysRange = 61; // 30 previous + today + 30 next
    const startHour = 9;
    const endHour = 20; // 9-20 (12 hours)
    const eventsPerHour = 4;
    const strokesPerEvent = 750;
    const totalEvents = daysRange * (endHour - startHour + 1) * eventsPerHour;

    final random = Random();
    final now = TimeService.instance.now();

    // Get available event types
    final eventTypes = [
      EventType.consultation,
      EventType.surgery,
      EventType.followUp,
      EventType.emergency,
      EventType.checkUp,
      EventType.treatment,
    ];

    // Show progress dialog
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l10n.generatingEvents),
          content: StreamBuilder<Map<String, dynamic>>(
            stream: progressController.stream,
            builder: (context, snapshot) {
              final data = snapshot.data ?? {
                'stage': 1,
                'count': 0,
                'total': totalEvents,
              };
              final stage = data['stage'] as int;
              final count = data['count'] as int;
              final total = data['total'] as int;
              final percent = total > 0 ? (count * 100 ~/ total) : 0;

              final stageLabel = stage == 1 ? l10n.stage1Creating : l10n.stage2AddingStrokes;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    stageLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: count / total),
                  const SizedBox(height: 16),
                  Text(l10n.heavyLoadTestProgress(count, total, percent)),
                ],
              );
            },
          ),
        ),
      ),
    );

    // ======================
    // STAGE 1: Create Events
    // ======================
    debugPrint('🚀 Heavy Load Test - Stage 1: Creating $totalEvents events...');
    int createdEventsCount = 0;
    final createdEventIds = <int>[];
    final startDate = now.subtract(const Duration(days: 30));

    for (int day = 0; day < daysRange; day++) {
      final date = startDate.add(Duration(days: day));

      for (int hour = startHour; hour <= endHour; hour++) {
        for (int eventIndex = 0; eventIndex < eventsPerHour; eventIndex++) {
          final minute = eventIndex * 15;
          final eventStartTime = DateTime(date.year, date.month, date.day, hour, minute);

          // Random name
          final names = [
            '王小明', '李小華', '張美玲', '陳志豪',
            '林淑芬', '黃建國', '吳雅婷', '鄭明哲',
            '劉佳穎', '許文祥', '楊淑惠', '蔡明道',
          ];
          final name = names[random.nextInt(names.length)];
          final recordNumber = 'HEAVY-${createdEventsCount + 1}';
          final eventType = eventTypes[random.nextInt(eventTypes.length)];

          final event = Event(
            bookUuid: bookUuid,
            name: name,
            recordNumber: recordNumber,
            eventTypes: [eventType],
            startTime: eventStartTime,
            endTime: null, // Open-ended
            createdAt: now,
            updatedAt: now,
          );

          try {
            final createdEvent = await dbService.createEvent(event);
            createdEventIds.add(createdEvent.id!);
            createdEventsCount++;

            // Update progress
            progressController.add({
              'stage': 1,
              'count': createdEventsCount,
              'total': totalEvents,
            });
          } catch (e) {
            debugPrint('❌ Error creating event: $e');
          }
        }
      }
    }

    debugPrint('✅ Stage 1 Complete: Created $createdEventsCount events');

    // ==========================
    // STAGE 2: Add Strokes
    // ==========================
    debugPrint('🚀 Heavy Load Test - Stage 2: Adding strokes to $createdEventsCount events...');
    int strokesAddedCount = 0;
    int totalStrokes = 0;

    for (int i = 0; i < createdEventIds.length; i++) {
      final eventId = createdEventIds[i];

      try {
        // Generate random strokes
        final strokes = generateRandomStrokes(strokesPerEvent);
        totalStrokes += strokes.length;

        // Create note with strokes
        final note = Note(
          eventId: eventId,
          pages: [strokes], // Wrap strokes in array for multi-page format
          createdAt: now,
          updatedAt: now,
        );

        await dbService.saveCachedNote(note);
        strokesAddedCount++;

        // Update progress
        progressController.add({
          'stage': 2,
          'count': strokesAddedCount,
          'total': createdEventsCount,
        });

        // Yield to UI thread every 5 events
        if (strokesAddedCount % 5 == 0) {
          await Future.delayed(Duration.zero);
        }
      } catch (e) {
        debugPrint('❌ Error adding strokes to event $eventId: $e');
      }
    }

    debugPrint('✅ Stage 2 Complete: Added strokes to $strokesAddedCount events');

    // Close progress dialog
    if (context.mounted) {
      Navigator.pop(context);
    }

    // Calculate elapsed time
    final elapsed = DateTime.now().difference(startTime);
    final elapsedSeconds = elapsed.inSeconds;
    final timeStr = elapsedSeconds >= 60
        ? '${elapsedSeconds ~/ 60}分${elapsedSeconds % 60}秒'
        : '${elapsedSeconds}秒';

    // Show completion message
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.heavyLoadTestComplete(createdEventsCount, totalStrokes, timeStr)),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    debugPrint('🎉 Heavy Load Test Complete: $createdEventsCount events, $totalStrokes strokes, $timeStr');
  }

  /// Stage 1 Only: Create events without strokes
  static Future<void> generateHeavyLoadStage1({
    required BuildContext context,
    required IDatabaseService dbService,
    required String bookUuid,
    required StreamController<Map<String, dynamic>> progressController,
    bool clearAll = false,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final startTime = DateTime.now();

    // Clear existing events if requested
    if (clearAll) {
      await clearAllEventsInBook(dbService, bookUuid);
    }

    // Constants
    const daysRange = 61; // 30 previous + today + 30 next
    const startHour = 9;
    const endHour = 20; // 9-20 (12 hours)
    const gridsPerHour = 4; // 4 grids per hour (0, 15, 30, 45 minutes)
    const eventsPerGrid = 4; // 4 events per grid
    const totalEvents = daysRange * (endHour - startHour + 1) * gridsPerHour * eventsPerGrid;

    final random = Random();
    final now = TimeService.instance.now();

    // Get available event types
    final eventTypes = [
      EventType.consultation,
      EventType.surgery,
      EventType.followUp,
      EventType.emergency,
      EventType.checkUp,
      EventType.treatment,
    ];

    // Show progress dialog
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l10n.stage1Creating),
          content: StreamBuilder<Map<String, dynamic>>(
            stream: progressController.stream,
            builder: (context, snapshot) {
              final data = snapshot.data ?? {'count': 0, 'total': totalEvents};
              final count = data['count'] as int;
              final total = data['total'] as int;
              final percent = total > 0 ? (count * 100 ~/ total) : 0;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: count / total),
                  const SizedBox(height: 16),
                  Text(l10n.heavyLoadTestProgress(count, total, percent)),
                ],
              );
            },
          ),
        ),
      ),
    );

    debugPrint('🚀 Stage 1: Creating $totalEvents events...');
    int createdEventsCount = 0;
    final startDate = now.subtract(const Duration(days: 30));

    for (int day = 0; day < daysRange; day++) {
      final date = startDate.add(Duration(days: day));

      for (int hour = startHour; hour <= endHour; hour++) {
        for (int gridIndex = 0; gridIndex < gridsPerHour; gridIndex++) {
          final minute = gridIndex * 15; // 0, 15, 30, 45
          final eventStartTime = DateTime(date.year, date.month, date.day, hour, minute);

          // Create 4 events for this grid (all with same start time)
          for (int eventIndex = 0; eventIndex < eventsPerGrid; eventIndex++) {
            // Random name
            final names = [
              '王小明', '李小華', '張美玲', '陳志豪',
              '林淑芬', '黃建國', '吳雅婷', '鄭明哲',
              '劉佳穎', '許文祥', '楊淑惠', '蔡明道',
            ];
            final name = names[random.nextInt(names.length)];
            final recordNumber = 'HEAVY-${createdEventsCount + 1}';
            final eventType = eventTypes[random.nextInt(eventTypes.length)];

            final event = Event(
              bookUuid: bookUuid,
              name: name,
              recordNumber: recordNumber,
              eventTypes: [eventType],
              startTime: eventStartTime,
              endTime: null, // Open-ended
              createdAt: now,
              updatedAt: now,
            );

            try {
              await dbService.createEvent(event);
              createdEventsCount++;

              // Update progress
              progressController.add({
                'count': createdEventsCount,
                'total': totalEvents,
              });
            } catch (e) {
              debugPrint('❌ Error creating event: $e');
            }
          }
        }
      }
    }

    debugPrint('✅ Stage 1 Complete: Created $createdEventsCount events');

    // Close progress dialog
    if (context.mounted) {
      Navigator.pop(context);
    }

    // Calculate elapsed time
    final elapsed = DateTime.now().difference(startTime);
    final elapsedSeconds = elapsed.inSeconds;
    final timeStr = elapsedSeconds >= 60
        ? '${elapsedSeconds ~/ 60}分${elapsedSeconds % 60}秒'
        : '${elapsedSeconds}秒';

    // Show completion message
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.stage1Complete(createdEventsCount) + ' ($timeStr)'),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    debugPrint('🎉 Stage 1 Complete: $createdEventsCount events, $timeStr');
  }

  /// Stage 2 Only: Add strokes to existing HEAVY- events
  static Future<void> generateHeavyLoadStage2({
    required BuildContext context,
    required IDatabaseService dbService,
    required String bookUuid,
    required StreamController<Map<String, dynamic>> progressController,
    int? maxEvents,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final startTime = DateTime.now();

    // Cancellation flag
    bool isCancelled = false;

    const strokesPerEvent = 750;
    final now = TimeService.instance.now();

    debugPrint('🔍 Stage 2: Querying existing HEAVY- events...');

    // Query all events in the book
    final allEvents = await dbService.getAllEventsByBook(bookUuid);

    var heavyEvents = allEvents.where((e) => e.recordNumber?.startsWith('HEAVY-') ?? false).toList();

    if (heavyEvents.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('找不到 HEAVY- 活動。請先執行階段1。'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Limit events if maxEvents is specified
    if (maxEvents != null && maxEvents < heavyEvents.length) {
      heavyEvents = heavyEvents.sublist(0, maxEvents);
      debugPrint('📋 Found ${allEvents.where((e) => e.recordNumber?.startsWith('HEAVY-') ?? false).length} HEAVY- events, processing first $maxEvents');
    } else {
      debugPrint('📋 Found ${heavyEvents.length} HEAVY- events');
    }

    // Show progress dialog
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l10n.stage2AddingStrokes),
          content: StreamBuilder<Map<String, dynamic>>(
            stream: progressController.stream,
            builder: (context, snapshot) {
              final data = snapshot.data ?? {'count': 0, 'total': heavyEvents.length};
              final count = data['count'] as int;
              final total = data['total'] as int;
              final percent = total > 0 ? (count * 100 ~/ total) : 0;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: count / total),
                  const SizedBox(height: 16),
                  Text(l10n.heavyLoadTestProgress(count, total, percent)),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                isCancelled = true;
              },
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );

    debugPrint('🚀 Stage 2: Adding strokes to ${heavyEvents.length} events...');
    int strokesAddedCount = 0;
    int totalStrokes = 0;

    for (int i = 0; i < heavyEvents.length; i++) {
      // Check for cancellation
      if (isCancelled) {
        debugPrint('⚠️ Stage 2 cancelled by user');
        break;
      }

      final event = heavyEvents[i];

      try {
        // Generate random strokes
        final strokes = generateRandomStrokes(strokesPerEvent);
        totalStrokes += strokes.length;

        // Create note with strokes
        final note = Note(
          eventId: event.id!,
          pages: [strokes], // Wrap strokes in array for multi-page format
          createdAt: now,
          updatedAt: now,
        );

        await dbService.saveCachedNote(note);
        strokesAddedCount++;

        // Update event recordNumber: HEAVY-xxx -> DONE-HEAVY-xxx
        final updatedEvent = event.copyWith(
          recordNumber: event.recordNumber?.replaceFirst('HEAVY-', 'DONE-HEAVY-'),
        );
        await dbService.updateEvent(updatedEvent);

        // Update progress
        progressController.add({
          'count': strokesAddedCount,
          'total': heavyEvents.length,
        });

        // Yield to UI thread every 5 events
        if (strokesAddedCount % 5 == 0) {
          await Future.delayed(Duration.zero);
        }
      } catch (e) {
        debugPrint('❌ Error adding strokes to event ${event.id}: $e');
      }
    }

    final wasCancelled = isCancelled;
    debugPrint(wasCancelled
      ? '⚠️ Stage 2 Cancelled: Added strokes to $strokesAddedCount events before cancellation'
      : '✅ Stage 2 Complete: Added strokes to $strokesAddedCount events');

    // Close progress dialog
    if (context.mounted) {
      Navigator.pop(context);
    }

    // Calculate elapsed time
    final elapsed = DateTime.now().difference(startTime);
    final elapsedSeconds = elapsed.inSeconds;
    final timeStr = elapsedSeconds >= 60
        ? '${elapsedSeconds ~/ 60}分${elapsedSeconds % 60}秒'
        : '${elapsedSeconds}秒';

    // Show completion message
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(wasCancelled
            ? '⚠️ 已取消：已處理 $strokesAddedCount 個事件 (共 $totalStrokes 筆畫)，耗時 $timeStr'
            : l10n.stage2Complete(strokesAddedCount, totalStrokes, timeStr)),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    debugPrint(wasCancelled
      ? '⚠️ Stage 2 Cancelled: $strokesAddedCount events, $totalStrokes strokes, $timeStr'
      : '🎉 Stage 2 Complete: $strokesAddedCount events, $totalStrokes strokes, $timeStr');
  }

  /// Generate random strokes for handwriting notes
  static List<Stroke> generateRandomStrokes(int count) {
    final random = Random();
    final strokes = <Stroke>[];

    // Define canvas dimensions for note area
    const canvasWidth = 300.0;
    const canvasHeight = 400.0;

    // Color palette for strokes
    final colors = [
      0xFF000000, // Black
      0xFF0000FF, // Blue
      0xFFFF0000, // Red
      0xFF00AA00, // Green
      0xFF800080, // Purple
    ];

    for (int i = 0; i < count; i++) {
      // Random number of points per stroke (20-50)
      final pointCount = 20 + random.nextInt(31);
      final points = <StrokePoint>[];

      // Generate a curved stroke path
      final startX = random.nextDouble() * canvasWidth;
      final startY = random.nextDouble() * canvasHeight;

      // Create points that follow a smooth curve
      for (int j = 0; j < pointCount; j++) {
        final t = j / pointCount; // Progress along the stroke (0 to 1)

        // Use sine wave for natural curve
        final offsetX = (random.nextDouble() - 0.5) * 20; // Small random variation
        final offsetY = (random.nextDouble() - 0.5) * 20;

        final x = startX + (t * 50) + offsetX; // Move across canvas
        final y = startY + (sin(t * pi * 2) * 10) + offsetY; // Sinusoidal curve

        // Clamp to canvas bounds
        final clampedX = x.clamp(0.0, canvasWidth);
        final clampedY = y.clamp(0.0, canvasHeight);

        final pressure = 0.5 + (random.nextDouble() * 0.5); // Vary pressure

        points.add(StrokePoint(clampedX, clampedY, pressure: pressure));
      }

      // Random color and width
      final color = colors[random.nextInt(colors.length)];
      final strokeWidth = 1.0 + random.nextDouble() * 2.0; // 1.0 to 3.0

      strokes.add(Stroke(
        points: points,
        strokeWidth: strokeWidth,
        color: color,
      ));
    }

    return strokes;
  }
}
