import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';

/// Admin › B Grade Analysis
///
/// For one day or a range of days, per item:
///   opening   = total B grade counted in that day's stock update (it already
///               includes the previous day's leftover)
///   outflow   = main sales marked "B grade" + B-grade sales + mandi resale + dump
///   leftover  = opening - outflow
///   added next day = next day's counted B grade - leftover (new B grade)
///   value     = B-grade sales amount + main-sales-B kg x your rate + mandi kg x your rate (dump = 0)
/// compared with the purchase value of the same quantity (latest PO rate).
class BGradeAnalysisPage extends StatefulWidget {
  const BGradeAnalysisPage({super.key});

  @override
  State<BGradeAnalysisPage> createState() => _BGradeAnalysisPageState();
}

final NumberFormat _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final NumberFormat _kg = NumberFormat('#,##0.##', 'en_IN');
String _m(dynamic v) => v == null ? '-' : _inr.format((v as num).toDouble());
String _k(dynamic v) => v == null ? '-' : _kg.format((v as num).toDouble());

class _BGradeAnalysisPageState extends State<BGradeAnalysisPage> {
  DateTime? _start;
  DateTime? _end;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;
  // item -> {'main_b_rate': x, 'mandi_rate': y}
  final Map<String, Map<String, double?>> _rates = {};

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _show(DateTime d) => DateFormat('dd MMM yyyy').format(d);

  Future<void> _pick(bool isStart) async {
    final now = DateTime.now();
    final p = await showDatePicker(
      context: context,
      initialDate: (isStart ? _start : _end) ?? _start ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
    );
    if (p == null) return;
    setState(() {
      if (isStart) {
        _start = p;
        if (_end == null || _end!.isBefore(p)) _end = p;
      } else {
        _end = p;
        if (_start == null || _start!.isAfter(p)) _start = p;
      }
    });
  }

  Future<void> _run() async {
    if (_start == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick the start date'), backgroundColor: Colors.red));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/bgrade/analysis'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'start': _iso(_start!),
          'end': _iso(_end ?? _start!),
          'rates': _rates.map((k, v) => MapEntry(k, {'main_b_rate': v['main_b_rate'], 'mandi_rate': v['mandi_rate']})),
        }),
      );
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}: ${res.body}');
      final data = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      // keep the rates the server remembered so they show in the boxes
      for (final it in (data['items'] as List)) {
        final m = Map<String, dynamic>.from(it as Map);
        _rates[m['item'].toString()] = {
          'main_b_rate': (m['main_b_rate'] as num?)?.toDouble(),
          'mandi_rate': (m['mandi_rate'] as num?)?.toDouble(),
        };
      }
      if (!mounted) return;
      setState(() => _result = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editRates(String item) async {
    final r = _rates[item] ?? {};
    final b = TextEditingController(text: r['main_b_rate']?.toString() ?? '');
    final m = TextEditingController(text: r['mandi_rate']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rates for $item'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: b,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '₹ per kg - B grade sent in main sales', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: m,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '₹ per kg - mandi resale', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          const Text('Dump is always valued at 0. Rates are remembered for next time.', style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('APPLY')),
        ],
      ),
    );
    final bv = double.tryParse(b.text.trim());
    final mv = double.tryParse(m.text.trim());
    b.dispose();
    m.dispose();
    if (ok != true) return;
    _rates[item] = {'main_b_rate': bv, 'mandi_rate': mv};
    await _run();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('B Grade Analysis')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('One day or a range of days', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(_start == null ? 'Start date' : 'From ${_show(_start!)}'),
                  onPressed: () => _pick(true),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(_end == null ? 'End date' : 'To ${_show(_end!)}'),
                  onPressed: () => _pick(false),
                ),
                ElevatedButton.icon(
                  icon: _loading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.analytics_outlined),
                  label: const Text('Analyse'),
                  onPressed: _loading ? null : _run,
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'Opening = total B grade counted in that day\'s stock update. '
                'Out = main sales marked "B grade" + B-grade sales + mandi + dump. Leftover = opening - out. '
                'Added next day = next day\'s B grade - leftover (new B grade that came in). '
                'Value = B-grade sales amount + your rates for main-sales B and mandi (dump = 0), '
                'compared with what the same kg cost to buy (latest PO rate).',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ]),
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (_result != null) ..._resultWidgets(),
      ]),
    );
  }

  List<Widget> _resultWidgets() {
    final r = _result!;
    final t = Map<String, dynamic>.from(r['totals'] as Map);
    final items = List<Map<String, dynamic>>.from((r['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final missing = List<String>.from(r['missing_rates'] as List? ?? []);
    final rec = t['recovery_percent'];
    Widget line(String l, String v, {bool bold = false, Color? c}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(l, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null))),
            Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: c)),
          ]),
        );
    return [
      const SizedBox(height: 8),
      if (missing.isNotEmpty)
        Card(
          color: Colors.orange.shade50,
          child: ListTile(
            leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            title: const Text('Rates needed'),
            subtitle: Text('Enter the main-sales B / mandi rate for: ${missing.join(', ')}. Until then that quantity is valued at 0.'),
          ),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('All items · ${r['start']}${r['start'] == r['end'] ? '' : ' to ${r['end']}'}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 6),
            line('B grade at start', '${_k(t['opening'])} kg'),
            line('Sent in main sales as B', '${_k(t['main_b'])} kg'),
            line('B-grade sales', '${_k(t['bsales'])} kg'),
            line('Mandi resale', '${_k(t['mandi'])} kg'),
            line('Dump (value 0)', '${_k(t['dump'])} kg'),
            line('Leftover B grade at the end', '${_k(t['leftover'])} kg  (bought for ${_m(t['leftover_value'])})'),
            line('New B grade added (day to day)', '${_k(t['added'])} kg'),
            const Divider(),
            line('Value generated from B grade', _m(t['value']), bold: true, c: Colors.green.shade800),
            line('Purchase value of the same kg', _m(t['purchase_value']), bold: true),
            line('Recovered', rec == null ? '-' : '$rec %', bold: true,
                c: rec == null ? null : ((rec as num) >= 50 ? Colors.green.shade800 : Colors.red.shade700)),
          ]),
        ),
      ),
      for (final it in items) _itemCard(it),
    ];
  }

  Widget _itemCard(Map<String, dynamic> it) {
    final days = List<Map<String, dynamic>>.from((it['days'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final warnings = List<String>.from(it['warnings'] as List? ?? []);
    final rec = it['recovery_percent'];
    const h = TextStyle(fontWeight: FontWeight.bold, fontSize: 11);
    const c = TextStyle(fontSize: 11);
    DataCell cell(dynamic v, {bool money = false, Color? color}) =>
        DataCell(Text(money ? _m(v) : _k(v), style: c.copyWith(color: color)));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ExpansionTile(
        title: Text(it['item'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          'Out ${_k(it['outflow'])} kg · value ${_m(it['value_generated'])} vs bought ${_m(it['purchase_value'])}'
          '${rec == null ? '' : ' · $rec %'} · leftover ${_k(it['leftover'])} kg · new B ${_k(it['added_b_grade'])} kg',
          style: const TextStyle(fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Row(children: [
            Expanded(
              child: Text(
                'Rates: main-sales B ${it['main_b_rate'] == null ? 'not set' : '₹${it['main_b_rate']}/kg'} · '
                'mandi ${it['mandi_rate'] == null ? 'not set' : '₹${it['mandi_rate']}/kg'}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Rates'),
              onPressed: () => _editRates(it['item'].toString()),
            ),
          ]),
          for (final w in warnings)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(w, style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 14,
              headingRowHeight: 34,
              dataRowMinHeight: 30,
              dataRowMaxHeight: 34,
              headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50),
              columns: const [
                DataColumn(label: Text('Date', style: h)),
                DataColumn(label: Text('B in stock\nupdate', style: h), numeric: true),
                DataColumn(label: Text('Opening', style: h), numeric: true),
                DataColumn(label: Text('Main sales B', style: h), numeric: true),
                DataColumn(label: Text('B-grade sales', style: h), numeric: true),
                DataColumn(label: Text('Mandi', style: h), numeric: true),
                DataColumn(label: Text('Dump', style: h), numeric: true),
                DataColumn(label: Text('Leftover', style: h), numeric: true),
                DataColumn(label: Text('Added\nnext day', style: h), numeric: true),
                DataColumn(label: Text('Value', style: h), numeric: true),
                DataColumn(label: Text('Bought for', style: h), numeric: true),
              ],
              rows: days.map((d) {
                final left = (d['leftover'] as num).toDouble();
                return DataRow(cells: [
                  DataCell(Text(d['date'].toString(), style: c)),
                  cell(d['stock_update_b']),
                  DataCell(Text(_k(d['opening']), style: c.copyWith(
                      color: d['opening_from'] == 'previous leftover' ? Colors.orange.shade900 : null))),
                  cell(d['main_sales_b']),
                  cell(d['b_grade_sales']),
                  cell(d['mandi']),
                  cell(d['dump']),
                  cell(left, color: left < 0 ? Colors.red.shade700 : null),
                  cell(d['added_next_day'],
                      color: ((d['added_next_day'] as num?) ?? 0) < 0 ? Colors.red.shade700 : Colors.green.shade800),
                  cell(d['value_generated'], money: true),
                  cell(d['purchase_value'], money: true),
                ]);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
