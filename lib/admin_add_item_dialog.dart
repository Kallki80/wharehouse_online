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
  final _weightCtrl = TextEditingController();
  bool _isSaving = false;
  bool? _inPieces; // how this item's stock is counted: false = kg, true = pieces

  @override
  void dispose() {
    _nameCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_inPieces == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose whether stock is counted in Kg or Pieces'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final name = _nameCtrl.text.trim();
      final resp = await http.post(
        Uri.parse('$apiBaseUrl/insert_item'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'stock_in_pcs': _inPieces,
          if (_inPieces == true) 'avg_piece_weight_kg': double.tryParse(_weightCtrl.text.trim()),
        }),
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
              const SizedBox(height: 14),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Stock is counted in', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 6),
              Row(children: [
                ChoiceChip(
                  label: const Text('Kg'),
                  selected: _inPieces == false,
                  onSelected: _isSaving ? null : (_) => setState(() => _inPieces = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Pieces (like papaya)'),
                  selected: _inPieces == true,
                  onSelected: _isSaving ? null : (_) => setState(() => _inPieces = true),
                ),
              ]),
              if (_inPieces == true) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Average weight of one piece (kg)',
                    helperText: 'Used to turn pieces into kg. Can also be entered daily.',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (_inPieces != true) return null;
                    final w = double.tryParse((v ?? '').trim());
                    if (w == null || w <= 0) return 'Enter the average weight';
                    return null;
                  },
                  enabled: !_isSaving,
                ),
              ],
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

