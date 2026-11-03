import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';
import '../utils/file_saver.dart';

/// Admin › Rejection Check (Sales Report)
/// Per SO and item: sent (sales entries) − billed in the Sales Report (accepted by
/// the client) = rejection that should be entered against that SO, compared with
/// the Rejection Received entries - pieces with pieces, kg with kg.
class RejectionCheckPage extends StatefulWidget {
  const RejectionCheckPage({super.key});

  @override
  State<RejectionCheckPage> createState() => _RejectionCheckPageState();
}

class _RejectionCheckPageState extends State<RejectionCheckPage> {
  DateTime? _start;
  DateTime? _end;
  bool _loading = false;
  bool _exporting = false;
  String? _error;
  Map<String, dynamic>? _r;
  bool _onlyIssues = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // default: yesterday's control date (Sales Report is uploaded the next day)
    _end = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    _start = _end;
  }

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _show(DateTime d) => DateFormat('dd-MM-yyyy').format(d);
  String _dd(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? '${iso ?? ''}' : DateFormat('dd-MM-yy').format(d);
  }

  String _n(dynamic v) {
    final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    if (d == null) return '-';
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  }

  Map<String, String> get _q => {'start': _iso(_start!), 'end': _iso(_end!)};

  Future<void> _pick(bool start) async {
    final p = await showDatePicker(
      context: context,
      initialDate: (start ? _start : _end) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: start ? 'From (control date)' : 'To (control date)',
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
      final res = await http.get(Uri.parse('$baseUrl/rejection_check').replace(queryParameters: _q));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode} - is the new server file installed?');
      final b = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      if (mounted) setState(() => _r = b);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    setState(() => _exporting = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/rejection_check/export').replace(queryParameters: _q));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      if (!mounted) return;
      await saveOrShareFile(context, bytes: res.bodyBytes, fileName: 'REJECTION_CHECK_${_iso(_start!)}_to_${_iso(_end!)}.xlsx');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Color _sc(String s) {
    switch (s) {
      case 'ok':
        return Colors.green.shade700;
      case 'rejection not entered':
      case 'rejection short':
        return Colors.red.shade700;
      case 'rejection more':
      case 'billed more than sent':
        return Colors.orange.shade900;
      default:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rejection Check'),
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
              const Text('Sales Report control dates', style: TextStyle(fontWeight: FontWeight.w700)),
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
                    : const Icon(Icons.fact_check_outlined),
                label: const Text('Check rejections'),
                onPressed: _loading ? null : _run,
              ),
              const SizedBox(height: 6),
              Text(
                'What is billed in the Sales Report is what the client accepted. Sent (sales entries of the SO) − billed '
                '= rejection that should be in Rejection Received against that SO. Pieces are compared with pieces, kg with kg. '
                'Upload the Sales Report first (GPM or Fill Rate).',
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
    final rows = ((_r!['rows'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).where((x) {
      if (_onlyIssues && x['status'] == 'ok') return false;
      return _search.isEmpty || '${x['so_number']} ${x['client']} ${x['item']}'.toLowerCase().contains(_search);
    }).toList();
    final kg = Map<String, dynamic>.from((t['kg'] as Map?) ?? {});
    final pcs = Map<String, dynamic>.from((t['pcs'] as Map?) ?? {});
    // group by SO
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final x in rows) {
      groups.putIfAbsent('${x['so_number']}', () => []).add(x);
    }
    return [
      const SizedBox(height: 8),
      if (t.isNotEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('SOs ${t['orders']} · with a difference ${t['orders_with_mismatch']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Lines ${t['lines']} · matching ${t['ok']} · not matching ${t['mismatches']} · rejection not entered ${t['rejection_not_entered']}',
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text('Pieces: should be ${_n(pcs['expected'])} · entered ${_n(pcs['entered'])} · missing ${_n(pcs['missing'])}',
                  style: const TextStyle(fontSize: 12)),
              Text('Kg: should be ${_n(kg['expected'])} · entered ${_n(kg['entered'])} · missing ${_n(kg['missing'])}',
                  style: const TextStyle(fontSize: 12)),
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
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Only lines that do not match'),
        value: _onlyIssues,
        onChanged: (v) => setState(() => _onlyIssues = v),
      ),
      TextField(
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search SO, client or item', isDense: true),
        onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
      ),
      const SizedBox(height: 6),
      if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing to show.')),
      for (final e in groups.entries.take(300)) _soCard(e.key, e.value),
    ];
  }

  Widget _soCard(String so, List<Map<String, dynamic>> lines) {
    final first = lines.first;
    return Card(
      key: ValueKey('rc-$so'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('SO $so · ${first['client']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('Control date ${_dd(first['date'])}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          for (final x in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${x['item']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                  Text('${x['status']}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _sc('${x['status']}'))),
                ]),
                Text(
                  'Sent ${_n(x['sent'])} · billed ${_n(x['billed'])} ${x['unit']} → rejection should be ${_n(x['expected_rejection'])}, '
                  'entered ${_n(x['rejection_entered'])} ${x['unit']}'
                  '${(x['difference'] as num? ?? 0).abs() > 0 && x['status'] != 'ok' ? ' (difference ${_n(x['difference'])})' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
                if ('${x['note'] ?? ''}'.isNotEmpty) Text('${x['note']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              ]),
            ),
        ]),
      ),
    );
  }
}
