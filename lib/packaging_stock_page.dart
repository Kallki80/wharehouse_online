import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'api_config.dart';
import 'utils/item_picker.dart';

/// Packaging Stock: count of packaging material in stock, entered like the fruit
/// stock update. Valued at the PO rate; GPM uses opening and closing packaging stock
/// (packaging used = opening + packaging purchases - closing).
class PackagingStockPage extends StatefulWidget {
  const PackagingStockPage({super.key});

  @override
  State<PackagingStockPage> createState() => _PackagingStockPageState();
}

class _PackagingStockPageState extends State<PackagingStockPage> {
  static const _units = ['Pcs', 'Kg', 'Box', 'Bundle', 'Roll', 'Packet'];
  DateTime _date = DateTime.now();
  List<String> _items = [];
  String? _item;
  String _unit = 'Pcs';
  final _qty = TextEditingController();
  bool _saving = false;
  bool _loading = true;
  Map<String, dynamic>? _day;
  final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _loadItems();
    _loadDay();
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _n(dynamic v) {
    final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    if (d == null) return '-';
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  }

  void _snack(String t, Color c) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: c));
  }

  Future<void> _loadItems() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/packaging_stock/items'));
      if (res.statusCode == 200 && mounted) {
        setState(() => _items = (jsonDecode(res.body) as List).map((e) => '$e').toList());
      }
    } catch (_) {}
  }

  Future<void> _loadDay() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/packaging_stock').replace(queryParameters: {'date': _iso(_date)}));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode} - is the new server file installed?');
      if (mounted) setState(() => _day = Map<String, dynamic>.from(jsonDecode(res.body) as Map));
    } catch (e) {
      _snack('$e', Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final q = double.tryParse(_qty.text.trim());
    if (_item == null) {
      _snack('Select the packaging item', Colors.red);
      return;
    }
    if (q == null || q < 0) {
      _snack('Enter the quantity in stock', Colors.red);
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/packaging_stock'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'item': _item, 'qty': q, 'unit': _unit, 'date': _iso(_date)}),
      );
      Map b = {};
      try {
        b = jsonDecode(res.body) as Map;
      } catch (_) {}
      if (res.statusCode == 200 && b['success'] == true) {
        _snack('Saved: $_item ${_n(q)} $_unit', Colors.green);
        setState(() {
          _item = null;
          _qty.clear();
        });
        _loadDay();
      } else {
        _snack('Not saved: ${b['message'] ?? 'server error ${res.statusCode}'}', Colors.red);
      }
    } catch (e) {
      _snack('Not saved: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Map e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${e['item']} ${_n(e['qty'])} ${e['unit']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('DELETE', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    var res = await http.delete(Uri.parse('$baseUrl/packaging_stock/${e['id']}'));
    if (res.statusCode == 403 && mounted) {
      final c = TextEditingController();
      final pw = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Admin password'),
          content: TextField(controller: c, obscureText: true, autofocus: true,
              decoration: const InputDecoration(labelText: 'Entries of an earlier day need the Admin password')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('DELETE')),
          ],
        ),
      );
      c.dispose();
      if (pw == null || pw.isEmpty) return;
      res = await http.delete(Uri.parse('$baseUrl/packaging_stock/${e['id']}'), headers: {'X-Admin-Key': pw});
    }
    if (res.statusCode == 200) {
      _snack('Deleted', Colors.green);
      _loadDay();
    } else {
      _snack(res.statusCode == 403 ? 'Wrong Admin password' : 'Not deleted (${res.statusCode})', Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final val = Map<String, dynamic>.from((_day?['valuation'] as Map?) ?? {});
    final rows = ((val['rows'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final entries = ((_day?['entries'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Packaging Stock')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text('Stock date ${DateFormat('dd-MM-yyyy').format(_date)}'),
                onPressed: () async {
                  final p = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
                  if (p != null) {
                    setState(() => _date = p);
                    _loadDay();
                  }
                },
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () async {
                  final v = await showItemSearchDialog(context, _items, title: 'Packaging item');
                  if (v != null) setState(() => _item = v);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Packaging item', border: OutlineInputBorder(), suffixIcon: Icon(Icons.search)),
                  child: Text(_item ?? (_items.isEmpty ? 'No packaging items - mark them in Admin > Item Settings' : 'Tap to search and select'),
                      style: TextStyle(fontSize: 13, color: _item == null ? Colors.grey : Colors.black)),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Quantity in stock', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: _unit,
                  items: [for (final u in _units) DropdownMenuItem(value: u, child: Text(u))],
                  onChanged: (v) => setState(() => _unit = v ?? 'Pcs'),
                ),
              ]),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(minimumSize: const Size(64, 46)),
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: const Text('Save'),
                onPressed: _saving ? null : _save,
              ),
              const SizedBox(height: 6),
              Text('Enter the packaging material in stock, like the fruit stock update. GPM values it at the PO rate: '
                  'packaging used = opening stock + packaging purchases − closing stock.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_day != null) ...[
          Text('Stock of ${DateFormat('dd-MM-yyyy').format(_date)} · value ${_money.format((val['value'] as num?) ?? 0)}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final r in rows)
            ListTile(
              dense: true,
              title: Text('${r['item']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(r['rate'] == null
                  ? '${_n(r['qty'])} ${r['unit']} · no PO rate - valued at 0'
                  : '${_n(r['qty'])} ${r['unit']} × ₹${_n(r['rate'])} (${r['rate_from']})'),
              trailing: Text(_money.format((r['value'] as num?) ?? 0)),
            ),
          if (entries.isNotEmpty) ...[
            const Divider(),
            const Text('Entries', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final e in entries)
              ListTile(
                dense: true,
                title: Text('${e['item']}  ${_n(e['qty'])} ${e['unit']}'),
                subtitle: Text('${e['time'] ?? ''}'),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(e)),
              ),
          ] else
            const Padding(padding: EdgeInsets.all(12), child: Text('No packaging stock entered for this date.')),
        ],
      ]),
    );
  }
}
