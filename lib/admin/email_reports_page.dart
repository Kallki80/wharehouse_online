import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_config.dart';

/// Admin › Daily E-mail
///
/// Every day, once today's stock update is entered (= closing stock of the
/// previous control date) and the send time has passed, the Admin Report of all
/// items and the GPM of the previous control date are e-mailed as Excel files.
class EmailReportsPage extends StatefulWidget {
  const EmailReportsPage({super.key});

  @override
  State<EmailReportsPage> createState() => _EmailReportsPageState();
}

class _EmailReportsPageState extends State<EmailReportsPage> {
  bool _loading = true;
  bool _saving = false;
  bool _sending = false;
  String? _error;
  bool _enabled = false;
  bool _includeGpm = true;
  bool _useSsl = false;
  bool _passwordSet = false;
  String _sendAfter = '12:30';
  final _recipients = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _sender = TextEditingController();
  List<Map<String, dynamic>> _log = [];
  String? _adminKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_recipients, _host, _port, _user, _password, _sender]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse('$baseUrl/email_settings'));
      if (res.statusCode != 200) throw Exception('Server error ${res.statusCode}');
      final b = jsonDecode(res.body) as Map;
      final s = Map<String, dynamic>.from(b['settings'] as Map);
      if (!mounted) return;
      setState(() {
        _enabled = s['enabled'] == 1 || s['enabled'] == true;
        _includeGpm = s['include_gpm'] == 1 || s['include_gpm'] == true;
        _useSsl = s['use_ssl'] == 1 || s['use_ssl'] == true;
        _passwordSet = s['smtp_password_set'] == true;
        _sendAfter = (s['send_after'] ?? '12:30').toString();
        _recipients.text = ((s['recipients_list'] as List?) ?? []).join('\n');
        _host.text = (s['smtp_host'] ?? '').toString();
        _port.text = (s['smtp_port'] ?? '587').toString();
        _user.text = (s['smtp_user'] ?? '').toString();
        _sender.text = (s['sender_name'] ?? '').toString();
        _log = ((b['log'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
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

  Future<String?> _key() async {
    if (_adminKey != null) return _adminKey;
    final c = TextEditingController();
    final k = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Admin password'),
        content: TextField(
          controller: c,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Admin password'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
        ],
      ),
    );
    c.dispose();
    return (k == null || k.isEmpty) ? null : k;
  }

  void _snack(String t, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: c, duration: const Duration(seconds: 6)));
  }

  Future<void> _save() async {
    final key = await _key();
    if (key == null) return;
    setState(() => _saving = true);
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/email_settings'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'admin_key': key,
          'enabled': _enabled,
          'include_gpm': _includeGpm,
          'use_ssl': _useSsl,
          'recipients': _recipients.text,
          'send_after': _sendAfter,
          'smtp_host': _host.text.trim(),
          'smtp_port': int.tryParse(_port.text.trim()) ?? 587,
          'smtp_user': _user.text.trim(),
          'smtp_password': _password.text,
          'sender_name': _sender.text.trim(),
        }),
      );
      final b = jsonDecode(res.body) as Map;
      if (res.statusCode == 200 && b['success'] == true) {
        _adminKey = key;
        _password.clear();
        _snack('Saved', Colors.green);
        _load();
      } else {
        if (res.statusCode == 403) _adminKey = null;
        _snack(b['message']?.toString() ?? 'Save failed', Colors.red);
      }
    } catch (e) {
      _snack('Save failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendNow() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.subtract(const Duration(days: 1)),
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Control date to send',
    );
    if (picked == null) return;
    final key = await _key();
    if (key == null) return;
    setState(() => _sending = true);
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/email_reports/send_now'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'admin_key': key, 'date': DateFormat('yyyy-MM-dd').format(picked)}),
          )
          .timeout(const Duration(minutes: 3));
      final b = jsonDecode(res.body) as Map;
      if (res.statusCode == 200 && b['success'] == true) _adminKey = key;
      _snack(b['message']?.toString() ?? 'Done', res.statusCode == 200 ? Colors.green : Colors.red);
    } catch (e) {
      _snack('Send failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickTime() async {
    final parts = _sendAfter.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 12, minute: int.tryParse(parts.last) ?? 30),
    );
    if (t != null) {
      setState(() => _sendAfter = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
    }
  }

  Widget _section(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily E-mail'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load: $_error'))
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
                  Text(
                    'Every day, after today\'s stock update is entered (the closing stock of the previous control date) '
                    'and the send time has passed, the Admin Report of all items and the GPM of the previous control '
                    'date are e-mailed as Excel files.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  _section('Send', [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Send automatically every day'),
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Include GPM'),
                      subtitle: const Text('Uses the uploaded Sales Report - upload it before the send time', style: TextStyle(fontSize: 12)),
                      value: _includeGpm,
                      onChanged: (v) => setState(() => _includeGpm = v),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: Text('Not before $_sendAfter'),
                      subtitle: const Text('Sent when the stock is entered and this time has passed', style: TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.edit),
                      onTap: _pickTime,
                    ),
                    TextField(
                      controller: _recipients,
                      minLines: 3,
                      maxLines: 8,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Send to (one e-mail per line)',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ]),
                  _section('Sending e-mail account', [
                    Text(
                      'For Gmail: turn on 2-step verification, create an "App password" (Google Account > Security > '
                      'App passwords) and paste it here. Your normal Gmail password will not work.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    TextField(controller: _user, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Sender e-mail')),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'App password',
                        helperText: _passwordSet ? 'Saved - leave empty to keep it' : 'Not set yet',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(controller: _sender, decoration: const InputDecoration(labelText: 'Sender name')),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(flex: 3, child: TextField(controller: _host, decoration: const InputDecoration(labelText: 'SMTP server'))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(controller: _port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port')),
                      ),
                    ]),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('SSL (port 465)'),
                      value: _useSsl,
                      onChanged: (v) => setState(() => _useSsl = v),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: const Text('Save'),
                    onPressed: _saving ? null : _save,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                    label: const Text('Send now (choose a control date)'),
                    onPressed: _sending ? null : _sendNow,
                  ),
                  if (_log.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text('Recently sent', style: TextStyle(fontWeight: FontWeight.w700)),
                    for (final l in _log)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          l['status'] == 'sent' ? Icons.check_circle : (l['status'] == 'failed' ? Icons.error : Icons.hourglass_top),
                          color: l['status'] == 'sent' ? Colors.green : (l['status'] == 'failed' ? Colors.red : Colors.orange),
                        ),
                        title: Text('Control date ${l['control_date']} · ${l['status']}'),
                        subtitle: Text('${l['sent_at'] ?? ''}  ${l['message'] ?? ''}', style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ]),
    );
  }
}
