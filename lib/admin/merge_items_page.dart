import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_config.dart';

/// Admin › Merge Items
///
/// Two names in the Admin item list that are the same thing (e.g. "Shimla"
/// and "Capsicum"). All entries of the item you remove are renamed to the
/// item you keep - nothing is deleted - and its reports are recalculated.
class MergeItemsPage extends StatefulWidget {
  const MergeItemsPage({super.key});

  @override
  State<MergeItemsPage> createState() => _MergeItemsPageState();
}

class _MergeItemsPageState extends State<MergeItemsPage> {
  bool _loading = true;
  String? _error;
  List<String> _items = [];
  String? _from;
  String? _to;
  Map<String, dynamic>? _preview;
  bool _previewing = false;
  bool _merging = false;
  final _password = TextEditingController();
  final List<String> _done = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse('$baseUrl/get_items?distinct=1'));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      final list = (jsonDecode(res.body) as List)
          .map((e) => (e is Map ? e['name'] : e)?.toString() ?? '')
          .where((n) => n.trim().isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _items = list;
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

  Future<void> _pick(bool isFrom) async {
    final exclude = isFrom ? _to : _from;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ItemPickerSheet(
        title: isFrom ? 'Item to remove' : 'Item to keep',
        items: _items.where((i) => i != exclude).toList(),
      ),
    );
    if (chosen == null) return;
    setState(() {
      if (isFrom) {
        _from = chosen;
      } else {
        _to = chosen;
      }
      _preview = null;
    });
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    if (_from == null || _to == null) return;
    setState(() => _previewing = true);
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/merge_items'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'from_item': _from, 'to_item': _to, 'preview': true}),
      );
      final b = jsonDecode(res.body) as Map;
      if (!mounted) return;
      if (res.statusCode == 200 && b['success'] == true) {
        setState(() => _preview = Map<String, dynamic>.from(b));
      } else {
        _snack(b['message']?.toString() ?? 'Could not check', Colors.red);
      }
    } catch (e) {
      _snack('Could not check: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _merge() async {
    if (_from == null || _to == null) return;
    if (_password.text.isEmpty) {
      _snack('Enter the admin password', Colors.orange);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Merge items?'),
        content: Text(
          "All entries of '$_from' will be renamed to '$_to', and '$_from' will be removed from the item list.\n\n"
          'No entries are deleted. This cannot be undone from the app.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('MERGE')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _merging = true);
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/merge_items'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'from_item': _from, 'to_item': _to, 'admin_key': _password.text}),
          )
          .timeout(const Duration(minutes: 3));
      final b = jsonDecode(res.body) as Map;
      if (res.statusCode == 200 && b['success'] == true) {
        final renamed = Map<String, dynamic>.from((b['renamed_rows'] as Map?) ?? {});
        final total = renamed.values.fold<num>(0, (s, v) => s + (v as num));
        _done.insert(0, "'${b['from_item']}' → '${b['to_item']}' · $total entries moved");
        _snack(b['message']?.toString() ?? 'Merged', Colors.green);
        setState(() {
          _from = null;
          _preview = null;
        });
        await _loadItems();
      } else {
        _snack(b['message']?.toString() ?? 'Merge failed', Colors.red);
      }
    } catch (e) {
      _snack('Merge failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _merging = false);
    }
  }

  void _snack(String t, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: c));
  }

  Widget _pickerTile(String label, String? value, bool isFrom, Color color) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Icon(isFrom ? Icons.remove_circle_outline : Icons.check_circle_outline, color: color),
        title: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        subtitle: Text(
          value ?? 'Tap to choose',
          style: TextStyle(
            fontSize: 16,
            fontWeight: value == null ? FontWeight.normal : FontWeight.w700,
            color: value == null ? Colors.grey : null,
          ),
        ),
        trailing: const Icon(Icons.arrow_drop_down),
        onTap: _merging ? null : () => _pick(isFrom),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Merge Items'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _loadItems)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load items: $_error'))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Text(
                    'Use this when the item list has the same item under two names. Every entry of the item you remove '
                    '(stock update, purchase, sales, B grade, dump, mandi, rejections, packaging, POs, SOs, FMD) is renamed '
                    'to the item you keep. Nothing is deleted, and reports are recalculated. The removed name is remembered, '
                    'so if anyone types it again it is still counted under the kept item.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  _pickerTile('Item to remove (duplicate / wrong name)', _from, true, Colors.red.shade400),
                  const Center(child: Icon(Icons.arrow_downward)),
                  _pickerTile('Item to keep', _to, false, Colors.green.shade600),
                  const SizedBox(height: 8),
                  if (_previewing) const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
                  if (_preview != null) _previewCard(),
                  if (_preview != null) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Admin password', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                      icon: _merging
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.merge_type),
                      label: Text(_merging ? 'Merging...' : "Merge '$_from' into '$_to'"),
                      onPressed: _merging ? null : _merge,
                    ),
                  ],
                  if (_done.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('Merged in this session', style: TextStyle(fontWeight: FontWeight.w700)),
                    for (final d in _done)
                      Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(d, style: const TextStyle(fontSize: 13))),
                  ],
                ]),
    );
  }

  Widget _previewCard() {
    final p = _preview!;
    final details = List<Map<String, dynamic>>.from(
        ((p['details'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
    final warnings = List<String>.from((p['warnings'] as List?) ?? []);
    return Card(
      color: Colors.indigo.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            details.isEmpty
                ? "'${p['from_item']}' has no entries. It will just be removed from the list."
                : "${p['total_rows']} entries of '${p['from_item']}' will move to '${p['to_item']}':",
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          for (final d in details)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(children: [
                Expanded(child: Text(d['label'].toString(), style: const TextStyle(fontSize: 13))),
                Text('${d['rows']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          for (final w in warnings)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(w, style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
            ),
        ]),
      ),
    );
  }
}

/// Bottom sheet with a search box and the item list (no pop-up overlay).
class _ItemPickerSheet extends StatefulWidget {
  final String title;
  final List<String> items;
  const _ItemPickerSheet({required this.title, required this.items});

  @override
  State<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<_ItemPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty ? widget.items : widget.items.where((i) => i.toLowerCase().contains(q)).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search item'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('No matching item'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) => ListTile(
                        dense: true,
                        title: Text(list[i]),
                        onTap: () => Navigator.pop(context, list[i]),
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
