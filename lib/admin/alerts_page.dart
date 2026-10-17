import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';
import '../head_approvals_page.dart';
import '../piece_weights_page.dart';
import 'item_settings_page.dart';

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
  bool _hideInfo = false;
  bool _showDone = false; // show the alerts marked "action taken"
  DateTimeRange? _range; // optional: control dates to check (null = last 10 days)

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
      final f = DateFormat('yyyy-MM-dd');
      final uri = Uri.parse('$baseUrl/alerts').replace(
        queryParameters: _range == null ? null : {'start': f.format(_range!.start), 'end': f.format(_range!.end)},
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 120));
      if (res.statusCode != 200) {
        String msg = 'Server error ${res.statusCode}';
        try {
          msg = (jsonDecode(res.body) as Map)['message']?.toString() ?? msg;
        } catch (_) {}
        throw Exception(msg);
      }
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

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: _range ?? DateTimeRange(start: today.subtract(const Duration(days: 10)), end: today),
      helpText: 'Control dates to check',
    );
    if (picked == null) return;
    setState(() => _range = picked);
    _load();
  }

  void _clearRange() {
    setState(() => _range = null);
    _load();
  }

  /// Mark an alert (detail == null) or one entry of it as "action taken",
  /// or undo that. Asks for an optional note when marking.
  Future<void> _markAction(Map<String, dynamic> a, {String? detail, bool undo = false}) async {
    String? note;
    if (!undo) {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(detail == null ? 'Mark alert as action taken' : 'Mark this entry as action taken'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(detail ?? a['title'].toString(), style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              decoration: const InputDecoration(labelText: 'What was done (optional)', border: OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            Text('It will be hidden from alerts. New entries of the same alert still appear.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ACTION TAKEN')),
          ],
        ),
      );
      note = c.text.trim();
      c.dispose();
      if (ok != true) return;
    }
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/alerts/action'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': a['code'],
          'control_date': a['control_date'],
          'detail': detail,
          'note': note,
          'undo': undo,
        }),
      );
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(undo ? 'Alert shown again' : 'Marked as action taken'),
        backgroundColor: undo ? Colors.blueGrey : Colors.green,
        duration: const Duration(seconds: 2),
      ));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e'), backgroundColor: Colors.red));
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
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Choose control dates',
            onPressed: _loading ? null : _pickRange,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not load alerts: $_error')))
              : _buildBody(),
    );
  }

  String _money(num v) => NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(v);

  static const Map<String, IconData> _sectionIcons = {
    'Stock': Icons.inventory_2_outlined,
    'Purchase': Icons.shopping_cart_outlined,
    'Sales': Icons.point_of_sale,
    'B grade': Icons.trending_down,
    'Mandi': Icons.storefront_outlined,
    'Dump': Icons.delete_outline,
    'Rejection received': Icons.assignment_return_outlined,
    'LMD/FMD': Icons.local_shipping_outlined,
    'Verification': Icons.verified_user_outlined,
    'Forecast': Icons.insights_outlined,
  };

  Widget _buildBody() {
    final d = _data!;
    final all = List<Map<String, dynamic>>.from((d['alerts'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final sections = List<Map<String, dynamic>>.from(((d['sections'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
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
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ActionChip(
            avatar: const Icon(Icons.date_range, size: 18),
            label: Text(_range == null
                ? 'Last ${dates.length} days (tap to choose dates)'
                : '${_fmtDate(dates.first)} – ${_fmtDate(dates.last)}'),
            onPressed: _pickRange,
          ),
          if (_range != null)
            ActionChip(
              avatar: const Icon(Icons.close, size: 18),
              label: const Text('Back to last 10 days'),
              onPressed: _clearRange,
            ),
        ]),
        const SizedBox(height: 4),
        Text(
          'Checked ${d['generated_at']} · control dates ${_fmtDate(dates.first)} to ${_fmtDate(dates.last)}'
          '${_range != null && d['range_end'] != d['today'] ? ' · today\'s checks not included' : ''}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        Row(children: [
          badge('to fix', (s['error'] as num).toInt(), Colors.red.shade700),
          badge('warnings', (s['warning'] as num).toInt(), Colors.orange.shade800),
          badge('info', (s['info'] as num).toInt(), Colors.blueGrey),
          const Spacer(),
          FilterChip(label: const Text('Hide info'), selected: _hideInfo, onSelected: (v) => setState(() => _hideInfo = v)),
        ]),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: FilterChip(
            avatar: const Icon(Icons.task_alt, size: 18),
            label: Text('Show action taken (${(d['done_count'] as num?)?.toInt() ?? 0})'),
            selected: _showDone,
            onSelected: (v) => setState(() => _showDone = v),
          ),
        ),
        const SizedBox(height: 8),
        if (sections.isEmpty)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nothing to show - all good.'))),
        for (final sec in sections) _sectionCard(sec, all.where((a) => a['category'] == sec['section']).toList()),
        if (_showDone) _doneCard(List<Map<String, dynamic>>.from(
            ((d['done_alerts'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)))),
      ]),
    );
  }

  Widget _sectionCard(Map<String, dynamic> sec, List<Map<String, dynamic>> alerts) {
    final list = alerts.where((a) => !(_hideInfo && a['severity'] == 'info')).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    final errors = (sec['errors'] as num).toInt();
    final warnings = (sec['warnings'] as num).toInt();
    final amount = (sec['amount'] as num?) ?? 0;
    final color = errors > 0 ? Colors.red.shade700 : warnings > 0 ? Colors.orange.shade800 : Colors.blueGrey;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        initiallyExpanded: errors > 0,
        leading: Icon(_sectionIcons[sec['section']] ?? Icons.flag_outlined, color: color),
        title: Text(sec['section'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${list.length} ${list.length == 1 ? 'alert' : 'alerts'}'
          '${errors > 0 ? ' · $errors to fix' : ''}'
          '${amount > 0 ? ' · cost at stake ${_money(amount)}' : ''}',
          style: TextStyle(fontSize: 12, color: color),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: [for (final a in list) _alertTile(a)],
      ),
    );
  }

  /// Button that fixes the alert directly, where there is one.
  Widget? _actionFor(String? code) {
    Widget button(String label, IconData icon, Widget page) => Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ElevatedButton.icon(
              icon: Icon(icon, size: 18),
              label: Text(label),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
                _load();
              },
            ),
          ),
        );
    switch (code) {
      case 'piece_weight_missing':
        return button('Enter weights', Icons.scale, const PieceWeightsPage());
      case 'item_unit_missing':
        return button('Open Item Settings', Icons.tune, const ItemSettingsPage());
      case 'verification_pending':
        return button('Open Head Approvals', Icons.verified_user_outlined, const HeadApprovalsPage());
      default:
        return null;
    }
  }

  Widget _alertTile(Map<String, dynamic> a) {
    final sev = a['severity'];
    final color = sev == 'error' ? Colors.red.shade700 : sev == 'warning' ? Colors.orange.shade800 : Colors.blueGrey;
    final icon = sev == 'error' ? Icons.error_outline : sev == 'warning' ? Icons.warning_amber_rounded : Icons.info_outline;
    final details = List<String>.from(a['details'] as List? ?? []);
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(a['title'].toString(), style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${_fmtDate(a['control_date']?.toString())}'
          '${details.isNotEmpty ? ' · ${details.length} ${details.length == 1 ? 'entry' : 'entries'}' : ''}'
          '${((a['amount'] as num?) ?? 0) > 0 ? ' · ≈ ${_money(a['amount'] as num)}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(56, 0, 8, 12),
        children: [
          if (_actionFor(a['code']?.toString()) != null) _actionFor(a['code']?.toString())!,
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.task_alt, size: 18),
              label: Text(details.length > 1 ? 'Action taken for all' : 'Mark action taken'),
              onPressed: () => _markAction(a),
            ),
          ),
          ...details.map((t) => Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: SelectableText(t, style: const TextStyle(fontSize: 13)),
                  ),
                ),
                if (details.length > 1)
                  IconButton(
                    tooltip: 'Action taken for this entry',
                    icon: Icon(Icons.check_circle_outline, size: 20, color: Colors.green.shade600),
                    onPressed: () => _markAction(a, detail: t),
                  ),
              ])),
        ],
      ),
    );
  }

  /// Alerts (or entries) marked "action taken", with Undo.
  Widget _doneCard(List<Map<String, dynamic>> done) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: Colors.green.shade50,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(Icons.task_alt, color: Colors.green.shade700),
        title: const Text('Action taken', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(done.isEmpty ? 'Nothing marked yet' : 'Hidden from alerts - tap Undo to show again',
            style: const TextStyle(fontSize: 12)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
        children: [
          for (final a in done) ...[
            const Divider(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('${a['title']} · ${_fmtDate(a['control_date']?.toString())}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            if (a['whole'] == true)
              Row(children: [
                Expanded(
                  child: Text(
                    [
                      if ((a['details'] as List? ?? []).isNotEmpty) '${(a['details'] as List).length} entries',
                      if ((a['note'] ?? '').toString().isNotEmpty) 'Note: ${a['note']}',
                      'Marked ${a['done_at'] ?? ''}',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
                TextButton(onPressed: () => _markAction(a, undo: true), child: const Text('UNDO')),
              ])
            else
              for (final e in List<Map<String, dynamic>>.from(
                  ((a['done'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map))))
                Row(children: [
                  Expanded(
                    child: Text(
                      '${e['detail']}'
                      '${(e['note'] ?? '').toString().isNotEmpty ? ' · Note: ${e['note']}' : ''}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _markAction(a, detail: e['detail']?.toString(), undo: true),
                    child: const Text('UNDO'),
                  ),
                ]),
          ],
        ],
      ),
    );
  }
}
