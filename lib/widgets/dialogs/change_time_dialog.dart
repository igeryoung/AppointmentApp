import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/datetime_picker_utils.dart';
import '../../constants/change_reasons.dart';

/// Result class for change time dialog
class ChangeEventTimeResult {
  final DateTime startTime;
  final DateTime? endTime;
  final String reason;

  const ChangeEventTimeResult({
    required this.startTime,
    required this.endTime,
    required this.reason,
  });
}

/// Dialog to change event time with reason
class ChangeTimeDialog {
  static Future<ChangeEventTimeResult?> show(
    BuildContext context, {
    required DateTime initialStartTime,
    required DateTime? initialEndTime,
  }) async {
    final l10n = AppLocalizations.of(context)!;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        DateTime newStartTime = initialStartTime;
        DateTime? newEndTime = initialEndTime;
        final additionalTextController = TextEditingController();
        String? selectedReason;
        String? reasonErrorMessage;

        // Calculate initial duration from start/end times
        int durationHours = 0;
        int durationMinutes = 0;
        if (initialEndTime != null) {
          final duration = initialEndTime.difference(initialStartTime);
          durationHours = duration.inHours;
          durationMinutes = duration.inMinutes % 60;
        }

        return StatefulBuilder(
          builder: (context, setState) {
            final showAdditionalField = ChangeReasons.requiresAdditionalInput(selectedReason);
            final bool hasValidReason = selectedReason != null &&
                (!showAdditionalField || additionalTextController.text.trim().isNotEmpty);

            // Calculate end time from start time + duration
            DateTime? calculatedEndTime;
            if (durationHours > 0 || durationMinutes > 0) {
              calculatedEndTime = newStartTime.add(Duration(
                hours: durationHours,
                minutes: durationMinutes,
              ));
            }

            return AlertDialog(
              title: Text(l10n.changeEventTimeTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.changeTimeMessage),
                  const SizedBox(height: 16),
                  // Start Time Picker
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            final result = await DateTimePickerUtils.pickDateTime(
                              context,
                              initialDateTime: newStartTime,
                            );
                            if (result == null) return;

                            setState(() {
                              newStartTime = result;
                            });
                          },
                          child: Text(
                            'Start: ${DateFormat('MMM d, HH:mm', Localizations.localeOf(context).toString()).format(newStartTime)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Duration Input Section
                  Row(
                    children: [
                      Text('Duration: ', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      // Duration picker button
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            await _showDurationPicker(
                              context,
                              initialHours: durationHours,
                              initialMinutes: durationMinutes,
                              onChanged: (hours, minutes) {
                                setState(() {
                                  durationHours = hours;
                                  durationMinutes = minutes;
                                });
                              },
                            );
                          },
                          child: Text(
                            (durationHours > 0 || durationMinutes > 0)
                                ? '${durationHours}h ${durationMinutes}m'
                                : 'Set Duration (Optional)',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      if (durationHours > 0 || durationMinutes > 0)
                        IconButton(
                          onPressed: () => setState(() {
                            durationHours = 0;
                            durationMinutes = 0;
                          }),
                          icon: const Icon(Icons.clear, size: 16),
                        ),
                    ],
                  ),
                  // Show calculated end time
                  if (calculatedEndTime != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 8),
                      child: Text(
                        'End: ${DateFormat('MMM d, HH:mm', Localizations.localeOf(context).toString()).format(calculatedEndTime)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(l10n.reasonForTimeChangeField, style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  // Dropdown for reason selection
                  DropdownButtonFormField<String>(
                    value: selectedReason,
                    decoration: InputDecoration(
                      hintText: '請選擇原因',
                      border: const OutlineInputBorder(),
                      errorText: reasonErrorMessage,
                    ),
                    isExpanded: true,
                    items: ChangeReasons.allReasons.map((reason) {
                      return DropdownMenuItem(
                        value: reason,
                        child: Text(reason),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedReason = value;
                        reasonErrorMessage = null;
                        // Clear additional text when switching away from "other"
                        if (!ChangeReasons.requiresAdditionalInput(value)) {
                          additionalTextController.clear();
                        }
                      });
                    },
                  ),
                  // Conditional text field for "other" option
                  if (showAdditionalField) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: additionalTextController,
                      decoration: const InputDecoration(
                        hintText: '請輸入其他原因...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                      autofocus: true,
                      onChanged: (value) {
                        setState(() {
                          // Trigger rebuild to update button state
                        });
                      },
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: () {
                    // Validation
                    if (selectedReason == null) {
                      setState(() {
                        reasonErrorMessage = '請選擇原因';
                      });
                      return;
                    }

                    // Format the reason based on selection
                    String finalReason;
                    if (showAdditionalField) {
                      final additionalText = additionalTextController.text.trim();
                      if (additionalText.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('請輸入其他原因')),
                        );
                        return;
                      }
                      finalReason = ChangeReasons.formatReason(selectedReason!, additionalText);
                    } else {
                      finalReason = selectedReason!;
                    }

                    Navigator.pop(context, {
                      'startTime': newStartTime,
                      'endTime': calculatedEndTime,
                      'reason': finalReason,
                    });
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: hasValidReason ? Theme.of(context).primaryColor : Colors.grey.shade300,
                    foregroundColor: hasValidReason ? Colors.white : Colors.grey.shade600,
                  ),
                  child: Text(l10n.changeTimeButton),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return null;

    return ChangeEventTimeResult(
      startTime: result['startTime'],
      endTime: result['endTime'],
      reason: result['reason'],
    );
  }

  /// Shows iPhone-style duration picker with spinners
  static Future<void> _showDurationPicker(
    BuildContext context, {
    required int initialHours,
    required int initialMinutes,
    required Function(int hours, int minutes) onChanged,
  }) async {
    int selectedHours = initialHours;
    int selectedMinutes = initialMinutes;

    // Create controllers for the pickers
    final FixedExtentScrollController hoursController = FixedExtentScrollController(
      initialItem: initialHours,
    );
    final FixedExtentScrollController minutesController = FixedExtentScrollController(
      initialItem: initialMinutes,
    );

    await showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          height: 300,
          color: Colors.white,
          child: Column(
            children: [
              // Header with Done button
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const Text(
                      'Duration',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    TextButton(
                      onPressed: () {
                        onChanged(selectedHours, selectedMinutes);
                        Navigator.pop(context);
                      },
                      child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              // Spinner pickers
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Hours picker
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: hoursController,
                        itemExtent: 40,
                        onSelectedItemChanged: (int index) {
                          selectedHours = index;
                        },
                        children: List<Widget>.generate(13, (int index) {
                          return Center(
                            child: Text(
                              '$index',
                              style: const TextStyle(fontSize: 24),
                            ),
                          );
                        }),
                      ),
                    ),
                    const Text('hours', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 16),
                    // Minutes picker
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: minutesController,
                        itemExtent: 40,
                        onSelectedItemChanged: (int index) {
                          selectedMinutes = index;
                        },
                        children: List<Widget>.generate(60, (int index) {
                          return Center(
                            child: Text(
                              '$index',
                              style: const TextStyle(fontSize: 24),
                            ),
                          );
                        }),
                      ),
                    ),
                    const Text('min', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    // Dispose controllers
    hoursController.dispose();
    minutesController.dispose();
  }
}
