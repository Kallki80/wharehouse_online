import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';

/// Admin › Edit Permissions
///
/// Existing entries can be changed outside Admin (Inventory dashboard, LMD-FMD
/// list) only when they are unlocked here: pick what, pick the control date,
/// tick the POs / SOs (or the whole date for B grade / mandi / dump).
class EditPermissionsPage extends StatefulWidget {
  const EditPermissionsPage({super.key});

  @override
  State<EditPermissionsPage> createState() => _EditPermissionsPageState();
}

class _EditPermissionsPageState extends State<EditPermissionsPage> {
  static const _kinds = <String, String>{
    'po': 'Purchases (PO)',
    'so': 'Sales (SO)',
    'lmd': 'LMD (SO)',
    'fmd': 'FMD (PO)',
    'bgrade': 'B grade sales',
    'mandi': 'Mandi resale',
    'dump': 'Dump sale',
  };
  static const _help = <String, String>{
    'po': 'Purchase and packaging entries of the PO: edit, delete and add items.',
    'so': 'Sales entries of the SO (client and SO number shown).',
    'lmd': 'LMD entries of the SO.',
    'fmd': 'FMD entries of the PO.',
    'bgrade': 'All B grade sales entries of the control date.',
    'mandi': 'All mandi resale entries of the control date.',
    'dump': 'All dump sale entries of the control date.',
  };

  String _kind = 'po';
  DateTime _date = DateTime.now();
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _cands = [];
  List<Map<String, dynamic>> _unlocked = [];
  final Set<String> _busy = {};

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String t, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: c));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r1 = await http.get(Uri.parse('$baseUrl/edit_unlocks/candidates')
          .replace(queryParameters: {'kind': _kind, 'date': _iso(_date)}));
      final r2 = await http.get(Uri.parse('$baseUrl/edit_unlocks'));
      if (r1.statusCode != 200 || r2.statusCode != 200) {
        throw Exception('Server error ${r1.statusCode}/${r2.statusCode} - is the new server file installed?');
      }
      final b1 = jsonDecode(r1.body) as Map;
      final b2 = jsonDecode(r2.body) as Map;
      if (!mounted) return;
      setState(() {
        _cands = ((b1['data'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _unlocked = ((b2['data'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _set(String kind, String key, String label, String? ctrlDate, bool unlock) async {
    setState(() => _busy.add('$kind|$key'));
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/edit_unlocks'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'kind': kind, 'key': key, 'label': label, 'ctrl_date': ctrlDate, 'unlocked': unlock}),
      );
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      await _load();
    } catch (e) {
      _snack('Could not save: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _busy.remove('$kind|$key'));
    }
  }

  Future<void> _lockAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lock everything?'),
        content: Text('All ${_unlocked.length} unlocked entries will be locked again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('LOCK ALL')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await http.post(Uri.parse('$baseUrl/edit_unlocks/lock_all'),
          headers: {'Content-Type': 'application/json'}, body: jsonEncode({}));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      _snack('All locked', Colors.green);
      await _load();
    } catch (e) {
      _snack('Could not lock: $e', Colors.red);
    }
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      helpText: 'Control date',
    );
    if (p == null) return;
    setState(() => _date = p);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Permissions'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
        Text(
          'Outside Admin, an existing entry can be edited or deleted only when it is unlocked here. '
          'New entries can always be made from the entry screens. Admin can always edit.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final k in _kinds.entries)
                  ChoiceChip(
                    label: Text(k.value),
                    selected: _kind == k.key,
                    onSelected: (_) {
                      setState(() => _kind = k.key);
                      _load();
                    },
                  ),
              ]),
              const SizedBox(height: 8),
              Text(_help[_kind]!, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text('Control date ${DateFormat('dd-MM-yyyy').format(_date)}'),
                  onPressed: _pickDate,
                ),
              ),
            ]),
          ),
        ),
        if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (!_loading && _error == null && _cands.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Nothing for ${_kinds[_kind]} on ${DateFormat('dd-MM-yyyy').format(_date)}.'),
          ),
        for (final c in _cands)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 3),
            child: CheckboxListTile(
              value: c['unlocked'] == true,
              onChanged: _busy.contains('$_kind|${c['key']}')
                  ? null
                  : (v) => _set(_kind, c['key'].toString(), c['label'].toString(), _iso(_date), v == true),
              title: Text(c['label'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${(c['entries'] as num?) ?? 0} entr${((c['entries'] as num?) ?? 0) == 1 ? 'y' : 'ies'}'
                '${((c['details'] as List?) ?? []).isEmpty ? '' : ' · ${(c['details'] as List).join(', ')}'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              secondary: Icon(c['unlocked'] == true ? Icons.lock_open : Icons.lock_outline,
                  color: c['unlocked'] == true ? Colors.green : Colors.grey),
            ),
          ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: Text('Unlocked now (${_unlocked.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          if (_unlocked.isNotEmpty)
            TextButton.icon(onPressed: _lockAll, icon: const Icon(Icons.lock), label: const Text('Lock all')),
        ]),
        if (_unlocked.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Everything is locked.')),
        for (final u in _unlocked)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_open, color: Colors.green),
            title: Text('${_kinds[u['kind']] ?? u['kind']}: ${u['label']}'),
            subtitle: Text('Control date ${u['ctrl_date'] ?? '-'} · unlocked ${u['unlocked_at'] ?? ''}',
                style: const TextStyle(fontSize: 11)),
            trailing: TextButton(
              onPressed: _busy.contains('${u['kind']}|${u['key']}')
                  ? null
                  : () => _set(u['kind'].toString(), u['key'].toString(), u['label'].toString(), u['ctrl_date']?.toString(), false),
              child: const Text('LOCK'),
            ),
          ),
      ]),
    );
  }
}
