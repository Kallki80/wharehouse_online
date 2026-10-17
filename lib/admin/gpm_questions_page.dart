import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';

/// Asked before the GPM report when stock can't be valued yet:
///  * average weight per piece (papaya / pineapple...) for a date
///  * kg in one box / bag / crate when the PO is priced per box but stock is in kg
///  * stock older than the first purchase: use the next PO rate or enter a rate
///  * no PO rate at all: enter a rate
///
/// Pops 'calc' after saving the answers, 'skip' to calculate without them,
/// or null when cancelled.
class GpmQuestionsPage extends StatefulWidget {
  final List<Map<String, dynamic>> questions;
  final String start;
  final String end;
  const GpmQuestionsPage({super.key, required this.questions, required this.start, required this.end});

  @override
  State<GpmQuestionsPage> createState() => _GpmQuestionsPageState();
}

class _GpmQuestionsPageState extends State<GpmQuestionsPage> {
  final Map<int, TextEditingController> _ctrls = {};
  final Map<int, String> _mode = {}; // price_choice: 'next' | 'manual'
  final Map<int, String> _rateUnit = {}; // 'kg' | 'pcs'
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      _ctrls[i] = TextEditingController(
        text: q['type'] == 'avg_weight' && q['last_weight'] != null ? '${q['last_weight']}' : '',
      );
      _mode[i] = 'next';
      _rateUnit[i] = q['is_pcs'] == true ? 'pcs' : 'kg';
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _d(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? '${iso ?? ''}' : DateFormat('dd-MM-yyyy').format(d);
  }

  String _n(dynamic v) {
    final d = double.tryParse('${v ?? ''}');
    if (d == null) return '${v ?? ''}';
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  }

  Future<void> _save() async {
    final answers = <Map<String, dynamic>>[];
    for (var i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      final v = double.tryParse(_ctrls[i]!.text.trim());
      switch (q['type']) {
        case 'avg_weight':
          if (v != null && v > 0) answers.add({'type': 'avg_weight', 'item': q['item'], 'date': q['date'], 'value': v});
          break;
        case 'kg_per_unit':
          if (v != null && v > 0) answers.add({'type': 'kg_per_unit', 'item': q['item'], 'unit': q['unit'], 'value': v});
          break;
        case 'price_choice':
          if (_mode[i] == 'next') {
            answers.add({'type': 'price_choice', 'item': q['item'], 'date': q['date'], 'mode': 'next'});
          } else if (v != null && v > 0) {
            answers.add({'type': 'price_choice', 'item': q['item'], 'date': q['date'], 'mode': 'manual', 'value': v, 'unit': _rateUnit[i]});
          }
          break;
        case 'price_missing':
          if (v != null && v > 0) {
            answers.add({'type': 'price_missing', 'item': q['item'], 'date': q['date'], 'mode': 'manual', 'value': v, 'unit': _rateUnit[i]});
          }
          break;
      }
    }
    setState(() => _saving = true);
    try {
      if (answers.isNotEmpty) {
        final res = await http.post(
          Uri.parse('$baseUrl/gpm/precheck/answers'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'answers': answers}),
        );
        if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      }
      if (!mounted) return;
      Navigator.pop(context, 'calc');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _numField(int i, String label, {String? helper, String? suffix}) => TextField(
        controller: _ctrls[i],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, helperText: helper, suffixText: suffix, isDense: true),
      );

  Widget _unitChips(int i) => Wrap(spacing: 8, children: [
        for (final u in const ['kg', 'pcs'])
          ChoiceChip(
            label: Text('per $u'),
            selected: _rateUnit[i] == u,
            onSelected: (_) => setState(() => _rateUnit[i] = u),
          ),
      ]);

  Widget _card(int i) {
    final q = widget.questions[i];
    final which = q['which'] == 'opening' ? 'Opening' : 'Closing';
    final stock = q['qty'] != null ? '$which stock ${_n(q['qty'])} ${q['qty_unit']} on ${_d(q['date'])}' : '';
    late final IconData icon;
    late final String title;
    late final List<Widget> body;
    switch (q['type']) {
      case 'avg_weight':
        icon = Icons.scale;
        title = '${q['item']} - average weight per piece';
        body = [
          Text('$stock. Needed to turn pieces into kg for the PO rate.', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          _numField(i, 'Average weight of one piece on ${_d(q['date'])}',
              suffix: 'kg',
              helper: q['last_weight'] != null ? 'Last entered: ${q['last_weight']} kg on ${_d(q['last_weight_date'])}' : null),
        ];
        break;
      case 'kg_per_unit':
        icon = Icons.inventory_2_outlined;
        title = '${q['item']} - kg in one ${q['unit']}';
        body = [
          Text('PO ${q['po_number'] ?? ''} is ₹${_n(q['rate'])} per ${q['unit']}, but stock is counted in '
              '${q['is_pcs'] == true ? 'pieces' : 'kg'}. Saved for this item and used every time.',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          _numField(i, 'Weight of one ${q['unit']}', suffix: 'kg'),
        ];
        break;
      case 'price_choice':
        icon = Icons.history;
        title = '${q['item']} - no purchase before ${_d(q['date'])}';
        body = [
          Text('$stock is older than the first purchase entry in the app.', style: const TextStyle(fontSize: 13)),
          RadioGroup<String>(
            groupValue: _mode[i],
            onChanged: (v) => setState(() => _mode[i] = v ?? 'next'),
            child: Column(children: [
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: 'next',
                title: Text('Use the next PO rate: ₹${_n(q['next_rate'])} per ${q['next_unit']}'),
                subtitle: Text('PO ${q['next_po'] ?? ''}, ${_d(q['next_date'])}'),
              ),
              const RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: 'manual',
                title: Text('Enter the rate myself'),
              ),
            ]),
          ),
          if (_mode[i] == 'manual') ...[
            _numField(i, 'Rate on ${_d(q['date'])}', suffix: '₹'),
            const SizedBox(height: 6),
            if (q['is_pcs'] == true) _unitChips(i),
          ],
        ];
        break;
      default: // price_missing
        icon = Icons.money_off;
        title = '${q['item']} - no PO rate found';
        body = [
          Text('$stock. No purchase entry or PO with a rate for this item - check the name (merge duplicate names) '
              'or enter a rate. Leave empty to value it at 0.',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          _numField(i, 'Rate on ${_d(q['date'])}', suffix: '₹'),
          const SizedBox(height: 6),
          if (q['is_pcs'] == true) _unitChips(i),
        ];
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: Colors.indigo, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 6),
          ...body,
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Before the GPM report')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
        Text(
          'For ${_d(widget.start)} to ${_d(widget.end)} these items can\'t be valued yet. Fill in what you know - '
          'answers are saved and used again. Anything left empty is valued at 0 and shown in the flags.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < widget.questions.length; i++) _card(i),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: const Text('Save and make GPM report'),
          onPressed: _saving ? null : _save,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, 'skip'),
          child: const Text('Skip - make the report without these'),
        ),
      ]),
    );
  }
}
