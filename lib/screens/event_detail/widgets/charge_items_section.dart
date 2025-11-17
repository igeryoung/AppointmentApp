import 'package:flutter/material.dart';
import '../../../models/charge_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/dialogs/charge_item_dialog.dart';

/// Floating overlay section for managing charge items
/// Displays as a collapsed header that expands into an overlay panel
class ChargeItemsSection extends StatefulWidget {
  final List<ChargeItem> chargeItems;
  final Function(List<ChargeItem>) onChargeItemsChanged;

  const ChargeItemsSection({
    super.key,
    required this.chargeItems,
    required this.onChargeItemsChanged,
  });

  @override
  State<ChargeItemsSection> createState() => _ChargeItemsSectionState();
}

class _ChargeItemsSectionState extends State<ChargeItemsSection> {
  bool _isExpanded = false;
  final GlobalKey _headerKey = GlobalKey();

  int get _totalAmount => widget.chargeItems.fold(0, (sum, item) => sum + item.cost);
  int get _paidAmount => widget.chargeItems
      .where((item) => item.isPaid)
      .fold(0, (sum, item) => sum + item.cost);

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
  }

  void _closeOverlay() {
    if (_isExpanded) {
      setState(() => _isExpanded = false);
    }
  }

  void _addChargeItem() async {
    final result = await showDialog<ChargeItem>(
      context: context,
      builder: (context) => const ChargeItemDialog(),
    );

    if (result != null) {
      final updatedItems = [...widget.chargeItems, result];
      widget.onChargeItemsChanged(updatedItems);
    }
  }

  void _editChargeItem(int index) async {
    final result = await showDialog<ChargeItem>(
      context: context,
      builder: (context) => ChargeItemDialog(existingItem: widget.chargeItems[index]),
    );

    if (result != null) {
      final updatedItems = [...widget.chargeItems];
      updatedItems[index] = result;
      widget.onChargeItemsChanged(updatedItems);
    }
  }

  void _deleteChargeItem(int index) {
    final updatedItems = [...widget.chargeItems];
    updatedItems.removeAt(index);
    widget.onChargeItemsChanged(updatedItems);
  }

  void _togglePaidStatus(int index) {
    final updatedItems = [...widget.chargeItems];
    updatedItems[index] = updatedItems[index].copyWith(
      isPaid: !updatedItems[index].isPaid,
    );
    widget.onChargeItemsChanged(updatedItems);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Main header (always visible)
        Card(
          key: _headerKey,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: InkWell(
            onTap: _toggleExpanded,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    _isExpanded ? Icons.expand_more : Icons.chevron_right,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.chargeItems,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'NT\$${_paidAmount.toString()} / NT\$${_totalAmount.toString()}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.secondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Floating overlay panel (shown when expanded)
        if (_isExpanded)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: GestureDetector(
              onTap: () {}, // Prevent closing when tapping inside panel
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header (same as collapsed state)
                      InkWell(
                        onTap: _toggleExpanded,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.expand_more,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.chargeItems,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'NT\$${_paidAmount.toString()} / NT\$${_totalAmount.toString()}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.secondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const Divider(height: 1),

                      // Add button (at top of list)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _addChargeItem,
                            icon: const Icon(Icons.add),
                            label: Text(l10n.addChargeItem),
                          ),
                        ),
                      ),

                      // Scrollable list of charge items
                      if (widget.chargeItems.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: widget.chargeItems.length,
                            itemBuilder: (context, index) {
                              final item = widget.chargeItems[index];
                              return ListTile(
                                leading: Checkbox(
                                  value: item.isPaid,
                                  onChanged: (_) => _togglePaidStatus(index),
                                ),
                                title: Text(item.itemName),
                                subtitle: Text(
                                  'NT\$${item.cost.toString()}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.secondary,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 20),
                                      onPressed: () => _editChargeItem(index),
                                      tooltip: l10n.editChargeItemTitle,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, size: 20),
                                      onPressed: () => _deleteChargeItem(index),
                                      tooltip: l10n.delete,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Invisible barrier to close overlay when clicking outside
        if (_isExpanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeOverlay,
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
      ],
    );
  }
}
