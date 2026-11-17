import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';
import '../utils/file_saver.dart';

/// Admin › Tag Profitability
/// Each purchase lot (item tag) from arrival until it is finished: cost, sold, B grade,
/// dumped, left in stock and the profit kept - tag-wise and vendor-wise.
class TagProfitPage extends StatefulWidget {
  const TagProfitPage({super.key});

  @override
  State<TagProfitPage> createState() => _TagProfitPageState();
}

class _TagProfitPageState extends State<TagProfitPage> {
  DateTime? _start;
  DateTime? _end;
  bool _loading = false;
  bool _exporting = false;
  String? _error;
  Map<String, dynamic>? _r;
  String _view = 'lots'; // lots | vendors
  String _search = '';
  String _sort = 'arrived'; // arrived | profit | margin
  final Set<String> _open = {};
  final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = DateTime(now.year, now.month, now.day);
    _start = _end!.subtract(const Duration(days: 14));
  }

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _show(DateTime d) => DateFormat('dd-MM-yyyy').format(d);
  String _m(dynamic v) => v == null ? '-' : _money.format(v is num ? v : (double.tryParse('$v') ?? 0));
  String _n(dynamic v) {
    final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    if (d == null) return '-';
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  }

  String _dd(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? '${iso ?? '-'}' : DateFormat('dd-MM').format(d);
  }

  Map<String, String> get _q => {'start': _iso(_start!), 'end': _iso(_end!)};

  void _snack(String t, Color c) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: c));
  }

  Future<void> _pick(bool start) async {
    final p = await showDatePicker(
      context: context,
      initialDate: (start ? _start : _end) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: start ? 'Lots arrived from' : 'Lots arrived to',
    );
    if (p == null) return;
    setState(() {
      if (start) {
        _start = p;
        if (_end!.isBefore(p)) _end = p;
      } else {
        _end = p;
        if (_start!.isAfter(p)) _start = p;
      }
    });
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // selling rates: always shown first (typed rate / Sales Report average), can be changed
      final ok = await _TagRatesPage.confirm(context, _q);
      if (!ok) return;
      final res = await http.get(Uri.parse('$baseUrl/tag_profit').replace(queryParameters: _q));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode} - is the new server file installed?');
      final b = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      if (mounted) {
        setState(() {
          _r = b;
          _open.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    setState(() => _exporting = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/tag_profit/export').replace(queryParameters: _q));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      if (!mounted) return;
      await saveOrShareFile(context, bytes: res.bodyBytes, fileName: 'TAG_PROFIT_${_iso(_start!)}_to_${_iso(_end!)}.xlsx');
    } catch (e) {
      _snack('Download failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tag Profitability'),
        actions: [
          IconButton(
            tooltip: 'Download Excel',
            icon: _exporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            onPressed: _r == null || _exporting ? null : _download,
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Lots (item tags) that arrived', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text('From ${_show(_start!)}'),
                  onPressed: () => _pick(true),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text('To ${_show(_end!)}'),
                  onPressed: () => _pick(false),
                ),
              ]),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(minimumSize: const Size(64, 46)),
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sell_outlined),
                label: const Text('Calculate'),
                onPressed: _loading ? null : _run,
              ),
              const SizedBox(height: 6),
              Text(
                'Each lot is followed through the stock updates until it is finished. Going out between two stock counts = '
                'tag stock before + arrived − tag stock after; split into dumped, B grade and sold (tagged entries first). '
                'Sold value: Sales Report lines whose Lot No. is the tag, the rest at the selling rate of the day '
                '(typed, else the Sales Report average). Profit kept = sold + B grade + stock left (at cost) − cost.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
            ]),
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (_r != null) ..._results(),
      ]),
    );
  }

  List<Widget> _results() {
    final t = Map<String, dynamic>.from((_r!['totals'] as Map?) ?? {});
    final flags = ((_r!['flags'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final lots = ((_r!['lots'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).where((l) {
      return _search.isEmpty || '${l['item']} ${l['tag']} ${l['vendor']} ${l['po']}'.toLowerCase().contains(_search);
    }).toList();
    num key(Map l) => _sort == 'profit'
        ? ((l['profit'] as num?) ?? 0)
        : (_sort == 'margin' ? ((l['margin_percent'] as num?) ?? -9999) : 0);
    if (_sort != 'arrived') lots.sort((a, b) => key(b).compareTo(key(a)));
    final vendors = ((_r!['vendors'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final profit = (t['profit'] as num?) ?? 0;
    return [
      const SizedBox(height: 8),
      if (t.isNotEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 18, runSpacing: 10, children: [
              _kv('Lots', '${t['lots']} (${t['finished']} finished)'),
              _kv('Cost', _m(t['cost'])),
              _kv('Profit kept', _m(t['profit']), color: profit < 0 ? Colors.red.shade700 : Colors.green.shade800),
              _kv('Margin', t['margin_percent'] == null ? '-' : '${t['margin_percent']} %'),
            ]),
          ),
        ),
      for (final f in flags)
        Card(
          color: Colors.orange.shade50,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.info_outline, color: Colors.orange),
            title: Text('${f['message']}', style: const TextStyle(fontSize: 12)),
          ),
        ),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'lots', label: Text('Lots (tags)'), icon: Icon(Icons.sell_outlined)),
          ButtonSegment(value: 'vendors', label: Text('Vendors'), icon: Icon(Icons.storefront_outlined)),
        ],
        selected: {_view},
        onSelectionChanged: (s) => setState(() => _view = s.first),
      ),
      const SizedBox(height: 8),
      if (_view == 'lots') ...[
        Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search item, tag, vendor, PO', isDense: true),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: _sort,
            items: const [
              DropdownMenuItem(value: 'arrived', child: Text('Arrival')),
              DropdownMenuItem(value: 'profit', child: Text('Profit')),
              DropdownMenuItem(value: 'margin', child: Text('Margin %')),
            ],
            onChanged: (v) => setState(() => _sort = v ?? 'arrived'),
          ),
        ]),
        const SizedBox(height: 6),
        if (lots.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No lots with an item tag in these dates.')),
        for (final l in lots) _lotCard(l),
      ] else ...[
        for (final v in vendors)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              title: Text('${v['vendor']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${v['lots']} lot(s) · cost ${_m(v['cost'])} · dumped worth ${_m(v['dumped_cost'])}',
                  style: const TextStyle(fontSize: 12)),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_m(v['profit']),
                    style: TextStyle(fontWeight: FontWeight.w800, color: ((v['profit'] as num?) ?? 0) < 0 ? Colors.red.shade700 : Colors.green.shade800)),
                Text(v['margin_percent'] == null ? '' : '${v['margin_percent']} %', style: const TextStyle(fontSize: 11)),
              ]),
            ),
          ),
      ],
    ];
  }

  Widget _kv(String k, String v, {Color? color}) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(k, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        Text(v, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
      ]);

  Widget _lotCard(Map<String, dynamic> l) {
    final id = '${l['item']}|${l['tag']}';
    final open = _open.contains(id);
    final u = '${l['unit']}';
    final p = (l['profit'] as num?) ?? 0;
    final periods = ((l['periods'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    const h = TextStyle(fontWeight: FontWeight.bold, fontSize: 11);
    const c = TextStyle(fontSize: 11);
    final priced = <String>[
      if (((l['exact_qty'] as num?) ?? 0) > 0) 'Lot No. ${_n(l['exact_qty'])}',
      if (((l['typed_qty'] as num?) ?? 0) > 0) 'typed rate ${_n(l['typed_qty'])}',
      if (((l['average_qty'] as num?) ?? 0) > 0) 'day average ${_n(l['average_qty'])}',
      if (((l['unpriced_qty'] as num?) ?? 0) > 0) 'NO RATE ${_n(l['unpriced_qty'])}',
    ];
    return Card(
      key: ValueKey('tp-$id'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          dense: true,
          title: Text('${l['item']} · ${l['tag']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            '${l['vendor']}${'${l['po']}'.isNotEmpty ? ' · PO ${l['po']}' : ''} · arrived ${_dd(l['arrived'])} · ${l['status']}'
            '${l['days_to_clear'] != null ? ' in ${l['days_to_clear']} day(s)' : ''}\n'
            'In ${_n(l['qty_in'])} $u for ${_m(l['cost'])} (₹${_n(l['cost_per_unit'])}/$u)\n'
            'Sold ${_n(l['sold'])} $u for ${_m(l['sold_value'])}${l['avg_sale_rate'] != null ? ' (₹${_n(l['avg_sale_rate'])}/$u)' : ''} · '
            'B grade ${_n(l['b_grade'])} (${_m(l['b_value'])}) · dumped ${_n(l['dumped'])} · left ${_n(l['left'])}'
            '${((l['unaccounted'] as num?) ?? 0).abs() > 0.01 ? ' · unaccounted ${_n(l['unaccounted'])}' : ''}'
            '${priced.isNotEmpty ? '\nSold priced by: ${priced.join(' · ')} $u' : ''}',
            style: const TextStyle(fontSize: 11),
          ),
          isThreeLine: true,
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_m(p), style: TextStyle(fontWeight: FontWeight.w800, color: p < 0 ? Colors.red.shade700 : Colors.green.shade800)),
            Text(l['margin_percent'] == null ? '' : '${l['margin_percent']} %', style: const TextStyle(fontSize: 11)),
          ]),
          onTap: () => setState(() => open ? _open.remove(id) : _open.add(id)),
        ),
        if (open)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: DataTable(
              columnSpacing: 12,
              headingRowHeight: 30,
              dataRowMinHeight: 28,
              dataRowMaxHeight: 32,
              headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50),
              columns: const [
                DataColumn(label: Text('Days', style: h)),
                DataColumn(label: Text('Stock before', style: h), numeric: true),
                DataColumn(label: Text('Arrived', style: h), numeric: true),
                DataColumn(label: Text('Stock after', style: h), numeric: true),
                DataColumn(label: Text('Sold', style: h), numeric: true),
                DataColumn(label: Text('B grade', style: h), numeric: true),
                DataColumn(label: Text('Dumped', style: h), numeric: true),
                DataColumn(label: Text('Rate', style: h), numeric: true),
                DataColumn(label: Text('Rate from', style: h)),
                DataColumn(label: Text('Sold value', style: h), numeric: true),
              ],
              rows: [
                for (final d in periods)
                  DataRow(cells: [
                    DataCell(Text(d['from'] == d['to'] ? _dd(d['from']) : '${_dd(d['from'])} – ${_dd(d['to'])}', style: c)),
                    DataCell(Text(_n(d['stock_before']), style: c)),
                    DataCell(Text(_n(d['arrived']), style: c)),
                    DataCell(Text(_n(d['stock_after']), style: c)),
                    DataCell(Text(_n(d['sold']), style: c)),
                    DataCell(Text(_n(d['b_grade']), style: c)),
                    DataCell(Text(_n(d['dumped']), style: c)),
                    DataCell(Text(_n(d['rate']), style: c)),
                    DataCell(Text('${d['rate_from'] ?? '-'}${((d['exact_qty'] as num?) ?? 0) > 0 ? ' + Lot No.' : ''}', style: c)),
                    DataCell(Text(_m(d['sold_value']), style: c)),
                  ]),
              ],
            ),
          ),
      ]),
    );
  }
}

/// Selling rate per item and day used for the sold quantity of the lots: the Sales
/// Report average is filled in, a typed rate is kept and can be changed; blank = average.
class _TagRatesPage extends StatefulWidget {
  final Map<String, String> query;
  final List<Map<String, dynamic>> rows;
  const _TagRatesPage({required this.query, required this.rows});

  static Future<bool> confirm(BuildContext context, Map<String, String> q) async {
    final res = await http.get(Uri.parse('$baseUrl/tag_profit/rates').replace(queryParameters: q));
    if (res.statusCode != 200) throw Exception('Server error ${res.statusCode} - is the new server file installed?');
    final b = jsonDecode(res.body) as Map;
    final rows = ((b['rows'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (rows.isEmpty) return true;
    if (!context.mounted) return false;
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _TagRatesPage(query: q, rows: rows)));
    return ok == true;
  }

  @override
  State<_TagRatesPage> createState() => _TagRatesPageState();
}

class _TagRatesPageState extends State<_TagRatesPage> {
  final Map<int, TextEditingController> _c = {};
  bool _saving = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.rows.length; i++) {
      final t = widget.rows[i]['typed'];
      _c[i] = TextEditingController(text: t == null ? '' : '$t');
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
    if (d == null) return '-';
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  }

  Future<void> _ok() async {
    final missing = <String>[];
    final send = <Map<String, dynamic>>[];
    for (var i = 0; i < widget.rows.length; i++) {
      final r = widget.rows[i];
      final txt = _c[i]!.text.trim();
      final v = double.tryParse(txt);
      if (txt.isNotEmpty && (v == null || v <= 0)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Check the rate of ${r['item']} on ${r['date']}'), backgroundColor: Colors.red));
        return;
      }
      if (v == null && r['average'] == null) missing.add('${r['item']} ${r['date']}');
      final old = (r['typed'] as num?)?.toDouble();
      if (old != v) send.add({'item': r['item'], 'date': r['date'], 'rate': v});
    }
    if (missing.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Some selling rates are empty'),
          content: Text('${missing.length} item-day(s) have no Sales Report and no typed rate - their sold quantity will be valued at 0. Go on?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ENTER RATES')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('GO ON')),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() => _saving = true);
    try {
      if (send.isNotEmpty) {
        final res = await http.post(Uri.parse('$baseUrl/tag_profit/rates'),
            headers: {'Content-Type': 'application/json'}, body: jsonEncode({'rows': send}));
        if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      }
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
      for (var i = 0; i < widget.rows.length; i++)
        if (_search.isEmpty || '${widget.rows[i]['item']}'.toLowerCase().contains(_search)) i
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Selling rates')),
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
                child: Text(_saving ? 'Saving...' : 'OK - CALCULATE'),
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
              'Selling rate of each item per day, used for the sold quantity of the lots that has no Lot No. in the Sales Report. '
              'Leave a box empty to use the Sales Report average shown under it, or type a rate (it is saved and used next time). '
              'Days without a Sales Report need a rate.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search item', isDense: true),
          onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 6),
        for (final i in idx)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 3),
            shape: widget.rows[i]['average'] == null && widget.rows[i]['typed'] == null
                ? RoundedRectangleBorder(side: BorderSide(color: Colors.red.shade300), borderRadius: BorderRadius.circular(12))
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${widget.rows[i]['item']} · ${widget.rows[i]['date']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(
                      'Lots sold ~${_n(widget.rows[i]['qty'])} ${widget.rows[i]['unit']} · Sales Report average '
                      '${widget.rows[i]['average'] == null ? 'none' : '₹${_n(widget.rows[i]['average'])}'}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ]),
                ),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _c[i],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: '₹ / ${widget.rows[i]['unit']}',
                      hintText: widget.rows[i]['average'] == null ? 'required' : _n(widget.rows[i]['average']),
                    ),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
