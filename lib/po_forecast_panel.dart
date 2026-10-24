import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'api_config.dart';

/// Stock forecast for one PO line, shown after the item and the expected date
/// of arrival are picked.
///
/// stock now - average sales per day x days until arrival + open POs arriving
/// by then = stock on arrival; needed for "keep stock for N days" = average x N;
/// suggested order = needed - stock on arrival. The PO quantity may differ by
/// up to 20 %; more than that, or ordering when the forecast says it is not
/// needed, needs Admin approval when the PO is created.
class PoForecastPanel extends StatefulWidget {
  final String item;
  final DateTime expectedDate;
  final String unit;

  /// The parameters used (avg / keep_days / window) - sent again for the approval check.
  final void Function(Map<String, String> params, Map<String, dynamic>? forecast) onChanged;

  /// "Use this quantity" - the suggested quantity in the PO unit.
  final void Function(double qty) onUseSuggested;

  const PoForecastPanel({
    super.key,
    required this.item,
    required this.expectedDate,
    required this.unit,
    required this.onChanged,
    required this.onUseSuggested,
  });

  @override
  State<PoForecastPanel> createState() => _PoForecastPanelState();
}

class _PoForecastPanelState extends State<PoForecastPanel> {
  final _avg = TextEditingController();
  final _keep = TextEditingController(text: '3');
  final _conv = TextEditingController();
  bool _ownAvg = false;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _f;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PoForecastPanel old) {
    super.didUpdateWidget(old);
    if (old.item != widget.item || old.expectedDate != widget.expectedDate || old.unit != widget.unit) {
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _avg.dispose();
    _keep.dispose();
    _conv.dispose();
    super.dispose();
  }

  Map<String, String> get _params => {
        if (_ownAvg && double.tryParse(_avg.text.trim()) != null) 'avg': _avg.text.trim(),
        'keep_days': '${int.tryParse(_keep.text.trim()) ?? 3}',
        'window': '7',
      };

  void _later() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse('$baseUrl/forecast/po_check').replace(queryParameters: {
        'item': widget.item,
        'expected_date': DateFormat('yyyy-MM-dd').format(widget.expectedDate),
        'unit': widget.unit,
        ..._params,
      }));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      final b = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      if (!mounted) return;
      setState(() => _f = b);
      widget.onChanged(_params, b);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Forecast not available: $e');
      widget.onChanged(_params, null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveConversion() async {
    final v = double.tryParse(_conv.text.trim());
    if (v == null || v <= 0) return;
    final f = _f!;
    // pcs item ordered in kg/box: the weight of one piece; else kg in one box / bag
    final unit = (f['stock_unit'] == 'pcs' && f['kg_per_unit'] != null) ? 'pcs' : widget.unit;
    try {
      final res = await http.post(Uri.parse('$baseUrl/forecast/unit_weight'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'item': widget.item, 'unit': unit, 'kg_per_unit': v}));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      _conv.clear();
      _load();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: $e');
    }
  }

  String _n(dynamic v) {
    final d = (v as num?)?.toDouble();
    if (d == null) return '-';
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final f = _f;
    final su = (f?['stock_unit'] ?? 'kg').toString();
    final status = f?['status'];
    final color = status == 'order'
        ? Colors.green.shade800
        : (status == 'not_needed' ? Colors.orange.shade900 : Colors.grey.shade700);
    Widget line(String a, String b, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(children: [
            Expanded(child: Text(a, style: const TextStyle(fontSize: 12))),
            Text(b, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.insights, color: Colors.teal.shade700, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Stock forecast for ${DateFormat('dd-MM-yyyy').format(widget.expectedDate)}',
                style: TextStyle(fontWeight: FontWeight.w700, color: Colors.teal.shade900, fontSize: 13)),
          ),
          if (_loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: false,
              label: Text(f == null ? 'Sales average' : 'Sales avg ${_n(f['sales_avg'])} $su/day',
                  style: const TextStyle(fontSize: 11)),
            ),
            const ButtonSegment(value: true, label: Text('My average', style: TextStyle(fontSize: 11))),
          ],
          selected: {_ownAvg},
          showSelectedIcon: false,
          onSelectionChanged: (s) {
            setState(() => _ownAvg = s.first);
            _load();
          },
        ),
        const SizedBox(height: 8),
        Row(children: [
          if (_ownAvg) ...[
            Expanded(
              child: TextField(
                controller: _avg,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Sales per day ($su)',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: (_) => _later(),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: _keep,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Keep stock for (days)',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (_) => _later(),
            ),
          ),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12))),
        if (f != null) ...[
          const SizedBox(height: 8),
          line('Stock now${f['stock_date'] != null ? ' (stock update ${f['stock_date']})' : ''}', '${_n(f['stock'])} $su'),
          line('Average sales per day (${f['avg_basis'] ?? 'none'})', f['avg_used'] == null ? '-' : '${_n(f['avg_used'])} $su'),
          line('Days until arrival', '${f['days_to_arrival']}'),
          if (((f['incoming'] as num?) ?? 0) > 0)
            line('Open POs arriving by then', '+ ${_n(f['incoming'])} $su'),
          if (f['consumption_until_arrival'] != null)
            line('Sold until arrival', '- ${_n(f['consumption_until_arrival'])} $su'),
          if (f['stock_on_arrival'] != null)
            line('Stock on arrival', '${_n(f['stock_on_arrival'])} $su'
                '${f['days_of_cover_on_arrival'] != null ? ' (${_n(f['days_of_cover_on_arrival'])} days)' : ''}', bold: true),
          if (f['need_for_keep_days'] != null) line('Needed for ${f['keep_days']} days', '${_n(f['need_for_keep_days'])} $su'),
          const Divider(height: 14),
          Text(
            status == 'order'
                ? 'Order needed: about ${_n(f['suggested'])} $su'
                    '${f['suggested_in_unit'] != null && widget.unit != su ? ' = ${_n(f['suggested_in_unit'])} ${widget.unit}' : ''}'
                : status == 'not_needed'
                    ? 'Not needed for this date - stock on arrival covers ${f['keep_days']} days. '
                        'Ordering anyway needs Admin approval.'
                    : 'No sales history - choose "My average" and enter the expected sales per day.',
            style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 13),
          ),
          if (status == 'order' && f['min_in_unit'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Expanded(
                  child: Text(
                    'Allowed without approval: ${_n(f['min_in_unit'])} - ${_n(f['max_in_unit'])} ${widget.unit} (±${f['tolerance_percent']}%)',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                TextButton(
                  onPressed: () => widget.onUseSuggested(((f['suggested_in_unit'] as num).toDouble() * 100).round() / 100),
                  child: const Text('Use this qty'),
                ),
              ]),
            ),
          if (status == 'order' && f['stock_units_per_po_unit'] == null) ...[
            const SizedBox(height: 6),
            Text(
              su == 'pcs' && f['kg_per_unit'] != null
                  ? 'Enter the weight of one piece to compare the ${widget.unit} quantity with the forecast:'
                  : 'Enter the kg in one ${widget.unit} to compare the quantity with the forecast:',
              style: const TextStyle(fontSize: 11),
            ),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _conv,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: su == 'pcs' && f['kg_per_unit'] != null ? 'kg per piece' : 'kg in one ${widget.unit}',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              TextButton(onPressed: _saveConversion, child: const Text('SAVE')),
            ]),
          ],
          for (final n in ((f['notes'] as List?) ?? []))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $n', style: TextStyle(fontSize: 11, color: Colors.grey.shade800)),
            ),
        ],
      ]),
    );
  }
}

/// Before creating the PO: lines that need Admin approval (not needed by the
/// forecast, or more than 20 % away from it) are approved with the admin
/// password. Returns true when the PO may be created.
Future<bool> approvePoAgainstForecast(BuildContext context, String poNumber, List<Map<String, dynamic>> lines) async {
  Future<http.Response> call(String? pw) => http.post(
        Uri.parse('$baseUrl/forecast/po_approval'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'po_number': poNumber, 'items': lines, if (pw != null) 'password': pw}),
      );
  http.Response res;
  try {
    res = await call(null);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not check the forecast: $e'), backgroundColor: Colors.red));
    }
    return false;
  }
  if (res.statusCode != 200) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not check the forecast (server ${res.statusCode}) - is the new server file installed?'),
          backgroundColor: Colors.red));
    }
    return false;
  }
  final b = jsonDecode(res.body) as Map;
  if (b['needs_approval'] != true) return true;
  final reasons = ((b['lines'] as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .where((l) => l['reason'] != null)
      .toList();
  if (!context.mounted) return false;
  final pwC = TextEditingController();
  String? err;
  bool ok = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        icon: const Icon(Icons.admin_panel_settings_outlined, color: Colors.orange),
        title: const Text('Admin approval needed'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final l in reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${l['item']} (${l['expected_date']}): ${l['reason']}', style: const TextStyle(fontSize: 13)),
                ),
              const SizedBox(height: 6),
              TextField(
                controller: pwC,
                obscureText: true,
                decoration: InputDecoration(labelText: 'Admin password', border: const OutlineInputBorder(), errorText: err),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL - change the PO')),
          TextButton(
            onPressed: () async {
              try {
                final r = await call(pwC.text);
                final rb = jsonDecode(r.body) as Map;
                if (r.statusCode == 200 && rb['approved'] == true) {
                  ok = true;
                  if (ctx.mounted) Navigator.pop(ctx);
                } else {
                  setD(() => err = rb['message']?.toString() ?? 'Not approved');
                }
              } catch (e) {
                setD(() => err = '$e');
              }
            },
            child: const Text('APPROVE'),
          ),
        ],
      ),
    ),
  );
  pwC.dispose();
  return ok;
}
