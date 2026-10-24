import 'dart:convert';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';
import '../utils/file_saver.dart';
import 'gpm_questions_page.dart';
import 'gpm_saved_values_page.dart';

/// Admin › GPM Analysis
///
/// Tab 1  Analysis         – pick CTRL dates, see overall + item-wise GPM and flags, download Excel
/// Tab 2  Upload Reports   – upload the Sales Report and Purchase Report (.xlsx)
/// Tab 3  Product Matching – match Sales Report product IDs to app items (saved)
class GpmAnalysisPage extends StatefulWidget {
  const GpmAnalysisPage({super.key});

  @override
  State<GpmAnalysisPage> createState() => _GpmAnalysisPageState();
}

final NumberFormat _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final NumberFormat _qtyFmt = NumberFormat('#,##0.##', 'en_IN');
String _money(dynamic v) => v == null ? '-' : _inr.format((v as num).toDouble());
String _qty(dynamic v) => v == null ? '-' : _qtyFmt.format((v as num).toDouble());
String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String _show(DateTime d) => DateFormat('dd MMM yyyy').format(d);

String _errorText(http.Response res) {
  try {
    final b = jsonDecode(res.body);
    return (b['message'] ?? b['error'] ?? res.body).toString();
  } catch (_) {
    return 'Server error ${res.statusCode}';
  }
}

class _GpmAnalysisPageState extends State<GpmAnalysisPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final GlobalKey<_ProductsTabState> _productsKey = GlobalKey<_ProductsTabState>();

  DateTime? _start;
  DateTime? _end;
  bool _inclPackaging = true;
  bool _inclLogistics = true;
  bool _calculating = false;
  bool _exporting = false;
  String _purchaseSource = 'app'; // 'app' (inventory entries) or 'report' (Purchase Report)
  String _mode = 'standard'; // 'standard' (item-wise + overall) or 'overall' (all sales & purchases from reports)
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String get _variant {
    if (_inclPackaging && _inclLogistics) return 'including_packaging_and_lmd_fmd';
    if (_inclPackaging) return 'including_packaging';
    if (_inclLogistics) return 'including_lmd_fmd';
    return 'excluding_packaging_and_lmd_fmd';
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _start : _end) ?? _start ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      helpText: isStart ? 'Start CTRL date' : 'End CTRL date',
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end == null || _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
        if (_start == null || _start!.isAfter(picked)) _start = picked;
      }
      _result = null;
    });
  }

  Map<String, String> get _query => {'start': _iso(_start!), 'end': _iso(_end!)};
  Map<String, String> get _queryWithSource => {..._query, 'purchase_source': _purchaseSource, 'mode': _mode};

  /// What to calculate, and which purchases to use:
  ///  * Item-wise + overall (items in stock) - purchases from the Purchase Report
  ///    or the app entries (asked only when a Purchase Report is uploaded)
  ///  * Overall from reports - every sale and purchase of the period from the
  ///    Sales / Purchase Report, LMD / FMD from the expense sheet, only the
  ///    opening / closing stock values from the app.
  Future<bool> _askMode(int reportDays, int salesDays, int expenseDays, int days) async {
    String mode = _mode;
    String source = reportDays > 0 ? _purchaseSource : 'app';
    String cover(int n) => n <= 0 ? 'not uploaded' : (n >= days ? 'uploaded' : 'uploaded for $n of $days day(s)');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('GPM calculation'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                RadioGroup<String>(
                  groupValue: mode,
                  onChanged: (v) => setD(() => mode = v ?? 'standard'),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'standard',
                      title: Text('Item-wise + overall'),
                      subtitle: Text('Items in stock in the app; LMD / FMD from the app entries', style: TextStyle(fontSize: 12)),
                    ),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'overall',
                      title: const Text('Overall - all sales & purchases (reports)'),
                      subtitle: Text(
                        'All sales from the Sales Report (${cover(salesDays)}), all purchases from the Purchase Report '
                        '(${cover(reportDays)}${reportDays <= 0 ? ' - app entries used' : ', app purchase & packaging entries not added'}), '
                        'LMD / FMD from the expense sheet (${cover(expenseDays)}${expenseDays <= 0 ? ' - app entries used' : ''}). '
                        'Only opening / closing stock values come from the app; items without stock in the app count as 0.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ]),
                ),
                if (mode == 'standard' && reportDays > 0) ...[
                  const Divider(),
                  const Text('Purchases', style: TextStyle(fontWeight: FontWeight.w700)),
                  RadioGroup<String>(
                    groupValue: source,
                    onChanged: (v) => setD(() => source = v ?? 'app'),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: 'report',
                        title: const Text('Purchase Report'),
                        subtitle: Text(
                            'Uploaded for $reportDays of $days day(s). Overall: every purchase in the report. '
                            'Item-wise: report products matched to items in stock.',
                            style: const TextStyle(fontSize: 12)),
                      ),
                      const RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: 'app',
                        title: Text('Inventory data only'),
                        subtitle: Text('App purchase + packaging entries x PO rate', style: TextStyle(fontSize: 12)),
                      ),
                    ]),
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CONTINUE')),
          ],
        ),
      ),
    );
    if (ok != true) return false;
    _mode = mode;
    _purchaseSource = mode == 'overall' ? 'report' : source;
    return true;
  }

  Future<void> _calculate() async {
    if (_start == null || _end == null) {
      _snack('Select the start and end CTRL dates', Colors.red);
      return;
    }
    setState(() {
      _calculating = true;
      _error = null;
    });
    try {
      // First ask for what is missing to value the stock (piece weights,
      // kg per box, price when the stock is older than the first purchase).
      final pre = await http.get(Uri.parse('$baseUrl/gpm/precheck').replace(queryParameters: _query));
      if (pre.statusCode == 200) {
        final preBody = jsonDecode(pre.body) as Map;
        if (!mounted) return;
        final go = await _askMode(
          (preBody['purchase_report_days'] as num?)?.toInt() ?? 0,
          (preBody['sales_report_days'] as num?)?.toInt() ?? 0,
          (preBody['expense_days'] as num?)?.toInt() ?? 0,
          (preBody['days'] as num?)?.toInt() ?? 1,
        );
        if (!go) return;
        final qs = List<Map<String, dynamic>>.from(
            (preBody['questions'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
        if (qs.isNotEmpty) {
          if (!mounted) return;
          final answer = await Navigator.push<String>(
            context,
            MaterialPageRoute(builder: (_) => GpmQuestionsPage(questions: qs, start: _query['start']!, end: _query['end']!)),
          );
          if (answer == null) return; // cancelled
        }
      }
      final res = await http.get(Uri.parse('$baseUrl/gpm/analyze').replace(queryParameters: _queryWithSource));
      if (res.statusCode != 200) throw Exception(_errorText(res));
      final data = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      if (!mounted) return;
      setState(() => _result = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
  }

  Future<void> _download() async {
    if (_start == null || _end == null) return;
    setState(() => _exporting = true);
    try {
      final res = await http.get(Uri.parse('$baseUrl/gpm/export').replace(queryParameters: _queryWithSource));
      if (res.statusCode != 200) throw Exception(_errorText(res));
      String name = 'GPM_${_iso(_start!)}_to_${_iso(_end!)}.xlsx';
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

  void _snack(String text, Color color, {int seconds = 4}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color, duration: Duration(seconds: seconds)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPM Analysis'),
        actions: [
          IconButton(
            tooltip: 'Change saved weights / rates',
            icon: const Icon(Icons.edit_note),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GpmSavedValuesPage())),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.analytics_outlined), text: 'Analysis'),
            Tab(icon: Icon(Icons.upload_file), text: 'Upload Reports'),
            Tab(icon: Icon(Icons.link), text: 'Product Matching'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildAnalysisTab(),
          _UploadsTab(onUploaded: () => _productsKey.currentState?.reload()),
          _ProductsTab(key: _productsKey),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Analysis tab
  // ------------------------------------------------------------------
  Widget _buildAnalysisTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('CTRL dates', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Start and end can be the same date.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(_start == null ? 'Start date' : 'From ${_show(_start!)}'),
                    onPressed: () => _pickDate(true),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(_end == null ? 'End date' : 'To ${_show(_end!)}'),
                    onPressed: () => _pickDate(false),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(minimumSize: const Size(64, 44)),
                    icon: _calculating
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.calculate_outlined),
                    label: const Text('Calculate GPM'),
                    onPressed: _calculating ? null : _calculate,
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
                    icon: _exporting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download),
                    label: const Text('Download Excel'),
                    onPressed: (_result == null || _exporting) ? null : _download,
                  ),
                ]),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Include packaging material'),
                  value: _inclPackaging,
                  onChanged: (v) => setState(() => _inclPackaging = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Include LMD / FMD'),
                  value: _inclLogistics,
                  onChanged: (v) => setState(() => _inclLogistics = v),
                ),
              ],
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        if (_result != null) ...[
          const SizedBox(height: 12),
          if (_result!['is_worst_case'] == true) _worstCaseBanner(),
          _summaryCard(),
          const SizedBox(height: 12),
          _flagsCard(),
          const SizedBox(height: 12),
          _paymentsCard(),
          const SizedBox(height: 12),
          _itemsCard(),
        ],
      ],
    );
  }

  Widget _worstCaseBanner() {
    final r = _result!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'WORST CASE GPM — ${r['worst_case_entries']} purchase entries have no accepted quantity, so '
            '${_money(r['worst_case_amount'])} of purchases is priced as received quantity × PO rate. '
            'Enter accepted / low-grade quantities in the purchase entries for the actual GPM.',
            style: TextStyle(color: Colors.orange.shade900),
          ),
        ),
      ]),
    );
  }

  Widget _summaryCard() {
    final o = Map<String, dynamic>.from(_result!['overall'] as Map);
    final gp = (o['gross_profit'] as Map)[_variant];
    final pct = (o['gp_percent'] as Map)[_variant];
    Widget line(String label, dynamic value, {String sign = '', bool bold = false, Color? color, String? note}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 18, child: Text(sign, style: TextStyle(color: Colors.grey.shade600))),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null)),
                if (note != null) TextSpan(text: '  $note', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ])),
            ),
            Text(_money(value),
                style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 18 : 14, color: color)),
          ]),
        );
    final gpColor = (gp as num) < 0 ? Colors.red.shade700 : Colors.green.shade800;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${_result!['mode'] == 'overall' ? 'Overall GPM - all sales & purchases' : 'Overall GPM'}  ·  '
              '${_result!['start']} to ${_result!['end']}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          line('Sales', o['sales_total'], note: '(Sales Report, ${o['sales_source']})'),
          line('Purchases', o['purchase_total'], sign: '−',
              note: o['purchase_source'] == 'report' ? '(Purchase Report)' : '(app purchase entries)'),
          line('Opening stock value', o['opening_stock_value'], sign: '−'),
          line('Closing stock value', o['closing_stock_value'], sign: '+'),
          if (_inclPackaging) line('Packaging material', o['packaging_total'], sign: '−'),
          if (_inclLogistics)
            line('LMD', o['lmd_total'], sign: '−', note: o['logistics_source'] == 'expense_sheet' ? '(expense sheet)' : '(app entries)'),
          if (_inclLogistics)
            line('FMD', o['fmd_total'], sign: '−', note: o['logistics_source'] == 'expense_sheet' ? '(expense sheet)' : '(app entries)'),
          if (_inclLogistics && ((o['lmd_fmd_not_split'] as num?) ?? 0) != 0)
            line('LMD + FMD (not split)', o['lmd_fmd_not_split'], sign: '−', note: '(expense sheet)'),
          const Divider(),
          line('Gross profit', gp, sign: '=', bold: true, color: gpColor),
          Align(
            alignment: Alignment.centerRight,
            child: Text(pct == null ? 'GP % : -' : 'GP % of sales: ${pct.toStringAsFixed(2)}%',
                style: TextStyle(color: gpColor, fontWeight: FontWeight.w600)),
          ),
          if (o['expense_check'] != null) _expenseCheck(Map<String, dynamic>.from(o['expense_check'] as Map)),
          if (o['purchase_report_total'] != null) ...[
            const SizedBox(height: 8),
            Text(
              o['purchase_source'] == 'report'
                  ? 'Purchase Report total ${_money(o['purchase_report_total'])} (packaging in it: ${_money(o['packaging_total'])}'
                      '${(o['purchase_report_unmatched'] ?? 0) != 0 ? ', not matched to items: ${_money(o['purchase_report_unmatched'])}' : ''}). '
                      'App entries: purchases ${_money(o['purchase_total_app'])}, packaging ${_money(o['packaging_total_app'])}.'
                  : 'Uploaded Purchase Report total (not used): ${_money(o['purchase_report_total'])}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ]),
      ),
    );
  }

  /// Expense sheet (paid) vs the app's LMD + FMD entries.
  Widget _expenseCheck(Map<String, dynamic> e) {
    final diff = (e['difference'] as num?)?.toDouble() ?? 0;
    final ok = diff.abs() <= 1;
    final c = ok ? Colors.green.shade800 : Colors.red.shade700;
    TableRow row(String a, dynamic b, dynamic d, {bool bold = false}) => TableRow(children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(a, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w700 : null))),
          Text(b == null ? '' : _money(b), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w700 : null)),
          Text(d == null ? '' : _money(d), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w700 : null)),
        ]);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ok ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Expense sheet vs app LMD / FMD', style: TextStyle(fontWeight: FontWeight.w700, color: c)),
        const SizedBox(height: 6),
        Table(columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1.4), 2: FlexColumnWidth(1.4)}, children: [
          row('', 'Sheet (total)', 'App', bold: true),
          row('LMD', e['sheet_lmd'], e['app_lmd']),
          row('FMD', e['sheet_fmd'], e['app_fmd']),
          if (((e['sheet_not_split'] as num?) ?? 0) != 0) row('LMD + FMD not split', e['sheet_not_split'], null),
          row('Total', e['sheet_lmd_fmd_total'], e['app_total'], bold: true),
        ]),
        const SizedBox(height: 6),
        Text(
          ok ? 'Matches' : 'Difference (sheet - app): ${_money(diff)}',
          style: TextStyle(fontWeight: FontWeight.w800, color: c),
        ),
        Text(
          'Paid: sheet ${_money(e['sheet_paid'])} · app ${_money(e['app_paid'])} · difference ${_money(e['difference_vs_app_paid'])}'
          '${((e['sheet_other'] as num?) ?? 0) != 0 ? ' · other expenses in sheet (not counted) ${_money(e['sheet_other'])}' : ''}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
      ]),
    );
  }

  Widget _flagsCard() {
    final flags = List<Map<String, dynamic>>.from((_result!['flags'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final errors = flags.where((f) => f['severity'] == 'error').length;
    final hasUnmatched = flags.any((f) => f['code'] == 'product_not_matched');
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          leading: Icon(Icons.flag_outlined, color: errors > 0 ? Colors.red : Colors.orange),
          title: Text('Flags (${flags.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(flags.isEmpty
              ? 'No issues found'
              : '$errors need fixing · tap a flag to see the entries'),
          trailing: hasUnmatched
              ? TextButton(onPressed: () => _tabs.animateTo(2), child: const Text('Match products'))
              : null,
        ),
        for (final f in flags) _flagTile(f),
      ]),
    );
  }

  Widget _flagTile(Map<String, dynamic> f) {
    final sev = f['severity'];
    final color = sev == 'error' ? Colors.red.shade700 : sev == 'warning' ? Colors.orange.shade800 : Colors.blueGrey;
    final icon = sev == 'error' ? Icons.error_outline : sev == 'warning' ? Icons.warning_amber_rounded : Icons.info_outline;
    final details = List<String>.from(f['details'] as List? ?? []);
    final amount = (f['amount'] as num?) ?? 0;
    return ExpansionTile(
      leading: Icon(icon, color: color),
      title: Text(f['message'].toString(), style: TextStyle(fontSize: 13, color: color)),
      subtitle: Text('${f['count']} ${f['count'] == 1 ? 'case' : 'cases'}${amount != 0 ? ' · ${_money(amount)}' : ''}',
          style: const TextStyle(fontSize: 12)),
      childrenPadding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
      children: details.isEmpty
          ? [const Align(alignment: Alignment.centerLeft, child: Text('-'))]
          : details
              .map((d) => Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: SelectableText(d, style: const TextStyle(fontSize: 12)),
                    ),
                  ))
              .toList(),
    );
  }

  Widget _paymentsCard() {
    final rows = List<Map<String, dynamic>>.from(
        ((_result!['po_payments'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
    const labels = {
      'extra_paid': 'EXTRA PAID',
      'paid_no_entry': 'Paid - no entry in app',
      'balance_due': 'Balance due',
      'unpaid': 'Unpaid',
      'paid_entries_other_dates': 'Paid - entries on other dates',
      'paid': 'Paid',
    };
    Color colorOf(String s) => switch (s) {
          'extra_paid' || 'paid_no_entry' => Colors.red.shade700,
          'balance_due' || 'unpaid' => Colors.orange.shade800,
          _ => Colors.green.shade700,
        };
    double sum(String status, String field) =>
        rows.where((r) => r['status'] == status).fold(0.0, (a, r) => a + ((r[field] as num?) ?? 0).toDouble().abs());
    const h = TextStyle(fontWeight: FontWeight.bold, fontSize: 12);
    const c = TextStyle(fontSize: 12);
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          leading: const Icon(Icons.payments_outlined),
          title: const Text('PO payments (Purchase Report vs app)', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(rows.isEmpty
              ? 'Upload the Purchase Report (with PO numbers) to check payments.'
              : 'Unpaid ${_money(sum('unpaid', 'app_amount'))} · balance due ${_money(sum('balance_due', 'difference'))} · '
                  'extra paid ${_money(sum('extra_paid', 'difference'))}'),
        ),
        if (rows.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50),
              columns: const [
                DataColumn(label: Text('PO', style: h)),
                DataColumn(label: Text('Vendor', style: h)),
                DataColumn(label: Text('App amount', style: h), numeric: true),
                DataColumn(label: Text('Paid', style: h), numeric: true),
                DataColumn(label: Text('Difference', style: h), numeric: true),
                DataColumn(label: Text('Status', style: h)),
              ],
              rows: rows.map((r) {
                final st = r['status'].toString();
                return DataRow(cells: [
                  DataCell(Text(r['po_number'].toString(), style: c)),
                  DataCell(Text((r['vendor'] ?? '').toString(), style: c)),
                  DataCell(Text('${_money(r['app_amount'])}${r['app_basis'] == 'worst case' ? ' *' : ''}', style: c)),
                  DataCell(Text(_money(r['paid_amount']), style: c)),
                  DataCell(Text(_money(r['difference']), style: c)),
                  DataCell(Text(labels[st] ?? st, style: c.copyWith(color: colorOf(st), fontWeight: FontWeight.w700))),
                ]);
              }).toList(),
            ),
          ),
        if (rows.any((r) => r['app_basis'] == 'worst case'))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('* worst case (accepted quantity not entered), so the real amount owed may be lower.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          ),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _itemsCard() {
    final items = List<Map<String, dynamic>>.from((_result!['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    const h = TextStyle(fontWeight: FontWeight.bold, fontSize: 12);
    const c = TextStyle(fontSize: 12);
    DataCell cell(dynamic v, {bool money = true, Color? color}) =>
        DataCell(Text(money ? _money(v) : _qty(v), style: c.copyWith(color: color)));
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          title: Text('Item-wise GPM (${items.length} items with stock update)', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('GP = Closing value + Sales − Purchases − Opening value (opening less vendor returns)'),
        ),
        if (items.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('No stock update entries in this period.'))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50),
              columns: const [
                DataColumn(label: Text('Item', style: h)),
                DataColumn(label: Text('Unit', style: h)),
                DataColumn(label: Text('Opening', style: h), numeric: true),
                DataColumn(label: Text('Vendor ret.', style: h), numeric: true),
                DataColumn(label: Text('Opening value', style: h), numeric: true),
                DataColumn(label: Text('Closing', style: h), numeric: true),
                DataColumn(label: Text('Closing value', style: h), numeric: true),
                DataColumn(label: Text('Purchases', style: h), numeric: true),
                DataColumn(label: Text('of which worst case', style: h), numeric: true),
                DataColumn(label: Text('Sales', style: h), numeric: true),
                DataColumn(label: Text('Gross profit', style: h), numeric: true),
                DataColumn(label: Text('GP %', style: h), numeric: true),
              ],
              rows: items.map((i) {
                final gp = (i['gross_profit'] as num).toDouble();
                final rateNote = i['closing_rate'] == null ? '' : ' @${i['closing_rate']}/${i['closing_rate_unit']}';
                return DataRow(cells: [
                  DataCell(Text(i['item'].toString(), style: c)),
                  DataCell(Text(i['stock_unit'].toString(), style: c)),
                  cell(i['opening_stock'], money: false),
                  cell(i['vendor_returns'], money: false),
                  cell(i['opening_value']),
                  DataCell(Text('${_qty(i['closing_stock'])}$rateNote', style: c)),
                  cell(i['closing_value']),
                  cell(i['purchase_amount']),
                  cell(i['worst_case_amount'], color: ((i['worst_case_amount'] as num?) ?? 0) > 0 ? Colors.orange.shade900 : null),
                  cell(i['sales_amount']),
                  cell(gp, color: gp < 0 ? Colors.red.shade700 : Colors.green.shade800),
                  DataCell(Text(i['gp_percent'] == null ? '-' : '${i['gp_percent']}%', style: c)),
                ]);
              }).toList(),
            ),
          ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

// ======================================================================
// Upload Reports tab
// ======================================================================
class _UploadsTab extends StatefulWidget {
  final VoidCallback onUploaded;
  const _UploadsTab({required this.onUploaded});

  @override
  State<_UploadsTab> createState() => _UploadsTabState();
}

class _UploadsTabState extends State<_UploadsTab> with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  List<Map<String, dynamic>> _uploads = [];
  Map<String, dynamic> _coverage = {};
  String? _busyType;
  final Map<String, Map<String, dynamic>> _lastResult = {};
  final GlobalKey<_ExpenseCategoriesState> _expKey = GlobalKey<_ExpenseCategoriesState>();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/gpm/uploads'));
      if (res.statusCode == 200) {
        final b = jsonDecode(res.body);
        setState(() {
          _uploads = List<Map<String, dynamic>>.from((b['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
          _coverage = Map<String, dynamic>.from(b['coverage'] as Map);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _upload(String type) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    List<int>? bytes = file.bytes;
    if (bytes == null && !kIsWeb && file.path != null) {
      bytes = await io.File(file.path!).readAsBytes();
    }
    if (bytes == null) {
      _snack('Could not read the file', Colors.red);
      return;
    }
    setState(() => _busyType = type);
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/gpm/upload_report'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'report_type': type, 'filename': file.name, 'file_b64': base64Encode(bytes)}),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        setState(() => _lastResult[type] = Map<String, dynamic>.from(body as Map));
        _snack(body['message'].toString(), Colors.green);
        widget.onUploaded();
        if (type == 'expense') _expKey.currentState?.reload();
        await _load();
      } else {
        _snack(body['message']?.toString() ?? 'Upload failed', Colors.red);
      }
    } catch (e) {
      _snack('Upload failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _busyType = null);
    }
  }

  void _snack(String t, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: c, duration: const Duration(seconds: 6)));
  }

  Widget _reportCard(String type, String title, String help) {
    final cov = _coverage[type] as Map?;
    final last = _lastResult[type];
    final busy = _busyType == type;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text(help, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          Text(
            cov == null || cov['from_date'] == null
                ? 'Nothing uploaded yet'
                : 'Data available from ${cov['from_date']} to ${cov['to_date']}',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              icon: busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file),
              label: Text(busy ? 'Uploading...' : 'Choose Excel file (.xlsx)'),
              onPressed: _busyType != null ? null : () => _upload(type),
            ),
          ),
          if (last != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(last['message'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                if ((last['rows_without_control_date'] ?? 0) > 0)
                  Text('${last['rows_without_control_date']} rows had no control date - their invoice date was used (flagged in the analysis).',
                      style: TextStyle(color: Colors.orange.shade900, fontSize: 12)),
                const SizedBox(height: 4),
                ...((last['detected']?['sheets'] as Map?) ?? {}).entries.map((e) {
                  final cols = Map<String, dynamic>.from((e.value as Map)['columns'] as Map);
                  return Text(
                    "Sheet '${e.key}': ${cols.entries.map((c) => '${c.key} = \"${c.value}\"').join(', ')}",
                    style: const TextStyle(fontSize: 11),
                  );
                }),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        _reportCard('sales', 'Sales Report',
            'Excel export with the invoice sheet (control date, invoice no, total amount) and the item sheet '
            '(invoice no, product ID, item name, amount). Uploading again replaces the earlier data for the same dates.'),
        const SizedBox(height: 12),
        _reportCard('purchase', 'Purchase Report',
            'Used when you choose "Purchase Report" (or Overall) in GPM: every purchase of the period, product-wise '
            'matching for item-wise GPM. Otherwise only a cross-check against the app purchase entries.'),
        const SizedBox(height: 12),
        _reportCard('expense', 'Expense Sheet (LMD / FMD)',
            'Excel with date (control date if there is one), category, party name, total amount and paid amount. '
            'The total amount of LMD / FMD rows is used in Overall GPM and matched against the app\'s LMD + FMD entries. '
            'Rows whose party name says LMD / FMD are counted as LMD / FMD.'),
        const SizedBox(height: 8),
        _ExpenseCategories(key: _expKey),
        const SizedBox(height: 16),
        const Text('Recent uploads', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        if (_uploads.isEmpty) const Text('None yet'),
        ..._uploads.map((u) => ListTile(
              dense: true,
              leading: Icon(u['report_type'] == 'sales'
                  ? Icons.point_of_sale
                  : (u['report_type'] == 'expense' ? Icons.receipt_outlined : Icons.shopping_cart_outlined)),
              title: Text('${u['filename'] ?? '(file)'} — ${u['report_type']}'),
              subtitle: Text('${u['from_date'] ?? '?'} to ${u['to_date'] ?? '?'} · ${u['invoice_rows']} invoices, '
                  '${u['item_rows']} item rows · uploaded ${u['uploaded_at']}'),
            )),
      ]),
    );
  }
}

// ======================================================================
// Expense sheet categories: which ones are LMD / FMD
// ======================================================================
class _ExpenseCategories extends StatefulWidget {
  const _ExpenseCategories({super.key});

  @override
  State<_ExpenseCategories> createState() => _ExpenseCategoriesState();
}

class _ExpenseCategoriesState extends State<_ExpenseCategories> {
  bool _loading = true;
  List<Map<String, dynamic>> _cats = [];
  static const _kinds = {
    'lmd': 'LMD',
    'fmd': 'FMD',
    'logistics': 'LMD + FMD (not split)',
    'other': 'Not LMD / FMD',
  };

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/gpm/expense_categories'));
      if (res.statusCode == 200) {
        final b = jsonDecode(res.body) as Map;
        if (!mounted) return;
        setState(() => _cats = ((b['categories'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _set(Map<String, dynamic> c, String kind) async {
    final old = c['kind'];
    setState(() => c['kind'] = kind);
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/gpm/expense_categories'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'category_key': c['category_key'], 'category': c['category'], 'kind': kind}),
      );
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
    } catch (e) {
      if (!mounted) return;
      setState(() => c['kind'] = old);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_cats.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.category_outlined),
        title: Text('Expense categories (${_cats.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('Mark which categories are LMD / FMD - guessed from the name, change if wrong',
            style: TextStyle(fontSize: 12)),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          for (final c in _cats)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(
                  child: Text(
                      '${c['category']}\n${c['rows']} rows · total ${NumberFormat('#,##0.##').format((c['amount'] as num?) ?? (c['paid'] as num?) ?? 0)}'
                      ' · paid ${NumberFormat('#,##0.##').format((c['paid'] as num?) ?? 0)}'
                      '${((c['lmd_by_party'] as num?) ?? 0) > 0 ? '\nLMD by party name ${NumberFormat('#,##0.##').format(c['lmd_by_party'])}' : ''}',
                      style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('exp-${c['category_key']}-${c['kind']}'),
                    initialValue: _kinds.containsKey(c['kind']) ? c['kind'] as String : 'other',
                    isExpanded: true,
                    isDense: true,
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                    items: [
                      for (final k in _kinds.entries)
                        DropdownMenuItem(value: k.key, child: Text(k.value, style: const TextStyle(fontSize: 12))),
                    ],
                    onChanged: (v) {
                      if (v != null && v != c['kind']) _set(c, v);
                    },
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

// ======================================================================
// Product Matching tab
// ======================================================================
class _ProductsTab extends StatefulWidget {
  const _ProductsTab({super.key});

  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab> with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _products = [];
  List<String> _items = [];
  bool _onlyUnmatched = true;
  String _search = '';
  String _type = 'sales'; // which report's products: 'sales' or 'purchase'

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Future.wait([
        http.get(Uri.parse('$baseUrl/gpm/products').replace(queryParameters: {'type': _type})),
        http.get(Uri.parse('$baseUrl/get_items?distinct=1')),
      ]);
      if (res[0].statusCode != 200) throw Exception(_errorText(res[0]));
      final products = (jsonDecode(res[0].body)['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final items = (jsonDecode(res[1].body) as List).map((e) => (e as Map)['name'].toString()).toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _products = products;
        _items = items;
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

  Future<void> _saveMappings(List<Map<String, dynamic>> maps) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/gpm/map_product'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'mappings': maps}),
      );
      if (res.statusCode != 200) throw Exception(_errorText(res));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${maps.length} match(es)'), backgroundColor: Colors.green),
        );
      }
      await reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _pickItem(Map<String, dynamic> p) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => _ItemPickerDialog(
        items: _items,
        title: '${p['product_id'] ?? ''} ${p['product_name'] ?? ''}'.trim(),
        suggestion: p['suggested_item']?.toString(),
      ),
    );
    if (chosen == null) return;
    await _saveMappings([
      {'product_key': p['product_key'], 'item': chosen},
    ]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Could not load products: $_error'));
    final q = _search.trim().toLowerCase();
    final list = _products.where((p) {
      if (_onlyUnmatched && p['mapped'] == true) return false;
      if (q.isEmpty) return true;
      return '${p['product_id'] ?? ''} ${p['product_name'] ?? ''} ${p['item'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
    final withSuggestion = _products.where((p) => p['mapped'] != true && p['suggested_item'] != null).toList();
    final unmatched = _products.where((p) => p['mapped'] != true).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'sales', label: Text('Sales Report'), icon: Icon(Icons.point_of_sale, size: 18)),
              ButtonSegment(value: 'purchase', label: Text('Purchase Report'), icon: Icon(Icons.shopping_cart_outlined, size: 18)),
            ],
            selected: {_type},
            onSelectionChanged: (s) {
              setState(() => _type = s.first);
              reload();
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Match each ${_type == 'purchase' ? 'Purchase' : 'Sales'} Report product ID to the app item it belongs to. '
            'Matches are saved and reused; change one here if a product ID changes. Choose "Not a tracked item" for '
            'products without stock in the app${_type == 'purchase' ? ' (packaging is matched to its packaging item)' : ''}.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 240,
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search', isDense: true, border: OutlineInputBorder()),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          FilterChip(
            label: Text('Not matched ($unmatched)'),
            selected: _onlyUnmatched,
            onSelected: (v) => setState(() => _onlyUnmatched = v),
          ),
          if (withSuggestion.isNotEmpty)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: Text('Accept ${withSuggestion.length} suggestion(s)'),
              onPressed: () => _saveMappings(withSuggestion
                  .map((p) => {'product_key': p['product_key'], 'item': p['suggested_item']})
                  .toList()),
            ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Text(_products.isEmpty
                    ? 'Upload a Sales Report first.'
                    : (_onlyUnmatched ? 'All products are matched.' : 'Nothing found.')))
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final p = list[i];
                  final mapped = p['mapped'] == true;
                  final item = (p['item'] ?? '').toString();
                  return ListTile(
                    title: Text('${p['product_id'] ?? '(no ID)'}  ·  ${p['product_name'] ?? ''}'),
                    subtitle: Text(
                      mapped
                          ? (item.isEmpty ? 'Not a tracked item' : 'Matched to $item')
                          : (p['suggested_item'] != null ? 'Suggested: ${p['suggested_item']}' : 'Not matched'),
                      style: TextStyle(color: mapped ? Colors.green.shade700 : Colors.orange.shade900, fontSize: 12),
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_money(p['amount']), style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 8),
                      if (!mapped && p['suggested_item'] != null)
                        IconButton(
                          tooltip: 'Use suggestion',
                          icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                          onPressed: () => _saveMappings([
                            {'product_key': p['product_key'], 'item': p['suggested_item']}
                          ]),
                        ),
                      TextButton(onPressed: () => _pickItem(p), child: Text(mapped ? 'Change' : 'Match')),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}

class _ItemPickerDialog extends StatefulWidget {
  final List<String> items;
  final String title;
  final String? suggestion;
  const _ItemPickerDialog({required this.items, required this.title, this.suggestion});

  @override
  State<_ItemPickerDialog> createState() => _ItemPickerDialogState();
}

class _ItemPickerDialogState extends State<_ItemPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = widget.items.where((i) => q.isEmpty || i.toLowerCase().contains(q)).toList();
    return AlertDialog(
      title: Text('Match "${widget.title}"'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search app item', border: OutlineInputBorder(), isDense: true),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          if (widget.suggestion != null)
            ListTile(
              dense: true,
              leading: const Icon(Icons.auto_fix_high, color: Colors.green),
              title: Text('Suggested: ${widget.suggestion}'),
              onTap: () => Navigator.pop(context, widget.suggestion),
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.block, color: Colors.grey),
            title: const Text('Not a tracked item'),
            subtitle: const Text('Counted in overall sales only'),
            onTap: () => Navigator.pop(context, ''),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (ctx, i) => ListTile(
                dense: true,
                title: Text(list[i]),
                onTap: () => Navigator.pop(context, list[i]),
              ),
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL'))],
    );
  }
}
