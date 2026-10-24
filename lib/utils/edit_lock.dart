import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_config.dart';

/// Headers for create / update / delete calls made outside Admin. The server
/// lets an existing entry be changed only when Admin has unlocked it
/// (Admin > Edit Permissions).
const Map<String, String> kDashboardEditHeaders = {
  'Content-Type': 'application/json',
  'X-Edit-Context': 'dashboard',
};

/// Tables that need an unlock from Admin before their entries can be changed
/// outside Admin.
const Set<String> kLockableTables = {
  'purchases',
  'packaging_materials',
  'sales',
  'b_grade_sales',
  'mandi_resales',
  'dump_sales',
  'lmd_data',
  'fmd_data',
};

/// null when the entries may be changed, else the message to show.
Future<String?> editLockMessage(String table, List<dynamic> ids) async {
  if (!kLockableTables.contains(table)) return null;
  try {
    final uri = Uri.parse('$baseUrl/edit_unlocks/check').replace(queryParameters: {
      'table': table,
      'ids': ids.map((e) => e.toString()).join(','),
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null; // server still checks on save
    final b = jsonDecode(res.body) as Map;
    return b['allowed'] == false ? (b['message']?.toString() ?? 'Locked - ask Admin to allow editing') : null;
  } catch (_) {
    return null;
  }
}

/// Shows the lock message; returns true when editing may go on.
Future<bool> ensureUnlocked(BuildContext context, String table, List<dynamic> ids) async {
  final msg = await editLockMessage(table, ids);
  if (msg == null) return true;
  if (!context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.lock_outline, color: Colors.orange),
      title: const Text('Locked'),
      content: Text(msg),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
  return false;
}

/// Server message of a failed call ("error" / "message"), or the status code.
String serverError(http.Response res) {
  try {
    final b = jsonDecode(res.body);
    if (b is Map) {
      final m = b['message'] ?? b['error'];
      if (m != null && m.toString().isNotEmpty) return m.toString();
    }
  } catch (_) {}
  return 'Server error ${res.statusCode}';
}
