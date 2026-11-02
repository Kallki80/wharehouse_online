import 'dart:convert';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'sourcing_api.dart';

/// One item: Farmers | Specifications | Quotations (cheapest first).
class SourcingItemPage extends StatefulWidget {
  final String item;
  const SourcingItemPage({super.key, required this.item});

  @override
  State<SourcingItemPage> createState() => _SourcingItemPageState();
}

class _SourcingItemPageState extends State<SourcingItemPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _d = {};
  String _status = 'open';
  final List<TextEditingController> _points = [];
  bool _specsDirty = false;

  @override
  void initState() {
    super.initState();
    // last data of this item at once, fresh data right after
    final c = SourcingApi.cached('/sourcing/item', {'item': widget.item, 'status': _status});
    if (c != null) _apply(c);
    _load();
  }

  void _apply(Map<String, dynamic> b) {
    _d = b;
    if (!_specsDirty) {
      for (final c in _points) {
        c.dispose();
      }
      _points
        ..clear()
        ..addAll(((b['specs'] as List?) ?? []).map((t) => TextEditingController(text: '$t')));
      if (_points.isEmpty) _points.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    for (final c in _points) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> _l(String k) => ((_d[k] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  void _snack(String t, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: c, duration: const Duration(seconds: 6)));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final b = await SourcingApi.get('/sourcing/item', {'item': widget.item, 'status': _status});
      if (!mounted) return;
      setState(() => _apply(b));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _n(dynamic v) {
    final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    if (d == null) return '-';
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  }

  String _date(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? '${iso ?? ''}' : DateFormat('dd-MM-yyyy').format(d);
  }

  // ------------------------------------------------------------ farmers
  Future<void> _editFarmer([Map<String, dynamic>? f]) async {
    final fields = <String, String>{
      'name': 'Farmer name *',
      'mobile': 'Mobile number * (login user name)',
      'address': 'Address',
      'pincode': 'Pincode',
      'season': 'Season of delivery (e.g. Oct - Feb)',
      'email': 'E-mail ID',
      'account_holder': 'Account holder name',
      'account_number': 'Account number',
      'ifsc': 'IFSC',
      'bank_name': 'Bank name',
      'upi': 'UPI ID',
    };
    final ctrls = {for (final k in fields.keys) k: TextEditingController(text: '${f?[k] ?? ''}')};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(f == null ? 'Add farmer for ${widget.item}' : 'Edit farmer'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final e in fields.entries) ...[
                if (e.key == 'account_holder')
                  const Padding(
                    padding: EdgeInsets.only(top: 10, bottom: 4),
                    child: Align(alignment: Alignment.centerLeft, child: Text('Account details', style: TextStyle(fontWeight: FontWeight.w700))),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: TextField(
                    controller: ctrls[e.key],
                    keyboardType: e.key == 'mobile' || e.key == 'pincode' || e.key == 'account_number'
                        ? TextInputType.number
                        : (e.key == 'email' ? TextInputType.emailAddress : TextInputType.text),
                    textCapitalization: e.key == 'ifsc' ? TextCapitalization.characters : TextCapitalization.words,
                    maxLines: e.key == 'address' ? 2 : 1,
                    decoration: InputDecoration(labelText: e.value, border: const OutlineInputBorder(), isDense: true),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text('The farmer logs in with the mobile number; the password is the first name.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SAVE')),
        ],
      ),
    );
    final body = {for (final e in ctrls.entries) e.key: e.value.text.trim()};
    for (final c in ctrls.values) {
      c.dispose();
    }
    if (ok != true) return;
    try {
      final b = await SourcingApi.post('/sourcing/farmer', {...body, if (f != null) 'id': f['id'], 'item': widget.item});
      _snack(b['message']?.toString() ?? 'Saved', Colors.green);
      _load();
    } catch (e) {
      _snack('$e', Colors.red);
    }
  }

  Future<void> _removeFarmer(Map<String, dynamic> f, {bool delete = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(delete ? 'Delete ${f['name']}?' : 'Remove ${f['name']} from ${widget.item}?'),
        content: Text(delete
            ? 'The farmer and his login are deleted for all items. His quotations stay in the list.'
            : 'He stays in the farmer database for his other items.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SourcingApi.post('/sourcing/farmer/unlink', {'id': f['id'], 'item': widget.item, 'delete': delete});
      _load();
    } catch (e) {
      _snack('$e', Colors.red);
    }
  }

  Widget _farmersTab() {
    final farmers = _l('farmers');
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
      if (farmers.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No farmers yet - tap "Add farmer".')),
      for (final f in farmers)
        Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ExpansionTile(
            leading: CircleAvatar(child: Text('${f['name']}'.isNotEmpty ? '${f['name']}'[0].toUpperCase() : '?')),
            title: Text('${f['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${f['mobile']} · ${f['pincode'] ?? ''} · season ${f['season'] ?? '-'}', style: const TextStyle(fontSize: 12)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final kv in [
                ['Address', f['address']],
                ['E-mail', f['email']],
                ['Account holder', f['account_holder']],
                ['Account number', f['account_number']],
                ['IFSC', f['ifsc']],
                ['Bank', f['bank_name']],
                ['UPI', f['upi']],
                ['Items', ((f['items'] as List?) ?? []).map((i) => (i as Map)['item']).join(', ')],
              ])
                if ('${kv[1] ?? ''}'.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text('${kv[0]}: ${kv[1]}', style: const TextStyle(fontSize: 12)),
                  ),
              Text('Login: ${f['mobile']} / first name', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              Row(children: [
                TextButton.icon(onPressed: () => _editFarmer(f), icon: const Icon(Icons.edit, size: 16), label: const Text('Edit')),
                TextButton.icon(onPressed: () => _removeFarmer(f), icon: const Icon(Icons.link_off, size: 16), label: const Text('Remove')),
                TextButton.icon(
                  onPressed: () => _removeFarmer(f, delete: true),
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                  label: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ]),
            ],
          ),
        ),
    ]);
  }

  // ------------------------------------------------------------ specifications
  Future<void> _saveSpecs() async {
    try {
      await SourcingApi.post('/sourcing/specs', {'item': widget.item, 'points': _points.map((c) => c.text.trim()).toList()});
      _specsDirty = false;
      _snack('Specifications saved', Colors.green);
      _load();
    } catch (e) {
      _snack('$e', Colors.red);
    }
  }

  Future<void> _addImage() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    List<int>? bytes = file.bytes;
    if (bytes == null && !kIsWeb && file.path != null) bytes = await io.File(file.path!).readAsBytes();
    if (bytes == null) {
      _snack('Could not read the image', Colors.red);
      return;
    }
    if (!mounted) return;
    final cap = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reference image'),
        content: TextField(controller: cap, decoration: const InputDecoration(labelText: 'Caption (optional)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('UPLOAD')),
        ],
      ),
    );
    final caption = cap.text.trim();
    cap.dispose();
    if (ok != true) return;
    try {
      await SourcingApi.post('/sourcing/spec_image',
          {'item': widget.item, 'file_name': file.name, 'file_b64': base64Encode(bytes), 'caption': caption});
      _snack('Image added', Colors.green);
      _load();
    } catch (e) {
      _snack('$e', Colors.red);
    }
  }

  Future<void> _deleteImage(Map<String, dynamic> img) async {
    try {
      await SourcingApi.post('/sourcing/spec_image/${img['id']}/delete', {});
      _load();
    } catch (e) {
      _snack('$e', Colors.red);
    }
  }

  Widget _specsTab() {
    final images = _l('images');
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
      const Text('Product specification - one point per line', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      for (var i = 0; i < _points.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 24, child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(
              child: TextField(
                controller: _points[i],
                maxLines: null,
                onChanged: (_) => _specsDirty = true,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
              onPressed: () => setState(() {
                _specsDirty = true;
                _points.removeAt(i).dispose();
                if (_points.isEmpty) _points.add(TextEditingController());
              }),
            ),
          ]),
        ),
      Row(children: [
        TextButton.icon(
          onPressed: () => setState(() {
            _specsDirty = true;
            _points.add(TextEditingController());
          }),
          icon: const Icon(Icons.add),
          label: const Text('Add point'),
        ),
        const Spacer(),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: _saveSpecs,
          icon: const Icon(Icons.save),
          label: const Text('Save'),
        ),
      ]),
      const Divider(height: 28),
      Row(children: [
        const Expanded(child: Text('Reference images (optional)', style: TextStyle(fontWeight: FontWeight.w700))),
        TextButton.icon(onPressed: _addImage, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Add image')),
      ]),
      if (images.isEmpty) Text('No images', style: TextStyle(color: Colors.grey.shade600)),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final img in images)
          SizedBox(
            width: 150,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                InkWell(
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(SourcingApi.imageUrl('${img['url']}')))),
                  ),
                  child: Image.network(
                    SourcingApi.thumbUrl('${img['url']}'),
                    height: 110,
                    cacheWidth: 300, // decoded small: little memory
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(height: 110, child: Icon(Icons.broken_image)),
                  ),
                ),
                Row(children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text('${img['caption'] ?? img['file_name'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () => _deleteImage(img)),
                ]),
              ]),
            ),
          ),
      ]),
    ]);
  }

  // ------------------------------------------------------------ quotations
  Future<void> _setStatus(Map<String, dynamic> q, String st) async {
    try {
      await SourcingApi.post('/sourcing/quote_status', {'id': q['id'], 'status': st});
      _load();
    } catch (e) {
      _snack('$e', Colors.red);
    }
  }

  Widget _quotesTab() {
    final quotes = _l('quotes');
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
      Wrap(spacing: 6, children: [
        for (final s in const ['open', 'accepted', 'rejected', 'all'])
          ChoiceChip(
            label: Text(s[0].toUpperCase() + s.substring(1)),
            selected: _status == s,
            onSelected: (_) {
              setState(() => _status = s);
              _load();
            },
          ),
      ]),
      const SizedBox(height: 6),
      Text('Lowest rate first (compared per kg when the unit can be converted).',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      if (quotes.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No quotations.')),
      for (var i = 0; i < quotes.length; i++)
        Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: i == 0 && _status == 'open' ? Colors.green.shade50 : null,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: i == 0 ? Colors.green.shade700 : Colors.grey.shade400,
              child: Text('${i + 1}', style: const TextStyle(color: Colors.white)),
            ),
            title: Text('₹${_n(quotes[i]['rate'])} / ${quotes[i]['unit']}  ·  ${quotes[i]['farmer'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${_n(quotes[i]['qty'])} ${quotes[i]['unit']} · reaches warehouse ${_date(quotes[i]['delivery_date'])}'
              '${quotes[i]['rate_per_kg'] != null && quotes[i]['unit'] != 'kg' ? ' · ≈ ₹${_n(quotes[i]['rate_per_kg'])}/kg' : ''}'
              '\nValue ₹${_n(quotes[i]['value'])} · ${quotes[i]['mobile'] ?? ''} · ${quotes[i]['status']}'
              '${'${quotes[i]['note'] ?? ''}'.isNotEmpty ? '\nNote: ${quotes[i]['note']}' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
            isThreeLine: true,
            trailing: PopupMenuButton<String>(
              onSelected: (s) => _setStatus(quotes[i], s),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'accepted', child: Text('Accept')),
                PopupMenuItem(value: 'rejected', child: Text('Reject')),
                PopupMenuItem(value: 'open', child: Text('Mark open')),
              ],
            ),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.item),
            actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
            bottom: const TabBar(tabs: [
              Tab(icon: Icon(Icons.agriculture), text: 'Farmers'),
              Tab(icon: Icon(Icons.rule), text: 'Specifications'),
              Tab(icon: Icon(Icons.request_quote_outlined), text: 'Quotations'),
            ]),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _editFarmer(),
            icon: const Icon(Icons.person_add),
            label: const Text('Add farmer'),
          ),
          body: _loading && _d.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _d.isEmpty
                  ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)))
                  : TabBarView(children: [_farmersTab(), _specsTab(), _quotesTab()]),
        );
      }),
    );
  }
}
