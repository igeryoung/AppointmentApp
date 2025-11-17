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
              title: Text(
                l10n.changeEventTimeTitle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.changeTimeMessage,
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 20),

                    // Time Section Card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Start Time
                          Row(
                            children: [
                              Icon(Icons.access_time, size: 20, color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              const Text(
                                'Start Time',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () async {
                              final result = await DateTimePickerUtils.pickDateTime(
                                context,
                                initialDateTime: newStartTime,
                              );
                              if (result == null) return;

                              setState(() {
                                newStartTime = result;
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Text(
                                DateFormat('MMM d, yyyy • HH:mm', Localizations.localeOf(context).toString()).format(newStartTime),
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),
                          const Divider(height: 1),
                          const SizedBox(height: 16),

                          // Duration
                          Row(
                            children: [
                              Icon(Icons.timer_outlined, size: 20, color: Colors.orange[700]),
                              const SizedBox(width: 8),
                              const Text(
                                'Duration',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              if (durationHours > 0 || durationMinutes > 0)
                                TextButton.icon(
                                  onPressed: () => setState(() {
                                    durationHours = 0;
                                    durationMinutes = 0;
                                  }),
                                  icon: const Icon(Icons.clear, size: 16),
                                  label: const Text('Clear', style: TextStyle(fontSize: 12)),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () async {
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
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: (durationHours > 0 || durationMinutes > 0)
                                    ? Colors.orange[300]!
                                    : Colors.grey[300]!,
                                  width: (durationHours > 0 || durationMinutes > 0) ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    (durationHours > 0 || durationMinutes > 0)
                                        ? '${durationHours}h ${durationMinutes}min'
                                        : 'Tap to set duration (optional)',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: (durationHours > 0 || durationMinutes > 0)
                                        ? FontWeight.w500
                                        : FontWeight.w400,
                                      color: (durationHours > 0 || durationMinutes > 0)
                                        ? Colors.black87
                                        : Colors.grey[600],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: Colors.grey[400],
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Calculated End Time
                          if (calculatedEndTime != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue[200]!),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.event_available, size: 16, color: Colors.blue[700]),
                                  const SizedBox(width: 8),
                                  Text(
                                    'End: ${DateFormat('MMM d • HH:mm', Localizations.localeOf(context).toString()).format(calculatedEndTime)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.blue[900],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Reason Section
                    Text(
                      l10n.reasonForTimeChangeField,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedReason,
                      decoration: InputDecoration(
                        hintText: '請選擇原因',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
                        ),
                        errorText: reasonErrorMessage,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down),
                      items: ChangeReasons.allReasons.map((reason) {
                        return DropdownMenuItem(
                          value: reason,
                          child: Text(reason, style: const TextStyle(fontSize: 14)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedReason = value;
                          reasonErrorMessage = null;
                          if (!ChangeReasons.requiresAdditionalInput(value)) {
                            additionalTextController.clear();
                          }
                        });
                      },
                    ),

                    // Additional text field for "other" option
                    if (showAdditionalField) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: additionalTextController,
                        decoration: InputDecoration(
                          hintText: '請輸入其他原因...',
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        maxLines: 2,
                        autofocus: true,
                        onChanged: (value) {
                          setState(() {});
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    l10n.cancel,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: hasValidReason ? () {
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
                  } : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade600,
                  ),
                  child: Text(
                    l10n.changeTimeButton,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
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
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          height: 340,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header with Done button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey[600],
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.timer_outlined, color: Colors.orange[700], size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Set Duration',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () {
                        onChanged(selectedHours, selectedMinutes);
                        Navigator.pop(context);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).primaryColor,
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),
              const SizedBox(height: 8),

              // Spinner pickers
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Hours picker
                    Expanded(
                      flex: 2,
                      child: CupertinoPicker(
                        scrollController: hoursController,
                        itemExtent: 48,
                        squeeze: 1.1,
                        diameterRatio: 1.5,
                        onSelectedItemChanged: (int index) {
                          selectedHours = index;
                        },
                        selectionOverlay: Container(
                          decoration: BoxDecoration(
                            border: Border.symmetric(
                              horizontal: BorderSide(
                                color: Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                        children: List<Widget>.generate(13, (int index) {
                          return Center(
                            child: Text(
                              '$index',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'hours',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),

                    // Minutes picker
                    Expanded(
                      flex: 2,
                      child: CupertinoPicker(
                        scrollController: minutesController,
                        itemExtent: 48,
                        squeeze: 1.1,
                        diameterRatio: 1.5,
                        onSelectedItemChanged: (int index) {
                          selectedMinutes = index;
                        },
                        selectionOverlay: Container(
                          decoration: BoxDecoration(
                            border: Border.symmetric(
                              horizontal: BorderSide(
                                color: Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                        children: List<Widget>.generate(60, (int index) {
                          return Center(
                            child: Text(
                              '$index',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 16, left: 8),
                      child: Text(
                        'min',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
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
