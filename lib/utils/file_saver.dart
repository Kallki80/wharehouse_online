import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// One place for saving files the app creates (Excel exports).
///
/// * Android / iPhone: asks "Save to phone" (the phone's own Save screen, so
///   the user picks the folder, e.g. Downloads or Google Drive) or "Share"
///   (WhatsApp, email, Drive...).
/// * Windows / Mac / Linux: saves straight into the Downloads folder and
///   shows the full path.
///
/// Returns where the file went (path or name), or null if cancelled/failed.
Future<String?> saveOrShareFile(
  BuildContext context, {
  required List<int> bytes,
  required String fileName,
  String? note,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void snack(String text, Color color, {int seconds = 6}) {
    messenger?.showSnackBar(SnackBar(content: Text(text), backgroundColor: color, duration: Duration(seconds: seconds)));
  }

  final data = Uint8List.fromList(bytes);
  final extra = note == null || note.isEmpty ? '' : ' ($note)';

  if (kIsWeb) {
    snack('Saving files is not supported in the web version', Colors.red);
    return null;
  }

  // ---------------- Desktop ----------------
  if (io.Platform.isWindows || io.Platform.isMacOS || io.Platform.isLinux) {
    try {
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final file = io.File('${dir.path}${io.Platform.pathSeparator}$fileName');
      await file.writeAsBytes(data, flush: true);
      snack('Saved$extra:\n${file.path}', Colors.green, seconds: 8);
      return file.path;
    } catch (e) {
      snack('Could not save the file: $e', Colors.red);
      return null;
    }
  }

  // ---------------- Android / iPhone ----------------
  if (!context.mounted) return null;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('$fileName$extra', style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        ),
        ListTile(
          leading: const Icon(Icons.save_alt),
          title: const Text('Save to phone'),
          subtitle: const Text('Choose the folder, e.g. Downloads'),
          onTap: () => Navigator.pop(ctx, 'save'),
        ),
        ListTile(
          leading: const Icon(Icons.share),
          title: const Text('Share'),
          subtitle: const Text('WhatsApp, email, Google Drive...'),
          onTap: () => Navigator.pop(ctx, 'share'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (choice == null) return null;

  if (choice == 'save') {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Excel file',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: data,
      );
      if (result == null) return null; // cancelled
      snack('Saved: $fileName$extra', Colors.green);
      return result;
    } catch (e) {
      snack('Could not save the file: $e', Colors.red);
      return null;
    }
  }

  // share: write a temporary copy, then open the share screen
  try {
    final tmp = await getTemporaryDirectory();
    final file = io.File('${tmp.path}/$fileName');
    await file.writeAsBytes(data, flush: true);
    Rect? origin;
    if (context.mounted) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) origin = box.localToGlobal(Offset.zero) & box.size; // needed on iPad
    }
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', name: fileName)],
      subject: fileName,
      sharePositionOrigin: origin,
    );
    return fileName;
  } catch (e) {
    snack('Could not share the file: $e', Colors.red);
    return null;
  }
}
