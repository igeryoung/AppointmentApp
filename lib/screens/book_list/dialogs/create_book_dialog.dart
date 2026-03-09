import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';

/// Dialog for creating a new book
/// Returns book name + password if created, null if cancelled
class CreateBookInput {
  final String name;
  final String password;

  const CreateBookInput({required this.name, required this.password});
}

class CreateBookDialog extends StatefulWidget {
  const CreateBookDialog({super.key});

  /// Show the dialog and return the create payload if confirmed
  static Future<CreateBookInput?> show(BuildContext context) {
    return showDialog<CreateBookInput>(
      context: context,
      builder: (context) => const CreateBookDialog(),
    );
  }

  @override
  State<CreateBookDialog> createState() => _CreateBookDialogState();
}

class _CreateBookDialogState extends State<CreateBookDialog> {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.createNewBook),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.bookName,
                hintText: l10n.enterBookName,
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l10n.bookNameRequired;
                }
                if (value.trim().length > 50) {
                  return l10n.bookNameTooLong;
                }
                return null;
              },
              autofocus: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
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
              textInputAction: TextInputAction.done,
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
        ElevatedButton(onPressed: _submit, child: Text(l10n.create)),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(
        context,
        CreateBookInput(
          name: _nameController.text.trim(),
          password: _passwordController.text.trim(),
        ),
      );
    }
  }
}
