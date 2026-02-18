import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/charge_item.dart';
import '../../../widgets/dialogs/charge_item_dialog.dart';
import '../event_detail_controller.dart';

/// Summary row that opens a popup for charge item management.
/// Charge items are linked to records (person-level), optionally filtered by event.
class ChargeItemsSection extends StatelessWidget {
  final List<ChargeItem> chargeItems;
  final EventDetailController controller;
  final bool hasRecordUuid;
  final bool showOnlyThisEventItems;

  const ChargeItemsSection({
    super.key,
    required this.chargeItems,
    required this.controller,
    required this.hasRecordUuid,
    required this.showOnlyThisEventItems,
  });

  int get _totalAmount =>
      chargeItems.fold(0, (sum, item) => sum + item.itemPrice);
  int get _receivedAmount =>
      chargeItems.fold(0, (sum, item) => sum + item.receivedAmount);

  Future<void> _openChargeItemsPopup(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final sheetWidth = constraints.maxWidth >= 900
                ? 820.0
                : constraints.maxWidth >= 600
                ? 620.0
                : constraints.maxWidth;

            return Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                child: SizedBox(
                  width: sheetWidth,
                  child: FractionallySizedBox(
                    heightFactor: 0.88,
                    child: _ChargeItemsPopup(
                      controller: controller,
                      hasRecordUuid: hasRecordUuid,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final progress = _totalAmount == 0
        ? 0.0
        : (_receivedAmount / _totalAmount).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openChargeItemsPopup(context),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.08),
                  theme.colorScheme.secondary.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.18),
              ),
            ),
            child: SizedBox(
              height: 62,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Text(
                      l10n.chargeItems,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Center(
                            child: SizedBox(
                              width: constraints.maxWidth * 0.8,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  minHeight: 8,
                                  value: progress,
                                  backgroundColor: theme.colorScheme.primary
                                      .withValues(alpha: 0.12),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'NT\$${_receivedAmount.toString()} / NT\$${_totalAmount.toString()}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    IconButton(
                      onPressed: () => _openChargeItemsPopup(context),
                      icon: const Icon(Icons.open_in_new_rounded, size: 19),
                      tooltip: l10n.chargeItems,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChargeItemsPopup extends StatefulWidget {
  final EventDetailController controller;
  final bool hasRecordUuid;

  const _ChargeItemsPopup({
    required this.controller,
    required this.hasRecordUuid,
  });

  @override
  State<_ChargeItemsPopup> createState() => _ChargeItemsPopupState();
}

class _ChargeItemsPopupState extends State<_ChargeItemsPopup> {
  List<ChargeItem> get _chargeItems => widget.controller.state.chargeItems;
  bool get _showOnlyThisEventItems =>
      widget.controller.state.showOnlyThisEventItems;

  int get _totalAmount =>
      _chargeItems.fold(0, (sum, item) => sum + item.itemPrice);
  int get _receivedAmount =>
      _chargeItems.fold(0, (sum, item) => sum + item.receivedAmount);

  void _refreshFromController() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleFilter() async {
    await widget.controller.toggleChargeItemsFilter();
    _refreshFromController();
  }

  Future<void> _addChargeItem() async {
    if (!widget.hasRecordUuid) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.chargeItemsRequireRecordNumber)),
      );
      return;
    }

    final result = await showDialog<ChargeItem>(
      context: context,
      builder: (context) => const ChargeItemDialog(),
    );

    if (result == null) {
      return;
    }

    await widget.controller.addChargeItem(
      result,
      associateWithEvent: _showOnlyThisEventItems,
    );
    _refreshFromController();
  }

  Future<void> _editChargeItem(ChargeItem item) async {
    final result = await showDialog<ChargeItem>(
      context: context,
      builder: (context) => ChargeItemDialog(existingItem: item),
    );

    if (result == null) {
      return;
    }

    await widget.controller.editChargeItem(result.copyWith(id: item.id));
    _refreshFromController();
  }

  Future<void> _deleteChargeItem(ChargeItem item) async {
    await widget.controller.deleteChargeItem(item);
    _refreshFromController();
  }

  Future<void> _togglePaidStatus(ChargeItem item) async {
    await widget.controller.toggleChargeItemPaidStatus(item);
    _refreshFromController();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final progress = _totalAmount == 0
        ? 0.0
        : (_receivedAmount / _totalAmount).clamp(0.0, 1.0);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Text(
                  l10n.chargeItems,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: l10n.cancel,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.4,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'NT\$${_receivedAmount.toString()} / NT\$${_totalAmount.toString()}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${(progress * 100).round()}%',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: progress,
                      backgroundColor: theme.colorScheme.primary.withValues(
                        alpha: 0.14,
                      ),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: SwitchListTile.adaptive(
              value: _showOnlyThisEventItems,
              onChanged: (_) => _toggleFilter(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: Text(
                _showOnlyThisEventItems ? 'This event only' : 'All items',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _addChargeItem,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.addChargeItem),
              ),
            ),
          ),
          Expanded(
            child: _chargeItems.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.addChargeItem,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: _chargeItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = _chargeItems[index];
                      final remainingAmount =
                          (item.itemPrice - item.receivedAmount) < 0
                          ? 0
                          : (item.itemPrice - item.receivedAmount);

                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          border: Border.all(
                            color: item.isPaid
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.22,
                                  )
                                : theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
                          child: Row(
                            children: [
                              Checkbox(
                                value: item.isPaid,
                                onChanged: (_) => _togglePaidStatus(item),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.itemName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            decoration: item.isPaid
                                                ? TextDecoration.lineThrough
                                                : TextDecoration.none,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'NT\$${item.receivedAmount} / NT\$${item.itemPrice}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: item.isPaid
                                                ? theme.colorScheme.primary
                                                : theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'NT\$${remainingAmount.toString()}',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: item.isPaid
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.secondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (item.isPaid) const SizedBox(height: 2),
                                  if (item.isPaid)
                                    Text(
                                      l10n.paid,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                          ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, size: 20),
                                tooltip: l10n.editChargeItemTitle,
                                onPressed: () => _editChargeItem(item),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 20,
                                ),
                                tooltip: l10n.delete,
                                onPressed: () => _deleteChargeItem(item),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
