import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
// SocketException
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'api_config.dart';
import 'admin_report.dart';
import 'auth/auth_manager.dart';
import 'admin_login.dart';
import 'admin/passwords_tab.dart';
import 'admin_add_item_dialog.dart';
import 'admin_simple_add_dialog.dart';

enum AdminTableType {
  purchases, packagingMaterials, sales, stockUpdates, lmdData, fmdData,
  generatedPos, generatedSos, rejectionReceived, vendorRejections,
  dumpSales, mandiResales, bGradeSales, items, clientList,
  purchaseVendors, bGradeClients, productManagers,
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

enum AdminTab { dashboard, passwords }

class _AdminDashboardState extends State<AdminDashboard> {
  AdminTab _currentTab = AdminTab.dashboard;
  AdminTableType _selectedTable = AdminTableType.purchases;
  List<Map<String, dynamic>> _allData = [];
  List<Map<String, dynamic>> _filteredData = [];
  bool _isLoadingData = true;
  bool _isExporting = false;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _searchQuery;

  static String _getEndpoint(AdminTableType type) {
    switch (type) {
      case AdminTableType.purchases: return '/get_all_purchases';
      case AdminTableType.packagingMaterials: return '/get_all_packaging_materials';
      case AdminTableType.sales: return '/get_all_sales';
      case AdminTableType.stockUpdates: return '/get_all_stock_updates';
      case AdminTableType.lmdData: return '/get_all_lmd_data';
      case AdminTableType.fmdData: return '/get_all_fmd_data';
      case AdminTableType.generatedPos: return '/get_all_generated_pos';
      case AdminTableType.generatedSos: return '/get_all_generated_sos_with_items';
      case AdminTableType.rejectionReceived: return '/get_all_rejection_received';
      case AdminTableType.vendorRejections: return '/get_all_vendor_rejections';
      case AdminTableType.dumpSales: return '/get_all_dump_sales';
      case AdminTableType.mandiResales: return '/get_all_mandi_resales';
      case AdminTableType.bGradeSales: return '/get_all_b_grade_sales';
      case AdminTableType.items: return '/get_items';
      case AdminTableType.clientList: return '/get_vendors_with_details';
      case AdminTableType.purchaseVendors: return '/get_purchase_vendors';
      case AdminTableType.bGradeClients: return '/get_b_grade_clients';
      case AdminTableType.productManagers: return '/get_product_managers';
    }
  }

  static String _getTableName(AdminTableType type) {
    switch (type) {
      case AdminTableType.purchases: return 'purchases';
      case AdminTableType.packagingMaterials: return 'packaging_materials';
      case AdminTableType.sales: return 'sales';
      case AdminTableType.stockUpdates: return 'stock_updates';
      case AdminTableType.lmdData: return 'lmd_data';
      case AdminTableType.fmdData: return 'fmd_data';
      case AdminTableType.generatedPos: return 'generated_pos';
      case AdminTableType.generatedSos: return 'generated_sos';
      case AdminTableType.rejectionReceived: return 'rejection_received';
      case AdminTableType.vendorRejections: return 'vendor_rejections';
      case AdminTableType.dumpSales: return 'dump_sales';
      case AdminTableType.mandiResales: return 'mandi_resales';
      case AdminTableType.bGradeSales: return 'b_grade_sales';
      case AdminTableType.items: return 'items';
      case AdminTableType.clientList: return 'vendors'; // FIXED: was 'client list' → SQL error
      case AdminTableType.purchaseVendors: return 'purchase_vendors';
      case AdminTableType.bGradeClients: return 'b_grade_clients';
      case AdminTableType.productManagers: return 'product_managers';
    }
  }

  static String _getUpdateEndpoint(AdminTableType type) {
    switch (type) {
      case AdminTableType.purchases: return '/update_purchase';
      case AdminTableType.packagingMaterials: return '/update_packaging_material';
      case AdminTableType.sales: return '/update_sale';
      case AdminTableType.stockUpdates: return '/update_stock_update';
      case AdminTableType.lmdData: return '/update_lmd_data';
      case AdminTableType.fmdData: return '/update_fmd_data';
      case AdminTableType.generatedPos: return '/update_po_item';
      case AdminTableType.generatedSos: return '/update_so';
      case AdminTableType.rejectionReceived: return '/update_rejection_received';
      case AdminTableType.vendorRejections: return '/update_vendor_rejection';
      case AdminTableType.dumpSales: return '/update_dump_sale';
      case AdminTableType.mandiResales: return '/update_mandi_resale';
      case AdminTableType.bGradeSales: return '/update_b_grade_sale';
      case AdminTableType.items: return '/update_item';
      case AdminTableType.clientList: return '/update_vendor';
      case AdminTableType.purchaseVendors: return '/update_purchase_vendor';
      case AdminTableType.bGradeClients: return '/update_b_grade_client';
      case AdminTableType.productManagers: return '/update_product_manager';
    }
  }

  static String? _getInsertEndpoint(AdminTableType type) {
    switch (type) {
      case AdminTableType.items:
        return '/insert_item';
      case AdminTableType.purchaseVendors:
        return '/insert_purchase_vendor';
      case AdminTableType.bGradeClients:
        return '/insert_b_grade_client';
      case AdminTableType.clientList:
        return '/insert_vendor';
      case AdminTableType.productManagers:
        return '/insert_product_manager';
      default:
        return null;
    }
  }


  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<List<Map<String, dynamic>>> _fetchData(AdminTableType type) async {
    final String endpoint = _getEndpoint(type);
    final String urlStr = '$apiBaseUrl$endpoint';
    final Uri url = Uri.parse(urlStr);
    debugPrint('AdminDashboard: Fetching $endpoint from: $urlStr');
    
    http.Response? response;
    int retryCount = 0;
    const maxRetries = 1;
    
    while (retryCount <= maxRetries) {
      try {
        response = await http.get(url).timeout(const Duration(seconds: 20));
        debugPrint('AdminDashboard: Response status: ${response.statusCode}');
        if (response.statusCode != 200) {
          debugPrint('AdminDashboard: Non-200 status: ${response.statusCode}, body preview: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
        }
        break;
      } catch (e) {
        debugPrint('AdminDashboard: HTTP request failed (attempt ${retryCount + 1}): $e');
        if (retryCount < maxRetries) {
          await Future.delayed(const Duration(seconds: 2));
          retryCount++;
        } else {
          rethrow;
        }
      }
    }
    
    if (response!.statusCode == 200) {
      try {
        final decoded = json.decode(response.body);
        debugPrint('AdminDashboard: Decoded data type: ${decoded.runtimeType}');
        List<dynamic> dataList;
        if (decoded is Map && decoded['data'] != null) {
          dataList = decoded['data'];
          debugPrint('AdminDashboard: Using paginated data, length: ${dataList.length}');
        } else if (decoded is List) {
          dataList = decoded;
        } else {
          debugPrint('AdminDashboard: Invalid response format: $decoded');
          return [];
        }
        List<Map<String, dynamic>> data = dataList.map((item) {
          if (item is Map) return Map<String, dynamic>.from(item);
          if (item is String) return {'id': item, 'name': item};
          return <String, dynamic>{};
        }).toList();
        
        if (type == AdminTableType.items) {
          final seenNames = <String>{};
          data = data.where((row) => seenNames.add(row['name'] ?? '')).toList();
        }
        debugPrint('AdminDashboard: Processed ${data.length} rows');
        return data;
      } catch (e) {
        debugPrint('AdminDashboard: JSON decode error: $e, body: ${response.body}');
        return [];
      }
    }
    throw Exception('HTTP ${response.statusCode}: ${response.body}');
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoadingData = true);
    try {
      debugPrint('AdminDashboard: Starting _loadData for table: ${_selectedTable.name}');
      List<Map<String, dynamic>> data = await _fetchData(_selectedTable);
      if (!mounted) return;
      debugPrint('AdminDashboard: _loadData success, data length: ${data.length}');
      setState(() {
        _allData = data;
        _applyFilters();
        _isLoadingData = false;
      });
    } catch (e) {
      debugPrint('AdminDashboard: _loadData FAILED: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      if (mounted) {
        setState(() => _isLoadingData = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load ${_selectedTable.name}: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _loadData,
            ),
          ),
        );
      }
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> data = List.from(_allData);
    if (_startDate != null && _endDate != null) {
      data = data.where((row) {
        try {
          final dateStr = row['date'] ?? row['ctrl_date'] ?? row['expected_date'] ?? row['date_of_dispatch'];
          if (dateStr == null) return false;
          final rowDate = DateTime.parse(dateStr.toString());
          return rowDate.isAfter(_startDate!.subtract(const Duration(days: 1))) && rowDate.isBefore(_endDate!.add(const Duration(days: 1)));
        } catch (e) { return false; }
      }).toList();
    }
    if (_searchQuery != null && _searchQuery!.isNotEmpty) {
      final query = _searchQuery!.toLowerCase();
      data = data.where((row) => row.values.any((val) => val?.toString().toLowerCase().contains(query) ?? false)).toList();
    }
    setState(() => _filteredData = data);
  }

  Future<void> _deleteEntry(dynamic identifier) async {
    String deleteMsg;
    Map<String, dynamic> requestBody;
    Uri deleteUri;

    if (_selectedTable == AdminTableType.purchaseVendors) {
      final vendorName = identifier.toString();
      if (vendorName.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid vendor name"), backgroundColor: Colors.red));
        return;
      }
      deleteMsg = 'Delete vendor: "$vendorName"?';
      deleteUri = Uri.parse('$apiBaseUrl/delete_purchase_vendor');
      // FIXED: Get password from separate dialog before delete
      final password = await _showDeletePasswordDialog(context);
      if (password == null) return; // Cancelled
      requestBody = {'name': vendorName, 'password': password};
    } else {
      // For many tables, backend expects string IDs (even if API returns them as string).
      final idStr = identifier.toString();
      final idInt = int.tryParse(idStr);

      if (idStr.trim().isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid ID"), backgroundColor: Colors.red));
        return;
      }

      // If it's a valid positive int, send as int (backend can handle ints).
      // Otherwise send as string to avoid failing when id is non-numeric.
      deleteMsg = idInt != null ? "Delete entry ID: $idInt?" : "Delete entry: $idStr?";
      deleteUri = Uri.parse('$apiBaseUrl/delete_multiple_entries');
      final idsPayload = idInt != null && idInt > 0 ? <dynamic>[idInt] : <dynamic>[idStr];
      requestBody = {'table_name': _getTableName(_selectedTable), 'ids': idsPayload};
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: Text(deleteMsg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("DELETE"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      debugPrint('🔥 DELETE DEBUG: $deleteUri | Body: ${json.encode(requestBody)}');
      
      try {
        final response = await http.delete(
          deleteUri,
          headers: {'Content-Type': 'application/json'},
          body: json.encode(requestBody),
        ).timeout(const Duration(seconds: 10)); // TIMEOUT ADDED
        
        debugPrint('🔥 DELETE RESPONSE: ${response.statusCode} | Body: ${response.body}');
        
        if (response.statusCode == 200) {
          _loadData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_selectedTable == AdminTableType.purchaseVendors 
                    ? "Vendor deleted successfully" 
                    : "Entry deleted"),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Server Error ${response.statusCode}: ${response.body.substring(0, 150)}"),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } on SocketException catch (e) {
        debugPrint('🔥 NETWORK ERROR: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ Server offline/unreachable. Start: python flask_api.py"),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
      } catch (e) {
        debugPrint('🔥 DELETE ERROR: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Delete failed: $e"), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<String?> _showDeletePasswordDialog(BuildContext context) async {
    final passwordController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Admin Password Required"),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: "Enter Password (1008)",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, passwordController.text),
            child: const Text("CONFIRM"),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteByDateRange() async {
    DateTime? s, e;
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (context, setDS) => AlertDialog(
      title: const Text("Delete by Date"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        OutlinedButton(
          onPressed: () async {
            final p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (p != null) setDS(() => s = p);
          },
          child: Text(s == null ? "Start Date" : DateFormat('dd/MM/yyyy').format(s!)),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            final p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (p != null) setDS(() => e = p);
          },
          child: Text(e == null ? "End Date" : DateFormat('dd/MM/yyyy').format(e!)),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
        ElevatedButton(onPressed: () { if (s != null && e != null) Navigator.pop(ctx, {'s': s, 'e': e}); }, child: const Text("SELECT")),
      ],
    ))).then((r) async {
      if (r == null) return;
      final ids = <int>[];
      for (var row in _allData) {
        try {
          final d = row['date'] ?? row['ctrl_date'] ?? row['expected_date'] ?? row['date_of_dispatch'];
          if (d != null) {
            final rd = DateTime.parse(d.toString());
            if (rd.isAfter(r['s'].subtract(const Duration(days: 1))) && rd.isBefore(r['e'].add(const Duration(days: 1)))) {
              final rawId = row['id'];
              if (rawId is int) {
                ids.add(rawId);
              } else {
                // If backend expects string IDs, use a stable hash fallback is not safe.
                // Instead, parse int if possible, otherwise skip this row.
                final parsed = int.tryParse(rawId?.toString() ?? '');
                if (parsed != null && parsed > 0) {
                  ids.add(parsed);
                }
              }
            }
          }
        } catch (_) { continue; }
      }
      if (ids.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data found"), backgroundColor: Colors.orange));
        return;
      }
      final cfm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text("Confirm"),
        content: Text("Delete ${ids.length} entries?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("DELETE ALL")),
        ],
      ));
      if (cfm == true) {
        debugPrint('🔥 BULK DELETE: ${_getTableName(_selectedTable)} | IDs: $ids');
        // Ensure we don't send empty list
        if (ids.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No IDs to delete'), backgroundColor: Colors.orange));
          }
          return;
        }
        try {
          final resp = await http.delete(
            Uri.parse('$apiBaseUrl/delete_multiple_entries'),
            body: json.encode({'table_name': _getTableName(_selectedTable), 'ids': ids}), 
            headers: {'Content-Type': 'application/json'}
          ).timeout(const Duration(seconds: 10));
          
          debugPrint('🔥 BULK RESPONSE: ${resp.statusCode} | ${resp.body}');
          
          if (resp.statusCode == 200) {
            _loadData();
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${ids.length} deleted"), backgroundColor: Colors.green));
          } else {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Bulk delete failed ${resp.statusCode}: ${resp.body}"), backgroundColor: Colors.red));
          }
        } on SocketException catch (e) {
          debugPrint('🔥 BULK NETWORK ERROR: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("❌ Server offline. Run: python flask_api.py"), backgroundColor: Colors.red)
          );
          }
        } catch (e) {
          debugPrint('🔥 BULK ERROR: $e');
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Bulk delete error: $e"), backgroundColor: Colors.red));
        }
      }
    });
  }

  Future<void> _exportToExcel() async {
    print('=== EXPORT START ===');
    print('Filtered data count: ${_filteredData.length}');
    setState(() => _isExporting = true);
    try {
      final xl = excel.Excel.createExcel();
      final sheet = xl[xl.getDefaultSheet()!];
      print('Excel sheet created: Sheet1');
      
      if (_filteredData.isNotEmpty) {
        print('Headers from first row: ${_filteredData.first.keys.toList()}');
        final hdrs = _filteredData.first.keys.toList();
        sheet.appendRow(hdrs.map((h) => excel.TextCellValue(h.toString())).toList());
        print('Headers added');
        
        for (int i = 0; i < _filteredData.length; i++) {
          final row = _filteredData[i];
          final rowData = hdrs.map((h) => excel.TextCellValue(row[h]?.toString() ?? '')).toList();
          sheet.appendRow(rowData);
          if (i % 10 == 0) print('Added row $i');
        }
        print('All ${_filteredData.length} rows added');
      } else {
        print('No data - empty export');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No data to export.'),
            backgroundColor: Colors.orange,
          ));
        }
        return;
      }

      final bytes = xl.save()!;
      print('Bytes length: ${bytes.length}');
      if (bytes.isEmpty) throw Exception('Failed to generate Excel file - bytes empty');

      final filename = '${_getTableName(_selectedTable)}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      print('Filename: $filename');

      try {
        // Try Downloads first
        final dir = await getDownloadsDirectory();
        Directory saveDir;
        if (dir != null) {
          saveDir = dir;
          print('Using Downloads: ${dir.path}');
        } else {
          // Fallback to Documents
          saveDir = await getApplicationDocumentsDirectory();
          print('Using Documents: ${saveDir.path}');
        }
        
        final fullPath = '${saveDir.path}/$filename';
        print('Full path: $fullPath');
        
        final file = File(fullPath);
        await file.writeAsBytes(bytes);
        print('File written successfully: ${file.existsSync()}');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Excel saved: $filename\\n$fullPath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 6),
          ));
        }
        print('=== EXPORT SUCCESS ===');
      } catch (saveError) {
        print('Save error: $saveError');
        throw Exception('Save failed: $saveError');
      }
    } catch (e) {
      print('Export ERROR: $e');
      print('Stack trace: ${StackTrace.current}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
      print('=== EXPORT END ===');
    }
  }

  List<DataColumn> _getDataColumns() {
    if (_filteredData.isEmpty) return [const DataColumn(label: Text('No Data'))];
    
    final Set<String> allKeys = {};
    for (var row in _filteredData) {
      allKeys.addAll(row.keys);
    }
    final keys = allKeys.toList();
    
    final columns = keys.map((k) => DataColumn(label: Text(k.toString().replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)))).toList();
    columns.add(const DataColumn(label: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))));
    return columns;
  }

  Future<void> _editEntry(Map<String, dynamic> row) async {
    // Some endpoints (like /get_items) may return rows without `id`.
    // Avoid crashing on tap.
    final dynamic rawId = row['id'];
    final int? idInt = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    final editableRow = Map<String, dynamic>.from(row);

    // If id missing, disable edit for that row.
    // (Backend update endpoints require `id`.)
    if (idInt == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Edit not available: missing id'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await showDialog(

      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Edit ${_getTableName(_selectedTable)} - ID: ${idInt ?? row['id'] ?? ''}"),

        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: editableRow.entries
                .where((e) => e.key != 'id' && e.key != 'so_id' && e.key != 'item_id')
                .map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: TextField(
                        controller: TextEditingController(text: e.value?.toString() ?? ''),
                        decoration: InputDecoration(
                          labelText: e.key.replaceAll('_', ' ').toUpperCase(),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (val) => editableRow[e.key] = val,
                      ),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, editableRow),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("SAVE"),
          ),
        ],
      ),
    ).then((updatedRow) async {
      if (updatedRow == null) return;
      
      // Keep `id` so backend can identify which row to update.
      updatedRow.remove('so_id');
      updatedRow.remove('item_id');
      
      
      try {
        final response = await http.put(
          Uri.parse('$apiBaseUrl${_getUpdateEndpoint(_selectedTable)}'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(updatedRow),
        );
        
        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Updated successfully"), backgroundColor: Colors.green),
            );
          }
          _loadData();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Update failed: ${response.body}"), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
          );
        }
      }
    });
  }

  List<DataRow> _getDataRows() {
    if (_filteredData.isEmpty) return [];
    
    final Set<String> allKeys = {};
    for (var row in _filteredData) {
      allKeys.addAll(row.keys);
    }
    final keys = allKeys.toList();
    
    return _filteredData.map((row) {
      final cells = <DataCell>[];
      for (var key in keys) {
        cells.add(DataCell(Text(row[key]?.toString() ?? '', style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)));
      }
        cells.add(DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: const Icon(Icons.edit, size: 18, color: Colors.blue), onPressed: () => _editEntry(row)),
        IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () {
          // Backend delete_multiple_entries expects `id` for most tables.
          // For `items` table, frontend list returns `name` only, so `row['id']` might be missing.
          // Fix: when selected table is `items`, prefer `row['id']` if present else use `row['name']`.
          final identifier = _selectedTable == AdminTableType.purchaseVendors
              ? (row['name'] ?? '')
              : (_selectedTable == AdminTableType.items
                  ? ((row['id']?.toString().isNotEmpty ?? false) ? row['id'].toString() : (row['name'] ?? ''))
                  : (row['id']?.toString() ?? ''));
          if (identifier.isNotEmpty) {
            _deleteEntry(identifier);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Missing ID/Name'), backgroundColor: Colors.red),
            );
          }
        }),
      ])));
      return DataRow(cells: cells);
    }).toList();
  }

  Future<void> _showDateRangePicker() async {
    DateTime? start = _startDate;
    DateTime? end = _endDate;
    
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          title: const Text("Select Date Range"),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            OutlinedButton(
              onPressed: () async {
                final p = await showDatePicker(
                  context: context,
                  initialDate: start ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (p != null) setDS(() => start = p);
              },
              child: Text(start == null ? "Select Start Date" : DateFormat('dd/MM/yyyy').format(start!)),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                final p = await showDatePicker(
                  context: context,
                  initialDate: end ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (p != null) setDS(() => end = p);
              },
              child: Text(end == null ? "Select End Date" : DateFormat('dd/MM/yyyy').format(end!)),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("CANCEL"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx, {'start': start, 'end': end});
              },
              child: const Text("APPLY"),
            ),
          ],
        ),
      ),
    ).then((result) {
      if (result != null && result['start'] != null && result['end'] != null) {
        setState(() {
          _startDate = result['start'];
          _endDate = result['end'];
          _applyFilters();
        });
      }
    });
  }

  void _clearFilters() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _searchQuery = null;
      _applyFilters();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${_currentTab == AdminTab.dashboard ? 'Dashboard' : 'Passwords'} - ADMIN", 
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.indigo,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _currentTab == AdminTab.dashboard ? _loadData : null,
            tooltip: 'Refresh Data',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthManager.clearAllTokens();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const AdminLogin()),
                );
              }
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.indigo),
              child: Text('Admin Menu', style: TextStyle(color: Colors.white, fontSize: 24)),
            ),

            

            ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text('Dashboard'),
              selected: _currentTab == AdminTab.dashboard,
              onTap: () {
                Navigator.pop(context);
                if (_currentTab != AdminTab.dashboard) {
                  setState(() => _currentTab = AdminTab.dashboard);
                }
              },
            ),

            ListTile(
              leading: Icon(Icons.table_rows_outlined,
                  color: Colors.indigo.shade400),
              title: const Text("Admin Report"),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdminReport(),
                  ),
                ).then((_) => _loadData());
              },
            ),
            
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Passwords'),
              selected: _currentTab == AdminTab.passwords,
              onTap: () {
                Navigator.pop(context);
                if (_currentTab != AdminTab.passwords) {
                  setState(() => _currentTab = AdminTab.passwords);
                }
              },
            ),

            
            
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () async {
                Navigator.pop(context);
                await AuthManager.clearAllTokens();
                if (mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const AdminLogin()),
                  );
                }
              },
            ),
          ],
        ),
      ),
      body: _currentTab == AdminTab.dashboard
          ? Column(children: [
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: AdminTableType.values.map((t) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(
                        t.name.replaceAllMapped(RegExp(r'[A-Z]'), (match) => ' ${match.group(0)}').trim().toUpperCase(),
                        style: const TextStyle(fontSize: 10),
                      ),
                      selected: _selectedTable == t,
                      selectedColor: Colors.indigo.shade200,
                      onSelected: (v) {
                        if (v) {
                          setState(() => _selectedTable = t);
                          _loadData();
                        }
                      },
                    ),
                  )).toList(),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: _isExporting 
                        ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download, size: 18),
                      label: const Text("EXCEL", style: TextStyle(fontSize: 10)),
                      onPressed: _isExporting || _filteredData.isEmpty ? null : _exportToExcel,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.date_range, size: 18),
                      label: const Text("DATE FILTER", style: TextStyle(fontSize: 10)),
                      onPressed: _showDateRangePicker,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.delete, size: 18),
                      label: const Text("DELETE", style: TextStyle(fontSize: 10)),
                      onPressed: _deleteByDateRange,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: "Search...",
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (v) {
                    setState(() => _searchQuery = v);
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Records: ${_filteredData.length}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (_startDate != null || _endDate != null || _searchQuery != null)
                      TextButton(onPressed: _clearFilters, child: const Text("Clear")),
                  ],
                ),
              ),
              Expanded(
                child: _isLoadingData
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredData.isEmpty
                    ? const Center(child: Text("No data"))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50),
                            dataRowMinHeight: 40,
                            dataRowMaxHeight: 60,
                            columns: _getDataColumns(),
                            rows: _getDataRows(),
                          ),
                        ),
                      ),
              ),
            ]
          ) : const PasswordsTab(),
floatingActionButton: (() {
            // 1) items: custom dialog (already exists)
            if (_selectedTable == AdminTableType.items) {
              return FloatingActionButton.extended(
                onPressed: () async {
                  final added = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => const AdminAddItemDialog(),
                  );
                  if (added == true) _loadData();
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Item'),
                backgroundColor: Colors.indigo,
              );
            }

            // 2) other simple tables: {name} + insert endpoint
            final insertEndpoint = _getInsertEndpoint(_selectedTable);
            if (insertEndpoint == null) return null;

            String title;
            switch (_selectedTable) {
              case AdminTableType.clientList:
                title = 'Add Client';
                break;
              case AdminTableType.purchaseVendors:
                title = 'Add Purchase Vendor';
                break;
              case AdminTableType.bGradeClients:
                title = 'Add B Grade Client';
                break;
              case AdminTableType.productManagers:
                title = 'Add Product Manager';
                break;
              default:
                title = 'Add';
            }

            return FloatingActionButton.extended(
              onPressed: () async {
                final added = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AdminSimpleAddDialog(
                    titleText: title,
                    insertEndpoint: insertEndpoint,
                  ),
                );
                if (added == true) _loadData();
              },
              icon: const Icon(Icons.add),
              label: Text(title),
              backgroundColor: Colors.indigo,
            );
          })(),
      bottomNavigationBar: null,
    );
  }
}

