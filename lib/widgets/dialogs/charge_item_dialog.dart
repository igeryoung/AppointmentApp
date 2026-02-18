import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/charge_item.dart';

/// Dialog for adding or editing a charge item.
class ChargeItemDialog extends StatefulWidget {
  final ChargeItem? existingItem;

  const ChargeItemDialog({super.key, this.existingItem});

  @override
  State<ChargeItemDialog> createState() => _ChargeItemDialogState();
}

class _ChargeItemDialogState extends State<ChargeItemDialog> {
  late TextEditingController _nameController;
  late TextEditingController _costController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingItem?.itemName ?? '',
    );
    _costController = TextEditingController(
      text: widget.existingItem != null
          ? widget.existingItem!.itemPrice.toString()
          : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _handleSave() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final chargeItem = ChargeItem(
      id: widget.existingItem?.id,
      recordUuid: widget.existingItem?.recordUuid ?? '',
      eventId: widget.existingItem?.eventId,
      itemName: _nameController.text.trim(),
      itemPrice: int.parse(_costController.text.trim()),
      receivedAmount: widget.existingItem?.receivedAmount ?? 0,
    );
    Navigator.of(context).pop(chargeItem);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEditing = widget.existingItem != null;
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenWidth < 420 ? 20 : 28,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                      ),
                      child: Icon(
                        isEditing
                            ? Icons.edit_rounded
                            : Icons.add_circle_outline_rounded,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isEditing
                            ? l10n.editChargeItemTitle
                            : l10n.addChargeItemTitle,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: l10n.chargeItemName,
                    hintText: l10n.chargeItemName,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.inventory_2_outlined),
                  ),
                  textInputAction: TextInputAction.next,
                  autofocus: true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.chargeItemNameRequired;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _costController,
                  decoration: InputDecoration(
                    labelText: l10n.chargeItemCost,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.attach_money_rounded),
                    prefixText: 'NT\$ ',
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handleSave(),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.chargeItemCostInvalid;
                    }
                    final cost = int.tryParse(value.trim());
                    if (cost == null || cost <= 0) {
                      return l10n.chargeItemCostInvalid;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l10n.cancel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _handleSave,
                        child: Text(l10n.save),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
