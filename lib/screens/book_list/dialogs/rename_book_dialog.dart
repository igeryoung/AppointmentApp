import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/book.dart';

/// Dialog for renaming a book
/// Returns the new name if renamed, null if cancelled
class RenameBookDialog extends StatefulWidget {
  final Book book;

  const RenameBookDialog({
    super.key,
    required this.book,
  });

  /// Show the dialog and return the new name if renamed
  static Future<String?> show(BuildContext context, {required Book book}) {
    return showDialog<String>(
      context: context,
      builder: (context) => RenameBookDialog(book: book),
    );
  }

  @override
  State<RenameBookDialog> createState() => _RenameBookDialogState();
}

class _RenameBookDialogState extends State<RenameBookDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.book.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.renameBook),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: l10n.bookName,
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
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(l10n.save),
        ),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }
}
