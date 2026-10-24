import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';
import '../utils/file_saver.dart';

/// Admin › Vendor Purchases
///
/// Purchase + packaging entries vendor-wise for a range of CTRL dates, with the
/// amount calculated from the entries the same way GPM does it:
/// accepted (in the PO unit) x PO rate + low grade + under/overweight + extra
/// expense; when no accepted quantity is entered, received x PO rate (worst case).
class VendorPurchasesPage extends StatefulWidget {
  const VendorPurchasesPage({super.key});

  @override
  State<VendorPurchasesPage> createState() => _VendorPurchasesPageState();
}

class _VendorPurchasesPageState extends State<VendorPurchasesPage> {
  late DateTime _start;
  late DateTime _end;
  bool _loading = false;
  bool _exporting = false;
  String? _error;
  Map<String, dynamic>? _r;
  String _search = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = DateTime(now.year, now.month, now.day);
    _start = _end.subtract(const Duration(days: 6));
    _load();
  }

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _show(DateTime d) => DateFormat('dd-MM-yyyy').format(d);
  final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  String _m(dynamic v) => _money.format((v as num?) ?? 0);

  Future<void> _pick(bool start) async {
    final p = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      helpText: start ? 'From CTRL date' : 'To CTRL date',
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
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse('$baseUrl/purchases/vendor_summary')
          .replace(queryParameters: {'start': _iso(_start), 'end': _iso(_end)}));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode} - is the new server file installed?');
      final b = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      if (!mounted) return;
      setState(() => _r = b);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download({String? vendor}) async {
    setState(() => _exporting = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/purchases/vendor_export').replace(queryParameters: {
        'start': _iso(_start),
        'end': _iso(_end),
        if (vendor != null) 'vendor': vendor,
      }));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      String name = 'PURCHASES_${_iso(_start)}_to_${_iso(_end)}.xlsx';
      final cd = res.headers['content-disposition'];
      final mm = cd == null ? null : RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
      if (mm != null) name = mm.group(1)!;
      if (!mounted) return;
      await saveOrShareFile(context, bytes: res.bodyBytes, fileName: name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendors = ((_r?['vendors'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((v) => _search.isEmpty || '${v['vendor']} ${(v['spellings'] as List?)?.join(' ')}'.toLowerCase().contains(_search))
        .toList();
    final t = Map<String, dynamic>.from((_r?['totals'] as Map?) ?? {});
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendor Purchases'),
        actions: [
          IconButton(
            tooltip: 'Download Excel (all vendors)',
            icon: _exporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download),
            onPressed: _exporting ? null : () => _download(),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
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
        ]),
        const SizedBox(height: 6),
        Text(
          'Amount = accepted x PO rate + low grade + under/overweight + extra expense. When the accepted quantity '
          'is not entered, received x PO rate is used (worst case).',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        if (_r != null && !_loading) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('All vendors: ${_m(t['amount'])}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text('${t['entries']} entries · worst case ${_m(t['worst_case_amount'])} · '
                    'in entries ${_m(t['entry_amount'])} · paid ${_m(t['paid'])}',
                    style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search vendor', isDense: true),
            onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 6),
          if (vendors.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No purchase entries in these dates.')),
          for (final v in vendors)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                title: Text(v['vendor'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${v['entries']} entries · ${v['po_count']} POs · ${v['item_count']} items'
                  '${((v['worst_case_entries'] as num?) ?? 0) > 0 ? ' · ${v['worst_case_entries']} worst case' : ''}'
                  '${((v['entries_with_issues'] as num?) ?? 0) > 0 ? ' · ${v['entries_with_issues']} with issues' : ''}'
                  '${((v['spellings'] as List?)?.length ?? 0) > 1 ? '\nAlso written: ${(v['spellings'] as List).skip(1).join(', ')}' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Text(_m(v['amount']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _VendorEntriesPage(vendor: v['vendor'].toString(), start: _iso(_start), end: _iso(_end)),
                  ),
                ),
              ),
            ),
        ],
      ]),
    );
  }
}

class _VendorEntriesPage extends StatefulWidget {
  final String vendor;
  final String start;
  final String end;
  const _VendorEntriesPage({required this.vendor, required this.start, required this.end});

  @override
  State<_VendorEntriesPage> createState() => _VendorEntriesPageState();
}

class _VendorEntriesPageState extends State<_VendorEntriesPage> {
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  Map<String, dynamic>? _r;
  final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  String _m(dynamic v) => _money.format((v as num?) ?? 0);

  String _n(dynamic v) {
    final d = (v as num?)?.toDouble();
    if (d == null) return '';
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/purchases/vendor_entries')
          .replace(queryParameters: {'start': widget.start, 'end': widget.end, 'vendor': widget.vendor}));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      final b = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      if (!mounted) return;
      setState(() => _r = b);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    setState(() => _exporting = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/purchases/vendor_export')
          .replace(queryParameters: {'start': widget.start, 'end': widget.end, 'vendor': widget.vendor}));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      String name = 'PURCHASES_${widget.vendor}.xlsx';
      final cd = res.headers['content-disposition'];
      final mm = cd == null ? null : RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
      if (mm != null) name = mm.group(1)!;
      if (!mounted) return;
      await saveOrShareFile(context, bytes: res.bodyBytes, fileName: name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = Map<String, dynamic>.from((_r?['vendor'] as Map?) ?? {});
    final rows = ((_r?['entries'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    const h = TextStyle(fontWeight: FontWeight.bold, fontSize: 11);
    const c = TextStyle(fontSize: 11);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.vendor),
        actions: [
          IconButton(
            tooltip: 'Download Excel',
            icon: _exporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download),
            onPressed: _exporting ? null : _download,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  Text('${widget.start} to ${widget.end}', style: TextStyle(color: Colors.grey.shade700)),
                  const SizedBox(height: 4),
                  Text('Total ${_m(v['amount'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text(
                    '${v['entries'] ?? 0} entries · worst case ${_m(v['worst_case_amount'])} · '
                    'amount saved in the entries ${_m(v['entry_amount'])} · paid ${_m(v['paid'])}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 12,
                      headingRowHeight: 32,
                      dataRowMinHeight: 28,
                      dataRowMaxHeight: 44,
                      headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50),
                      columns: const [
                        DataColumn(label: Text('CTRL date', style: h)),
                        DataColumn(label: Text('PO', style: h)),
                        DataColumn(label: Text('Item', style: h)),
                        DataColumn(label: Text('Received', style: h)),
                        DataColumn(label: Text('Accepted', style: h)),
                        DataColumn(label: Text('PO rate', style: h), numeric: true),
                        DataColumn(label: Text('Qty x rate', style: h)),
                        DataColumn(label: Text('Amount', style: h), numeric: true),
                        DataColumn(label: Text('Basis', style: h)),
                        DataColumn(label: Text('Note', style: h)),
                      ],
                      rows: [
                        for (final e in rows)
                          DataRow(
                            color: WidgetStateProperty.all(
                                (e['issue_text'] as List?)?.isNotEmpty == true ? Colors.orange.shade50 : null),
                            cells: [
                              DataCell(Text('${e['ctrl_date'] ?? ''}', style: c)),
                              DataCell(Text('${e['po_number'] ?? ''}', style: c)),
                              DataCell(Text('${e['item'] ?? ''}${e['source'] == 'packaging' ? ' (packaging)' : ''}', style: c)),
                              DataCell(Text('${_n(e['qty_received'])} ${e['unit_received'] ?? ''}'
                                  '${e['pcs_received'] != null ? ' / ${_n(e['pcs_received'])} pcs' : ''}', style: c)),
                              DataCell(Text(e['qty_accepted'] == null
                                  ? '-'
                                  : '${_n(e['qty_accepted'])} ${e['unit_accepted'] ?? ''}'
                                      '${e['pcs_accepted'] != null ? ' / ${_n(e['pcs_accepted'])} pcs' : ''}', style: c)),
                              DataCell(Text('${_n(e['po_rate'])} / ${e['po_unit'] ?? ''}', style: c)),
                              DataCell(Text('${_n(e['qty_costed'])} x ${_n(e['po_rate'])}', style: c)),
                              DataCell(Text(_m(e['amount']), style: c.copyWith(fontWeight: FontWeight.w700))),
                              DataCell(Text(e['basis'] == 'worst_case' ? 'worst case' : 'accepted',
                                  style: c.copyWith(color: e['basis'] == 'worst_case' ? Colors.orange.shade900 : null))),
                              DataCell(SizedBox(
                                width: 200,
                                child: Text(((e['issue_text'] as List?) ?? []).join('; '), style: const TextStyle(fontSize: 10)),
                              )),
                            ],
                          ),
                      ],
                    ),
                  ),
                ]),
    );
  }
}
