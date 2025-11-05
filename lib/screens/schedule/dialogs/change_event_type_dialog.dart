import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/event.dart';
import '../../../models/event_type.dart';

/// Show dialog to change event type
Future<EventType?> showChangeEventTypeDialog(
  BuildContext context,
  Event event,
  List<EventType> eventTypes,
  String Function(BuildContext, EventType) getLocalizedEventType,
) async {
  final l10n = AppLocalizations.of(context)!;

  return showDialog<EventType>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.changeEventType),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: eventTypes
            .map((type) => ListTile(
                  title: Text(getLocalizedEventType(context, type)),
                  leading: Radio<EventType>(
                    value: type,
                    groupValue: event.eventType,
                    onChanged: (value) => Navigator.pop(context, value),
                  ),
                  onTap: () => Navigator.pop(context, type),
                ))
            .toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    ),
  );
}
