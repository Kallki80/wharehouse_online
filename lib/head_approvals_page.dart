import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Head Approvals
///
/// A second LMD entry for an SO (or a second FMD entry for a PO) is saved but
/// held here until the head approves or rejects it with the verification
/// password. Rejected entries are removed. The verification password is
/// separate from every section password and is never shown anywhere.
class HeadApprovalsPage extends StatefulWidget {
  const HeadApprovalsPage({super.key});

  @override
  State<HeadApprovalsPage> createState() => _HeadApprovalsPageState();
}

class _HeadApprovalsPageState extends State<HeadApprovalsPage> {
  bool _loading = true;
  String? _error;
  bool _passwordSet = true;
  bool _showDecided = false;
  List<Map<String, dynamic>> _items = [];

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
      final res = await Future.wait([
        http.get(Uri.parse('$baseUrl/verification/password_status')),
        http.get(Uri.parse('$baseUrl/verifications?status=${_showDecided ? 'all' : 'pending'}')),
      ]);
      if (res[1].statusCode != 200) throw Exception('Server error ${res[1].statusCode}');
      if (!mounted) return;
      setState(() {
        _passwordSet = jsonDecode(res[0].body)['is_set'] == true;
        _items = (jsonDecode(res[1].body)['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
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

  Future<void> _decide(Map<String, dynamic> v, String decision) async {
    final pw = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(decision == 'approve' ? 'Approve this entry?' : 'Reject and remove this entry?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: pw,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Verification password', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: decision == 'approve' ? Colors.green : Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(decision == 'approve' ? 'APPROVE' : 'REJECT'),
          ),
        ],
      ),
    );
    final password = pw.text;
    final noteText = note.text;
    pw.dispose();
    note.dispose();
    if (ok != true) return;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/verifications/decide'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': v['id'], 'decision': decision, 'password': password, 'note': noteText}),
      );
      final b = jsonDecode(res.body);
      _snack(b['message']?.toString() ?? 'Done', res.statusCode == 200 ? Colors.green : Colors.red);
      if (res.statusCode == 200) _load();
    } catch (e) {
      _snack('Failed: $e', Colors.red);
    }
  }

  Future<void> _setPassword() async {
    final first = !_passwordSet;
    final oldOrAdmin = TextEditingController();
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(first ? 'Set verification password' : 'Change verification password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            first
                ? 'One-time setup: the admin password is needed once. Choose a password only the head knows; it must differ from all section passwords.'
                : 'Enter the current verification password and the new one.',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: oldOrAdmin,
            obscureText: true,
            decoration: InputDecoration(
              labelText: first ? 'Admin password' : 'Current verification password',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(controller: p1, obscureText: true, decoration: const InputDecoration(labelText: 'New verification password', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: p2, obscureText: true, decoration: const InputDecoration(labelText: 'Repeat new password', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SAVE')),
        ],
      ),
    );
    final a = oldOrAdmin.text, n1 = p1.text, n2 = p2.text;
    oldOrAdmin.dispose();
    p1.dispose();
    p2.dispose();
    if (ok != true) return;
    if (n1 != n2) {
      _snack('The two new passwords are different', Colors.red);
      return;
    }
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/verification/set_password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'new_password': n1, if (first) 'admin_key': a else 'old_password': a}),
      );
      final b = jsonDecode(res.body);
      _snack(b['message']?.toString() ?? 'Done', res.statusCode == 200 ? Colors.green : Colors.red);
      if (res.statusCode == 200) _load();
    } catch (e) {
      _snack('Failed: $e', Colors.red);
    }
  }

  String _entrySummary(String type, Map<String, dynamic> e) {
    String v(String k) => (e[k] ?? '').toString();
    if (type == 'LMD') {
      return '${v('client_name')} · SO ${v('po_number')} · ${v('vehicle_number')} · ${v('driver_name')} · ₹${v('total_amount')} · ${v('ctrl_date').isNotEmpty ? v('ctrl_date') : v('date')}';
    }
    return '${v('vendor_name')} · PO ${v('po_number')} · ${v('items')} · ${v('vehicle_number')} · ₹${v('total_amount')} · ${v('ctrl_date').isNotEmpty ? v('ctrl_date') : v('date')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Head Approvals'),
        actions: [
          IconButton(icon: const Icon(Icons.key), tooltip: 'Verification password', onPressed: _setPassword),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load: $_error'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(12), children: [
                    if (!_passwordSet)
                      Card(
                        color: Colors.orange.shade50,
                        child: ListTile(
                          leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                          title: const Text('Verification password not set yet'),
                          subtitle: const Text('Tap to set it (needs the admin password once).'),
                          onTap: _setPassword,
                        ),
                      ),
                    Text(
                      'A second LMD entry for the same SO, or a second FMD entry for the same PO, waits here. '
                      'Approve to keep it, reject to remove it.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Show approved / rejected too'),
                      value: _showDecided,
                      onChanged: (v) {
                        setState(() => _showDecided = v);
                        _load();
                      },
                    ),
                    if (_items.isEmpty)
                      const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nothing waiting for approval.'))),
                    for (final v in _items) _card(v),
                  ]),
                ),
    );
  }

  Widget _card(Map<String, dynamic> v) {
    final type = v['type'].toString();
    final status = v['status'].toString();
    final entry = Map<String, dynamic>.from(v['entry'] as Map? ?? {});
    final existing = List<Map<String, dynamic>>.from((v['existing_entries'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
    final color = status == 'pending' ? Colors.orange.shade800 : status == 'approved' ? Colors.green.shade700 : Colors.red.shade700;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('Second $type entry for ${v['ref_type']} ${v['ref']}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            Text(status.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          ]),
          const SizedBox(height: 4),
          Text('Made ${v['created_at'] ?? ''}${v['decided_at'] != null ? ' · decided ${v['decided_at']}' : ''}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          const Text('New entry (on hold):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          Text(_entrySummary(type, entry), style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Text('Already entered (${existing.length}):', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          for (final e in existing) Text('• ${_entrySummary(type, e)}', style: const TextStyle(fontSize: 12)),
          if ((v['note'] ?? '').toString().isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('Note: ${v['note']}', style: const TextStyle(fontSize: 12))),
          if (status == 'pending') ...[
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40)),
                icon: const Icon(Icons.close, color: Colors.red),
                label: const Text('Reject'),
                onPressed: () => _decide(v, 'reject'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size(64, 40)),
                icon: const Icon(Icons.check),
                label: const Text('Approve'),
                onPressed: () => _decide(v, 'approve'),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
