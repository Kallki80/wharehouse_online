import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home.dart';
import 'sourcing/farmer_pages.dart';
import 'sourcing/sourcing_api.dart';
import 'utils/device_auth.dart';

/// First screen: Farmer or Shabari team.
///  * Farmer      -> farmer login -> only his quotation page
///  * Shabari team -> team password once on this phone -> the whole app as before
///                   (each section still asks its own password)
/// A phone opens straight where it was last unlocked; "Lock app" (Profile) or a
/// farmer's log out brings this screen back.
class StartPage extends StatefulWidget {
  const StartPage({super.key});

  static const staffKey = 'staff_unlocked';

  /// Staff: lock the app again on this phone (the device login is needed again).
  static Future<void> lockApp(BuildContext context) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(staffKey);
    } catch (_) {}
    await DeviceAuth.logout();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true)
        .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const StartPage()), (_) => false);
  }

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    bool staff = false;
    try {
      final p = await SharedPreferences.getInstance();
      staff = p.getBool(StartPage.staffKey) ?? false;
    } catch (_) {}
    await FarmerApi.load();
    // registered device -> straight in; while the server is in "record only" mode
    // a phone opened earlier with the team password still gets in
    final st = DeviceAuth.token != null || staff ? await DeviceAuth.status() : null;
    if (!mounted) return;
    final registered = st?['registered'] == true;
    final offline = st == null;
    if (registered || (DeviceAuth.token != null && offline) || (staff && (offline || st['mode'] != 'block'))) {
      _go(const Home());
    } else if (FarmerApi.token != null) {
      _go(const FarmerHomePage());
    } else {
      if (DeviceAuth.token != null && !registered) await DeviceAuth.logout(); // switched off by Admin
      setState(() => _checking = false);
    }
  }

  void _go(Widget page) {
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero, // no delay when opening the app
    ));
  }

  /// Device login: user name + password Admin created for THIS device (once).
  Future<void> _staff() async {
    final u = TextEditingController();
    final c = TextEditingController();
    String? err;
    bool ok = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Shabari team - device login'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: u, autofocus: true, decoration: const InputDecoration(labelText: 'Device user name')),
            TextField(controller: c, obscureText: true, decoration: InputDecoration(labelText: 'Password', errorText: err)),
            const SizedBox(height: 8),
            const Text('Needed once on this device. Ask Admin for a device login (Admin > Devices).',
                style: TextStyle(fontSize: 11)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            TextButton(
              onPressed: () async {
                final e = await DeviceAuth.login(u.text, c.text);
                if (e == null) {
                  ok = true;
                  if (ctx.mounted) Navigator.pop(ctx);
                } else {
                  setD(() => err = e);
                }
              },
              child: const Text('OPEN'),
            ),
          ],
        ),
      ),
    );
    u.dispose();
    c.dispose();
    if (!ok) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(StartPage.staffKey, true);
    } catch (_) {}
    if (mounted) _go(const Home());
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
            const Icon(Icons.storefront, size: 56, color: Colors.indigo),
            const SizedBox(height: 8),
            const Text('Welcome', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
              icon: const Icon(Icons.agriculture),
              label: const Text('I AM A FARMER'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FarmerLoginPage())),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
              icon: const Icon(Icons.badge_outlined),
              label: const Text('SHABARI TEAM'),
              onPressed: _staff,
            ),
          ]),
        ),
      ),
    );
  }
}
