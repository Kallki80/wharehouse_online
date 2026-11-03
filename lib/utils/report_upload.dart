import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../api_config.dart';

/// Uploads a Sales / Purchase Report or Expense sheet in small pieces
/// (about 500 KB each), so a big Excel file is not refused by a proxy / network
/// limit in front of the server. Returns the server's answer as a map
/// (success, message, ...); never throws.
Future<Map<String, dynamic>> uploadReport({
  required String reportType, // sales | purchase | expense
  required String fileName,
  required List<int> bytes,
  void Function(int done, int total)? onProgress,
}) async {
  const pieceSize = 500 * 1024;
  final text = base64Encode(bytes);
  final total = max(1, (text.length / pieceSize).ceil());
  final key = '${DateTime.now().millisecondsSinceEpoch}${Random().nextInt(1 << 30)}';
  Map<String, dynamic> last = {'success': false, 'message': 'Upload failed'};
  for (var i = 0; i < total; i++) {
    final part = text.substring(i * pieceSize, min(text.length, (i + 1) * pieceSize));
    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$baseUrl/gpm/upload_chunk'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'upload_key': key,
              'index': i,
              'total': total,
              'report_type': reportType,
              'filename': fileName,
              'data': part,
            }),
          )
          .timeout(const Duration(minutes: 3));
    } catch (e) {
      return {'success': false, 'message': 'Upload failed (piece ${i + 1} of $total): $e'};
    }
    try {
      last = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    } catch (_) {
      final txt = res.body.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      return {
        'success': false,
        'message': res.statusCode == 404
            ? 'The server is older - install the new server file first'
            : 'Server error ${res.statusCode}${txt.isEmpty ? '' : ': ${txt.length > 160 ? txt.substring(0, 160) : txt}'}',
      };
    }
    if (res.statusCode != 200 || last['success'] != true) {
      if (res.statusCode == 404) last['message'] = 'The server is older - install the new server file first';
      return last;
    }
    onProgress?.call(i + 1, total);
  }
  return last;
}
