import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';

/// Admin › GPM Saved Values
///
/// Values entered when GPM asked before the report - change or delete them
/// later: kg in one box / bag / piece, average weight per piece on a date, and
/// rates entered for stock older than the first purchase (or with no PO rate).
/// A deleted value is asked again by the next GPM report.
class GpmSavedValuesPage extends StatefulWidget {
  const GpmSavedValuesPage({super.key});

  @override
  State<GpmSavedValuesPage> createState() => _GpmSavedValuesPageState();
}

class _GpmSavedValuesPageState extends State<GpmSavedValuesPage> {
  bool _loading = true;
  String? _error;
  String _search = '';
  List<Map<String, dynamic>> _unitW = [];
  List<Map<String, dynamic>> _pieceW = [];
  List<Map<String, dynamic>> _rates = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _l(dynamic v) => ((v as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse('$baseUrl/gpm/saved_values'));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode} - is the new server file installed?');
      final b = jsonDecode(res.body) as Map;
      if (!mounted) return;
      setState(() {
        _unitW = _l(b['unit_weights']);
        _pieceW = _l(b['piece_weights']);
        _rates = _l(b['rates']);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _d(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? '${iso ?? ''}' : DateFormat('dd-MM-yyyy').format(d);
  }

  String _n(dynamic v) {
    final d = (v as num?)?.toDouble();
    if (d == null) return '-';
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  }

  Future<void> _send(Map<String, dynamic> body) async {
    try {
      final res = await http.post(Uri.parse('$baseUrl/gpm/saved_values'),
          headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
      final b = jsonDecode(res.body) as Map;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(b['message']?.toString() ?? (res.statusCode == 200 ? 'Saved' : 'Failed')),
        backgroundColor: res.statusCode == 200 ? Colors.green : Colors.red,
      ));
      if (res.statusCode == 200) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _delete(String what, Map<String, dynamic> body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('$what\n\nThe next GPM report will ask for it again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('DELETE', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) await _send({...body, 'delete': true});
  }

  /// value dialog; for rates also "per kg / per piece" and "use the next PO rate".
  Future<void> _edit({
    required String title,
    required String label,
    required dynamic value,
    required Map<String, dynamic> body,
    bool isRate = false,
    String rateUnit = 'kg',
    String mode = 'manual',
  }) async {
    final c = TextEditingController(text: value == null ? '' : _n(value));
    String unit = rateUnit;
    String m = mode;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (isRate)
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'manual', label: Text('My rate')),
                  ButtonSegment(value: 'next', label: Text('Next PO rate')),
                ],
                selected: {m},
                onSelectionChanged: (s) => setD(() => m = s.first),
              ),
            if (!isRate || m == 'manual') ...[
              const SizedBox(height: 10),
              TextField(
                controller: c,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
              ),
              if (isRate) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final u in const ['kg', 'pcs'])
                    ChoiceChip(label: Text('per $u'), selected: unit == u, onSelected: (_) => setD(() => unit = u)),
                ]),
              ],
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SAVE')),
          ],
        ),
      ),
    );
    final v = double.tryParse(c.text.trim());
    c.dispose();
    if (ok != true) return;
    if (isRate && m == 'next') {
      await _send({...body, 'mode': 'next'});
    } else if (v == null || v <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a number more than 0'), backgroundColor: Colors.red));
      }
    } else {
      await _send({...body, 'value': v, 'mode': 'manual', 'rate_unit': unit});
    }
  }

  bool _hit(Map<String, dynamic> r) => _search.isEmpty || '${r['item_name']}'.toLowerCase().contains(_search);

  Widget _section(String title, String help, List<Widget> rows) => Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: ExpansionTile(
          initiallyExpanded: true,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(help, style: const TextStyle(fontSize: 12)),
          children: rows.isEmpty ? [const Padding(padding: EdgeInsets.all(12), child: Text('None'))] : rows,
        ),
      );

  Widget _row(String title, String sub, VoidCallback onEdit, VoidCallback onDelete) => ListTile(
        dense: true,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 20), onPressed: onEdit),
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: onDelete),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPM Saved Values'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)))
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
                  Text(
                    'Values you entered when GPM asked. Change them here if they were wrong - the next GPM report '
                    'uses the new value. Delete a value and GPM will ask for it again.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search item', isDense: true),
                    onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                  ),
                  _section('Kg in one box / bag / piece', 'Used when the PO rate is per box, bag or piece', [
                    for (final r in _unitW.where(_hit))
                      _row(
                        '${r['item_name']} - 1 ${r['unit']} = ${_n(r['kg_per_unit'])} kg',
                        'Changed ${r['updated_at'] ?? ''}',
                        () => _edit(
                          title: '${r['item_name']} - kg in one ${r['unit']}',
                          label: 'kg in one ${r['unit']}',
                          value: r['kg_per_unit'],
                          body: {'type': 'unit_weight', 'item_key': r['item_key'], 'unit': r['unit']},
                        ),
                        () => _delete('${r['item_name']}: 1 ${r['unit']} = ${_n(r['kg_per_unit'])} kg',
                            {'type': 'unit_weight', 'item_key': r['item_key'], 'unit': r['unit']}),
                      ),
                  ]),
                  _section('Average weight per piece', 'Weight of one piece on a date (used from that date on)', [
                    for (final r in _pieceW.where(_hit))
                      _row(
                        '${r['item_name']} - ${_n(r['avg_piece_weight_kg'])} kg per piece',
                        'From ${_d(r['date'])}',
                        () => _edit(
                          title: '${r['item_name']} - ${_d(r['date'])}',
                          label: 'kg per piece',
                          value: r['avg_piece_weight_kg'],
                          body: {'type': 'piece_weight', 'item_key': r['item_key'], 'date': r['date']},
                        ),
                        () => _delete('${r['item_name']} on ${_d(r['date'])}: ${_n(r['avg_piece_weight_kg'])} kg per piece',
                            {'type': 'piece_weight', 'item_key': r['item_key'], 'date': r['date']}),
                      ),
                  ]),
                  _section('Rates entered for stock', 'Stock older than the first purchase, or no PO rate', [
                    for (final r in _rates.where(_hit))
                      _row(
                        '${r['item_name']} - ${r['mode'] == 'next' ? 'next PO rate' : '₹${_n(r['rate'])} per ${r['unit'] ?? 'kg'}'}',
                        'Stock of ${_d(r['date'])}',
                        () => _edit(
                          title: '${r['item_name']} - rate on ${_d(r['date'])}',
                          label: 'Rate ₹',
                          value: r['rate'],
                          isRate: true,
                          rateUnit: (r['unit'] ?? 'kg').toString() == 'pcs' ? 'pcs' : 'kg',
                          mode: r['mode'] == 'next' ? 'next' : 'manual',
                          body: {'type': 'rate', 'item_key': r['item_key'], 'date': r['date']},
                        ),
                        () => _delete('${r['item_name']}: rate for ${_d(r['date'])}',
                            {'type': 'rate', 'item_key': r['item_key'], 'date': r['date']}),
                      ),
                  ]),
                ]),
    );
  }
}
