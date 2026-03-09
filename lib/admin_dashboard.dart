import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'api_config.dart';
import 'admin_login.dart';

enum AdminTableType {
  purchases, sales, stockUpdates, lmdData, fmdData,
  generatedPos, generatedSos, rejectionReceived, vendorRejections,
  dumpSales, mandiResales, bGradeSales, items, vendors,
  purchaseVendors, bGradeClients, productManagers,
}

String _getUpdateEndpoint(AdminTableType type) {
  switch (type) {
    case AdminTableType.purchases: return '/update_purchase';
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
    case AdminTableType.vendors: return '/update_vendor';
    case AdminTableType.purchaseVendors: return '/update_purchase_vendor';
    case AdminTableType.bGradeClients: return '/update_b_grade_client';
    case AdminTableType.productManagers: return '/update_product_manager';
  }
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  AdminTableType _selectedTable = AdminTableType.purchases;
  List<Map<String, dynamic>> _allData = [];
  List<Map<String, dynamic>> _filteredData = [];
  bool _isLoadingData = true;
  bool _isExporting = false;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _searchQuery;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _getEndpoint(AdminTableType type) {
    switch (type) {
      case AdminTableType.purchases: return '/get_all_purchases';
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
      case AdminTableType.vendors: return '/get_vendors_with_details';
      case AdminTableType.purchaseVendors: return '/get_purchase_vendors';
      case AdminTableType.bGradeClients: return '/get_b_grade_clients';
      case AdminTableType.productManagers: return '/get_product_managers';
    }
  }

  String _getTableName(AdminTableType type) {
    switch (type) {
      case AdminTableType.purchases: return 'purchases';
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
      case AdminTableType.vendors: return 'vendors';
      case AdminTableType.purchaseVendors: return 'purchase_vendors';
      case AdminTableType.bGradeClients: return 'b_grade_clients';
      case AdminTableType.productManagers: return 'product_managers';
    }
  }

  Future<List<Map<String, dynamic>>> _fetchData(AdminTableType type) async {
    final response = await http.get(Uri.parse('$apiBaseUrl${_getEndpoint(type)}'));
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded is! List) return [];
      return decoded.map((item) {
        if (item is Map) return Map<String, dynamic>.from(item);
        if (item is String) return {'id': item, 'name': item};
        return <String, dynamic>{};
      }).toList();
    }
    throw Exception('Failed to load data');
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoadingData = true);
    try {
      List<Map<String, dynamic>> data = await _fetchData(_selectedTable);
      if (!mounted) return;
      setState(() {
        _allData = data;
        _applyFilters();
        _isLoadingData = false;
      });
    } catch (e) {
      debugPrint("Error loading data: $e");
      if (mounted) setState(() => _isLoadingData = false);
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

  void _clearFilters() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _searchQuery = null;
      _applyFilters();
    });
  }

  Future<void> _deleteEntry(int id) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Confirm Delete"),
      content: Text("Delete entry ID: $id?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("DELETE")),
      ],
    ));
    if (confirmed == true) {
      final response = await http.delete(Uri.parse('$apiBaseUrl/delete_multiple_entries'),
        body: json.encode({'table_name': _getTableName(_selectedTable), 'ids': [id]}),
        headers: {'Content-Type': 'application/json'});
      if (response.statusCode == 200) {
        _loadData();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Deleted"), backgroundColor: Colors.green));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed"), backgroundColor: Colors.red));
      }
    }
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
              ids.add(row['id'] as int);
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
        final resp = await http.delete(Uri.parse('$apiBaseUrl/delete_multiple_entries'),
          body: json.encode({'table_name': _getTableName(_selectedTable), 'ids': ids}), headers: {'Content-Type': 'application/json'});
        if (resp.statusCode == 200) {
          _loadData();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${ids.length} deleted"), backgroundColor: Colors.green));
        }
      }
    });
  }

  Future<void> _exportToExcel() async {
    setState(() => _isExporting = true);
    try {
      final xl = excel.Excel.createExcel();
      final sheet = xl[xl.getDefaultSheet()!];
      if (_filteredData.isNotEmpty) {
        final hdrs = _filteredData.first.keys.toList();
        sheet.appendRow(hdrs.map((h) => excel.TextCellValue(h.toString())).toList());
        for (var row in _filteredData) {
          sheet.appendRow(hdrs.map((h) => excel.TextCellValue(row[h]?.toString() ?? '')).toList());
        }
      }
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        final f = '${_getTableName(_selectedTable)}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
        final fullPath = '${dir.path}/$f';
        File(fullPath).writeAsBytesSync(xl.save()!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved at: $fullPath'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isExporting = false);
    }
  }

  List<DataColumn> _getDataColumns() {
    if (_filteredData.isEmpty) return [const DataColumn(label: Text('No Data'))];
    
    // Get all unique keys from all rows to ensure consistency
    final Set<String> allKeys = {};
    for (var row in _filteredData) {
      allKeys.addAll(row.keys);
    }
    final keys = allKeys.toList();
    
    // Add Actions column
    final columns = keys.map((k) => DataColumn(label: Text(k.toString().replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)))).toList();
    columns.add(const DataColumn(label: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))));
    return columns;
  }

  Future<void> _editEntry(Map<String, dynamic> row) async {
    final id = row['id'] as int;
    final editableRow = Map<String, dynamic>.from(row);
    
    // Show edit dialog based on table type
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Edit ${_getTableName(_selectedTable)} - ID: $id"),
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
      
      // Remove non-editable fields
      updatedRow.remove('id');
      updatedRow.remove('so_id');
      updatedRow.remove('item_id');
      
      // Send update to API
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
    
    // Get all unique keys from all rows
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
      // Add edit and delete buttons
      cells.add(DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: const Icon(Icons.edit, size: 18, color: Colors.blue), onPressed: () => _editEntry(row)),
        IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () => _deleteEntry(row['id'] as int)),
      ])));
      return DataRow(cells: cells);
    }).toList();
  }

  // Method to show date range picker
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ADMIN DASHBOARD", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.indigo,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const AdminLogin()))),
        ],
      ),
      body: Column(children: [
        Container(height: 50, padding: const EdgeInsets.symmetric(vertical: 8), child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8),
          children: AdminTableType.values.map((t) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(label: Text(t.name.replaceAll(RegExp(r'([A-Z])'), ' \$1').trim().toUpperCase(), style: const TextStyle(fontSize: 10)),
              selected: _selectedTable == t, selectedColor: Colors.indigo.shade200, onSelected: (v) { if (v) { setState(() => _selectedTable = t); _loadData(); } }))).toList())),
        Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [
          Expanded(child: ElevatedButton.icon(icon: _isExporting ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.download, size: 18),
            label: const Text("EXCEL", style: TextStyle(fontSize: 10)), onPressed: _isExporting || _filteredData.isEmpty ? null : _exportToExcel, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white))),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.date_range, size: 18), label: const Text("DATE FILTER", style: TextStyle(fontSize: 10)), onPressed: _showDateRangePicker, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white))),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.delete, size: 18), label: const Text("DELETE", style: TextStyle(fontSize: 10)), onPressed: _deleteByDateRange, style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white))),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(
          decoration: InputDecoration(hintText: "Search...", prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onChanged: (v) { setState(() => _searchQuery = v); _applyFilters(); }
        )),
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text("Records: ${_filteredData.length}", style: const TextStyle(fontWeight: FontWeight.bold)),
          if (_startDate != null || _endDate != null || _searchQuery != null) TextButton(onPressed: _clearFilters, child: const Text("Clear")),
        ])),
        Expanded(child: _isLoadingData ? const Center(child: CircularProgressIndicator()) : _filteredData.isEmpty ? const Center(child: Text("No data")) :
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: SingleChildScrollView(child: DataTable(headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50), dataRowMinHeight: 40, dataRowMaxHeight: 60, columns: _getDataColumns(), rows: _getDataRows())))),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Use mobile app for add/edit"), backgroundColor: Colors.blue)); },
        backgroundColor: Colors.indigo, child: const Icon(Icons.add, color: Colors.white)),
    );
  }
}

