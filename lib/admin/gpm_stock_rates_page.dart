import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_config.dart';

/// GPM: rates used to value the opening and closing stock, shown before the GPM
/// is worked out.
///  * A grade + ungraded x weighted average purchase rate
///  * B grade (and C grade) x last B grade rate per kg - type it when missing
///  * dump x 0
/// Returns true on OK (rates saved), null when cancelled.
class GpmStockRatesPage extends StatefulWidget {
  final Map<String, String> query; // start, end, mode
  const GpmStockRatesPage({super.key, required this.query});

  /// Loads the rates; when there is nothing to value, returns true at once.
  static Future<bool?> confirm(BuildContext context, Map<String, String> query) async {
    return Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => GpmStockRatesPage(query: query)));
  }

  @override
  State<GpmStockRatesPage> createState() => _GpmStockRatesPageState();
}

class _GpmStockRatesPageState extends State<GpmStockRatesPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  final Map<String, TextEditingController> _b = {};
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _b.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _n(dynamic v, [int d = 2]) {
    final x = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    if (x == null) return '-';
    return x == x.roundToDouble() ? x.toStringAsFixed(0) : x.toStringAsFixed(d);
  }

  Future<void> _load() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/gpm/stock_rates').replace(queryParameters: widget.query));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode} - is the new server file installed?');
      final b = jsonDecode(res.body) as Map;
      final items = ((b['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      for (final i in items) {
        _b['${i['item']}'] = TextEditingController(text: i['b_rate'] == null ? '' : _n(i['b_rate'], 4));
      }
      if (!mounted) return;
      if (items.isEmpty) {
        Navigator.pop(context, true); // no stock to value
        return;
      }
      setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ok() async {
    final missing = _items
        .where((i) => i['uses_b_rate'] == true && (_b['${i['item']}']!.text.trim().isEmpty || double.tryParse(_b['${i['item']}']!.text.trim()) == null))
        .map((i) => '${i['item']}')
        .toList();
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Enter the B grade rate per kg for: ${missing.join(', ')}'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    // only rates that were typed or changed are sent
    final changed = <Map<String, dynamic>>[];
    for (final i in _items) {
      if (i['uses_b_rate'] != true) continue;
      final v = double.parse(_b['${i['item']}']!.text.trim());
      final old = (i['b_rate'] as num?)?.toDouble();
      if (old == null || (old - v).abs() > 1e-6) changed.add({'item': i['item'], 'b_rate': v});
    }
    setState(() => _saving = true);
    try {
      if (changed.isNotEmpty) {
        final res = await http.post(
          Uri.parse('$baseUrl/gpm/stock_rates'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'start': widget.query['start'], 'end': widget.query['end'], 'rates': changed}),
        );
        if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Not saved: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _items.where((i) => _search.isEmpty || '${i['item']}'.toLowerCase().contains(_search)).toList()
      ..sort((a, b) => (b['b_rate_needed'] == true ? 1 : 0).compareTo(a['b_rate_needed'] == true ? 1 : 0));
    final needed = _items.where((i) => i['b_rate_needed'] == true).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Stock value rates')),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
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
                      child: Text(_saving ? 'Saving...' : 'OK - CALCULATE GPM'),
                    ),
                  ),
                ]),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Colors.red))))
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
                  Card(
                    color: Colors.indigo.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Opening and closing stock are valued as:\n'
                        '• A grade + ungraded × weighted average purchase rate (accepted amount ÷ accepted qty of the '
                        'period; none in the period → 30 days before)\n'
                        '• B grade (and C grade) × B grade rate per kg (last B grade sale; else the rate entered here / in B grade analysis)\n'
                        '• Dump × 0\n'
                        'Check the rates, type the missing B grade rates, then press OK.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  if (needed > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text('$needed item(s) need a B grade rate', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700)),
                    ),
                  TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search item', isDense: true),
                    onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 6),
                  for (final i in shown) _card(i),
                ]),
    );
  }

  Widget _card(Map<String, dynamic> i) {
    final u = '${i['stock_unit']}';
    final o = Map<String, dynamic>.from(i['opening'] as Map);
    final c = Map<String, dynamic>.from(i['closing'] as Map);
    final need = i['b_rate_needed'] == true;
    final usesB = i['uses_b_rate'] == true;
    TableRow r(String a, String b, String cc) => TableRow(children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(a, style: const TextStyle(fontSize: 11))),
          Text(b, style: const TextStyle(fontSize: 11), textAlign: TextAlign.right),
          Text(cc, style: const TextStyle(fontSize: 11), textAlign: TextAlign.right),
        ]);
    return Card(
      key: ValueKey('sr-${i['item']}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: need ? RoundedRectangleBorder(side: BorderSide(color: Colors.red.shade300), borderRadius: BorderRadius.circular(12)) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${i['item']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 4),
          Text('Weighted avg purchase rate: ${i['wap'] == null ? 'not available' : '₹${_n(i['wap'])} per $u'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          Text('${i['wap_basis'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          if (usesB)
            TextField(
              controller: _b['${i['item']}'],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'B grade rate per kg (₹)',
                isDense: true,
                helperText: need
                    ? 'No B grade sale and no rate entered - type the rate'
                    : '${i['b_source']}${i['b_date'] != null ? ' (${i['b_date']})' : ''} - change it if needed',
                helperStyle: TextStyle(color: need ? Colors.red.shade700 : null, fontSize: 11),
              ),
            )
          else
            Text('No B / C grade in stock - B rate not needed', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Table(columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.2)}, children: [
            r('', 'Opening', 'Closing'),
            r('A + ungraded ($u)', _n(o['a_ungraded']), _n(c['a_ungraded'])),
            r('B + C grade ($u)', _n(o['b_c']), _n(c['b_c'])),
            r('Dump ($u, value 0)', _n(o['dump']), _n(c['dump'])),
            r('Value now (₹)', _n(o['value']), _n(c['value'])),
          ]),
        ]),
      ),
    );
  }
}
