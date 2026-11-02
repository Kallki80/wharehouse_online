import 'dart:convert';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';
import '../utils/file_saver.dart';

/// Admin › Fill Rate - two sections:
///  * Dispatch Fill Rate: SO vs the sales entries made against that SO
///  * SI Fill Rate: SO vs the Sales Report (invoices raised against that SO -
///    the invoice's Order No), control date wise
/// Client-wise, item-wise and unit-wise (kg with kg, pieces / units with pieces).
/// Fill % of a line = sent (or invoiced) / ordered, capped at 100 % (extra shown separately).
class FillRatePage extends StatefulWidget {
  const FillRatePage({super.key});

  @override
  State<FillRatePage> createState() => _FillRatePageState();
}

class _FillRatePageState extends State<FillRatePage> {
  DateTime? _start;
  DateTime? _end;
  String? _client; // null = all clients
  List<String> _clients = [];
  double _tolerance = 0;
  bool _excludeUnsent = false;
  bool _loading = false;
  bool _exporting = false;
  String? _error;
  Map<String, dynamic>? _r;
  String _view = 'clients'; // clients | items | client_items | lines
  bool _onlyShort = true;
  String _search = '';
  final Set<String> _open = {};
  String _source = 'dispatch'; // dispatch | invoice (SI)
  bool _uploading = false;

  bool get _si => _source == 'invoice';
  String get _sentWord => _si ? 'invoiced' : 'sent';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    _start = _end!.subtract(const Duration(days: 6));
    _loadClients();
  }

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _show(DateTime d) => DateFormat('dd-MM-yyyy').format(d);
  String _showIso(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? '${iso ?? ''}' : DateFormat('dd-MM-yy').format(d);
  }

  String _n(dynamic v) {
    final d = (v as num?)?.toDouble();
    if (d == null) return '-';
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  }

  String _p(dynamic v) => v == null ? '-' : '${_n(v)} %';

  Color _pc(dynamic v) {
    final d = (v as num?)?.toDouble();
    if (d == null) return Colors.grey;
    if (d >= 95) return Colors.green.shade700;
    if (d >= 80) return Colors.orange.shade800;
    return Colors.red.shade700;
  }

  Map<String, String> get _query => {
        'start': _iso(_start!),
        'end': _iso(_end ?? _start!),
        if (_client != null) 'client': _client!,
        if (_tolerance > 0) 'tolerance': _tolerance.toString(),
        if (_excludeUnsent) 'exclude_unsent': '1',
        if (_si) 'source': 'invoice',
      };

  void _setSource(String s) {
    if (s == _source) return;
    setState(() {
      _source = s;
      _r = null;
      _error = null;
      _open.clear();
    });
  }

  /// SI fill rate: upload the Sales Report (same upload as GPM - one copy on the server).
  Future<void> _uploadSalesReport() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx'], withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    List<int>? bytes = file.bytes;
    if (bytes == null && !kIsWeb && file.path != null) bytes = await io.File(file.path!).readAsBytes();
    if (bytes == null) {
      _snack('Could not read the file', Colors.red);
      return;
    }
    setState(() => _uploading = true);
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/gpm/upload_report'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'report_type': 'sales', 'filename': file.name, 'file_b64': base64Encode(bytes)}),
      );
      final b = jsonDecode(res.body);
      if (res.statusCode == 200 && b['success'] == true) {
        _snack(b['message'].toString(), Colors.green);
        if (_r != null) _run();
      } else {
        _snack(b['message']?.toString() ?? 'Upload failed', Colors.red);
      }
    } catch (e) {
      _snack('Upload failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _snack(String t, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: c));
  }

  Future<void> _loadClients() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/fill_rate/clients'));
      if (res.statusCode != 200) return;
      final b = jsonDecode(res.body) as Map;
      if (!mounted) return;
      setState(() => _clients = ((b['clients'] as List?) ?? []).map((e) => e.toString()).toList());
    } catch (_) {}
  }

  Future<void> _pick(bool start) async {
    final now = DateTime.now();
    final p = await showDatePicker(
      context: context,
      initialDate: (start ? _start : _end) ?? now,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 30)),
      helpText: start ? 'From (SO dispatch date)' : 'To (SO dispatch date)',
    );
    if (p == null) return;
    setState(() {
      if (start) {
        _start = p;
        if (_end != null && _end!.isBefore(p)) _end = p;
      } else {
        _end = p;
        if (_start == null || _start!.isAfter(p)) _start = p;
      }
    });
  }

  Future<void> _run() async {
    if (_start == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse('$baseUrl/fill_rate').replace(queryParameters: _query));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}: ${res.body}');
      final b = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      if (!mounted) return;
      setState(() {
        _r = b;
        _open.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    if (_start == null) return;
    setState(() => _exporting = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/fill_rate/export').replace(queryParameters: _query));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      String name = '${_si ? 'SI' : 'DISPATCH'}_FILL_RATE_${_iso(_start!)}_to_${_iso(_end ?? _start!)}.xlsx';
      final cd = res.headers['content-disposition'];
      final m = cd == null ? null : RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
      if (m != null) name = m.group(1)!;
      if (!mounted) return;
      await saveOrShareFile(context, bytes: res.bodyBytes, fileName: name);
    } catch (e) {
      _snack('Download failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  List<Map<String, dynamic>> _list(String key) =>
      ((_r?[key] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  // ---------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_si ? 'SI Fill Rate' : 'Dispatch Fill Rate'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SegmentedButton<String>(
              style: SegmentedButton.styleFrom(backgroundColor: Colors.white),
              segments: const [
                ButtonSegment(value: 'dispatch', label: Text('Dispatch Fill Rate'), icon: Icon(Icons.local_shipping_outlined)),
                ButtonSegment(value: 'invoice', label: Text('SI Fill Rate'), icon: Icon(Icons.receipt_long_outlined)),
              ],
              selected: {_source},
              onSelectionChanged: (s) => _setSource(s.first),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Download Excel',
            icon: _exporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download),
            onPressed: (_r == null || _exporting) ? null : _download,
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
        _filters(),
        if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (_r != null) ..._results(),
      ]),
    );
  }

  Widget _filters() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_si ? 'SOs by control date (dispatch date)' : 'SOs by dispatch date', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_si) ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
                icon: _uploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file),
                label: const Text('Upload Sales Report (.xlsx)'),
                onPressed: _uploading ? null : _uploadSalesReport,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text('The same Sales Report as in GPM - upload it once (here or in GPM) for the dates you check.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              ),
            ],
            Wrap(spacing: 10, runSpacing: 10, children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(_start == null ? 'From' : 'From ${_show(_start!)}'),
                onPressed: () => _pick(true),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(_end == null ? 'To' : 'To ${_show(_end!)}'),
                onPressed: () => _pick(false),
              ),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: _client,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Client', prefixIcon: Icon(Icons.storefront_outlined), isDense: true),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('All clients')),
                for (final c in _clients) DropdownMenuItem<String?>(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _client = v),
            ),
            const SizedBox(height: 10),
            Row(children: [
              const Text('Count as full within', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(spacing: 6, children: [
                  for (final t in const [0.0, 2.0, 5.0])
                    ChoiceChip(
                      label: Text(t == 0 ? 'exact' : '${t.toStringAsFixed(0)} %'),
                      selected: _tolerance == t,
                      onSelected: (_) => setState(() => _tolerance = t),
                    ),
                ]),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(_si ? 'Leave out SOs with no invoice' : 'Leave out SOs with no sales entry'),
              subtitle: Text(_si ? 'Cancelled orders, or not billed yet' : 'Cancelled orders, or sales not entered yet',
                  style: const TextStyle(fontSize: 11)),
              value: _excludeUnsent,
              onChanged: (v) => setState(() => _excludeUnsent = v),
            ),
            ElevatedButton.icon(
              icon: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.analytics_outlined),
              label: const Text('Calculate fill rate'),
              onPressed: _loading || _start == null ? null : _run,
            ),
            const SizedBox(height: 6),
            Text(
              _si
                  ? 'SO quantity is matched with the Sales Report lines of the invoices raised against that SO (invoice Order No), '
                      'item by item: kg with kg, pieces / units with pieces (packs with a weight in the name, e.g. 500 gm, also count as kg). '
                      'Fill % = invoiced / ordered (max 100 %). Products are matched to items with the GPM product matches, else by name.'
                  : 'SO quantity is matched with the sales entries made against that SO number, item by item: kg with kg, '
                      'pieces with pieces. Fill % = sent / ordered (max 100 %; extra sent is shown separately). '
                      'Overall fill % = average of the order lines, so kg and pieces can be combined.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ]),
        ),
      );

  List<Widget> _results() {
    final r = _r!;
    final o = Map<String, dynamic>.from(r['overall'] as Map);
    final kg = Map<String, dynamic>.from(o['kg'] as Map);
    final pcs = Map<String, dynamic>.from(o['pcs'] as Map);
    final flags = _list('flags');
    final mismatches = flags.where((f) => f['code'] == 'unit_mismatch').toList();
    return [
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${_client ?? 'All clients'} · ${_showIso(r['start'])}${r['start'] == r['end'] ? '' : ' to ${_showIso(r['end'])}'}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _tile('Overall fill', o['avg_fill_percent'], 'avg of ${o['lines']} lines'),
              _tile('Lines full', o['line_fill_percent'], '${o['full_lines']} of ${o['lines']}'),
              _tile('Kg fill', kg['fill_percent'], '${_n(kg['filled'])} of ${_n(kg['ordered'])} kg'),
              _tile('Pcs fill', pcs['fill_percent'], '${_n(pcs['filled'])} of ${_n(pcs['ordered'])} pcs'),
            ]),
            const SizedBox(height: 10),
            Text(
              'SOs: ${o['orders']} · fully filled ${o['full_orders']}   ·   Lines short ${o['short_lines']} · not $_sentWord ${o['not_sent_lines']}\n'
              'Kg: short ${_n(kg['short'])} · extra ${_n(kg['excess'])}   ·   Pcs: short ${_n(pcs['short'])} · extra ${_n(pcs['excess'])}',
              style: const TextStyle(fontSize: 12),
            ),
          ]),
        ),
      ),
      for (final f in flags.where((f) => f['code'] != 'unit_mismatch'))
        Card(
          color: Colors.orange.shade50,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.info_outline, color: Colors.orange),
            title: Text(f['message'].toString(), style: const TextStyle(fontSize: 12)),
            onTap: f['code'] == 'unsent_sos'
                ? _showUnsent
                : (f['code'] == 'not_in_so'
                    ? _showNotInSo
                    : (f['code'] == 'unmatched_products' ? () => _showProducts(f['products'] as List?) : null)),
            trailing: (f['code'] == 'unsent_sos' || f['code'] == 'not_in_so' || f['code'] == 'unmatched_products')
                ? const Icon(Icons.chevron_right)
                : null,
          ),
        ),
      if (mismatches.isNotEmpty)
        Card(
          color: Colors.orange.shade50,
          child: ExpansionTile(
            leading: const Icon(Icons.scale, color: Colors.orange),
            title: Text('${mismatches.length} line(s) ordered in one unit but $_sentWord in the other',
                style: const TextStyle(fontSize: 12)),
            subtitle: const Text('Enter the average weight per piece (Item Settings) to compare them', style: TextStyle(fontSize: 11)),
            children: [
              for (final m in mismatches)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(m['message'].toString(), style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'dates', label: Text('Dates'), icon: Icon(Icons.event_outlined)),
            ButtonSegment(value: 'clients', label: Text('Clients'), icon: Icon(Icons.storefront_outlined)),
            ButtonSegment(value: 'items', label: Text('Items'), icon: Icon(Icons.eco_outlined)),
            ButtonSegment(value: 'client_items', label: Text('Client × Item')),
            ButtonSegment(value: 'lines', label: Text('SO lines'), icon: Icon(Icons.list_alt)),
          ],
          selected: {_view},
          onSelectionChanged: (s) => setState(() {
            _view = s.first;
            _open.clear();
          }),
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search client, item or SO', isDense: true),
        onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
      ),
      if (_view == 'lines')
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Only lines not fully filled'),
          value: _onlyShort,
          onChanged: (v) => setState(() => _onlyShort = v),
        ),
      const SizedBox(height: 6),
      ..._viewWidgets(),
    ];
  }

  Widget _tile(String label, dynamic pct, String sub) => Container(
        width: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _pc(pct).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _pc(pct).withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          Text(_p(pct), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _pc(pct))),
          Text(sub, style: const TextStyle(fontSize: 10)),
        ]),
      );

  bool _hit(Map<String, dynamic> g) {
    if (_search.isEmpty) return true;
    return '${g['client'] ?? ''} ${g['item'] ?? ''} ${g['so_number'] ?? ''}'.toLowerCase().contains(_search);
  }

  List<Widget> _viewWidgets() {
    if (_view == 'lines') return [_linesTable()];
    final key = _view;
    final rows = _list(key).where(_hit).toList();
    if (rows.isEmpty) return [const Padding(padding: EdgeInsets.all(16), child: Text('Nothing to show.'))];
    return [for (final g in rows) _groupCard(g)];
  }

  String _gName(Map<String, dynamic> g) {
    if (_view == 'client_items') return '${g['client']} · ${g['item']}';
    if (_view == 'dates') return 'Control date ${_showIso(g['date'])}';
    return (g['client'] ?? g['item']).toString();
  }

  Widget _groupCard(Map<String, dynamic> g) {
    final kg = Map<String, dynamic>.from(g['kg'] as Map);
    final pcs = Map<String, dynamic>.from(g['pcs'] as Map);
    final name = _gName(g);
    final parts = <String>[
      if ((kg['lines'] as num) > 0) 'kg ${_p(kg['fill_percent'])} (${_n(kg['filled'])}/${_n(kg['ordered'])}, short ${_n(kg['short'])})',
      if ((pcs['lines'] as num) > 0) 'pcs ${_p(pcs['fill_percent'])} (${_n(pcs['filled'])}/${_n(pcs['ordered'])}, short ${_n(pcs['short'])})',
    ];
    final canOpen = _view == 'clients' || _view == 'items';
    final open = _open.contains(name);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: [
        ListTile(
          dense: true,
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            '${parts.join('\n')}\nLines full ${g['full_lines']}/${g['lines']} · SOs full ${g['full_orders']}/${g['orders']}',
            style: const TextStyle(fontSize: 11),
          ),
          isThreeLine: true,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_p(g['avg_fill_percent']),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _pc(g['avg_fill_percent']))),
            if (canOpen) Icon(open ? Icons.expand_less : Icons.expand_more),
          ]),
          onTap: canOpen ? () => setState(() => open ? _open.remove(name) : _open.add(name)) : null,
        ),
        if (canOpen && open) _breakdown(g),
      ]),
    );
  }

  /// Client -> its items, item -> its clients.
  Widget _breakdown(Map<String, dynamic> g) {
    final byClient = _view == 'clients';
    final sub = _list('client_items')
        .where((x) => byClient ? x['client'] == g['client'] : x['item'] == g['item'])
        .toList()
      ..sort((a, b) => ((a['avg_fill_percent'] as num?) ?? 0).compareTo((b['avg_fill_percent'] as num?) ?? 0));
    const h = TextStyle(fontWeight: FontWeight.bold, fontSize: 11);
    const c = TextStyle(fontSize: 11);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: DataTable(
        columnSpacing: 14,
        headingRowHeight: 30,
        dataRowMinHeight: 28,
        dataRowMaxHeight: 32,
        headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50),
        columns: [
          DataColumn(label: Text(byClient ? 'Item' : 'Client', style: h)),
          const DataColumn(label: Text('Fill %', style: h), numeric: true),
          DataColumn(label: Text('Kg ord / $_sentWord', style: h)),
          const DataColumn(label: Text('Kg short', style: h), numeric: true),
          DataColumn(label: Text('Pcs ord / $_sentWord', style: h)),
          const DataColumn(label: Text('Pcs short', style: h), numeric: true),
          const DataColumn(label: Text('Lines full', style: h)),
        ],
        rows: [
          for (final x in sub)
            DataRow(cells: [
              DataCell(Text((byClient ? x['item'] : x['client']).toString(), style: c)),
              DataCell(Text(_p(x['avg_fill_percent']), style: c.copyWith(color: _pc(x['avg_fill_percent']), fontWeight: FontWeight.w700))),
              DataCell(Text((x['kg']['lines'] as num) > 0 ? '${_n(x['kg']['ordered'])} / ${_n(x['kg']['dispatched'])}' : '-', style: c)),
              DataCell(Text((x['kg']['lines'] as num) > 0 ? _n(x['kg']['short']) : '-', style: c)),
              DataCell(Text((x['pcs']['lines'] as num) > 0 ? '${_n(x['pcs']['ordered'])} / ${_n(x['pcs']['dispatched'])}' : '-', style: c)),
              DataCell(Text((x['pcs']['lines'] as num) > 0 ? _n(x['pcs']['short']) : '-', style: c)),
              DataCell(Text('${x['full_lines']}/${x['lines']}', style: c)),
            ]),
        ],
      ),
    );
  }

  Widget _linesTable() {
    final rows = _list('lines').where((l) => (!_onlyShort || l['status'] != 'full') && _hit(l)).toList();
    if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Nothing to show.'));
    const h = TextStyle(fontWeight: FontWeight.bold, fontSize: 11);
    const c = TextStyle(fontSize: 11);
    final shown = rows.take(800).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (rows.length > shown.length)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Showing ${shown.length} of ${rows.length} lines - download the Excel for all of them.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 14,
          headingRowHeight: 32,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 40,
          headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50),
          columns: [
            const DataColumn(label: Text('Date', style: h)),
            const DataColumn(label: Text('SO', style: h)),
            const DataColumn(label: Text('Client', style: h)),
            const DataColumn(label: Text('Item', style: h)),
            const DataColumn(label: Text('Unit', style: h)),
            const DataColumn(label: Text('Ordered', style: h), numeric: true),
            DataColumn(label: Text(_si ? 'Invoiced' : 'Sent', style: h), numeric: true),
            const DataColumn(label: Text('Short', style: h), numeric: true),
            const DataColumn(label: Text('Extra', style: h), numeric: true),
            const DataColumn(label: Text('Fill %', style: h), numeric: true),
            const DataColumn(label: Text('Status', style: h)),
            const DataColumn(label: Text('Note', style: h)),
          ],
          rows: [
            for (final l in shown)
              DataRow(cells: [
                DataCell(Text(_showIso(l['date']), style: c)),
                DataCell(Text(l['so_number'].toString(), style: c)),
                DataCell(Text(l['client'].toString(), style: c)),
                DataCell(Text(l['item'].toString(), style: c)),
                DataCell(Text(l['unit'].toString(), style: c)),
                DataCell(Text(_n(l['ordered']), style: c)),
                DataCell(Text(_n(l['dispatched']), style: c)),
                DataCell(Text(_n(l['short']), style: c.copyWith(color: (l['short'] as num) > 0 ? Colors.red.shade700 : null))),
                DataCell(Text(_n(l['excess']), style: c)),
                DataCell(Text(_p(l['fill_percent']), style: c.copyWith(color: _pc(l['fill_percent']), fontWeight: FontWeight.w700))),
                DataCell(Text(_si ? l['status'].toString().replaceAll('not sent', 'not invoiced') : l['status'].toString(), style: c)),
                DataCell(SizedBox(width: 220, child: Text('${l['note'] ?? ''}', style: const TextStyle(fontSize: 10)))),
              ]),
          ],
        ),
      ),
    ]);
  }

  Future<void> _showUnsent() async {
    final rows = _list('unsent_orders');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_si ? 'SOs with no invoice' : 'SOs with no sales entry'),
        content: SizedBox(
          width: 420,
          child: ListView(shrinkWrap: true, children: [
            for (final x in rows)
              ListTile(
                dense: true,
                title: Text('SO ${x['so_number']} · ${x['client']}'),
                subtitle: Text('${_showIso(x['date'])} · ${x['lines']} item(s)'),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE'))],
      ),
    );
  }

  Future<void> _showProducts(List? products) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sales Report products not matched'),
        content: SizedBox(
          width: 420,
          child: ListView(shrinkWrap: true, children: [
            const Text('Match them to items in Admin > GPM (product matching), then calculate again.', style: TextStyle(fontSize: 12)),
            for (final p in products ?? const []) ListTile(dense: true, title: Text('$p', style: const TextStyle(fontSize: 12))),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE'))],
      ),
    );
  }

  Future<void> _showNotInSo() async {
    final rows = _list('not_in_so');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_si ? 'Invoiced but not on the SO' : 'Sent but not on the SO'),
        content: SizedBox(
          width: 420,
          child: ListView(shrinkWrap: true, children: [
            for (final x in rows)
              ListTile(
                dense: true,
                title: Text('${x['item']} · SO ${x['so_number']}'),
                subtitle: Text('${x['client']} · ${_showIso(x['date'])} · '
                    '${(x['kg'] as num) > 0 ? '${_n(x['kg'])} kg ' : ''}${(x['pcs'] as num) > 0 ? '${_n(x['pcs'])} pcs' : ''}'),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE'))],
      ),
    );
  }
}
