import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_config.dart';
import '../piece_weights_page.dart';

/// Admin › Item Settings
///
/// * Packaging: items marked here can only be entered in Packaging Material
///   Entry (and only their POs show there); all other items go through
///   Purchase Entry. Packaging is shown separately in GPM Analysis.
/// * Average weight per piece (kg): used by GPM Analysis to value papaya /
///   pineapple stock, which the Admin Report keeps in pieces.
class ItemSettingsPage extends StatefulWidget {
  const ItemSettingsPage({super.key});

  @override
  State<ItemSettingsPage> createState() => _ItemSettingsPageState();
}

class _ItemSettingsPageState extends State<ItemSettingsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String _search = '';
  bool _onlyMarked = false;
  String? _adminKey; // asked once while the page is open

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
      final res = await http.get(Uri.parse('$baseUrl/get_item_settings'));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      final data = jsonDecode(res.body)['data'] as List;
      if (!mounted) return;
      setState(() {
        _items = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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

  Future<String?> _getAdminKey() async {
    if (_adminKey != null) return _adminKey;
    final controller = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Admin password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Admin password', border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('OK')),
        ],
      ),
    );
    controller.dispose();
    return key;
  }

  Future<void> _save(Map<String, dynamic> item, Map<String, dynamic> change) async {
    final key = await _getAdminKey();
    if (key == null || key.isEmpty) return;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/update_item_settings'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'item': item['item'], 'admin_key': key, ...change}),
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        _adminKey = key;
        setState(() {
          item['is_packaging'] = body['is_packaging'];
          item['avg_piece_weight_kg'] = body['avg_piece_weight_kg'];
          if (body.containsKey('stock_in_pcs')) item['stock_in_pcs'] = body['stock_in_pcs'];
          if (body.containsKey('is_pcs_item')) item['is_pcs_item'] = body['is_pcs_item'];
          if (body['stock_in_pcs'] != null) item['needs_unit'] = false;
        });
        _snack('Saved: ${item['item']}', Colors.green);
      } else {
        if (res.statusCode == 403) _adminKey = null;
        _snack(body['message']?.toString() ?? 'Save failed', Colors.red);
      }
    } catch (e) {
      _snack('Save failed: $e', Colors.red);
    }
  }

  Future<void> _editWeight(Map<String, dynamic> item) async {
    final controller = TextEditingController(text: item['avg_piece_weight_kg']?.toString() ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Average weight of one ${item['item']}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Kg per piece (e.g. 1.2)',
            helperText: 'Used to value stock kept in pieces. Leave empty to clear.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('SAVE')),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    if (value.isNotEmpty && ((double.tryParse(value) ?? 0) <= 0)) {
      _snack('Enter a weight above 0', Colors.red);
      return;
    }
    await _save(item, {'avg_piece_weight_kg': value.isEmpty ? null : double.parse(value)});
  }

  void _snack(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final visible = _items.where((i) {
      if (q.isNotEmpty && !i['item'].toString().toLowerCase().contains(q)) return false;
      if (_onlyMarked && i['is_packaging'] != true && i['is_pcs_item'] != true && i['needs_unit'] != true) return false;
      return true;
    }).toList();
    final missingWeight = _items.where((i) => i['is_pcs_item'] == true && i['avg_piece_weight_kg'] == null).length;
    final needsUnit = _items.where((i) => i['needs_unit'] == true).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Settings'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.scale),
            label: const Text('Daily weights'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PieceWeightsPage())),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load items: $_error'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        'Mark packaging items (boxes, punnets, foam, nets...) so they are entered only in Packaging Material Entry. '
                        'Choose Kg or Pieces for how each item\'s stock is counted; for pieces, set a default weight per piece '
                        '(the daily weight entered in Daily weights is used first).',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                      ),
                    ),
                    if (needsUnit > 0)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text('$needsUnit new item(s): choose whether stock is counted in Kg or Pieces.',
                            style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
                      ),
                    if (missingWeight > 0)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text('$missingWeight piece-counted item(s) have no average weight yet.',
                            style: TextStyle(color: Colors.orange.shade900, fontSize: 13)),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search item',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => setState(() => _search = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Packaging / pieces / new'),
                          selected: _onlyMarked,
                          onSelected: (v) => setState(() => _onlyMarked = v),
                        ),
                      ]),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final item = visible[i];
                          final isPcs = item['is_pcs_item'] == true;
                          final w = item['avg_piece_weight_kg'];
                          return ListTile(
                            title: Text(item['item'].toString()),
                            subtitle: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              ChoiceChip(
                                label: const Text('Kg', style: TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                selected: !isPcs && item['needs_unit'] != true,
                                onSelected: (_) => _save(item, {'stock_in_pcs': false}),
                              ),
                              ChoiceChip(
                                label: const Text('Pieces', style: TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                selected: isPcs && item['needs_unit'] != true,
                                onSelected: (_) => _save(item, {'stock_in_pcs': true}),
                              ),
                              if (item['needs_unit'] == true)
                                Text('Choose Kg or Pieces', style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w600)),
                              TextButton.icon(
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                                icon: const Icon(Icons.scale, size: 16),
                                label: Text(
                                  w == null ? 'Set default weight / pc' : 'Default weight: $w kg / pc',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: (isPcs && w == null) ? Colors.orange.shade900 : null,
                                  ),
                                ),
                                onPressed: () => _editWeight(item),
                              ),
                            ]),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Text('Packaging', style: TextStyle(fontSize: 12)),
                              Switch(
                                value: item['is_packaging'] == true,
                                onChanged: (v) => _save(item, {'is_packaging': v}),
                              ),
                            ]),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
