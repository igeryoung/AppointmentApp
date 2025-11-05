import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

/// Status bar showing offline/syncing indicators
class EventDetailStatusBar extends StatelessWidget {
  final bool hasUnsyncedChanges;
  final bool isOffline;
  final bool isLoadingFromServer;

  const EventDetailStatusBar({
    super.key,
    required this.hasUnsyncedChanges,
    required this.isOffline,
    required this.isLoadingFromServer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Unsynced changes banner
        if (hasUnsyncedChanges && !isOffline)
          Material(
            color: Colors.blue.shade700,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context)!.syncingToServer,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),

        // Background loading indicator
        if (isLoadingFromServer && !hasUnsyncedChanges)
          const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }
}
