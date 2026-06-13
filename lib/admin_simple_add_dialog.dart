import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Generic add dialog for tables that just need `{ name }` and an insert endpoint.
///
/// Used for admin tables like:
/// - purchase_vendors
/// - b_grade_clients
/// - packaging_vendors
/// - product_managers
class AdminSimpleAddDialog extends StatefulWidget {
  final String titleText;
  final String insertEndpoint;

  /// If backend requires an extra password (some tables), pass label.
  /// (Currently not used in the implemented UI.)
  final String? submitPasswordLabel;

  final bool requirePassword;

  const AdminSimpleAddDialog({
    super.key,
    required this.titleText,
    required this.insertEndpoint,
    this.submitPasswordLabel,
    this.requirePassword = false,
  });

  @override
  State<AdminSimpleAddDialog> createState() => _AdminSimpleAddDialogState();
}

class _AdminSimpleAddDialogState extends State<AdminSimpleAddDialog> {
  final _nameCtrl = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final uri = Uri.parse('$apiBaseUrl${widget.insertEndpoint}');

      final safeName = name.replaceAll('"', '\\"');
      final body = '{"name":"$safeName"}';

      final resp = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Add failed: ${resp.statusCode} ${resp.body}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Add error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titleText),
      content: TextField(
        controller: _nameCtrl,
        decoration: const InputDecoration(
          labelText: 'Name',
          border: OutlineInputBorder(),
        ),
        enabled: !_isSubmitting,
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('ADD'),
        ),
      ],
    );
  }
}

