import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/event_type.dart';

/// Utility class for EventType localization
class EventTypeLocalizations {
  /// Get localized string for EventType
  static String getLocalizedEventType(BuildContext context, EventType type) {
    final l10n = AppLocalizations.of(context)!;
    switch (type) {
      case EventType.consultation:
        return l10n.consultation;
      case EventType.surgery:
        return l10n.surgery;
      case EventType.followUp:
        return l10n.followUp;
      case EventType.emergency:
        return l10n.emergency;
      case EventType.checkUp:
        return l10n.checkUp;
      case EventType.treatment:
        return l10n.treatment;
      case EventType.other:
        return 'Other';
    }
  }

  /// Common event types for quick selection
  static List<EventType> get commonEventTypes => [
        EventType.consultation,
        EventType.surgery,
        EventType.followUp,
        EventType.emergency,
        EventType.checkUp,
        EventType.treatment,
        EventType.other,
      ];
}
