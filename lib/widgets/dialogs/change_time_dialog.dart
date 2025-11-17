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
          final totalMinutes = duration.inMinutes % 60;
          // Round to nearest 15-minute interval
          durationMinutes = ((totalMinutes / 15).round() * 15).clamp(0, 45);
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
                          const SizedBox(height: 12),
                          // Inline Duration Spinners
                          Container(
                            height: 150,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Hours picker
                                Expanded(
                                  flex: 2,
                                  child: CupertinoPicker(
                                    scrollController: FixedExtentScrollController(initialItem: durationHours),
                                    itemExtent: 36,
                                    squeeze: 1.2,
                                    diameterRatio: 1.5,
                                    onSelectedItemChanged: (int index) {
                                      setState(() {
                                        durationHours = index;
                                      });
                                    },
                                    selectionOverlay: Container(
                                      decoration: BoxDecoration(
                                        border: Border.symmetric(
                                          horizontal: BorderSide(
                                            color: Colors.orange[200]!,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                    children: List<Widget>.generate(13, (int index) {
                                      return Center(
                                        child: Text(
                                          '$index',
                                          style: const TextStyle(
                                            fontSize: 24,
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
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                                // Minutes picker (0, 15, 30, 45)
                                Expanded(
                                  flex: 2,
                                  child: CupertinoPicker(
                                    scrollController: FixedExtentScrollController(
                                      initialItem: [0, 15, 30, 45].indexOf(durationMinutes).clamp(0, 3),
                                    ),
                                    itemExtent: 36,
                                    squeeze: 1.2,
                                    diameterRatio: 1.5,
                                    onSelectedItemChanged: (int index) {
                                      setState(() {
                                        durationMinutes = [0, 15, 30, 45][index];
                                      });
                                    },
                                    selectionOverlay: Container(
                                      decoration: BoxDecoration(
                                        border: Border.symmetric(
                                          horizontal: BorderSide(
                                            color: Colors.orange[200]!,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                    children: [0, 15, 30, 45].map((int minute) {
                                      return Center(
                                        child: Text(
                                          '$minute',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 16, left: 8),
                                  child: Text(
                                    'min',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),
                          const Divider(height: 1),
                          const SizedBox(height: 16),

                          // End Time (styled like Start Time)
                          Row(
                            children: [
                              Icon(Icons.event_available, size: 20, color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              const Text(
                                'End Time',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Text(
                              calculatedEndTime != null
                                  ? DateFormat('MMM d, yyyy • HH:mm', Localizations.localeOf(context).toString()).format(calculatedEndTime)
                                  : 'No end time (open-ended)',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: calculatedEndTime != null ? Colors.black87 : Colors.grey[500],
                              ),
                            ),
                          ),
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

}
