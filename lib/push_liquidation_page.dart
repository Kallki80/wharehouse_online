import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'api_config.dart';

/// Push Liquidation
///
/// From the latest stock update of each item (today's = closing of yesterday):
///  * B grade in stock - push it out
///  * ungraded + B grade more than N days of average sales (N = 3 or 4, can be
///    changed) - overstock, with the total available (A grade + ungraded)
class PushLiquidationPage extends StatefulWidget {
  const PushLiquidationPage({super.key});

  @override
  State<PushLiquidationPage> createState() => _PushLiquidationPageState();
}

class _PushLiquidationPageState extends State<PushLiquidationPage> {
  double _days = 3;
  String _filter = 'all'; // all | b_grade | overstock
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _r;
  String _search = '';
  final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _m(dynamic v) => v == null ? '-' : _money.format(v is num ? v : (double.tryParse('$v') ?? 0));

  String _n(dynamic v) {
    final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    if (d == null) return '-';
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
  }

  String _date(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? '${iso ?? ''}' : DateFormat('dd-MM').format(d);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse('$baseUrl/liquidation').replace(queryParameters: {'days': _n(_days)}));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode} - is the new server file installed?');
      final b = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      if (!mounted) return;
      setState(() => _r = b);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ((_r?['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final items = all.where((i) {
      final reasons = (i['reasons'] as List?) ?? [];
      if (_filter != 'all' && !reasons.contains(_filter)) return false;
      return _search.isEmpty || '${i['item']}'.toLowerCase().contains(_search);
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Push Liquidation'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
          Text(
            'From the latest stock update of each item: B grade in stock, and items whose ungraded + B grade stock '
            'is more than ${_n(_days)} days of average sales (last 7 days).',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Text('More than', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Wrap(spacing: 6, children: [
              for (final d in const [3.0, 4.0, 5.0])
                ChoiceChip(
                  label: Text('${d.toStringAsFixed(0)} days'),
                  selected: _days == d,
                  onSelected: (_) {
                    setState(() => _days = d);
                    _load();
                  },
                ),
            ]),
          ]),
          const SizedBox(height: 8),
          if (_r != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('B grade: ${_r!['b_grade_items']} items', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(_m(_r!['b_grade_value']), style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w800, fontSize: 16)),
                    ]),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Overstock: ${_r!['overstock_items']} items', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${_m(_r!['excess_value'])} extra', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w800, fontSize: 16)),
                    ]),
                  ),
                ]),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'b_grade', label: Text('B grade')),
                ButtonSegment(value: 'overstock', label: Text('Overstock')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search item', isDense: true),
            onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 6),
          if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          if (!_loading && _error == null && items.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Nothing to push - no B grade and no overstock.')),
          for (final i in items) _card(i),
        ]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> i) {
    final u = '${i['unit']}';
    final reasons = (i['reasons'] as List?) ?? [];
    final b = reasons.contains('b_grade');
    final over = reasons.contains('overstock');
    Widget chip(String t, Color c) => Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Text(t, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w700)),
        );
    Widget kv(String k, String v, {Color? c, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(children: [
            Expanded(child: Text(k, style: const TextStyle(fontSize: 12))),
            Text(v, style: TextStyle(fontSize: 12, color: c, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ]),
        );
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('${i['item']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            if (b) chip('B grade', Colors.orange.shade900),
            if (over) chip('Overstock', Colors.red.shade700),
          ]),
          Text('Stock update ${_date(i['stock_date'])}${i['stale'] == true ? ' (old - stock not entered since)' : ''}',
              style: TextStyle(fontSize: 11, color: i['stale'] == true ? Colors.red : Colors.grey.shade600)),
          const SizedBox(height: 6),
          if (b) kv('B grade in stock', '${_n(i['b_grade'])} $u  ·  ${_m(i['b_grade_value'])}', c: Colors.orange.shade900, bold: true),
          kv('Total available (A grade + ungraded)', '${_n(i['total_available'])} $u', bold: true),
          kv('A grade / ungraded', '${_n(i['a_grade'])} / ${_n(i['ungraded'])} $u'),
          kv('Average sales per day', i['no_sales'] == true ? 'no sales in 7 days' : '${_n(i['avg_sales_per_day'])} $u'),
          if (i['days_of_cover'] != null) kv('Ungraded + B grade lasts', '${_n(i['days_of_cover'])} days'),
          if (over)
            kv('More than ${_n(i['limit_days'])} days of stock by', '${_n(i['excess'])} $u  ·  ${_m(i['excess_value'])}',
                c: Colors.red.shade700, bold: true),
          if ('${i['value_basis'] ?? ''}'.isNotEmpty)
            Text('Value ${i['value_basis']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ]),
      ),
    );
  }
}
