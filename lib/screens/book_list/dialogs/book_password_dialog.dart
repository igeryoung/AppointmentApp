import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Generic dialog used to input a book password.
class BookPasswordDialog extends StatefulWidget {
  final String title;
  final String? description;
  final String? confirmLabel;

  const BookPasswordDialog({
    super.key,
    required this.title,
    this.description,
    this.confirmLabel,
  });

  static Future<String?> show(
    BuildContext context, {
    required String title,
    String? description,
    String? confirmLabel,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => BookPasswordDialog(
        title: title,
        description: description,
        confirmLabel: confirmLabel,
      ),
    );
  }

  @override
  State<BookPasswordDialog> createState() => _BookPasswordDialogState();
}

class _BookPasswordDialogState extends State<BookPasswordDialog> {
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.description != null && widget.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(widget.description!),
              ),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: l10n.bookPassword,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l10n.passwordRequired;
                }
                return null;
              },
              autofocus: true,
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel ?? l10n.confirm),
        ),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _passwordController.text.trim());
    }
  }
}
