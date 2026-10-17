import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// LMD-FMD › Drivers & Vehicles
///
/// Saved drivers with their vehicle number. In LMD and FMD entry, picking a
/// driver fills in his vehicle number automatically.
class DriversPage extends StatefulWidget {
  const DriversPage({super.key});

  @override
  State<DriversPage> createState() => _DriversPageState();
}

class _DriversPageState extends State<DriversPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _saved = [];
  List<Map<String, dynamic>> _fromEntries = [];
  String _search = '';

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
      final res = await http.get(Uri.parse('$apiBaseUrl/drivers'));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      final b = jsonDecode(res.body) as Map;
      if (!mounted) return;
      setState(() {
        _saved = ((b['saved'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _fromEntries = ((b['from_entries'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
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

  void _snack(String t, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: c));
  }

  /// Add (driver == null) or edit a driver.
  Future<void> _edit({Map<String, dynamic>? driver, String? name, String? vehicle}) async {
    final nameC = TextEditingController(text: driver?['name']?.toString() ?? name ?? '');
    final vehC = TextEditingController(text: driver?['vehicle_number']?.toString() ?? vehicle ?? '');
    final typeC = TextEditingController(text: driver?['vehicle_type']?.toString() ?? '');
    final phoneC = TextEditingController(text: driver?['phone']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(driver == null ? 'Add driver' : 'Edit driver'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'Driver name *', prefixIcon: Icon(Icons.person)),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: vehC,
                decoration: const InputDecoration(labelText: 'Vehicle number *', prefixIcon: Icon(Icons.local_shipping)),
                textCapitalization: TextCapitalization.characters,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the vehicle number' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: typeC,
                decoration: const InputDecoration(labelText: 'Vehicle type (optional)', prefixIcon: Icon(Icons.category_outlined)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneC,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone (optional)', prefixIcon: Icon(Icons.phone)),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    final body = {
      'name': nameC.text.trim(),
      'vehicle_number': vehC.text.trim().toUpperCase(),
      'vehicle_type': typeC.text.trim(),
      'phone': phoneC.text.trim(),
      if (driver != null) 'old_name': driver['name'],
    };
    nameC.dispose();
    vehC.dispose();
    typeC.dispose();
    phoneC.dispose();
    if (ok != true) return;
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/drivers/save'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      final b = jsonDecode(res.body) as Map;
      if (res.statusCode == 200 && b['success'] == true) {
        _snack(b['message']?.toString() ?? 'Saved', Colors.green);
        _load();
      } else {
        _snack(b['message']?.toString() ?? 'Save failed', Colors.red);
      }
    } catch (e) {
      _snack('Save failed: $e', Colors.red);
    }
  }

  Future<void> _delete(Map<String, dynamic> driver) async {
    final pwC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Remove ${driver['name']}?"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('The driver is removed from the lists. Past LMD / FMD entries keep his name.',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: pwC,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'LMD / FMD password', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('REMOVE', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    final pw = pwC.text;
    pwC.dispose();
    if (ok != true) return;
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/drivers/delete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': driver['name'], 'password': pw}),
      );
      final b = jsonDecode(res.body) as Map;
      if (res.statusCode == 200 && b['success'] == true) {
        _snack(b['message']?.toString() ?? 'Removed', Colors.green);
        _load();
      } else {
        _snack(b['message']?.toString() ?? 'Could not remove', Colors.red);
      }
    } catch (e) {
      _snack('Could not remove: $e', Colors.red);
    }
  }

  bool _matches(Map<String, dynamic> d) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '${d['name']} ${d['vehicle_number'] ?? ''} ${(d['vehicles'] as List?)?.join(' ') ?? ''}'.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved.where(_matches).toList();
    final past = _fromEntries.where(_matches).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drivers & Vehicles'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.person_add),
        label: const Text('Add driver'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load drivers: $_error'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
                    Text(
                      'Save each driver with his vehicle number. In LMD and FMD entry, choosing the driver fills in '
                      'the vehicle number automatically.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search driver or vehicle'),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                    const SizedBox(height: 12),
                    Text('Saved drivers (${saved.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (saved.isEmpty)
                      const Padding(padding: EdgeInsets.all(16), child: Text('No drivers saved yet. Tap "Add driver".')),
                    for (final d in saved)
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(d['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text([
                            d['vehicle_number'] ?? '-',
                            if ((d['vehicle_type'] ?? '').toString().isNotEmpty) d['vehicle_type'],
                            if ((d['phone'] ?? '').toString().isNotEmpty) d['phone'],
                          ].join(' · ')),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _edit(driver: d)),
                            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _delete(d)),
                          ]),
                        ),
                      ),
                    if (past.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('From past entries - not saved yet (${past.length})',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Tap Save to keep the driver with his vehicle number.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      for (final d in past)
                        Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: Colors.grey.shade50,
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.history),
                            title: Text(d['name'].toString()),
                            subtitle: Text(
                              '${((d['vehicles'] as List?) ?? []).join(', ')} · ${d['entries']} entries',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: TextButton(
                              onPressed: () => _edit(
                                name: d['name'].toString(),
                                vehicle: ((d['vehicles'] as List?) ?? []).isNotEmpty
                                    ? (d['vehicles'] as List).first.toString()
                                    : null,
                              ),
                              child: const Text('SAVE'),
                            ),
                          ),
                        ),
                    ],
                  ]),
                ),
    );
  }
}
