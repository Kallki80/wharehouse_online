import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_config.dart';

/// Admin › Item Spellings
///
/// Lists item names used in entries (stock update, purchase, sales, B-grade
/// sales, dump sale, mandi resale, rejection received, vendor rejection) that
/// are not written exactly as in the Admin item list, and lets the admin
/// convert them to the correct item so the Admin Report counts them.
class ItemSpellingsPage extends StatefulWidget {
  const ItemSpellingsPage({super.key});

  @override
  State<ItemSpellingsPage> createState() => _ItemSpellingsPageState();
}

enum _SpellingFilter { unmatched, autoMatched, converted }

class _ItemSpellingsPageState extends State<ItemSpellingsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _issues = [];
  List<Map<String, dynamic>> _aliases = [];
  List<String> _items = [];
  _SpellingFilter _filter = _SpellingFilter.unmatched;

  static const Map<String, String> _tableLabels = {
    'stock_updates': 'Stock update',
    'purchases': 'Purchase',
    'sales': 'Sales',
    'b_grade_sales': 'B-grade sales',
    'dump_sales': 'Dump sale',
    'mandi_resales': 'Mandi resale',
    'rejection_received': 'Rejection received',
    'vendor_rejections': 'Vendor rejection',
  };

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
      final responses = await Future.wait([
        http.get(Uri.parse('$baseUrl/get_item_spelling_issues')),
        http.get(Uri.parse('$baseUrl/get_item_aliases')),
        http.get(Uri.parse('$baseUrl/get_items?distinct=1')),
      ]);
      for (final r in responses) {
        if (r.statusCode != 200) {
          throw Exception('Server error ${r.statusCode}: ${r.body}');
        }
      }
      final issues = jsonDecode(responses[0].body)['data'] as List;
      final aliases = jsonDecode(responses[1].body)['data'] as List;
      final items = jsonDecode(responses[2].body) as List;
      if (!mounted) return;
      setState(() {
        _issues = issues.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _aliases = aliases.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _items = items.map((e) => (e as Map)['name'].toString()).toList();
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

  List<Map<String, dynamic>> _issuesWithStatus(String status) =>
      _issues.where((e) => e['status'] == status).toList();

  String _tablesText(Map<String, dynamic> issue) {
    final tables = Map<String, dynamic>.from(issue['tables'] as Map? ?? {});
    return tables.entries
        .map((t) => '${_tableLabels[t.key] ?? t.key} ${t.value}')
        .join(' · ');
  }

  void _snack(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color),
    );
  }

  // ------------------------------------------------------------------
  // Convert
  // ------------------------------------------------------------------
  Future<void> _convert(Map<String, dynamic> issue) async {
    final fromName = issue['name'].toString();
    final suggestions = List<String>.from(issue['suggestions'] as List? ?? []);
    final preset = (issue['matched_item'] ?? (suggestions.isNotEmpty ? suggestions.first : '')).toString();

    final result = await showDialog<_ConvertRequest>(
      context: context,
      builder: (ctx) => _ConvertDialog(
        fromName: fromName,
        items: _items,
        suggestions: suggestions,
        initialItem: preset,
        isAutoMatched: issue['status'] == 'auto_matched',
      ),
    );
    if (result == null) return;

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/convert_item_spelling'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'from_name': fromName,
          'to_item': result.toItem,
          'admin_key': result.password,
          'rename_existing': result.renameExisting,
        }),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        final renamed = Map<String, dynamic>.from(body['renamed_rows'] as Map? ?? {});
        final count = renamed.values.fold<int>(0, (a, b) => a + (b as num).toInt());
        _snack(
          '${body['message']}${count > 0 ? ' · $count entries renamed' : ''}. Reports updated.',
          Colors.green,
        );
        await _load();
      } else {
        _snack(body['message']?.toString() ?? 'Convert failed', Colors.red);
      }
    } catch (e) {
      _snack('Convert failed: $e', Colors.red);
    }
  }

  Future<void> _removeAlias(Map<String, dynamic> alias) async {
    final password = await _askPassword(
      title: 'Remove spelling',
      message:
          "Entries written as '${alias['alias']}' will no longer be counted as '${alias['item']}'. "
          'Entries that were already renamed stay renamed.',
    );
    if (password == null) return;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/delete_item_alias'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'alias': alias['alias'], 'admin_key': password}),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        _snack('Spelling removed', Colors.green);
        await _load();
      } else {
        _snack(body['message']?.toString() ?? 'Remove failed', Colors.red);
      }
    } catch (e) {
      _snack('Remove failed: $e', Colors.red);
    }
  }

  Future<String?> _askPassword({required String title, required String message}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Admin password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Spellings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFilterBar(),
                    const Divider(height: 1),
                    Expanded(child: _buildList()),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load spellings:\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    final unmatched = _issuesWithStatus('unmatched').length;
    final auto = _issuesWithStatus('auto_matched').length;
    Widget chip(_SpellingFilter f, String label) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _filter == f,
            onSelected: (_) => setState(() => _filter = f),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _filterHelp(),
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              chip(_SpellingFilter.unmatched, 'Not counted ($unmatched)'),
              chip(_SpellingFilter.autoMatched, 'Capitals / spaces only ($auto)'),
              chip(_SpellingFilter.converted, 'Converted (${_aliases.length})'),
            ]),
          ),
        ],
      ),
    );
  }

  String _filterHelp() {
    switch (_filter) {
      case _SpellingFilter.unmatched:
        return 'These names are not in the Admin item list, so their entries are NOT counted '
            'in any Admin Report. Convert each one to the correct item.';
      case _SpellingFilter.autoMatched:
        return 'These differ from the item list only in capital letters or spaces. They are '
            'already counted in the report; converting just tidies the name in the entries.';
      case _SpellingFilter.converted:
        return 'Spellings you converted earlier. New entries written this way are counted '
            'under the item shown.';
    }
  }

  Widget _buildList() {
    if (_filter == _SpellingFilter.converted) {
      if (_aliases.isEmpty) return _empty('No converted spellings yet.');
      return ListView.separated(
        itemCount: _aliases.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final a = _aliases[i];
          return ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text("'${a['alias']}'  →  ${a['item']}"),
            subtitle: a['created_at'] != null ? Text('Converted ${a['created_at']}') : null,
            trailing: TextButton(
              onPressed: () => _removeAlias(a),
              child: const Text('Remove'),
            ),
          );
        },
      );
    }

    final status = _filter == _SpellingFilter.unmatched ? 'unmatched' : 'auto_matched';
    final list = _issuesWithStatus(status);
    if (list.isEmpty) {
      return _empty(status == 'unmatched'
          ? 'All entries match the item list.'
          : 'No capital / space differences found.');
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final issue = list[i];
        final suggestions = List<String>.from(issue['suggestions'] as List? ?? []);
        final hint = status == 'auto_matched'
            ? 'Counted as ${issue['matched_item']}'
            : (suggestions.isEmpty ? 'No close match found' : 'Did you mean: ${suggestions.join(', ')}?');
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                status == 'unmatched' ? Icons.error_outline : Icons.check_circle_outline,
                color: status == 'unmatched' ? Colors.orange.shade700 : Colors.green.shade600,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("'${issue['name']}'", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${issue['total_rows']} entries · ${_tablesText(issue)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    Text(hint, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _convert(issue),
                child: const Text('Convert'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
        ),
      );
}

class _ConvertRequest {
  final String toItem;
  final String password;
  final bool renameExisting;
  const _ConvertRequest(this.toItem, this.password, this.renameExisting);
}

class _ConvertDialog extends StatefulWidget {
  final String fromName;
  final List<String> items;
  final List<String> suggestions;
  final String initialItem;
  final bool isAutoMatched;

  const _ConvertDialog({
    required this.fromName,
    required this.items,
    required this.suggestions,
    required this.initialItem,
    required this.isAutoMatched,
  });

  @override
  State<_ConvertDialog> createState() => _ConvertDialogState();
}

class _ConvertDialogState extends State<_ConvertDialog> {
  // Plain search box + list inside the dialog (no pop-up overlay), which
  // avoids the Autocomplete overlay errors seen on Windows/Android.
  final _passwordController = TextEditingController();
  final _searchController = TextEditingController();
  late String _toItem;
  String _query = '';
  bool _renameExisting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _toItem = widget.initialItem.trim();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _validItem => widget.items.any((i) => i.trim() == _toItem.trim());

  void _pick(String item) {
    setState(() {
      _toItem = item.trim();
      _error = null;
    });
  }

  void _submit() {
    if (!_validItem) {
      setState(() => _error = 'Pick an item from the Admin item list');
      return;
    }
    if (_passwordController.text.isEmpty) {
      setState(() => _error = 'Enter the admin password');
      return;
    }
    Navigator.pop(
      context,
      _ConvertRequest(_toItem.trim(), _passwordController.text, _renameExisting),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final matches = (q.isEmpty
            ? widget.items
            : widget.items.where((i) => i.toLowerCase().contains(q)))
        .take(100)
        .toList();

    return AlertDialog(
      title: Text("Convert '${widget.fromName}'"),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Count these entries as:'),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _validItem ? Colors.green.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _validItem ? Colors.green.shade300 : Colors.grey.shade300),
                ),
                child: Text(
                  _validItem ? _toItem : 'No item selected',
                  style: TextStyle(fontWeight: FontWeight.w700, color: _validItem ? Colors.green.shade900 : Colors.grey.shade700),
                ),
              ),
              if (widget.suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: widget.suggestions
                      .map((s) => ActionChip(label: Text(s), onPressed: () => _pick(s)))
                      .toList(),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search the Admin item list',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 6),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: matches.isEmpty
                    ? const Center(child: Text('No matching item'))
                    : ListView.builder(
                        itemCount: matches.length,
                        itemBuilder: (ctx, i) {
                          final item = matches[i];
                          final selected = item.trim() == _toItem.trim();
                          return InkWell(
                            onTap: () => _pick(item),
                            child: Container(
                              color: selected ? Colors.indigo.shade50 : null,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(children: [
                                Expanded(child: Text(item)),
                                if (selected) Icon(Icons.check, size: 18, color: Colors.indigo.shade400),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Checkbox(
                  value: _renameExisting,
                  onChanged: widget.isAutoMatched
                      ? null
                      : (v) => setState(() => _renameExisting = v ?? true),
                ),
                const Expanded(
                  child: Text('Also rename existing entries (stock update, purchase, sales and other entry screens)',
                      style: TextStyle(fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 6),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Admin password',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        ElevatedButton(onPressed: _submit, child: const Text('CONVERT')),
      ],
    );
  }
}
