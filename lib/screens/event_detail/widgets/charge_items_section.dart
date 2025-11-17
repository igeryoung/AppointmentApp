import 'package:flutter/material.dart';
import '../../../models/charge_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/dialogs/charge_item_dialog.dart';
import '../event_detail_controller.dart';

/// Floating overlay section for managing charge items
/// Displays as a collapsed header that expands into an overlay panel
/// Charge items are synced across all events with the same name + record number
class ChargeItemsSection extends StatefulWidget {
  final List<ChargeItem> chargeItems;
  final EventDetailController controller;
  final bool hasRecordNumber; // Whether the event has a record number set

  const ChargeItemsSection({
    super.key,
    required this.chargeItems,
    required this.controller,
    required this.hasRecordNumber,
  });

  @override
  State<ChargeItemsSection> createState() => _ChargeItemsSectionState();
}

class _ChargeItemsSectionState extends State<ChargeItemsSection> {
  bool _isExpanded = false;
  final GlobalKey _headerKey = GlobalKey();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  int get _totalAmount => widget.chargeItems.fold(0, (sum, item) => sum + item.cost);
  int get _paidAmount => widget.chargeItems
      .where((item) => item.isPaid)
      .fold(0, (sum, item) => sum + item.cost);

  void _toggleExpanded() {
    if (_isExpanded) {
      _closeOverlay();
    } else {
      _openOverlay();
    }
  }

  void _openOverlay() {
    if (_overlayEntry != null) return;
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    setState(() => _isExpanded = true);
    _overlayEntry = _buildOverlayEntry();
    overlay.insert(_overlayEntry!);
  }

  void _closeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;

    if (_isExpanded) {
      setState(() => _isExpanded = false);
    }
  }

  OverlayEntry _buildOverlayEntry() {
    return OverlayEntry(
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        final theme = Theme.of(context);
        final headerRenderBox = _headerKey.currentContext?.findRenderObject() as RenderBox?;
        final headerWidth = headerRenderBox?.size.width ?? MediaQuery.of(context).size.width;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeOverlay,
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset.zero,
              child: SizedBox(
                width: headerWidth,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.transparent,
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
          ],
        );
      },
    );
  }

  Future<T?> _runDialogWithOverlayPaused<T>(Future<T?> Function() dialogBuilder) async {
    final wasExpanded = _isExpanded;
    if (wasExpanded) {
      _closeOverlay();
    }

    final result = await dialogBuilder();

    if (wasExpanded && mounted && !_isExpanded) {
      _openOverlay();
    }

    return result;
  }

  void _addChargeItem() async {
    // Check if record number is set
    if (!widget.hasRecordNumber) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.chargeItemsRequireRecordNumber ?? 'Please add a record number to track charge items')),
      );
      return;
    }

    final result = await _runDialogWithOverlayPaused(
      () => showDialog<ChargeItem>(
        context: context,
        builder: (context) => const ChargeItemDialog(),
      ),
    );

    if (result != null) {
      await widget.controller.addChargeItem(result);
    }
  }

  void _editChargeItem(int index) async {
    final item = widget.chargeItems[index];

    final result = await _runDialogWithOverlayPaused(
      () => showDialog<ChargeItem>(
        context: context,
        builder: (context) => ChargeItemDialog(existingItem: item),
      ),
    );

    if (result != null) {
      // Preserve the ID from the original item
      final updatedItem = result.copyWith(id: item.id);
      await widget.controller.editChargeItem(updatedItem);
    }
  }

  void _deleteChargeItem(int index) async {
    final item = widget.chargeItems[index];
    await widget.controller.deleteChargeItem(item);
  }

  void _togglePaidStatus(int index) async {
    final item = widget.chargeItems[index];
    await widget.controller.toggleChargeItemPaidStatus(item);
  }

  void _scheduleOverlayRebuild() {
    if (!_isExpanded || _overlayEntry == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isExpanded) return;
      _overlayEntry?.markNeedsBuild();
    });
  }

  @override
  void didUpdateWidget(covariant ChargeItemsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleOverlayRebuild();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleOverlayRebuild();
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return CompositedTransformTarget(
      link: _layerLink,
      child: Card(
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
    );
  }
}
