import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';

/// Entries made only in pieces (no kg) need the average weight of one piece
/// before they can be saved (sales, B grade sales, mandi resale, dump sale,
/// stock update). The weight is saved as the item's weight per piece for that date.

bool _isPcsUnit(String? unit) {
  final u = (unit ?? '').trim().toLowerCase().replaceAll('.', '');
  return const {'pc', 'pcs', 'piece', 'pieces', 'nos', 'no', 'number', 'numbers'}.contains(u);
}

double _n(dynamic v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0.0);

/// quantity in pieces (unit pcs), or no kg but a pcs count.
bool isPiecesOnly(Map<String, dynamic> data, {String qtyKey = 'quantity', String unitKey = 'unit', String pcsKey = 'pcs'}) {
  final q = _n(data[qtyKey]);
  if (_isPcsUnit(data[unitKey]?.toString()) && q > 0) return true;
  return q <= 0 && _n(data[pcsKey]) > 0;
}

/// Pieces for the dialog text.
double piecesOf(Map<String, dynamic> data) =>
    _isPcsUnit(data['unit']?.toString()) && _n(data['quantity']) > 0 ? _n(data['quantity']) : _n(data['pcs']);

/// Adds the weight; when no kg was entered (only the pcs count), fills the kg as
/// pieces x weight and recalculates total / due when the entry has a rate.
void applyPieceWeight(Map<String, dynamic> data, double w) {
  data['avg_piece_weight_kg'] = w;
  final q = _n(data['quantity']);
  if (q <= 0 && !_isPcsUnit(data['unit']?.toString()) && _n(data['pcs']) > 0) {
    final kg = double.parse((_n(data['pcs']) * w).toStringAsFixed(3));
    data['quantity'] = kg;
    data['unit'] = 'Kg';
    if (data.containsKey('rate') && _n(data['rate']) > 0) {
      final total = double.parse((kg * _n(data['rate'])).toStringAsFixed(2));
      data['total_value'] = total;
      if (data.containsKey('amount_due')) data['amount_due'] = total - _n(data['amount_paid']);
    }
  }
}

/// Asks the weight per piece for every item in [pieces] ({item: pieces}).
/// Returns {item: kg per piece}, {} when nothing is needed, or null when cancelled.
Future<Map<String, double>?> askPieceWeights(BuildContext context, Map<String, double> pieces, DateTime date) async {
  if (pieces.isEmpty) return {};
  final d = DateFormat('yyyy-MM-dd').format(date);
  final ctrls = <String, TextEditingController>{};
  final hints = <String, String>{};
  for (final item in pieces.keys) {
    ctrls[item] = TextEditingController();
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/piece_weight/last').replace(queryParameters: {'item': item, 'date': d}))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final b = jsonDecode(res.body) as Map;
        final w = b['avg_piece_weight_kg'];
        if (w != null) {
          ctrls[item]!.text = '$w';
          hints[item] = b['from_date'] != null ? 'Last entered for ${b['from_date']}' : 'From Item Settings';
        }
      }
    } catch (_) {}
  }
  if (!context.mounted) return null;
  Map<String, double>? result;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      final values = {for (final e in ctrls.entries) e.key: double.tryParse(e.value.text.trim())};
      final ok = values.values.every((v) => v != null && v > 0 && v <= 50);
      return AlertDialog(
        icon: const Icon(Icons.scale, color: Colors.indigo),
        title: const Text('Average weight per piece'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('These items are entered only in pieces. Enter the average weight of one piece - '
                  'it is needed to save the entry.', style: TextStyle(fontSize: 12)),
              for (final item in pieces.keys) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: ctrls[item],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setD(() {}),
                  decoration: InputDecoration(
                    labelText: '$item - kg per piece (${pieces[item]!.toStringAsFixed(pieces[item]! % 1 == 0 ? 0 : 2)} pcs)',
                    helperText: hints[item],
                    border: const OutlineInputBorder(),
                    suffixText: 'kg',
                  ),
                ),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: ok
                ? () {
                    result = {for (final e in values.entries) e.key: e.value!};
                    Navigator.pop(ctx);
                  }
                : null,
            child: const Text('SAVE'),
          ),
        ],
      );
    }),
  );
  for (final c in ctrls.values) {
    c.dispose();
  }
  return result;
}

/// For a list of entry payloads: asks the weights of the pieces-only ones and
/// applies them. Returns false when cancelled.
Future<bool> ensurePieceWeights(BuildContext context, List<Map<String, dynamic>> entries, DateTime date) async {
  final need = <String, double>{};
  for (final e in entries) {
    if (isPiecesOnly(e)) {
      final item = '${e['item'] ?? ''}'.trim();
      if (item.isEmpty) continue;
      need[item] = (need[item] ?? 0) + piecesOf(e);
    }
  }
  if (need.isEmpty) return true;
  final w = await askPieceWeights(context, need, date);
  if (w == null) return false;
  for (final e in entries) {
    final item = '${e['item'] ?? ''}'.trim();
    if (w.containsKey(item) && isPiecesOnly(e)) applyPieceWeight(e, w[item]!);
  }
  return true;
}
