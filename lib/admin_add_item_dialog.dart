import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class AdminAddItemDialog extends StatefulWidget {
  const AdminAddItemDialog({super.key});

  @override
  State<AdminAddItemDialog> createState() => _AdminAddItemDialogState();
}

class _AdminAddItemDialogState extends State<AdminAddItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    try {
      final name = _nameCtrl.text.trim();
      final resp = await http.post(
        Uri.parse('$apiBaseUrl/insert_item'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );

      if (!mounted) return;
      if (resp.statusCode == 200) {
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Insert item failed: ${resp.statusCode} ${resp.body}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Insert item error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Item'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Item Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final s = v?.trim() ?? '';
                  if (s.isEmpty) return 'Name required';
                  return null;
                },
                enabled: !_isSaving,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _submit,
                  child: _isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Add'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

