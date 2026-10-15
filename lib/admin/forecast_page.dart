import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';
import 'item_settings_page.dart';

/// Admin › Stock Forecast (all quantities in kg)
///
/// * Tomorrow's order per item = average daily sales of the last 7 days
///   (default). Any item's expected order can be changed and reset.
/// * Stock = A grade + ungraded in the latest stock update (B grade is NOT counted).
/// * "Keep stock for X days" (default 3) decides what to order and by when.
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
  int _coverDays = 3;
  String _filter = 'All';

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
        http.get(Uri.parse('$baseUrl/forecast').replace(queryParameters: {'cover_days': '$_coverDays'})),
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

  void _snack(String t, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: c));
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    try {
      final res = await http.post(Uri.parse('$baseUrl$path'),
          headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
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

  Future<void> _pickCoverDays() async {
    final c = TextEditingController(text: '$_coverDays');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keep stock for how many days?'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Days (1-60)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('CHECK')),
        ],
      ),
    );
    c.dispose();
    final d = int.tryParse(v ?? '');
    if (d == null || d < 1 || d > 60) return;
    setState(() => _coverDays = d);
    _load();
  }

  Future<void> _editExpected(Map<String, dynamic> f, {bool add = false}) async {
    final item = f['item'].toString();
    final c = TextEditingController(text: f['expected_daily_qty']?.toString() ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Expected order per day: $item'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (f['sales_avg'] != null)
            Text('Average of the last ${_data?['window_days'] ?? 7} days: ${_q(f['sales_avg'])} kg / day',
                style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Kg per day', border: OutlineInputBorder()),
          ),
        ]),
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
    await _post('/forecast/expected_qty', {'item': item, 'expected_daily_qty': qty, if (add) 'add': true});
  }

  Future<void> _resetExpected(String item) => _post('/forecast/expected_qty', {'item': item, 'expected_daily_qty': null});

  Future<void> _addItem() async {
    final item = await showDialog<String>(context: context, builder: (ctx) => _PickItemDialog(items: _allItems));
    if (item == null) return;
    await _editExpected({'item': item}, add: true);
  }

  Future<void> _removeItem(String item) => _post('/forecast/remove_item', {'item': item});

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
    final all = List<Map<String, dynamic>>.from((d['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final window = List<String>.from(d['window'] as List);
    final orderNow = all.where((f) => f['status'] == 'order_now').length;
    final items = all.where((f) => _filter == 'All' || (_filter == 'Order now' && f['status'] == 'order_now') ||
        (_filter == 'Changed by you' && f['basis'] == 'expected (entered)')).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Keep stock for', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final n in const [1, 2, 3, 5, 7, 10])
                  ChoiceChip(
                    label: Text('$n ${n == 1 ? 'day' : 'days'}'),
                    selected: _coverDays == n,
                    onSelected: (_) {
                      setState(() => _coverDays = n);
                      _load();
                    },
                  ),
                ActionChip(
                  avatar: const Icon(Icons.edit, size: 16),
                  label: Text(const [1, 2, 3, 5, 7, 10].contains(_coverDays) ? 'Other...' : '$_coverDays days'),
                  onPressed: _pickCoverDays,
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'Tomorrow\'s order = average daily sales (kg) from ${_date(window.first)} to ${_date(window.last)} '
                '(${d['window_days']} days), unless you changed it for an item. '
                'Stock = A grade + ungraded only (B grade is not counted).',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          for (final f in ['All', 'Order now', 'Changed by you'])
            ChoiceChip(
              label: Text(f == 'Order now' ? 'Order now ($orderNow)' : f),
              selected: _filter == f,
              onSelected: (_) => setState(() => _filter = f),
            ),
        ]),
        const SizedBox(height: 6),
        if (items.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nothing to show.'))),
        for (final f in items) _card(f),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> f) {
    final status = f['status'].toString();
    final (Color color, String label) = switch (status) {
      'order_now' => (Colors.red.shade700, 'ORDER NOW'),
      'order_soon' => (Colors.orange.shade800, 'Order soon'),
      'needs_expected_qty' => (Colors.purple, 'New item - enter expected order'),
      'no_demand' => (Colors.blueGrey, 'No sales in the last ${_data!['window_days']} days'),
      _ => (Colors.green.shade700, 'OK for $_coverDays days'),
    };
    final changed = f['basis'] == 'expected (entered)';
    final notes = List<String>.from(f['notes'] as List? ?? []);
    Widget stat(String l, String v, {bool bold = false, Color? c}) => Padding(
          padding: const EdgeInsets.only(right: 18, top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            Text(v, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: c)),
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
            stat(changed ? 'Tomorrow\'s order (yours)' : 'Tomorrow\'s order', f['forecast_next_day'] == null ? '-' : '${_q(f['forecast_next_day'])} kg',
                c: changed ? Colors.purple : null),
            if (changed && f['sales_avg'] != null) stat('7-day average', '${_q(f['sales_avg'])} kg'),
            stat('Stock A+ungraded (${_date(f['stock_date'])})', '${_q(f['stock'])} kg'),
            stat('Open POs', '${_q(f['incoming_open_po'])} kg'),
            stat('Days of stock', f['days_of_cover'] == null ? '-' : _q(f['days_of_cover'])),
            stat('Runs out', _date(f['stock_out_date'])),
            stat('Need for $_coverDays days', f['need_for_cover_days'] == null ? '-' : '${_q(f['need_for_cover_days'])} kg'),
            if ((f['suggested_order_qty'] ?? 0) > 0) stat('Order', '${_q(f['suggested_order_qty'])} kg', bold: true, c: Colors.red.shade700),
            if (f['order_by'] != null && status != 'ok') stat('Order by', _date(f['order_by'])),
          ]),
          for (final n in notes)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(n, style: TextStyle(fontSize: 12, color: Colors.orange.shade900))),
          Wrap(spacing: 4, children: [
            TextButton.icon(
              icon: const Icon(Icons.edit, size: 16),
              label: Text(status == 'needs_expected_qty' ? 'Enter expected order' : 'Change tomorrow\'s order'),
              onPressed: () => _editExpected(f),
            ),
            if (changed && f['has_sales_history'] == true)
              TextButton.icon(
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('Use 7-day average'),
                onPressed: () => _resetExpected(f['item'].toString()),
              ),
            if (notes.any((n) => n.contains('weight per piece')))
              TextButton.icon(
                icon: const Icon(Icons.scale, size: 16),
                label: const Text('Item Settings'),
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
              itemBuilder: (ctx, i) => InkWell(
                onTap: () => Navigator.pop(context, list[i]),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Text(list[i])),
              ),
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL'))],
    );
  }
}
