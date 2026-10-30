import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';

/// Admin › Missing Stock
///
/// Days without a stock update (for items that have stock before and after)
/// can be calculated with the Admin Report logic:
///  * from the day before: stock + purchase + rejection received - vendor return
///    - sales - B grade sales - mandi - dump
///  * from the day after (reverse): next day's stock - those movements of the day
/// The calculated stock is saved as a stock update ("calculated"), so the
/// reports can be made for every day. It can be removed again.
class MissingStockPage extends StatefulWidget {
  const MissingStockPage({super.key});

  @override
  State<MissingStockPage> createState() => _MissingStockPageState();
}

class _MissingStockPageState extends State<MissingStockPage> {
  late DateTime _start;
  late DateTime _end;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  final Map<String, String> _method = {}; // key -> forward | backward | skip
  List<Map<String, dynamic>> _calculated = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = DateTime(now.year, now.month, now.day);
    _start = _end.subtract(const Duration(days: 14));
    _loadCalculated();
  }

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _show(dynamic iso) {
    final d = iso is DateTime ? iso : DateTime.tryParse('$iso');
    return d == null ? '$iso' : DateFormat('dd-MM-yyyy').format(d);
  }

  String _n(dynamic v) {
    final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    if (d == null) return '-';
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  }

  String _key(Map<String, dynamic> r) => '${r['date']}|${r['item']}';

  void _snack(String t, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: c, duration: const Duration(seconds: 6)));
  }

  Future<void> _pick(bool start) async {
    final p = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (p == null) return;
    setState(() {
      if (start) {
        _start = p;
        if (_end.isBefore(p)) _end = p;
      } else {
        _end = p;
        if (_start.isAfter(p)) _start = p;
      }
    });
  }

  Future<void> _find() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse('$baseUrl/stock_fill/missing')
          .replace(queryParameters: {'start': _iso(_start), 'end': _iso(_end)}));
      final b = jsonDecode(res.body) as Map;
      if (res.statusCode != 200) throw Exception(b['message'] ?? 'Server error ${res.statusCode}');
      final rows = ((b['rows'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _method.clear();
        for (final r in rows) {
          _method[_key(r)] = r['forward'] != null ? 'forward' : (r['backward'] != null ? 'backward' : 'skip');
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCalculated() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/stock_fill/calculated'));
      if (res.statusCode != 200) return;
      final b = jsonDecode(res.body) as Map;
      if (!mounted) return;
      setState(() => _calculated = ((b['data'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (_) {}
  }

  Future<void> _save() async {
    final items = [
      for (final r in _rows)
        if ((_method[_key(r)] ?? 'skip') != 'skip') {'date': r['date'], 'item': r['item'], 'method': _method[_key(r)]},
    ];
    if (items.isEmpty) {
      _snack('Nothing selected', Colors.orange);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save calculated stock?'),
        content: Text('${items.length} stock entries will be saved as "calculated" and the reports of those days '
            'recalculated. You can remove them later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SAVE')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      final res = await http
          .post(Uri.parse('$baseUrl/stock_fill/apply'),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode({'items': items}))
          .timeout(const Duration(minutes: 3));
      final b = jsonDecode(res.body) as Map;
      _snack(b['message']?.toString() ?? 'Done', res.statusCode == 200 ? Colors.green : Colors.red);
      if (res.statusCode == 200) {
        await _find();
        await _loadCalculated();
      }
    } catch (e) {
      _snack('Could not save: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(List<dynamic> ids, String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove calculated stock?'),
        content: Text(what),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('REMOVE', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await http.post(Uri.parse('$baseUrl/stock_fill/remove'),
          headers: {'Content-Type': 'application/json'}, body: jsonEncode({'ids': ids}));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      _snack('Removed', Colors.green);
      await _loadCalculated();
    } catch (e) {
      _snack('Could not remove: $e', Colors.red);
    }
  }

  Widget _choice(Map<String, dynamic> r, String method, String label, dynamic value, dynamic note, dynamic warn) {
    final k = _key(r);
    final enabled = value != null;
    return InkWell(
      onTap: enabled ? () => setState(() => _method[k] = method) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
            _method[k] == method ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 18,
            color: enabled ? Colors.indigo : Colors.grey.shade400,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(enabled ? '$label: ${_n(value)} ${r['unit'] ?? ''}' : '$label: not possible',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: enabled ? null : Colors.grey)),
              if (note != null) Text('$note', style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
              if (warn != null) Text('$warn', style: TextStyle(fontSize: 10, color: Colors.orange.shade900)),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final r in _rows) {
      byDate.putIfAbsent('${r['date']}', () => []).add(r);
    }
    final selected = _method.values.where((m) => m != 'skip').length;
    return Scaffold(
      appBar: AppBar(title: const Text('Missing Stock')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
        Text(
          'Finds days with no stock update for items that have stock before and after, and calculates them with '
          'the report logic: from the day before (stock + purchase + rejection received - vendor return - sales - '
          'B grade - mandi - dump) or backwards from the day after. The saved stock is marked "calculated".',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text('From ${_show(_start)}'),
            onPressed: () => _pick(true),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text('To ${_show(_end)}'),
            onPressed: () => _pick(false),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(minimumSize: const Size(64, 44)),
            icon: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search),
            label: const Text('Find missing stock'),
            onPressed: _loading ? null : _find,
          ),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (!_loading && _error == null && _rows.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: Text('Tap "Find missing stock".')),
        for (final e in byDate.entries) ...[
          const SizedBox(height: 10),
          Text('${_show(e.key)} - ${e.value.length} item(s) without stock', style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final r in e.value)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text('${r['item']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                    TextButton(
                      onPressed: () => setState(() => _method[_key(r)] = _method[_key(r)] == 'skip'
                          ? (r['forward'] != null ? 'forward' : 'backward')
                          : 'skip'),
                      child: Text(_method[_key(r)] == 'skip' ? 'Include' : 'Skip'),
                    ),
                  ]),
                  if (_method[_key(r)] != 'skip') ...[
                    _choice(r, 'forward', 'From the day before', r['forward'], r['forward_note'], r['forward_warning']),
                    _choice(r, 'backward', 'From the day after', r['backward'], r['backward_note'], r['backward_warning']),
                  ] else
                    Text('Skipped', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ]),
              ),
            ),
        ],
        if (_rows.isNotEmpty) ...[
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text('Save calculated stock ($selected)'),
            onPressed: _saving || selected == 0 ? null : _save,
          ),
        ],
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: Text('Calculated stock saved (${_calculated.length})', style: const TextStyle(fontWeight: FontWeight.w700))),
          if (_calculated.isNotEmpty)
            TextButton(
              onPressed: () => _remove(_calculated.map((c) => c['id']).toList(), 'All ${_calculated.length} calculated stock entries.'),
              child: const Text('Remove all'),
            ),
        ]),
        if (_calculated.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('None')),
        for (final c in _calculated)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${_show(c['date'])} · ${c['item']} · ${_n(c['qty'])} ${c['unit'] ?? ''}'),
            subtitle: Text('${c['note'] ?? ''}', style: const TextStyle(fontSize: 11)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _remove([c['id']], '${c['item']} on ${_show(c['date'])}'),
            ),
          ),
      ]),
    );
  }
}
