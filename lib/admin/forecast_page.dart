import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';
import 'item_settings_page.dart';

/// Admin › Stock Forecast
///
/// For items in stock during the last 10 days (all in kg): average daily
/// sales over the last 7 days (= forecast for tomorrow), A-grade +
/// ungraded stock, open POs, days of cover, and what to order to keep
/// 3 days of stock.
class ForecastPage extends StatefulWidget {
  const ForecastPage({super.key});

  @override
  State<ForecastPage> createState() => _ForecastPageState();
}

class _ForecastPageState extends State<ForecastPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  List<String> _allItems = [];

  final NumberFormat _n = NumberFormat('#,##0.##', 'en_IN');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Future.wait([
        http.get(Uri.parse('$baseUrl/forecast')),
        http.get(Uri.parse('$baseUrl/get_items?distinct=1')),
      ]);
      if (res[0].statusCode != 200) throw Exception('Server error ${res[0].statusCode}');
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(jsonDecode(res[0].body) as Map);
        if (res[1].statusCode == 200) {
          _allItems = (jsonDecode(res[1].body) as List).map((e) => (e as Map)['name'].toString()).toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _q(dynamic v) => v == null ? '-' : _n.format((v as num).toDouble());

  String _date(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '');
    return d == null ? '-' : DateFormat('dd MMM').format(d);
  }

  Future<void> _setExpected(String item, {bool add = false, num? current}) async {
    final c = TextEditingController(text: current?.toString() ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Expected daily order: $item'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Expected quantity per day',
            helperText: 'In kg',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('SAVE')),
        ],
      ),
    );
    c.dispose();
    if (v == null || v.isEmpty) return;
    final qty = double.tryParse(v);
    if (qty == null || qty < 0) {
      _snack('Enter a valid quantity', Colors.red);
      return;
    }
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/forecast/expected_qty'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'item': item, 'expected_daily_qty': qty, if (add) 'add': true}),
      );
      final b = jsonDecode(res.body);
      if (res.statusCode == 200 && b['success'] == true) {
        await _load();
      } else {
        _snack(b['message']?.toString() ?? 'Save failed', Colors.red);
      }
    } catch (e) {
      _snack('Save failed: $e', Colors.red);
    }
  }

  Future<void> _addItem() async {
    final item = await showDialog<String>(
      context: context,
      builder: (ctx) => _PickItemDialog(items: _allItems),
    );
    if (item == null) return;
    await _setExpected(item, add: true);
  }

  Future<void> _removeItem(String item) async {
    await http.post(
      Uri.parse('$baseUrl/forecast/remove_item'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'item': item}),
    );
    await _load();
  }

  void _snack(String t, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: c));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Forecast'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _addItem,
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load forecast: $_error'))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final d = _data!;
    final items = List<Map<String, dynamic>>.from((d['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final window = List<String>.from(d['window'] as List);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
        Text(
          'Forecast for tomorrow = average daily sales (kg, from sales entries) from ${_date(window.first)} to ${_date(window.last)} '
          '(${d['window_days']} days). Stock = A grade + ungraded (kg) in the latest stock update. '
          'Target: ${d['cover_days']} days of stock.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No items in stock in the last 10 days.'))),
        for (final f in items) _card(f),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> f) {
    final status = f['status'].toString();
    final unit = f['unit'].toString();
    final (Color color, String label) = switch (status) {
      'order_now' => (Colors.red.shade700, 'ORDER NOW'),
      'order_soon' => (Colors.orange.shade800, 'Order soon'),
      'needs_expected_qty' => (Colors.purple, 'New item - enter expected qty'),
      'no_demand' => (Colors.blueGrey, 'No sales in the last ${_data!['window_days']} days'),
      _ => (Colors.green.shade700, 'OK'),
    };
    final notes = List<String>.from(f['notes'] as List? ?? []);
    Widget stat(String l, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.only(right: 18, top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            Text(v, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ]),
        );
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(f['item'].toString(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ]),
          Wrap(children: [
            stat('Forecast / day', f['forecast_next_day'] == null ? '-' : '${_q(f['forecast_next_day'])} $unit'),
            stat('Stock (${_date(f['stock_date'])})', '${_q(f['stock'])} $unit'),
            stat('Open POs', '${_q(f['incoming_open_po'])} $unit'),
            stat('Days of stock', f['days_of_cover'] == null ? '-' : _q(f['days_of_cover'])),
            stat('Runs out', _date(f['stock_out_date'])),
            if ((f['suggested_order_qty'] ?? 0) > 0)
              stat('Order', '${_q(f['suggested_order_qty'])} $unit', bold: true),
            if (f['order_by'] != null && status != 'ok') stat('Order by', _date(f['order_by'])),
          ]),
          if (f['basis'] == 'expected (entered)')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Using the expected quantity you entered (${_q(f['expected_daily_qty'])} $unit / day)',
                  style: TextStyle(fontSize: 12, color: Colors.purple.shade400)),
            ),
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(n, style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
            ),
          Wrap(spacing: 8, children: [
            if (status == 'needs_expected_qty' || f['basis'] == 'expected (entered)')
              TextButton.icon(
                icon: const Icon(Icons.edit, size: 16),
                label: Text(status == 'needs_expected_qty' ? 'Enter expected daily order' : 'Change expected qty'),
                onPressed: () => _setExpected(f['item'].toString(), current: f['expected_daily_qty'] as num?),
              ),
            if (notes.any((n) => n.contains('weight per piece')))
              TextButton.icon(
                icon: const Icon(Icons.scale, size: 16),
                label: const Text('Open Item Settings'),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const ItemSettingsPage()));
                  _load();
                },
              ),
            if (f['added_manually'] == true)
              TextButton.icon(
                icon: const Icon(Icons.remove_circle_outline, size: 16),
                label: const Text('Remove from forecast'),
                onPressed: () => _removeItem(f['item'].toString()),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _PickItemDialog extends StatefulWidget {
  final List<String> items;
  const _PickItemDialog({required this.items});

  @override
  State<_PickItemDialog> createState() => _PickItemDialogState();
}

class _PickItemDialogState extends State<_PickItemDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = widget.items.where((i) => q.isEmpty || i.toLowerCase().contains(q)).toList();
    return AlertDialog(
      title: const Text('Add item to forecast'),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search item', border: OutlineInputBorder(), isDense: true),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (ctx, i) => ListTile(dense: true, title: Text(list[i]), onTap: () => Navigator.pop(context, list[i])),
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL'))],
    );
  }
}
