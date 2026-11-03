import 'dart:convert';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';
import '../utils/file_saver.dart';
import '../utils/report_upload.dart';
import 'client_weights_page.dart';

/// Admin › Item Profit (Sales Report)
/// Per item and control date: quantity sold and sales value from the Sales Report,
/// cost = quantity sold × weighted average purchase rate, profit kept = sales − cost.
class ItemProfitPage extends StatefulWidget {
  const ItemProfitPage({super.key});

  @override
  State<ItemProfitPage> createState() => _ItemProfitPageState();
}

class _ItemProfitPageState extends State<ItemProfitPage> {
  DateTime? _start;
  DateTime? _end;
  String _basis = 'day'; // day | period
  bool _loading = false;
  bool _exporting = false;
  bool _uploading = false;
  String? _error;
  Map<String, dynamic>? _r;
  String _search = '';
  String _sort = 'profit'; // profit | margin | sales
  final Set<String> _open = {};
  final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    _start = _end!.subtract(const Duration(days: 6));
  }

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _show(DateTime d) => DateFormat('dd-MM-yyyy').format(d);
  String _m(dynamic v) => v == null ? '-' : _money.format(v is num ? v : (double.tryParse('$v') ?? 0));
  String _n(dynamic v) {
    final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    if (d == null) return '-';
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  }

  String _dd(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? '${iso ?? ''}' : DateFormat('dd-MM-yy').format(d);
  }

  Map<String, String> get _q => {'start': _iso(_start!), 'end': _iso(_end!), 'rate_basis': _basis};

  void _snack(String t, Color c) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: c));
  }

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
      // client-wise weight per piece / unit: always shown first, saved values can be changed
      final go = await ClientWeightsPage.confirm(context, _iso(_start!), _iso(_end!));
      if (!go) return;
      final res = await http.get(Uri.parse('$baseUrl/item_profit').replace(queryParameters: _q));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode} - is the new server file installed?');
      final b = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      if (!mounted) return;
      setState(() {
        _r = b;
        _open.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    setState(() => _exporting = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/item_profit/export').replace(queryParameters: _q));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      if (!mounted) return;
      await saveOrShareFile(context, bytes: res.bodyBytes, fileName: 'ITEM_PROFIT_${_iso(_start!)}_to_${_iso(_end!)}.xlsx');
    } catch (e) {
      _snack('Download failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx'], withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    if (!file.name.toLowerCase().endsWith('.xlsx')) {
      _snack('Please choose an .xlsx file (save the report as Excel Workbook .xlsx)', Colors.red);
      return;
    }
    List<int>? bytes = file.bytes;
    if (bytes == null && !kIsWeb && file.path != null) bytes = await io.File(file.path!).readAsBytes();
    if (bytes == null) {
      _snack('Could not read the file', Colors.red);
      return;
    }
    setState(() => _uploading = true);
    try {
      // sent in small pieces: a big report is not refused by a network / proxy limit
      final Map b = await uploadReport(reportType: 'sales', fileName: file.name, bytes: bytes);
      if (b['success'] == true) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Profit (Sales Report)'),
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
              const Text('Control dates', style: TextStyle(fontWeight: FontWeight.w700)),
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
              const Text('Purchase rate used', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'day', label: Text("Each day's purchases")),
                  ButtonSegment(value: 'period', label: Text('Period average')),
                ],
                selected: {_basis},
                onSelectionChanged: (s) => setState(() => _basis = s.first),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(minimumSize: const Size(64, 46)),
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.calculate_outlined),
                label: const Text('Calculate profit'),
                onPressed: _loading ? null : _run,
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                icon: _uploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file),
                label: const Text('Upload Sales Report (.xlsx)'),
                onPressed: _uploading ? null : _upload,
              ),
              const SizedBox(height: 6),
              Text(
                'Quantity sold and sales value per item from the Sales Report (control date). Cost = quantity sold × '
                'weighted average purchase rate (accepted amount ÷ accepted qty of the purchase entries). '
                '"Each day\'s purchases": that control date\'s purchases, else the period average. '
                'Profit kept = sales value − cost.',
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
    final t = Map<String, dynamic>.from(_r!['totals'] as Map);
    final flags = ((_r!['flags'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final items = ((_r!['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).where((i) {
      return _search.isEmpty || '${i['item']}'.toLowerCase().contains(_search);
    }).toList();
    num key(Map i) => _sort == 'margin'
        ? ((i['margin_percent'] as num?) ?? -9999)
        : (_sort == 'sales' ? ((i['sales_value'] as num?) ?? 0) : ((i['profit'] as num?) ?? -1e12));
    items.sort((a, b) => key(b).compareTo(key(a)));
    final profit = (t['profit'] as num?) ?? 0;
    return [
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 16, runSpacing: 10, children: [
            _kv('Sales value', _m(t['sales_value'])),
            _kv('Cost (qty × avg rate)', _m(t['cost'])),
            _kv('Profit kept', _m(t['profit']), color: profit < 0 ? Colors.red.shade700 : Colors.green.shade800),
            _kv('Margin', t['margin_percent'] == null ? '-' : '${t['margin_percent']} %'),
            if (((t['uncosted_sales_value'] as num?) ?? 0) != 0) _kv('Sales not costed', _m(t['uncosted_sales_value'])),
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
            onTap: f['code'] == 'unmatched_products' ? () => _showList('Products not matched', f['products'] as List?) : null,
          ),
        ),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search item', isDense: true),
            onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: _sort,
          items: const [
            DropdownMenuItem(value: 'profit', child: Text('Profit')),
            DropdownMenuItem(value: 'margin', child: Text('Margin %')),
            DropdownMenuItem(value: 'sales', child: Text('Sales')),
          ],
          onChanged: (v) => setState(() => _sort = v ?? 'profit'),
        ),
      ]),
      const SizedBox(height: 6),
      if (items.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing to show - upload the Sales Report for these dates.')),
      for (final i in items) _itemCard(i),
    ];
  }

  Widget _kv(String k, String v, {Color? color}) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(k, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        Text(v, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
      ]);

  Widget _itemCard(Map<String, dynamic> i) {
    final name = '${i['item']}';
    final open = _open.contains(name);
    final p = i['profit'] as num?;
    final u = '${i['unit']}';
    final days = ((i['days'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    const h = TextStyle(fontWeight: FontWeight.bold, fontSize: 11);
    const c = TextStyle(fontSize: 11);
    return Card(
      key: ValueKey('ip-$name'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          dense: true,
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            'Sold ${_n(i['qty_sold'])} $u · sales ${_m(i['sales_value'])} · cost ${_m(i['cost'])}\n'
            'Avg sale ₹${_n(i['avg_sale_rate'])}/$u · avg purchase ₹${_n(i['avg_purchase_rate'])}/$u'
            '${(i['notes'] as List?)?.isNotEmpty == true ? '\n${(i['notes'] as List).join('\n')}' : ''}',
            style: const TextStyle(fontSize: 11),
          ),
          isThreeLine: true,
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_m(p), style: TextStyle(fontWeight: FontWeight.w800, color: p == null ? Colors.grey : (p < 0 ? Colors.red.shade700 : Colors.green.shade800))),
            Text(i['margin_percent'] == null ? '' : '${i['margin_percent']} %', style: const TextStyle(fontSize: 11)),
          ]),
          onTap: () => setState(() => open ? _open.remove(name) : _open.add(name)),
        ),
        if (open)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: DataTable(
              columnSpacing: 14,
              headingRowHeight: 30,
              dataRowMinHeight: 28,
              dataRowMaxHeight: 32,
              headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50),
              columns: [
                const DataColumn(label: Text('Date', style: h)),
                DataColumn(label: Text('Qty ($u)', style: h), numeric: true),
                const DataColumn(label: Text('Sales', style: h), numeric: true),
                const DataColumn(label: Text('Sale rate', style: h), numeric: true),
                const DataColumn(label: Text('Purchase rate', style: h), numeric: true),
                const DataColumn(label: Text('Rate from', style: h)),
                const DataColumn(label: Text('Cost', style: h), numeric: true),
                const DataColumn(label: Text('Profit', style: h), numeric: true),
                const DataColumn(label: Text('Margin', style: h), numeric: true),
              ],
              rows: [
                for (final d in days)
                  DataRow(cells: [
                    DataCell(Text(_dd(d['date']), style: c)),
                    DataCell(Text(_n(d['qty']), style: c)),
                    DataCell(Text(_m(d['sales_value']), style: c)),
                    DataCell(Text(_n(d['rate_per_unit_sold']), style: c)),
                    DataCell(Text(_n(d['wap']), style: c)),
                    DataCell(Text('${d['wap_basis'] ?? '-'}', style: c)),
                    DataCell(Text(_m(d['cost']), style: c)),
                    DataCell(Text(_m(d['profit']),
                        style: c.copyWith(fontWeight: FontWeight.w700, color: ((d['profit'] as num?) ?? 0) < 0 ? Colors.red.shade700 : null))),
                    DataCell(Text(d['margin_percent'] == null ? '-' : '${d['margin_percent']}%', style: c)),
                  ]),
              ],
            ),
          ),
      ]),
    );
  }

  Future<void> _showList(String title, List? rows) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: ListView(shrinkWrap: true, children: [
            const Text('Match them to items in Admin > GPM (product matching), then calculate again.', style: TextStyle(fontSize: 12)),
            for (final r in rows ?? const []) ListTile(dense: true, title: Text('$r', style: const TextStyle(fontSize: 12))),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE'))],
      ),
    );
  }
}
