import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Units the received / accepted / rejected quantity may be entered in,
/// based on the PO unit. Weight POs (kg, g, ton) accept Kg or g; count POs
/// (pcs, box, bag) only their own unit.
List<String> unitsForPoUnit(String? poUnit) {
  final u = _unitKey(poUnit);
  if (u == 'kg' || u == 'g' || u == 'ton') return const ['Kg', 'g'];
  if (u.isEmpty) return const ['Kg', 'g', 'pcs'];
  // PO in boxes, bags, crates, pieces, dozens...: enter the quantity in that
  // unit, so the amount is number of units x rate per unit
  return [u];
}

/// 'Boxes' -> 'box', 'PCS' -> 'pcs', 'Crates' -> 'crate', 'Kgs' -> 'kg'.
String _unitKey(String? unit) {
  var u = (unit ?? '').trim().toLowerCase().replaceAll('.', '');
  const same = {
    'kgs': 'kg', 'kilo': 'kg', 'kilos': 'kg', 'kilogram': 'kg', 'kilograms': 'kg',
    'gm': 'g', 'gms': 'g', 'gram': 'g', 'grams': 'g', 'tons': 'ton', 'tonne': 'ton',
    'pc': 'pcs', 'piece': 'pcs', 'pieces': 'pcs', 'nos': 'pcs', 'no': 'pcs',
    'boxes': 'box', 'bags': 'bag',
  };
  if (same.containsKey(u)) return same[u]!;
  if (u.length > 3 && u.endsWith('s') && !u.endsWith('ss')) u = u.substring(0, u.length - 1); // crates -> crate
  return u;
}

/// Quantity converted into the PO unit (null when it can't be converted).
double? qtyInPoUnit(double qty, String? unit, String? poUnit) {
  const toKg = {'g': 0.001, 'kg': 1.0, 'ton': 1000.0};
  final u = _unitKey(unit);
  final p = _unitKey(poUnit);
  if (u.isEmpty || u == p) return qty;
  if (toKg.containsKey(u) && toKg.containsKey(p)) return qty * toKg[u]! / toKg[p]!;
  return null;
}

/// Vendor -> PO -> Item picker for Purchase Entry and Packaging Material Entry.
///
/// [lines] are PO lines from `/get_pos_for_entry` for the selected CTRL date.
/// When a vendor has one PO it is selected automatically; when that PO has
/// one item it is selected too. [onChanged] gets the chosen PO line (or null).
class PoLineSelector extends StatefulWidget {
  final List<Map<String, dynamic>> lines;
  final Map<String, dynamic>? initialLine;
  final ValueChanged<Map<String, dynamic>?> onChanged;
  final bool enabled;
  final String disabledHint;

  const PoLineSelector({
    super.key,
    required this.lines,
    required this.onChanged,
    this.initialLine,
    this.enabled = true,
    this.disabledHint = 'Select CTRL date first',
  });

  @override
  State<PoLineSelector> createState() => _PoLineSelectorState();
}

class _PoLineSelectorState extends State<PoLineSelector> {
  String? _vendor;
  String? _po;
  Map<String, dynamic>? _line;

  @override
  void initState() {
    super.initState();
    final l = widget.initialLine;
    if (l != null) {
      _vendor = l['vendor_name']?.toString();
      _po = l['po_number']?.toString();
      _line = l;
    }
  }

  List<String> get _vendors {
    final s = widget.lines.map((l) => (l['vendor_name'] ?? '').toString()).where((v) => v.isNotEmpty).toSet().toList();
    s.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return s;
  }

  List<String> _posFor(String? vendor) {
    final s = widget.lines
        .where((l) => l['vendor_name']?.toString() == vendor)
        .map((l) => l['po_number'].toString())
        .toSet()
        .toList();
    s.sort();
    return s;
  }

  List<Map<String, dynamic>> _linesFor(String? vendor, String? po) => widget.lines
      .where((l) => l['vendor_name']?.toString() == vendor && l['po_number']?.toString() == po)
      .toList();

  String _lineKey(Map<String, dynamic> l) => '${l['po_number']}|${l['item_name']}';

  void _selectVendor(String? v) {
    setState(() {
      _vendor = v;
      _po = null;
      _line = null;
      final pos = _posFor(v);
      if (pos.length == 1) {
        _po = pos.first;
        final items = _linesFor(v, _po);
        if (items.length == 1) _line = items.first;
      }
    });
    widget.onChanged(_line);
  }

  void _selectPo(String? po) {
    setState(() {
      _po = po;
      _line = null;
      final items = _linesFor(_vendor, po);
      if (items.length == 1) _line = items.first;
    });
    widget.onChanged(_line);
  }

  void _selectLine(String? key) {
    setState(() {
      _line = _linesFor(_vendor, _po).firstWhere((l) => _lineKey(l) == key, orElse: () => <String, dynamic>{});
      if (_line!.isEmpty) _line = null;
    });
    widget.onChanged(_line);
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('dd-MM-yy').format(d);
  }

  String _fmtNum(dynamic v) {
    final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.indigo.shade300, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade50,
      );

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return InputDecorator(
        decoration: _dec('Vendor / PO / Item', Icons.receipt_long_outlined),
        child: Text(widget.disabledHint, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
      );
    }
    if (widget.lines.isEmpty) {
      return InputDecorator(
        decoration: _dec('Vendor / PO / Item', Icons.receipt_long_outlined),
        child: Text(
          'No PO is expected on this CTRL date. Turn on "Show POs of other dates" if the delivery came early or late.',
          style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
        ),
      );
    }
    final vendors = _vendors;
    final pos = _posFor(_vendor);
    final items = _linesFor(_vendor, _po);
    final line = _line;
    final problem = line?['problem']?.toString();
    final dateMatch = line?['date_match'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('vendor-${vendors.length}-$_vendor'),
          decoration: _dec('Select Vendor', Icons.store_mall_directory_outlined),
          style: const TextStyle(fontSize: 13, color: Colors.black),
          initialValue: vendors.contains(_vendor) ? _vendor : null,
          isExpanded: true,
          items: vendors
              .map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: _selectVendor,
          validator: (v) => v == null ? 'Please select vendor' : null,
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          key: ValueKey('po-$_vendor-$_po'),
          decoration: _dec(pos.length > 1 ? 'Select PO (${pos.length} POs from this vendor)' : 'PO Number',
              Icons.receipt_long_outlined),
          style: const TextStyle(fontSize: 13, color: Colors.black),
          initialValue: pos.contains(_po) ? _po : null,
          isExpanded: true,
          items: pos.map((po) {
            final l = _linesFor(_vendor, po).first;
            final other = l['date_match'] != true;
            return DropdownMenuItem(
              value: po,
              child: Text(
                '$po  (expected ${_fmtDate(l['expected_date']?.toString())})${other ? '  - other date' : ''}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: other ? Colors.orange.shade900 : null),
              ),
            );
          }).toList(),
          onChanged: _vendor == null ? null : _selectPo,
          validator: (v) => v == null ? 'PO number is required' : null,
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          key: ValueKey('item-$_vendor-$_po-${line == null ? '' : _lineKey(line)}'),
          decoration: _dec('Item (from PO)', Icons.inventory_2_outlined),
          style: const TextStyle(fontSize: 13, color: Colors.black),
          initialValue: line == null ? null : _lineKey(line),
          isExpanded: true,
          items: items
              .map((l) => DropdownMenuItem(
                    value: _lineKey(l),
                    child: Text(l['item_name'].toString(), overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: _po == null ? null : _selectLine,
          validator: (_) {
            if (line == null) return 'Please select item';
            if (problem != null) return problem;
            return null;
          },
        ),
        if (line != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: problem != null ? Colors.red.shade50 : Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: problem != null ? Colors.red.shade200 : Colors.indigo.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  problem ?? 'Rate (from PO): ₹${_fmtNum(line['rate'])} per ${line['unit']}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: problem != null ? Colors.red.shade800 : Colors.indigo.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ordered ${_fmtNum(line['qty_ordered'])} ${line['unit']} · received so far ${_fmtNum(line['received_so_far'])} ${line['unit']}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                ),
                if (!dateMatch)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'PO was expected on ${_fmtDate(line['expected_date']?.toString())}, not on the CTRL date.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
