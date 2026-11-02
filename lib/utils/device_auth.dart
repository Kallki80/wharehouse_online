import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api_config.dart';

/// Device login: a registered device gets a secret key from the server once
/// (Admin > Devices gives each device its own user name and password). The key
/// is attached to EVERY request in one central place ([KeyedHttpOverrides]),
/// so no screen needs to change and nobody types it again.
class DeviceAuth {
  static const _k = 'device_token';
  static const _n = 'device_name';
  static String? token;
  static String? name;

  /// farmer key, set by the farmer login (only opens the farmer pages)
  static String? farmerToken;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      token = p.getString(_k);
      name = p.getString(_n);
      farmerToken = p.getString('farmer_token');
    } catch (_) {}
  }

  /// null when logged in, else the message to show.
  static Future<String?> login(String username, String password) async {
    try {
      final r = await http.post(Uri.parse('$baseUrl/device/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username.trim(), 'password': password}));
      final b = jsonDecode(r.body) as Map;
      if (r.statusCode != 200 || b['success'] != true) return b['message']?.toString() ?? 'Login failed';
      token = b['token'].toString();
      name = b['device']?.toString();
      final p = await SharedPreferences.getInstance();
      await p.setString(_k, token!);
      await p.setString(_n, name ?? '');
      return null;
    } catch (e) {
      return 'Could not connect: $e';
    }
  }

  /// Admin login: the Admin password registers this device (first way in, so
  /// Admin can create device logins for the team). null = logged in, else the message.
  static Future<String?> adminLogin(String password, String deviceName) async {
    try {
      final r = await http.post(Uri.parse('$baseUrl/device/admin_login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'password': password, 'device_name': deviceName.trim()}));
      Map b = {};
      try {
        b = jsonDecode(r.body) as Map;
      } catch (_) {}
      if (r.statusCode == 404) return 'The server is older - install the new server file first';
      if (r.statusCode != 200 || b['success'] != true) return b['message']?.toString() ?? 'Login failed (${r.statusCode})';
      token = b['token'].toString();
      name = b['device']?.toString();
      final p = await SharedPreferences.getInstance();
      await p.setString(_k, token!);
      await p.setString(_n, name ?? '');
      return null;
    } catch (e) {
      return 'Could not connect: $e';
    }
  }

  static Future<void> logout() async {
    token = null;
    name = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_k);
      await p.remove(_n);
    } catch (_) {}
  }

  /// {registered, device, mode} from the server, or null when offline.
  static Future<Map<String, dynamic>?> status() async {
    try {
      final r = await http.get(Uri.parse('$baseUrl/device/status')).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    } catch (_) {
      return null;
    }
  }
}

/// Adds the device key (and a farmer's key) to every request the app makes.
class KeyedHttpOverrides extends HttpOverrides {
  final bool Function(X509Certificate cert, String host, int port)? badCertificate;
  KeyedHttpOverrides({this.badCertificate});

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final inner = super.createHttpClient(context);
    if (badCertificate != null) inner.badCertificateCallback = badCertificate;
    return _KeyedClient(inner);
  }
}

class _KeyedClient implements HttpClient {
  final HttpClient _c;
  _KeyedClient(this._c);

  Future<HttpClientRequest> _tag(Future<HttpClientRequest> f) => f.then((req) {
        final t = DeviceAuth.token;
        if (t != null && t.isNotEmpty) req.headers.set('X-Device-Token', t);
        final ft = DeviceAuth.farmerToken;
        if (ft != null && ft.isNotEmpty && req.headers.value('X-Farmer-Token') == null) {
          req.headers.set('X-Farmer-Token', ft);
        }
        return req;
      });

  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) => _tag(_c.open(method, host, port, path));
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => _tag(_c.openUrl(method, url));
  @override
  Future<HttpClientRequest> get(String host, int port, String path) => _tag(_c.get(host, port, path));
  @override
  Future<HttpClientRequest> getUrl(Uri url) => _tag(_c.getUrl(url));
  @override
  Future<HttpClientRequest> post(String host, int port, String path) => _tag(_c.post(host, port, path));
  @override
  Future<HttpClientRequest> postUrl(Uri url) => _tag(_c.postUrl(url));
  @override
  Future<HttpClientRequest> put(String host, int port, String path) => _tag(_c.put(host, port, path));
  @override
  Future<HttpClientRequest> putUrl(Uri url) => _tag(_c.putUrl(url));
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) => _tag(_c.delete(host, port, path));
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _tag(_c.deleteUrl(url));
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) => _tag(_c.patch(host, port, path));
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _tag(_c.patchUrl(url));
  @override
  Future<HttpClientRequest> head(String host, int port, String path) => _tag(_c.head(host, port, path));
  @override
  Future<HttpClientRequest> headUrl(Uri url) => _tag(_c.headUrl(url));

  @override
  bool get autoUncompress => _c.autoUncompress;
  @override
  set autoUncompress(bool v) => _c.autoUncompress = v;
  @override
  Duration? get connectionTimeout => _c.connectionTimeout;
  @override
  set connectionTimeout(Duration? v) => _c.connectionTimeout = v;
  @override
  Duration get idleTimeout => _c.idleTimeout;
  @override
  set idleTimeout(Duration v) => _c.idleTimeout = v;
  @override
  int? get maxConnectionsPerHost => _c.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? v) => _c.maxConnectionsPerHost = v;
  @override
  String? get userAgent => _c.userAgent;
  @override
  set userAgent(String? v) => _c.userAgent = v;
  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials credentials) => _c.addCredentials(url, realm, credentials);
  @override
  void addProxyCredentials(String host, int port, String realm, HttpClientCredentials credentials) =>
      _c.addProxyCredentials(host, port, realm, credentials);
  @override
  set authenticate(Future<bool> Function(Uri url, String scheme, String? realm)? f) => _c.authenticate = f;
  @override
  set authenticateProxy(Future<bool> Function(String host, int port, String scheme, String? realm)? f) =>
      _c.authenticateProxy = f;
  @override
  set badCertificateCallback(bool Function(X509Certificate cert, String host, int port)? callback) =>
      _c.badCertificateCallback = callback;
  @override
  set connectionFactory(Future<ConnectionTask<Socket>> Function(Uri url, String? proxyHost, int? proxyPort)? f) =>
      _c.connectionFactory = f;
  @override
  set findProxy(String Function(Uri url)? f) => _c.findProxy = f;
  @override
  set keyLog(Function(String line)? callback) => _c.keyLog = callback;
  @override
  void close({bool force = false}) => _c.close(force: force);
}
