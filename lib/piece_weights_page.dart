import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'api_config.dart';

/// Daily average weight per piece (papaya, pineapple and any item whose
/// stock is counted in pieces). Asked every day through Alerts; each day's
/// weight is stored and used for that day in GPM, B grade analysis,
/// alerts and forecast.
class PieceWeightsPage extends StatefulWidget {
  const PieceWeightsPage({super.key});

  @override
  State<PieceWeightsPage> createState() => _PieceWeightsPageState();
}

class _PieceWeightsPageState extends State<PieceWeightsPage> {
  DateTime _date = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _history = [];
  final Map<String, TextEditingController> _ctrls = {};

  String get _iso => DateFormat('yyyy-MM-dd').format(_date);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse('$baseUrl/piece_weights').replace(queryParameters: {'date': _iso}));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      final b = jsonDecode(res.body);
      final items = (b['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      for (final c in _ctrls.values) {
        c.dispose();
      }
      _ctrls.clear();
      for (final it in items) {
        _ctrls[it['item'].toString()] = TextEditingController(text: it['weight']?.toString() ?? '');
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _history = (b['history'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
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

  Future<void> _save() async {
    final weights = <String, dynamic>{};
    for (final it in _items) {
      final name = it['item'].toString();
      final t = _ctrls[name]!.text.trim();
      if (t.isEmpty) continue;
      final v = double.tryParse(t);
      if (v == null || v <= 0) {
        _snack('Enter a valid weight for $name', Colors.red);
        return;
      }
      weights[name] = v;
    }
    if (weights.isEmpty) {
      _snack('Enter at least one weight', Colors.orange);
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/piece_weights'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'date': _iso, 'weights': weights}),
      );
      final b = jsonDecode(res.body);
      if (res.statusCode == 200 && b['success'] == true) {
        _snack('Saved ${b['saved']} weight(s) for ${DateFormat('dd MMM').format(_date)}', Colors.green);
        await _load();
      } else {
        _snack(b['message']?.toString() ?? 'Save failed', Colors.red);
      }
    } catch (e) {
      _snack('Save failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String t, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: c));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily Piece Weights')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load: $_error'))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Row(children: [
                    Expanded(
                      child: Text('Average weight of one piece on ${DateFormat('dd MMM yyyy').format(_date)}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Date'),
                      onPressed: () async {
                        final p = await showDatePicker(
                            context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
                        if (p != null) {
                          setState(() => _date = p);
                          _load();
                        }
                      },
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    'Weigh a few pieces and enter the average. This day\'s weight is used to turn pieces into kg '
                    'for GPM, B grade analysis, alerts and forecast. Days without an entry use the last weight entered.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No piece-counted items in stock in the last 10 days.'),
                    ),
                  for (final it in _items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: TextField(
                        controller: _ctrls[it['item'].toString()],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: '${it['item']} - kg per piece',
                          helperText: it['last_weight'] != null
                              ? 'Last: ${it['last_weight']} kg on ${it['last_date']}'
                              : (it['default_weight'] != null ? 'Default: ${it['default_weight']} kg' : 'No weight entered before'),
                          border: const OutlineInputBorder(),
                          suffixText: 'kg',
                        ),
                      ),
                    ),
                  if (_items.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save),
                      label: const Text('Save weights'),
                      onPressed: _saving ? null : _save,
                    ),
                  ],
                  if (_history.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('Recent entries', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    for (final h in _history)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('${h['date']} · ${h['item']} · ${h['weight']} kg', style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                ]),
    );
  }
}
