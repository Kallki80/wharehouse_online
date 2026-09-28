import 'dart:io';

import 'package:excel/excel.dart' as excel;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// Builds and saves admin Excel exports.
class AdminExcelExporter {
  AdminExcelExporter._();

  /// Builds the .xlsx bytes for [rows]. Headers are the union of all row keys
  /// (so rows added by later pages are not lost) and every cell is written as
  /// text, which keeps ids/numbers looking exactly like they do on screen.
  static List<int> buildBytes(
    List<Map<String, dynamic>> rows, {
    String sheetName = 'Sheet1',
  }) {
    final xl = excel.Excel.createExcel();
    final String targetName = sheetName.trim().isEmpty ? 'Sheet1' : sheetName.trim();
    // createExcel() always has a default sheet (usually 'Sheet1'); reuse the
    // existing name when it already matches to avoid a needless rename.
    final defaultSheet = xl.sheets.keys.firstOrNull ?? 'Sheet1';
    if (defaultSheet != targetName) {
      xl.rename(defaultSheet, targetName);
    }
    final sheet = xl[targetName];

    final headers = <String>[];
    for (final row in rows) {
      for (final key in row.keys) {
        if (!headers.contains(key)) headers.add(key);
      }
    }

    sheet.appendRow(headers.map((h) => excel.TextCellValue(h)).toList());
    for (final row in rows) {
      sheet.appendRow(
        headers.map((h) => excel.TextCellValue(row[h]?.toString() ?? '')).toList(),
      );
    }

    final bytes = xl.encode();
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Failed to build the Excel file');
    }
    return bytes;
  }

  /// Saves [rows] as an .xlsx file and returns the full path it was written to.
  static Future<String> exportRows({
    required List<Map<String, dynamic>> rows,
    required String filePrefix,
    String sheetName = 'Sheet1',
  }) async {
    final bytes = buildBytes(rows, sheetName: sheetName);
    final filename =
        '${filePrefix}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';

    Directory saveDir;
    try {
      final downloads = await getDownloadsDirectory();
      saveDir = downloads ?? await getApplicationDocumentsDirectory();
    } catch (_) {
      saveDir = await getApplicationDocumentsDirectory();
    }

    final file = File('${saveDir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
