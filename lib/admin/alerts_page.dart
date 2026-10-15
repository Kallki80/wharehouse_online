import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';

/// Bell icon with a red badge (number of errors + warnings). Checks the
/// server when shown and every 5 minutes while the screen is open.
/// Tapping it opens [AlertsPage].
class AlertsBell extends StatefulWidget {
  final Color? color;
  const AlertsBell({super.key, this.color});

  @override
  State<AlertsBell> createState() => _AlertsBellState();
}

class _AlertsBellState extends State<AlertsBell> {
  int _errors = 0;
  int _warnings = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/alerts/count')).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200 || !mounted) return;
      final b = jsonDecode(res.body);
      setState(() {
        _errors = (b['error'] as num?)?.toInt() ?? 0;
        _warnings = (b['warning'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {
      // offline: keep the last numbers
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _errors + _warnings;
    return IconButton(
      tooltip: 'Alerts',
      onPressed: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertsPage()));
        _refresh();
      },
      icon: Stack(clipBehavior: Clip.none, children: [
        Icon(n > 0 ? Icons.notifications_active : Icons.notifications_none, color: widget.color),
        if (n > 0)
          Positioned(
            right: -6,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: _errors > 0 ? Colors.red : Colors.orange,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                n > 99 ? '99+' : '$n',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Daily checks for the last 10 control dates (stock, purchase, LMD/FMD,
/// sales vs SO, quality limits, forecast).
class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  String _category = 'All';
  bool _hideInfo = false;

  static const _categories = ['All', 'Stock', 'Purchase', 'Logistics', 'Sales', 'Quality', 'Forecast'];

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
      final res = await http.get(Uri.parse('$baseUrl/alerts')).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
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

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('EEE dd MMM').format(d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not load alerts: $_error')))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final d = _data!;
    final all = List<Map<String, dynamic>>.from((d['alerts'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final list = all.where((a) {
      if (_category != 'All' && a['category'] != _category) return false;
      if (_hideInfo && a['severity'] == 'info') return false;
      return true;
    }).toList();
    final s = Map<String, dynamic>.from(d['summary'] as Map);
    final dates = List<String>.from(d['control_dates'] as List);

    Widget badge(String label, int n, Color c) => Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
          child: Text('$n $label', style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
        );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
        Text(
          'Checked ${d['generated_at']} · control dates ${_fmtDate(dates.first)} to ${_fmtDate(dates.last)}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        Row(children: [
          badge('to fix', (s['error'] as num).toInt(), Colors.red.shade700),
          badge('warnings', (s['warning'] as num).toInt(), Colors.orange.shade800),
          badge('info', (s['info'] as num).toInt(), Colors.blueGrey),
        ]),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final c in _categories)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(c == 'All' ? 'All' : '$c (${all.where((a) => a['category'] == c).length})'),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
              ),
            FilterChip(label: const Text('Hide info'), selected: _hideInfo, onSelected: (v) => setState(() => _hideInfo = v)),
          ]),
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nothing to show - all good.'))),
        for (final a in list) _alertTile(a),
      ]),
    );
  }

  Widget _alertTile(Map<String, dynamic> a) {
    final sev = a['severity'];
    final color = sev == 'error' ? Colors.red.shade700 : sev == 'warning' ? Colors.orange.shade800 : Colors.blueGrey;
    final icon = sev == 'error' ? Icons.error_outline : sev == 'warning' ? Icons.warning_amber_rounded : Icons.info_outline;
    final details = List<String>.from(a['details'] as List? ?? []);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(a['title'].toString(), style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${a['category']} · ${_fmtDate(a['control_date']?.toString())}'
          '${details.isNotEmpty ? ' · ${details.length} ${details.length == 1 ? 'entry' : 'entries'}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
        children: details.isEmpty
            ? [const SizedBox.shrink()]
            : details
                .map((t) => Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: SelectableText(t, style: const TextStyle(fontSize: 13)),
                      ),
                    ))
                .toList(),
      ),
    );
  }
}
