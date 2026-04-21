import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../../api_config.dart';

enum AuthGroup {
  poSo('po_so'),
  inventory('inventory'),
  lmdFmd('lmd_fmd'),
  admin('admin');

  const AuthGroup(this.value);
  final String value;
}

class AuthManager {
  static const String _tokenPrefix = 'auth_token_';
  static const Duration _tokenExpiry = Duration(hours: 1);

  /// Verify password for group and get token
  static Future<bool> verifyGroupPassword({
    required AuthGroup group,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/verify_group_password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'group_name': group.value,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['valid'] == true) {
          await _storeToken(group);
          return true;
        }
      }
    } catch (e) {
      debugPrint('Auth verify error: $e');
    }
    return false;
  }

  /// Check if group access is valid (token exists and not expired)
  static Future<bool> hasValidAccess(AuthGroup group) async {
    final prefs = await SharedPreferences.getInstance();
    final tokenKey = _tokenPrefix + group.value;
    final tokenData = prefs.getString(tokenKey);
    
    if (tokenData == null) return false;

    try {
      final Map<String, dynamic> data = json.decode(tokenData);
      final expiry = DateTime.parse(data['expiry']);
      return expiry.isAfter(DateTime.now());
    } catch (e) {
      return false;
    }
  }

  /// Show password dialog and verify
  static Future<bool?> showPasswordDialog(
    BuildContext context, {
    required AuthGroup group,
    required String groupName,
  }) async {
    final passwordController = TextEditingController();
    
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Enter $groupName Password'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final success = await verifyGroupPassword(
                group: group,
                password: passwordController.text,
              );
              Navigator.pop(context, success);
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  /// Clear all tokens (admin logout)
  static Future<void> clearAllTokens() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_tokenPrefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// Private: Store token with expiry
  static Future<void> _storeToken(AuthGroup group) async {
    final prefs = await SharedPreferences.getInstance();
    final tokenKey = _tokenPrefix + group.value;
    final expiry = DateTime.now().add(_tokenExpiry).toIso8601String();
    
    await prefs.setString(tokenKey, json.encode({
      'group': group.value,
      'expiry': expiry,
    }));
  }
}
