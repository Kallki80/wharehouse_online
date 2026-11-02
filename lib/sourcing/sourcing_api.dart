import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api_config.dart';
import '../utils/device_auth.dart';

/// Staff side of Sourcing: every call carries the Sourcing password (the
/// farmer database holds bank details, so the server checks it).
class SourcingApi {
  static String? _key;

  /// Last answer of each screen: shown at once when the screen opens again,
  /// then refreshed in the background (no empty page while loading).
  static final Map<String, Map<String, dynamic>> _cache = {};
  static String _ck(String path, Map<String, String>? q) => '$path?${q ?? {}}';
  static Map<String, dynamic>? cached(String path, [Map<String, String>? q]) => _cache[_ck(path, q)];

  static Map<String, String> get _headers => {'Content-Type': 'application/json', 'X-Sourcing-Key': _key ?? ''};

  static bool get hasKey => _key != null;

  /// Asks the Sourcing password (Admin password also works) once per session.
  static Future<bool> ensureKey(BuildContext context) async {
    if (_key != null) return true;
    final c = TextEditingController();
    String? err;
    bool ok = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Sourcing password'),
          content: TextField(
            controller: c,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Password', errorText: err),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            TextButton(
              onPressed: () async {
                _key = c.text;
                try {
                  final r = await http.get(Uri.parse('$baseUrl/sourcing/items'), headers: _headers);
                  if (r.statusCode == 200) {
                    ok = true;
                    if (ctx.mounted) Navigator.pop(ctx);
                    return;
                  }
                  _key = null;
                  setD(() => err = r.statusCode == 401 ? 'Wrong password' : 'Server error ${r.statusCode}');
                } catch (e) {
                  _key = null;
                  setD(() => err = '$e');
                }
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    c.dispose();
    return ok;
  }

  static Future<Map<String, dynamic>> get(String path, [Map<String, String>? q]) async {
    final r = await http.get(Uri.parse('$baseUrl$path').replace(queryParameters: q), headers: _headers)
        .timeout(const Duration(seconds: 30));
    final b = _decode(r);
    if (_cache.length > 40) _cache.remove(_cache.keys.first); // keep memory small
    _cache[_ck(path, q)] = b;
    return b;
  }

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final r = await http.post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body));
    return _decode(r);
  }

  static Map<String, dynamic> _decode(http.Response r) {
    Map<String, dynamic> b;
    try {
      b = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    } catch (_) {
      throw Exception('Server error ${r.statusCode}');
    }
    if (r.statusCode == 401) _key = null;
    if (r.statusCode != 200) throw Exception(b['message'] ?? 'Server error ${r.statusCode}');
    return b;
  }

  static String imageUrl(String path) => '$baseUrl$path';

  /// Small (320 px) version for lists - full image only when opened.
  static String thumbUrl(String path) => '$baseUrl$path?thumb=1';
}

/// Farmer side: token from /farmer/login, kept on the phone.
class FarmerApi {
  static const _tokenKey = 'farmer_token';
  static const _nameKey = 'farmer_name';
  static String? token;
  static String? name;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      token = p.getString(_tokenKey);
      name = p.getString(_nameKey);
    } catch (_) {}
    DeviceAuth.farmerToken = token;
  }

  static Future<String?> login(String mobile, String password) async {
    final r = await http.post(Uri.parse('$baseUrl/farmer/login'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode({'mobile': mobile, 'password': password}));
    final b = jsonDecode(r.body) as Map;
    if (r.statusCode != 200 || b['success'] != true) return b['message']?.toString() ?? 'Login failed';
    token = b['token'].toString();
    DeviceAuth.farmerToken = token;
    name = (b['farmer'] as Map)['name']?.toString();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_tokenKey, token!);
      await p.setString(_nameKey, name ?? '');
    } catch (_) {}
    return null;
  }

  static Future<void> logout() async {
    try {
      await http.post(Uri.parse('$baseUrl/farmer/logout'), headers: {'X-Farmer-Token': token ?? ''});
    } catch (_) {}
    token = null;
    DeviceAuth.farmerToken = null;
    name = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_tokenKey);
      await p.remove(_nameKey);
    } catch (_) {}
  }

  static Map<String, String> get _headers => {'Content-Type': 'application/json', 'X-Farmer-Token': token ?? ''};

  static Future<Map<String, dynamic>> get(String path) async {
    final r = await http.get(Uri.parse('$baseUrl$path'), headers: _headers);
    return _decode(r);
  }

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final r = await http.post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body));
    return _decode(r);
  }

  static Map<String, dynamic> _decode(http.Response r) {
    Map<String, dynamic> b;
    try {
      b = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    } catch (_) {
      throw Exception('Server error ${r.statusCode}');
    }
    if (r.statusCode == 401) throw const FarmerLoggedOut();
    if (r.statusCode != 200) throw Exception(b['message'] ?? 'Server error ${r.statusCode}');
    return b;
  }
}

class FarmerLoggedOut implements Exception {
  const FarmerLoggedOut();
  @override
  String toString() => 'Please log in again';
}
