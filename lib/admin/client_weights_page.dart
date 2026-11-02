import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_config.dart';

/// Item Profit: weight of one piece / unit, client-wise, shown before the report.
/// Pieces / units sold of an item counted in kg (or kg of an item counted in
/// pieces) are converted with these weights. Saved values are shown and can be
/// changed; suggestions (weight in the product name, item average weight) are
/// saved for the client on OK. Returns true on OK, null when cancelled.
class ClientWeightsPage extends StatefulWidget {
  final String start;
  final String end;
  final List<Map<String, dynamic>> rows;
  const ClientWeightsPage({super.key, required this.start, required this.end, required this.rows});

  /// Shows the weights (when any line needs one); true = go on with the report.
  static Future<bool> confirm(BuildContext context, String start, String end) async {
    final res = await http.get(Uri.parse('$baseUrl/item_profit/weights').replace(queryParameters: {'start': start, 'end': end}));
    if (res.statusCode != 200) throw Exception('Server error ${res.statusCode} - is the new server file installed?');
    final b = jsonDecode(res.body) as Map;
    final rows = ((b['rows'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (rows.isEmpty) return true;
    if (!context.mounted) return false;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ClientWeightsPage(start: start, end: end, rows: rows)),
    );
    return ok == true;
  }

  @override
  State<ClientWeightsPage> createState() => _ClientWeightsPageState();
}

class _ClientWeightsPageState extends State<ClientWeightsPage> {
  late final List<Map<String, dynamic>> _rows;
  final Map<int, TextEditingController> _c = {};
  bool _saving = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _rows = List.of(widget.rows);
    for (var i = 0; i < _rows.length; i++) {
      final w = _rows[i]['kg_per_unit'];
      _c[i] = TextEditingController(text: w == null ? '' : _n(w));
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _n(dynamic v) {
    final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    if (d == null) return '';
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  }

  Future<void> _ok() async {
    final empty = <int>[];
    final send = <Map<String, dynamic>>[];
    for (var i = 0; i < _rows.length; i++) {
      final t = _c[i]!.text.trim();
      final v = double.tryParse(t);
      if (t.isNotEmpty && (v == null || v <= 0)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Check the weight of ${_rows[i]['item']} for ${_rows[i]['client']}'), backgroundColor: Colors.red));
        return;
      }
      if (v == null) empty.add(i);
      send.add({
        'client': _rows[i]['client'],
        'product_key': _rows[i]['product_key'],
        'product_name': _rows[i]['product_name'],
        'item': _rows[i]['item'],
        'unit': _rows[i]['unit'],
        'kg_per_unit': v,
      });
    }
    if (empty.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Some weights are empty'),
          content: Text('${empty.length} line(s) have no weight - their sales will be left out of the profit ("not costed"). Go on?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ENTER WEIGHTS')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('GO ON')),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() => _saving = true);
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/item_profit/weights'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'rows': send}),
      );
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Not saved: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = [
      for (var i = 0; i < _rows.length; i++)
        if (_search.isEmpty || '${_rows[i]['client']} ${_rows[i]['item']} ${_rows[i]['product_name']}'.toLowerCase().contains(_search)) i
    ];
    final missing = _rows.where((r) => r['kg_per_unit'] == null).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Weight per piece / unit')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48)),
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: const Size(64, 48)),
                onPressed: _saving ? null : _ok,
                child: Text(_saving ? 'Saving...' : 'OK - SAVE & CALCULATE'),
              ),
            ),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
        Card(
          color: Colors.indigo.shade50,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'These items were sold in pieces / units (or in kg for items counted in pieces). The weight of one piece / unit '
              'can be different for each client, so it is saved client-wise. Saved weights are filled in - change them if '
              'needed. Suggested weights (from the product name or the item\'s average weight) are saved for the client when '
              'you press OK.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
        if (missing > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('$missing line(s) have no weight yet', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700)),
          ),
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search client or item', isDense: true),
          onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 6),
        for (final i in idx) _card(i),
      ]),
    );
  }

  Widget _card(int i) {
    final r = _rows[i];
    final unit = '${r['unit']}'.isEmpty ? 'unit' : '${r['unit']}';
    final perPiece = r['item_unit'] == 'pcs';
    final src = r['source'];
    final saved = r['saved'] == true;
    final none = r['kg_per_unit'] == null;
    return Card(
      key: ValueKey('cw-$i'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: none ? RoundedRectangleBorder(side: BorderSide(color: Colors.red.shade300), borderRadius: BorderRadius.circular(12)) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${r['client']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('${r['item']}  ·  ${r['product_name'] ?? ''}', style: const TextStyle(fontSize: 12)),
          Text('Sold ${_n(r['qty'])} $unit (₹${_n(r['value'])}) · item counted in ${r['item_unit']}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          TextField(
            controller: _c[i],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              isDense: true,
              labelText: perPiece ? 'Weight of one piece (kg)' : 'Weight of one $unit (kg)',
              helperText: none
                  ? 'Not known - enter the weight for this client'
                  : (saved ? 'Saved for this client - change if needed' : 'Suggested: $src - check and change if needed'),
              helperStyle: TextStyle(fontSize: 11, color: none ? Colors.red.shade700 : (saved ? Colors.green.shade800 : Colors.orange.shade900)),
            ),
          ),
        ]),
      ),
    );
  }
}
