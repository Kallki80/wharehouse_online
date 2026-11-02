import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';
import '../utils/device_auth.dart';

/// Admin > Devices
///  * a login (user name + password) for every phone / computer of the team
///  * switch a device off (lost phone, staff left) - it is locked out at once
///  * "Record only" (nobody is blocked, unknown devices are listed) or
///    "Block" (only registered devices and farmers can use the server)
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  static String? _adminKey; // kept while the app is open
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _r;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Map<String, String> get _h => {'Content-Type': 'application/json', 'X-Admin-Key': _adminKey ?? ''};

  Future<bool> _askKey() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Admin password'),
        content: TextField(controller: c, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Admin password')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok == true && c.text.isNotEmpty) _adminKey = c.text;
    c.dispose();
    return ok == true;
  }

  String _err(http.Response res) {
    try {
      final b = jsonDecode(res.body);
      if (b is Map && (b['message'] ?? b['error']) != null) return '${b['message'] ?? b['error']}';
    } catch (_) {}
    return 'Server error ${res.statusCode}';
  }

  Future<void> _load() async {
    if (_adminKey == null && !await _askKey()) {
      if (mounted) setState(() => _error = 'Admin password needed.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse('$baseUrl/devices'), headers: _h).timeout(const Duration(seconds: 20));
      if (res.statusCode == 403 || res.statusCode == 401) {
        _adminKey = null;
        throw Exception(_err(res));
      }
      if (res.statusCode != 200) throw Exception('${_err(res)} - is the new server file installed?');
      if (!mounted) return;
      setState(() => _r = Map<String, dynamic>.from(jsonDecode(res.body) as Map));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _post(String path, Map<String, dynamic> body) async {
    try {
      final res = await http.post(Uri.parse('$baseUrl$path'), headers: _h, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) return true;
      _snack(_err(res));
    } catch (e) {
      _snack('$e');
    }
    return false;
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _when(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? 'never' : DateFormat('dd-MM-yy HH:mm').format(d.toLocal());
  }

  Future<void> _edit([Map<String, dynamic>? d]) async {
    final name = TextEditingController(text: '${d?['name'] ?? ''}');
    final user = TextEditingController(text: '${d?['username'] ?? ''}');
    final pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(d == null ? 'New device login' : 'Edit ${d['name']}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Device name (e.g. Warehouse phone 1)')),
            TextField(controller: user, decoration: const InputDecoration(labelText: 'User name')),
            TextField(
              controller: pw,
              decoration: InputDecoration(labelText: d == null ? 'Password' : 'New password (blank = keep)'),
            ),
            if (d != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('A new password logs this device out - it must log in again.', style: TextStyle(fontSize: 11)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SAVE')),
        ],
      ),
    );
    if (ok == true) {
      final body = <String, dynamic>{'name': name.text.trim(), 'username': user.text.trim()};
      if (d != null) body['id'] = d['id'];
      if (pw.text.isNotEmpty) body['password'] = pw.text;
      if (await _post('/devices/save', body)) {
        _snack(d == null ? 'Device login created - log in with it on that device' : 'Saved');
        _load();
      }
    }
    name.dispose();
    user.dispose();
    pw.dispose();
  }

  Future<void> _delete(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${d['name']}?'),
        content: const Text('The device is logged out and its login removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('DELETE', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true && await _post('/devices/active', {'id': d['id'], 'active': false, 'delete': true})) _load();
  }

  Future<void> _setMode(String mode) async {
    if (mode == 'block') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.shield_outlined, color: Colors.red),
          title: const Text('Block unregistered devices?'),
          content: const Text('Only devices logged in with a device login (and farmers on their own page) can use the server. '
              'Check that every team phone and computer is registered first - see the list below.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('BLOCK', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (await _post('/devices/mode', {'mode': mode})) _load();
  }

  @override
  Widget build(BuildContext context) {
    final mode = '${_r?['mode'] ?? 'record'}';
    final devices = ((_r?['devices'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final unreg = ((_r?['unregistered'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
      ),
      floatingActionButton: _r == null ? null : FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Device')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(children: [
                Text(_error!, style: const TextStyle(color: Colors.red)),
                TextButton(onPressed: _load, child: const Text('TRY AGAIN')),
              ]),
            ),
          if (_r != null) ...[
            Card(
              color: mode == 'block' ? Colors.green.shade50 : Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(mode == 'block' ? 'Protected: only registered devices' : 'Record only: nobody is blocked yet',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    mode == 'block'
                        ? 'Unregistered phones / computers are refused. Farmers can only open their own page.'
                        : 'Devices without a login still work; they are listed below so you can register them. '
                            'When the list stays empty, switch to Block.',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'record', label: Text('Record only'), icon: Icon(Icons.visibility_outlined)),
                      ButtonSegment(value: 'block', label: Text('Block'), icon: Icon(Icons.shield_outlined)),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) => _setMode(s.first),
                  ),
                  if (DeviceAuth.token == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('This device is not registered - log it in with a device login before switching to Block.',
                          style: TextStyle(fontSize: 11, color: Colors.red)),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Text('Device logins (${devices.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (devices.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('None yet - tap + Device.')),
            for (final d in devices)
              Card(
                key: ValueKey('dev-${d['id']}'),
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Icon(Icons.phone_android, color: d['active'] == true || d['active'] == 1 ? Colors.green : Colors.grey),
                  title: Text('${d['name']}${DeviceAuth.name == d['name'] ? '  (this device)' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    'User: ${d['username']}\nLast used ${_when(d['last_seen'])}${d['last_ip'] != null ? ' · ${d['last_ip']}' : ''}'
                    ' · login ${_when(d['last_login'])}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  isThreeLine: true,
                  onTap: () => _edit(d),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(
                      value: d['active'] == true || d['active'] == 1,
                      onChanged: (v) async {
                        if (await _post('/devices/active', {'id': d['id'], 'active': v})) _load();
                      },
                    ),
                    IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(d)),
                  ]),
                ),
              ),
            const SizedBox(height: 12),
            Text('Unregistered access - last 7 days (${unreg.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
            const Text('Phones / computers that used the server without a device login.', style: TextStyle(fontSize: 11)),
            if (unreg.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('None.')),
            for (final u in unreg)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.help_outline, color: Colors.orange),
                  title: Text('${u['ip']}  ·  ${u['day']}'),
                  subtitle: Text('${u['requests']} request(s), last ${_when(u['last_at'])}\n${((u['screens'] as List?) ?? []).join(', ')}',
                      maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                ),
              ),
          ],
        ]),
      ),
    );
  }
}
