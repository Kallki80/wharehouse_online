import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'start_page.dart';
import 'utils/device_auth.dart';
import 'app_theme.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

Future<void> main() async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // every request carries this device's key (and a farmer's key) - one place for the whole app
  HttpOverrides.global = KeyedHttpOverrides(badCertificate: (cert, host, port) => true);
  WidgetsFlutterBinding.ensureInitialized();
  await DeviceAuth.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Warehouse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // Farmer or Shabari team first: farmers never reach the other sections
      home: const StartPage(),
    );
  }
}
