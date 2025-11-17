import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/charge_item.dart';
import '../../l10n/app_localizations.dart';

/// Dialog for adding or editing a charge item
class ChargeItemDialog extends StatefulWidget {
  final ChargeItem? existingItem;

  const ChargeItemDialog({
    super.key,
    this.existingItem,
  });

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
    _nameController = TextEditingController(text: widget.existingItem?.itemName ?? '');
    _costController = TextEditingController(
      text: widget.existingItem != null ? widget.existingItem!.cost.toString() : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _handleSave() {
    if (_formKey.currentState!.validate()) {
      final chargeItem = ChargeItem(
        itemName: _nameController.text.trim(),
        cost: int.parse(_costController.text.trim()),
        isPaid: widget.existingItem?.isPaid ?? false,
      );
      Navigator.of(context).pop(chargeItem);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEditing = widget.existingItem != null;

    return AlertDialog(
      title: Text(isEditing ? l10n.editChargeItemTitle : l10n.addChargeItemTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Item Name Field
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.chargeItemName,
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l10n.chargeItemNameRequired;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // Cost Field
            TextFormField(
              controller: _costController,
              decoration: InputDecoration(
                labelText: l10n.chargeItemCost,
                border: const OutlineInputBorder(),
                prefixText: 'NT\$ ',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _handleSave,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
