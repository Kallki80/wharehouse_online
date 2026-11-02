import 'package:flutter/material.dart';

import 'sourcing_api.dart';
import 'sourcing_item_page.dart';

/// Sourcing: every item in stock (last 10 days, plus items already being
/// sourced) - farmers, specifications and the farmers' quotations per item.
class SourcingPage extends StatefulWidget {
  const SourcingPage({super.key});

  @override
  State<SourcingPage> createState() => _SourcingPageState();
}

class _SourcingPageState extends State<SourcingPage> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    final c = SourcingApi.cached('/sourcing/items');
    if (c != null) {
      _items = ((c['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    } else if (SourcingApi.hasKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    if (!SourcingApi.hasKey) {
      final ok = await SourcingApi.ensureKey(context);
      if (!ok) {
        if (mounted) setState(() => _error = 'Enter the Sourcing password to open this section.');
        return;
      }
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final b = await SourcingApi.get('/sourcing/items');
      if (!mounted) return;
      setState(() => _items = ((b['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
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

  @override
  Widget build(BuildContext context) {
    final items = _items.where((i) => _search.isEmpty || '${i['item']}'.toLowerCase().contains(_search)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sourcing'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
      ),
      body: !SourcingApi.hasKey && !_loading
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_outline, size: 40, color: Colors.grey),
                const SizedBox(height: 8),
                Text(_error ?? 'Farmer database, specifications and quotations'),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(minimumSize: const Size(64, 44)),
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Open Sourcing'),
                  onPressed: _load,
                ),
              ]),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
                TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search item', isDense: true),
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 8),
                if (_loading && _items.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                if (_loading && _items.isNotEmpty) const LinearProgressIndicator(minHeight: 2),
                if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                for (final i in items)
                  Card(
                    key: ValueKey('src-${i['item']}'),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text('${i['item']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${i['farmers']} farmer(s) · ${i['specs']} specification point(s) · ${i['open_quotes']} open quotation(s)'
                        '${i['best_rate'] != null ? '\nLowest: ₹${_n(i['best_rate'])}/${i['best_unit']} - ${i['best_farmer']}' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => SourcingItemPage(item: '${i['item']}')));
                        _load();
                      },
                    ),
                  ),
              ]),
            ),
    );
  }
}
