import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as flutter;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as excel;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';

import 'purchase.dart';
import 'packaging_material.dart';
import 'stock_update.dart';
import 'b-grade_sales.dart';
import 'sales.dart';
import 'rejection_received.dart';
import 'vendor_rejection.dart';
import 'dump_sale.dart';
import 'mandi_resale.dart';
import 'check_inventory.dart';

import 'api_config.dart';


// Simple Debouncer class to handle search/filter delays
class Debouncer {
  final Duration duration;
  Timer? _timer;

  Debouncer({required this.duration});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }
  
  void cancel() {
    _timer?.cancel();
  }
}

enum TableType { purchase, packagingMaterial, stockUpdate, bGradeSales, sales, rejectionReceived, vendorRejection, dumpSale, mandiResale }

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  TableType _selectedTable = TableType.purchase;

  List<Map<String, dynamic>> _allData = [];
  List<Map<String, dynamic>> _filteredData = [];
  bool _isLoadingData = false;
  bool _isDriveExporting = false;
  static const String _authPassword = "1008";


  // ✅ ADD THESE (pagination + scroll)
  int _page = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();


  DateTime? _startDate, _endDate;
  String? _selectedItem, _selectedClientVendor, _poNumber, _pcs, _itemTag;

  DateTime? _tempStartDate, _tempEndDate;
  String? _tempSelectedItem, _tempSelectedClientVendor;
  final TextEditingController _poNumberController = TextEditingController();
  final TextEditingController _pcsController = TextEditingController();
  final TextEditingController _itemTagController = TextEditingController();

  List<String> _itemsForFilter = [];
  List<String> _clientsVendorsForFilter = [];
  late final Debouncer _filterDebouncer;

  @override
  void initState() {
    super.initState();

    _filterDebouncer = Debouncer(duration: const Duration(milliseconds: 500));
    _populateFilterOptions();

    // 🔥 initial load
    _loadData();

    // 🔥 scroll listener
    _scrollController.addListener(_onScroll);
  }


  // void _onScroll() {
  //   if (!_scrollController.hasClients) return;

  //   if (_scrollController.position.pixels >=
  //           _scrollController.position.maxScrollExtent - 200 &&
  //       !_isLoadingMore &&
  //       _hasMore) {
  //     _loadData(isLoadMore: true);
  //   }
  // }


  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadData(isLoadMore: true);
    }
  }

  @override
  void dispose() {

    _scrollController.removeListener(_onScroll); // ✅ safe cleanup
    _scrollController.dispose(); // ✅ memory leak fix

    _poNumberController.dispose();
    _pcsController.dispose();
    _itemTagController.dispose();
    _filterDebouncer.cancel();
    super.dispose();
  }

String _getGetAllEndpoint(TableType type) {
    switch (type) {
      case TableType.purchase:
        return '/get_all_purchases';
      case TableType.packagingMaterial:
        return '/get_all_packaging_materials';
      case TableType.stockUpdate:
        return '/get_all_stock_updates';
      case TableType.bGradeSales:
        return '/get_all_b_grade_sales';
      case TableType.sales:
        return '/get_all_sales';
      case TableType.rejectionReceived:
        return '/get_all_rejection_received';
      case TableType.vendorRejection:
        return '/get_all_vendor_rejections';
      case TableType.dumpSale:
        return '/get_all_dump_sales';
      case TableType.mandiResale:
        return '/get_all_mandi_resales';
    }
  }

  // Future<void> _loadData() async {
  //   if (!mounted) return;
  //   setState(() { _isLoadingData = true; _filteredData = []; });

  //   try {
  //     final endpoint = _getGetAllEndpoint(_selectedTable);
  //     final url = Uri.parse('$apiBaseUrl$endpoint');
  //     debugPrint("Fetching data from: $url");

  //     final response = await http.get(url).timeout(const Duration(seconds: 15));

  //     if (response.statusCode == 200) {
  //       final dynamic decoded = json.decode(response.body);
  //       if (decoded is List) {
  //         _allData = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
  //       } else {
  //         _allData = [];
  //       }
  //     } else {
  //       debugPrint("API Error: ${response.statusCode}");
  //       _allData = [];
  //     }

  //     if (mounted) _applyFilters();
  //   } catch (e) {
  //     debugPrint("Error loading data: $e");
  //     _allData = [];
  //     if (mounted) _applyFilters();
  //   } finally {
  //     if (mounted) setState(() { _isLoadingData = false; });
  //   }
  // }

  // Future<void> _loadData() async {
  //   if (!mounted) return;

  //   setState(() {
  //     _isLoadingData = true;
  //     _filteredData = [];
  //   });

  //   try {
  //     final endpoint = _getGetAllEndpoint(_selectedTable);
  //     final url = Uri.parse('$apiBaseUrl$endpoint');

  //     final response = await http.get(url).timeout(const Duration(seconds: 15));

  //     if (response.statusCode == 200) {
  //       final decoded = json.decode(response.body);

  //       // ✅ FIX HERE
  //       if (decoded is Map && decoded.containsKey('data')) {
  //         _allData = List<Map<String, dynamic>>.from(decoded['data']);
  //       } 
  //       else if (decoded is List) {
  //         _allData = List<Map<String, dynamic>>.from(decoded);
  //       } 
  //       else {
  //         _allData = [];
  //       }

  //       print("DATA LENGTH: ${_allData.length}");
  //     } else {
  //       _allData = [];
  //     }

  //     _applyFilters();
  //   } catch (e) {
  //     print("ERROR: $e");
  //     _allData = [];
  //     _applyFilters();
  //   } finally {
  //     if (mounted) {
  //       setState(() {
  //         _isLoadingData = false;
  //       });
  //     }
  //   }
  // }

  Future<void> _loadData({bool isLoadMore = false}) async {
    if (!mounted) return;

    // 🔥 LOAD MORE
    if (isLoadMore) {
      if (_isLoadingMore || !_hasMore) return;

      setState(() {
        _isLoadingMore = true;
      });
    }
    // 🔥 FRESH LOAD
    else {
      setState(() {
        _isLoadingData = true;
        _filteredData = [];
        _allData = []; // ✅ ADD THIS
        _page = 1;
        _hasMore = true;
      });
    }

    try {
      final endpoint = _getGetAllEndpoint(_selectedTable);

      final url = Uri.parse(
        '$apiBaseUrl$endpoint?page=$_page&limit=20'
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);

        List<Map<String, dynamic>> newData = [];

        if (decoded is Map && decoded.containsKey('data')) {
          newData = List<Map<String, dynamic>>.from(decoded['data']);
          _hasMore = decoded['has_more'] ?? false;
        }

        // 🔥 DATA APPEND / REPLACE
        if (isLoadMore) {
          _allData.addAll(newData);
        } else {
          _allData = newData;
        }

        // ✅ PAGE INCREMENT ONLY IF DATA AAYA
        if (newData.isNotEmpty) {
          _page++;
        }

        _applyFilters();
        debugPrint('Post-load: allData=${_allData.length}, filteredData=${_filteredData.length}');
      }
    } catch (e) {
      debugPrint('LoadData ERROR: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingData = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _populateFilterOptions() async {
    try {
      final results = await Future.wait([
        http.get(Uri.parse('$apiBaseUrl/get_items')),
        http.get(Uri.parse('$apiBaseUrl/get_vendors')),
        http.get(Uri.parse('$apiBaseUrl/get_purchase_vendors')),
        http.get(Uri.parse('$apiBaseUrl/get_b_grade_clients')),
      ]);

      if (!mounted) return;

      final List<String> items = [];
      final Set<String> clients = {};

      for (var response in results) {
        if (response.statusCode == 200) {
          final decoded = json.decode(response.body);
          if (decoded is List) {
            if (results.indexOf(response) == 0) {
              items.addAll(decoded.map((e) => e.toString()));
            } else {
              clients.addAll(decoded.map((e) => e.toString()));
            }
          }
        }
      }

      setState(() {
        _itemsForFilter = items..sort();
        _clientsVendorsForFilter = clients.toList()..sort();
      });
    } catch (e) {
      debugPrint("Error populating filters: $e");
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> data = List.from(_allData);
    if (_startDate != null && _endDate != null) {
      data = data.where((row) {
        try {
          final dateStr = row['date'] ?? row['ctrl_date'] ?? row['created_at'] ?? row['entry_date'];
          if (dateStr == null) return false;
          
          final rowDate = DateTime.parse(dateStr.toString());
          DateTime start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
          DateTime end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
          DateTime current = DateTime(rowDate.year, rowDate.month, rowDate.day);
          
          return (current.isAtSameMomentAs(start) || current.isAfter(start)) && 
                 (current.isAtSameMomentAs(end) || current.isBefore(end));
        } catch (e) { return false; }
      }).toList();
    }
    
    if (_selectedItem != null) data = data.where((row) => row['item'] == _selectedItem).toList();
    if (_selectedClientVendor != null) data = data.where((row) => (row['vendor'] == _selectedClientVendor) || (row['clint'] == _selectedClientVendor) || (row['client_name'] == _selectedClientVendor)).toList();
    if (_poNumber != null && _poNumber!.isNotEmpty) data = data.where((row) => row['po_number']?.toString().contains(_poNumber!) ?? false).toList();
    if (_pcs != null && _pcs!.isNotEmpty) data = data.where((row) => row['pcs']?.toString() == _pcs).toList();
    if (_itemTag != null && _itemTag!.isNotEmpty) data = data.where((row) => row['item_tag']?.toString().contains(_itemTag!) ?? false).toList();
    
    if (mounted) setState(() { _filteredData = data; });
  }

  List<DataRow> _prepareTableRows() {
    if (_filteredData.isEmpty) return [];

    if (_selectedTable == TableType.purchase || _selectedTable == TableType.sales || _selectedTable == TableType.rejectionReceived || _selectedTable == TableType.bGradeSales || _selectedTable == TableType.dumpSale || _selectedTable == TableType.mandiResale) {
      Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var row in _filteredData) {
        final rawDate = row['date'] ?? row['ctrl_date'] ?? row['created_at'] ?? row['entry_date'];
        String dKey = 'no_date';
        if (rawDate != null) {
          try {
            dKey = DateFormat('yyyy-MM-dd').format(DateTime.parse(rawDate.toString()));
          } catch (e) {}
        }
        String key = "${row['po_number']}_${row['clint'] ?? row['vendor'] ?? row['client_name']}_$dKey";
        grouped.putIfAbsent(key, () => []).add(row);
      }
      return grouped.entries.map((e) => _buildGroupedRow(e.key, e.value)).toList();
    }
    return _filteredData.map((row) => DataRow(cells: _buildCells(row))).toList();
  }

  void _clearAllFilters() {
    setState(() { 
      _startDate = _endDate = _selectedItem = _selectedClientVendor = _poNumber = _pcs = _itemTag = null; 
      _poNumberController.clear(); _pcsController.clear(); _itemTagController.clear();
      _tempStartDate = _tempEndDate = _tempSelectedItem = _tempSelectedClientVendor = null;
    });
    _applyFilters();
  }

  void _resetTempFilters() {
    _tempStartDate = _startDate; _tempEndDate = _endDate;
    _tempSelectedItem = _selectedItem; _tempSelectedClientVendor = _selectedClientVendor;
    _poNumberController.text = _poNumber ?? ''; _pcsController.text = _pcs ?? '';
    _itemTagController.text = _itemTag ?? '';
  }

  Future<bool> _checkAuth() async {
    String entered = "";
    return await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Authentication Required"),
        content: TextField(obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "Enter Password"), onChanged: (v) => entered = v),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, entered == _authPassword), child: const Text("VERIFY")),
        ],
      ),
    ) ?? false;
  }

  Future<ServiceAccountCredentials> _loadCredentials() async {
    final jsonString = await flutter.rootBundle.loadString('assets/service_account_key.json');
    final jsonContent = json.decode(jsonString);
    return ServiceAccountCredentials.fromJson(jsonContent);
  }

  Future<void> uploadFileToDrive(List<int> fileBytes, String fileName, String folderId) async {
    try {
      final credentials = await _loadCredentials();
      final client = await clientViaServiceAccount(credentials, [drive.DriveApi.driveScope]);
      final driveApi = drive.DriveApi(client);
      
      // Create in-memory stream for upload
      final stream = Stream<List<int>>.value(fileBytes);
      final length = fileBytes.length;
      
      var fileMetadata = drive.File()
        ..name = fileName
        ..parents = [folderId];
        
      await driveApi.files.create(
        fileMetadata,
        uploadMedia: drive.Media(stream, length),
      );
      
      debugPrint('✅ Uploaded $fileName to Drive (size: ${length ~/ 1024} KB)');
    } catch (e) {
      debugPrint('Drive upload failed: $e');
      throw Exception("Failed to upload to Google Drive: $e");
    }
  }

  void _handleDelete(int id) async {
    if (await _checkAuth()) {
      final response = await http.delete(
        Uri.parse('$apiBaseUrl/delete_multiple_entries'),
        body: json.encode({'table_name': _getTableNameFromEnum(), 'ids': [id]}),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        _loadData();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Entry Deleted")));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to delete entry"), backgroundColor: Colors.red));
      }
    }
  }

  void _handleGroupDelete(String label, List<int> ids) async {
    if (await _checkAuth()) {
      bool confirm = await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Confirm Delete"),
          content: Text("Delete entire group for: $label?\n(${ids.length} items will be removed)"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("DELETE ALL", style: TextStyle(color: Colors.white))),
          ],
        ),
      ) ?? false;

      if (confirm) {
        final response = await http.delete(
          Uri.parse('$apiBaseUrl/delete_multiple_entries'),
          body: json.encode({'table_name': _getTableNameFromEnum(), 'ids': ids}),
          headers: {'Content-Type': 'application/json'},
        );
        if (response.statusCode == 200) {
          _loadData();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Group Deleted Successfully")));
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to delete group"), backgroundColor: Colors.red));
        }
      }
    }
  }

  void _handleEdit(Map<String, dynamic> row) async {
    if (await _checkAuth()) {
      final controllers = <String, TextEditingController>{};
      row.forEach((key, value) {
        if (key != 'id') {
          controllers[key] = TextEditingController(text: value?.toString() ?? '');
        }
      });

      void calculateRelatedValues(StateSetter setDialogState) {
        if (_selectedTable == TableType.purchase || _selectedTable == TableType.sales || _selectedTable == TableType.bGradeSales) {
          double qty = double.tryParse(controllers['quantity']?.text ?? controllers['qty_receive']?.text ?? '0') ?? 0.0;
          double rate = double.tryParse(controllers['rate']?.text ?? '0') ?? 0.0;
          
          if (controllers.containsKey('total_value')) {
            double total = qty * rate;
            controllers['total_value']!.text = total.toStringAsFixed(2);
            
            double paid = double.tryParse(controllers['amount_paid']?.text ?? '0') ?? 0.0;
            double due = total - paid;
            controllers['amount_due']?.text = due.toStringAsFixed(2);
            
            String status = 'Unpaid';
            if (total > 0) {
              if (paid >= total) {
                status = 'Paid';
              } else if (paid > 0) status = 'Partial Paid';
            }
            controllers['payment_status']?.text = status;
          }
        } else if (_selectedTable == TableType.stockUpdate) {
          double a = double.tryParse(controllers['a_grade_qty']?.text ?? '0') ?? 0.0;
          double b = double.tryParse(controllers['b_grade_qty']?.text ?? '0') ?? 0.0;
          double c = double.tryParse(controllers['c_grade_qty']?.text ?? '0') ?? 0.0;
          double u = double.tryParse(controllers['ungraded_qty']?.text ?? '0') ?? 0.0;
          double d = double.tryParse(controllers['dump_qty']?.text ?? '0') ?? 0.0;
          controllers['total_qty']?.text = (a + b + c + u + d).toStringAsFixed(2);
        }
        setDialogState(() {});
      }

      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text("Edit ${_selectedTable.name.toUpperCase()}"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: Map<String, TextEditingController>.from(controllers).length > 5 ? MainAxisSize.max : MainAxisSize.min,
                children: controllers.entries.map<Widget>((e) {
                  final String key = e.key;
                  final TextEditingController ctrl = e.value;
                  bool isAuto = (key == 'amount_due' || key == 'payment_status' || key == 'total_qty' || key == 'total_value');

                  if (key == 'item' || key == 'item_name') {
                    return _buildEditDropdown(key, ctrl, _itemsForFilter, setDialogState, calculateRelatedValues);
                  }
                  if (key == 'vendor' || key == 'clint' || key == 'client_name' || key == 'product_manager' || key == 'vendor_name') {
                    return _buildEditDropdown(key, ctrl, _clientsVendorsForFilter, setDialogState, calculateRelatedValues);
                  }
                  if (key == 'payment_status') {
                    return _buildEditDropdown(key, ctrl, ["Unpaid", "Paid", "Partial Paid"], setDialogState, calculateRelatedValues);
                  }
                  if (key == 'date' || key == 'ctrl_date') {
                    return _buildEditDateField(key, ctrl, context, setDialogState);
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: TextField(
                      controller: ctrl,
                      decoration: InputDecoration(
                        labelText: key.replaceAll('_', ' ').toUpperCase(),
                        border: const OutlineInputBorder(),
                        filled: isAuto,
                        fillColor: isAuto ? Colors.grey.shade100 : null,
                        suffixIcon: isAuto ? const Icon(Icons.auto_fix_high, size: 16, color: Colors.blueGrey) : null,
                      ),
                      readOnly: isAuto,
                      keyboardType: (row[key] is num) ? TextInputType.number : TextInputType.text,
                      onChanged: (_) => calculateRelatedValues(setDialogState),
                    ),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final updated = <String, dynamic>{'id': row['id']};
                    controllers.forEach((key, ctrl) {
                      updated[key] = double.tryParse(ctrl.text) ?? double.tryParse(row[key]?.toString() ?? '0') ?? 0.0;
                      if (row[key] is int) {
                        updated[key] = int.tryParse(ctrl.text) ?? int.tryParse(row[key]?.toString() ?? '0') ?? 0;
                      } else {
                        updated[key] = ctrl.text.isEmpty ? null : ctrl.text;
                      }
                    });

                    final endpoint = _getUpdateEndpoint(_selectedTable);
                    final resp = await http.put(
                      Uri.parse('$apiBaseUrl$endpoint'),
                      headers: {'Content-Type': 'application/json'},
                      body: json.encode({'data': updated}),
                    );
                    debugPrint('Edit API Response [${resp.statusCode}]: ${resp.body}');
                    debugPrint('Updated row ID: ${updated['id']}');

                    if (resp.statusCode == 200) {
                      _loadData();
                      if (mounted) Navigator.pop(ctx);
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Updated Successfully")));
                    } else {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Update Failed"), backgroundColor: Colors.red));
                    }
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                  }
                },
                child: const Text("SAVE CHANGES"),
              ),
            ],
          ),
        ),
      );
    }
  }


  Map<String, TextEditingController> _createEmptyControllersFromSample(
    Map<String, dynamic> sampleRow) {

    final controllers = <String, TextEditingController>{};

    sampleRow.forEach((key, value) {
      if (key != 'id') {
        controllers[key] = TextEditingController(text: '');
      }
    });

    return controllers;
  }


  void _handleEditGroup(List<Map<String, dynamic>> items) async {
    if (!(await _checkAuth())) return;

    List<Map<String, TextEditingController>> controllersList = [];

    for (var row in items) {
      final controllers = <String, TextEditingController>{};

      row.forEach((key, value) {
        if (key != 'id') {
          controllers[key] = TextEditingController(
            text: value?.toString() ?? '',
          );
        }
      });

      controllersList.add(controllers);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("Edit All Items"),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: controllersList.length,
                itemBuilder: (context, index) {
                  final controllers = controllersList[index];

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Text("Item ${index + 1}",
                              style: const TextStyle(fontWeight: FontWeight.bold)),

                          ...controllers.entries.map((e) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: TextField(
                                controller: e.value,
                                decoration: InputDecoration(
                                  labelText: e.key,
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            );
                          }),

                          // ❌ Remove item
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                controllersList.removeAt(index);
                                setDialogState(() {});
                              },
                            ),
                          )
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            actions: [
              // ✅ ADD MORE ITEM
              TextButton(
                onPressed: () {
                  // controllersList.add({});
                  controllersList.add(
                    _createEmptyControllersFromSample(items.first)
                  );
                  setDialogState(() {});
                },
                child: const Text("➕ Add More"),
              ),

              ElevatedButton(
                onPressed: () async {
                  int updatedCount = 0;
                  int createdCount = 0;
                  int failCount = 0;

                  for (int i = 0; i < controllersList.length; i++) {
                    try {
                      final controllers = controllersList[i];

                      Map<String, dynamic> updated = {};

                      controllers.forEach((key, ctrl) {
                        if (ctrl.text.trim().isNotEmpty) {
                          updated[key] = ctrl.text.trim();
                        }
                      });

                      // Set ID for existing, remove for new
                      bool isNew = i >= items.length;
                      if (!isNew) {
                        updated['id'] = items[i]['id'];
                      } else {
                        updated.remove('id');
                      }

                      http.Response resp;
                      if (isNew) {
                        // CREATE new item
                        final endpoint = _getCreateEndpoint(_selectedTable);
                        resp = await http.post(
                          Uri.parse('$apiBaseUrl$endpoint'),
                          headers: {'Content-Type': 'application/json'},
                          body: json.encode(updated),  // No {'data': } wrapper for POST
                        );
                        if (resp.statusCode == 200 || resp.statusCode == 201) {
                          createdCount++;
                        } else {
                          failCount++;
                          debugPrint('Create failed: ${resp.statusCode} ${resp.body}');
                        }
                      } else {
                        // UPDATE existing
                        final endpoint = _getUpdateEndpoint(_selectedTable);
                        resp = await http.put(
                          Uri.parse('$apiBaseUrl$endpoint'),
                          headers: {'Content-Type': 'application/json'},
                          body: json.encode({'data': updated}),
                        );
                        if (resp.statusCode == 200) {
                          updatedCount++;
                        } else {
                          failCount++;
                          debugPrint('Update failed: ${resp.statusCode} ${resp.body}');
                        }
                      }
                    } catch (e) {
                      failCount++;
                      debugPrint('Save error: $e');
                    }
                  }

                  // 🔥 REFRESH DASHBOARD - RESET PAGINATION
                  Navigator.pop(context);
                  _loadData(isLoadMore: false); // ✅ FRESH LOAD PAGE 1

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('$updatedCount updated, $createdCount created, $failCount failed'),
                      backgroundColor: (failCount > 0) ? Colors.orange : Colors.green,
                      duration: const Duration(seconds: 4),
                    ));
                  }
                },
                child: const Text("SAVE ALL"),
              ),
            ],
          );
        },
      ),
    );
  }




String _getUpdateEndpoint(TableType type) {
    switch (type) {
      case TableType.purchase:
        return '/update_purchase';
      case TableType.packagingMaterial:
        return '/update_packaging_material';
      case TableType.stockUpdate:
        return '/update_stock_update';
      case TableType.bGradeSales:
        return '/update_b_grade_sale';
      case TableType.sales:
        return '/update_sale';
      case TableType.rejectionReceived:
        return '/update_rejection_received';
      case TableType.vendorRejection:
        return '/update_vendor_rejection';
      case TableType.dumpSale:
        return '/update_dump_sale';
      case TableType.mandiResale:
        return '/update_mandi_resale';
    }
  }

String _getCreateEndpoint(TableType type) {
    switch (type) {
      case TableType.purchase:
        return '/insert_purchase';
      case TableType.packagingMaterial:
        return '/insert_packaging_material';
      case TableType.stockUpdate:
        return '/insert_stock_update';
      case TableType.bGradeSales:
        return '/insert_b_grade_sale';
      case TableType.sales:
        return '/insert_sale';
      case TableType.rejectionReceived:
        return '/insert_rejection_received';
      case TableType.vendorRejection:
        return '/insert_vendor_rejection';
      case TableType.dumpSale:
        return '/insert_dump_sale';
      case TableType.mandiResale:
        return '/insert_mandi_resale';
    }
  }

  Widget _buildEditDateField(String key, TextEditingController ctrl, BuildContext context, StateSetter setDialogState) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: TextField(
        controller: ctrl,
        readOnly: true,
        decoration: InputDecoration(labelText: key.replaceAll('_', ' ').toUpperCase(), border: const OutlineInputBorder(), suffixIcon: const Icon(Icons.calendar_today)),
        onTap: () async {
          final d = await showDatePicker(context: context, initialDate: DateTime.tryParse(ctrl.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (d != null) {
            ctrl.text = DateFormat('yyyy-MM-dd').format(d);
            setDialogState(() {});
          }
        },
      ),
    );
  }

  Future<void> _generatePdf(List<Map<String, dynamic>> items) async {
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (pw.Context context) {
        return [
          pw.Header(level: 0, child: pw.Text("Inventory Report - ${_selectedTable.name.toUpperCase()}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18))),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: _getColumnsForTable().map((c) => (c.label as Text).data!).where((t) => t != 'Actions').toList(),
            data: items.map((row) => _getPrintableRow(row)).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
        ];
      },
    ));
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  List<String> _getPrintableRow(Map<String, dynamic> row) {
    final date = _formatDate(row['date'] ?? row['ctrl_date'] ?? row['created_at']);
    if (_selectedTable == TableType.purchase) return [row['item_tag'] ?? '', row['item'] ?? '', row['vendor'] ?? '', row['po_number']?.toString() ?? '', "${row['qty_receive']} ${row['unit_receive']}", row['pcs_receive']?.toString() ?? '0', row['total_value']?.toString() ?? '0', row['amount_paid']?.toString() ?? '0', row['amount_due']?.toString() ?? '0', row['payment_status'] ?? '', date];
    if (_selectedTable == TableType.stockUpdate) return [row['item'] ?? '', row['po_number'] ?? '', "${row['a_grade_qty']} / ${row['pcs_a_grade']}", "${row['b_grade_qty']} / ${row['pcs_b_grade']}", "${row['c_grade_qty']} / ${row['pcs_c_grade']}", "${row['ungraded_qty']} / ${row['pcs_ungraded']}", "${row['dump_qty']} / ${row['pcs_dump']}", row['total_qty']?.toString() ?? '', date];
    if (_selectedTable == TableType.rejectionReceived) return [row['item_tag'] ?? '', row['item'] ?? '', row['clint'] ?? '', row['po_number'] ?? '', "${row['quantity']} ${row['unit']}", row['pcs']?.toString() ?? '', row['reason'] ?? '', date];
    if (_selectedTable == TableType.vendorRejection) return [row['item'] ?? '', row['vendor'] ?? '', row['po_number'] ?? '', "${row['quantity_sent']} ${row['unit']}", row['pcs']?.toString() ?? '', date];
    if (_selectedTable == TableType.bGradeSales) return [row['item'] ?? '', row['clint'] ?? '', row['po_number'] ?? '', "${row['quantity']} ${row['unit']}", row['pcs']?.toString() ?? '0', row['total_value']?.toString() ?? '0', row['amount_paid']?.toString() ?? '0', row['amount_due']?.toString() ?? '0', row['payment_status'] ?? '', date];
    if (_selectedTable == TableType.sales) return [row['item_tag'] ?? '', row['item'] ?? '', row['clint'] ?? '', row['po_number'] ?? '', "${row['quantity']} ${row['unit']}", row['pcs']?.toString() ?? '0', row['total_value']?.toString() ?? '0', row['amount_paid']?.toString() ?? '0', row['amount_due']?.toString() ?? '0', row['payment_status'] ?? '', date];
    if (_selectedTable == TableType.dumpSale || _selectedTable == TableType.mandiResale) return [row['item_tag'] ?? '', row['item'] ?? '', row['po_number']?.toString() ?? '', "${row['quantity']} ${row['unit']}", row['pcs']?.toString() ?? '', date];
    return [row['item'] ?? '', row['vendor'] ?? row['clint'] ?? row['client_name'] ?? '', row['po_number']?.toString() ?? '', row['quantity']?.toString() ?? row['qty_receive']?.toString() ?? '', date];
  }

String _getTableNameFromEnum() {
    switch (_selectedTable) {
      case TableType.purchase:
        return 'purchases';
      case TableType.packagingMaterial:
        return 'packaging_materials';
      case TableType.stockUpdate:
        return 'stock_updates';
      case TableType.bGradeSales:
        return 'b_grade_sales';
      case TableType.sales:
        return 'sales';
      case TableType.rejectionReceived:
        return 'rejection_received';
      case TableType.vendorRejection:
        return 'vendor_rejections';
      case TableType.dumpSale:
        return 'dump_sales';
      case TableType.mandiResale:
        return 'mandi_resales';
    }
  }

  List<DataColumn> _getColumnsForTable() {
    List<String> cols = [];
switch (_selectedTable) {
      case TableType.purchase:
      case TableType.packagingMaterial:
        cols = ['Tag', 'Item', 'Vendor', 'PO Num', 'Qty (Kg)', 'Qty (Pcs)', 'Total', 'Paid', 'Due', 'Status', 'Date', 'Actions'];
        break;
      case TableType.stockUpdate:
        cols = ['Item', 'PO Num', 'A-Grade (Kg/Pcs)', 'B-Grade (Kg/Pcs)', 'C-Grade (Kg/Pcs)', 'Ungraded (Kg/Pcs)', 'Dump (Kg/Pcs)', 'Total Kg', 'Date', 'Actions'];
        break;
      case TableType.sales:
        cols = ['Tag', 'Item', 'Client', 'PO Num', 'Qty (Kg)', 'Qty (Pcs)', 'Total', 'Paid', 'Due', 'Status', 'Date', 'Actions'];
        break;
      case TableType.rejectionReceived:
        cols = ['Tag', 'Item', 'Client', 'PO Num', 'Qty (Kg)', 'Qty (Pcs)', 'Reason', 'Date', 'Actions'];
        break;
      case TableType.vendorRejection:
        cols = ['Item', 'Vendor', 'PO Num', 'Qty (Kg)', 'Qty (Pcs)', 'Date', 'Actions'];
        break;
      case TableType.dumpSale:
        cols = ['Tag', 'Item', 'PO Num', 'Qty (Kg)', 'Qty (Pcs)', 'Date', 'Actions'];
        break;
      case TableType.mandiResale:
        cols = ['Tag', 'Item', 'PO Num', 'Qty (Kg)', 'Qty (Pcs)', 'Date', 'Actions'];
        break;
      case TableType.bGradeSales:
        cols = ['Item', 'Client', 'PO Num', 'Qty (Kg)', 'Qty (Pcs)', 'Total', 'Paid', 'Due', 'Status', 'Date', 'Actions'];
        break;
      default:
        cols = ['Item', 'Client/Vendor', 'PO Num', 'Qty', 'Date', 'Actions'];
    }
    return cols.map((c) => DataColumn(label: Text(c, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 9)))).toList();
  }

  DataRow _buildGroupedRow(String key, List<Map<String, dynamic>> items) {
    final first = items.first;
    const style = TextStyle(fontSize: 9);
    
    final List<int> allIdsInGroup = items.map((i) => int.tryParse(i['id'].toString()) ?? 0).toList();
    final String label = first['po_number']?.toString() ?? first['item_tag'] ?? 'Group';

    double subTotal = items.fold<double>(0.0, (sum, i) => sum + (double.tryParse(i['total_value']?.toString() ?? '0') ?? 0.0));
    double subPaid = items.fold<double>(0.0, (sum, i) => sum + (double.tryParse(i['amount_paid']?.toString() ?? '0') ?? 0.0));
    double subDue = items.fold<double>(0.0, (sum, i) => sum + (double.tryParse(i['amount_due']?.toString() ?? '0') ?? 0.0));

    List<DataCell> cells = [
      if (_selectedTable == TableType.purchase || _selectedTable == TableType.packagingMaterial || _selectedTable == TableType.rejectionReceived || _selectedTable == TableType.sales || _selectedTable == TableType.dumpSale || _selectedTable == TableType.mandiResale) 
        DataCell(Text(first['item_tag'] ?? '', style: style)),
      DataCell(_buildStackedText(items, (i) => i['item'] ?? '')),
    ];

    if (_selectedTable != TableType.dumpSale && _selectedTable != TableType.mandiResale) {
      cells.add(DataCell(Text(first['vendor'] ?? first['clint'] ?? first['client_name'] ?? '', style: style)));
    } else {
      cells.add(DataCell(Text('')));
    }

    cells.add(DataCell(Text(first['po_number']?.toString() ?? '', style: style)));

    if (_selectedTable == TableType.purchase || _selectedTable == TableType.packagingMaterial) {
      cells.addAll([
        DataCell(_buildStackedText(items, (i) => "${i['qty_receive'] ?? 0} ${i['unit_receive'] ?? ''}")),
        DataCell(_buildStackedText(items, (i) => i['pcs_receive']?.toString() ?? '0')),
        DataCell(Text(subTotal.toStringAsFixed(2), style: style)),
        DataCell(Text(subPaid.toStringAsFixed(2), style: const TextStyle(fontSize: 9, color: Colors.green))),
        DataCell(Text(subDue.toStringAsFixed(2), style: const TextStyle(fontSize: 9, color: Colors.red))),
        DataCell(_buildStatusCell(first['payment_status'])),
      ]);
    } else if (_selectedTable == TableType.rejectionReceived) {
      cells.addAll([
        DataCell(_buildStackedText(items, (i) => "${i['quantity']} ${i['unit']}")),
        DataCell(_buildStackedText(items, (i) => i['pcs']?.toString() ?? '')),
        DataCell(_buildStackedText(items, (i) => i['reason'] ?? '')),
        const DataCell(Text('')), // Padding for missing columns
        const DataCell(Text('')),
        const DataCell(Text('')),
      ]);
    } else if (_selectedTable == TableType.sales || _selectedTable == TableType.bGradeSales) {
      cells.addAll([
        DataCell(_buildStackedText(items, (i) => "${i['quantity']} ${i['unit']}")),
        DataCell(_buildStackedText(items, (i) => i['pcs']?.toString() ?? '0')),
        DataCell(Text(subTotal.toStringAsFixed(2), style: style)),
        DataCell(Text(subPaid.toStringAsFixed(2), style: const TextStyle(fontSize: 9, color: Colors.green))),
        DataCell(Text(subDue.toStringAsFixed(2), style: const TextStyle(fontSize: 9, color: Colors.red))),
        DataCell(_buildStatusCell(first['payment_status'])),
      ]);
    } else if (_selectedTable == TableType.dumpSale || _selectedTable == TableType.mandiResale) {
      cells.addAll([
        DataCell(_buildStackedText(items, (i) => "${i['quantity']} ${i['unit']}")),
        DataCell(_buildStackedText(items, (i) => i['pcs']?.toString() ?? '')),
        const DataCell(Text('')), // Padding
        const DataCell(Text('')),
        const DataCell(Text('')),
        const DataCell(Text('')),
      ]);
    } else {
      cells.addAll([
        DataCell(_buildStackedText(items, (i) => i['quantity']?.toString() ?? '')),
        DataCell(_buildStackedText(items, (i) => i['pcs']?.toString() ?? '')),
        const DataCell(Text('')),
        const DataCell(Text('')),
        const DataCell(Text('')),
        const DataCell(Text('')),
      ]);
    }

    cells.add(DataCell(Text(_formatDate(first['date'] ?? first['ctrl_date'] ?? first['created_at']), style: style)));
    cells.add(DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.blueGrey, size: 18), onPressed: () => _generatePdf(items)),
      IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 18), onPressed: () => _handleEditGroup(items)),
      IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => _handleGroupDelete(label, allIdsInGroup)),
    ])));

    int columnCount = _getColumnsForTable().length;

    while (cells.length < columnCount) {
      cells.add(const DataCell(Text('')));
    }

    if (cells.length > columnCount) {
      cells = cells.sublist(0, columnCount);
    }

    return DataRow(cells: cells);
  }

  Widget _buildStatusCell(String? status) {
    Color color = Colors.red;
    if (status == 'Paid') {
      color = Colors.green;
    } else if (status == 'Partial Paid') color = Colors.orange;
    return Text(status ?? 'Unpaid', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color));
  }

  Widget _buildStackedText(List<Map<String, dynamic>> items, String Function(Map<String, dynamic>) mapper) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: items.map((i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: Text(
            mapper(i),
            style: const TextStyle(fontSize: 9, height: 1.2),
            softWrap: true,
          ),
        )).toList(),
      ),
    );
  }

  List<DataCell> _buildCells(Map<String, dynamic> row) {
    const style = TextStyle(fontSize: 9);
    if (_selectedTable == TableType.stockUpdate) {
      return [
        DataCell(Text(row['item'] ?? '', style: style)),
        DataCell(Text(row['po_number'] ?? '', style: style)),
        DataCell(Text("${row['a_grade_qty']} Kg / ${row['pcs_a_grade'] ?? 0} Pcs", style: style)),
        DataCell(Text("${row['b_grade_qty']} Kg / ${row['pcs_b_grade'] ?? 0} Pcs", style: style)),
        DataCell(Text("${row['c_grade_qty']} Kg / ${row['pcs_c_grade'] ?? 0} Pcs", style: style)),
        DataCell(Text("${row['ungraded_qty'] ?? 0} Kg / ${row['pcs_ungraded'] ?? 0} Pcs", style: style)),
        DataCell(Text("${row['dump_qty'] ?? 0} Kg / ${row['pcs_dump'] ?? 0} Pcs", style: style)),
        DataCell(Text(row['total_qty']?.toString() ?? '', style: style)),
        DataCell(Text(_formatDate(row['date'] ?? row['ctrl_date'] ?? row['created_at']), style: style)),
        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.blueGrey, size: 18), onPressed: () => _generatePdf([row])),
          IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 18), onPressed: () => _handleEdit(row)),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => _handleDelete(row['id']))
        ]))
      ];
    }
    if (_selectedTable == TableType.vendorRejection) {
      return [
        DataCell(Text(row['item'] ?? '', style: style)),
        DataCell(Text(row['vendor'] ?? '', style: style)),
        DataCell(Text(row['po_number'] ?? '', style: style)),
        DataCell(Text("${row['quantity_sent']} ${row['unit']}", style: style)),
        DataCell(Text(row['pcs']?.toString() ?? '', style: style)),
        DataCell(Text(_formatDate(row['date'] ?? row['ctrl_date'] ?? row['created_at']), style: style)),
        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.blueGrey, size: 18), onPressed: () => _generatePdf([row])),
          IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 18), onPressed: () => _handleEdit(row)),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => _handleDelete(row['id']))
        ]))
      ];
    }
    if (_selectedTable == TableType.dumpSale || _selectedTable == TableType.mandiResale) {
      return [
        DataCell(Text(row['item_tag'] ?? '', style: style)),
        DataCell(Text(row['item'] ?? '', style: style)),
        DataCell(Text(row['po_number']?.toString() ?? '', style: style)),
        DataCell(Text("${row['quantity']} ${row['unit']}", style: style)),
        DataCell(Text(row['pcs']?.toString() ?? '', style: style)),
        DataCell(Text(_formatDate(row['date'] ?? row['ctrl_date'] ?? row['created_at']), style: style)),
        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.blueGrey, size: 18), onPressed: () => _generatePdf([row])),
          IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 18), onPressed: () => _handleEdit(row)),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => _handleDelete(row['id']))
        ]))
      ];
    }
    if (_selectedTable == TableType.packagingMaterial) {
      return [
        DataCell(Text(row['item_tag'] ?? '', style: style)),
        DataCell(Text(row['item'] ?? '', style: style)),
        DataCell(Text(row['vendor'] ?? '', style: style)),
        DataCell(Text(row['po_number']?.toString() ?? '', style: style)),
        DataCell(Text("${row['qty_receive'] ?? 0} ${row['unit_receive'] ?? ''}", style: style)),
        DataCell(Text(row['pcs_receive']?.toString() ?? '0', style: style)),
        DataCell(Text(row['total_value']?.toStringAsFixed(2) ?? '0', style: style)),
        DataCell(Text(row['amount_paid']?.toStringAsFixed(2) ?? '0', style: const TextStyle(fontSize: 9, color: Colors.green))),
        DataCell(Text(row['amount_due']?.toStringAsFixed(2) ?? '0', style: const TextStyle(fontSize: 9, color: Colors.red))),
        DataCell(_buildStatusCell(row['payment_status']?.toString())),
        DataCell(Text(_formatDate(row['date'] ?? row['ctrl_date'] ?? row['created_at']), style: style)),
        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.blueGrey, size: 18), onPressed: () => _generatePdf([row])),
          IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 18), onPressed: () => _handleEdit(row)),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => _handleDelete(row['id']))
        ]))
      ];
    }
    return [
      DataCell(Text(row['item'] ?? '', style: style)),
      DataCell(Text(row['vendor'] ?? row['clint'] ?? row['client_name'] ?? '', style: style)),
      DataCell(Text(row['po_number']?.toString() ?? '', style: style)),
      DataCell(Text(row['quantity']?.toString() ?? row['qty_receive']?.toString() ?? '', style: style)),
      DataCell(Text(_formatDate(row['date'] ?? row['ctrl_date'] ?? row['created_at']), style: style)),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.blueGrey, size: 18), onPressed: () => _generatePdf([row])),
        IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 18), onPressed: () => _handleEdit(row)),
        IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => _handleDelete(row['id']))
      ]))
    ];
  }

  String _formatDate(dynamic s) { if (s == null || s.toString().isEmpty) return ''; try { return DateFormat('dd-MM-yy').format(DateTime.parse(s.toString())); } catch (e) { return s.toString(); } }

  Widget _buildDateSelectionArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.indigo.shade100),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<TableType>(
                isExpanded: true,
                value: _selectedTable,
                items: TableType.values.map((type) => DropdownMenuItem(
                  value: type,
                  child: Text(type.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 13)),
                )).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedTable = val;
                      _filteredData = [];
                      _allData = [];
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final p = await showDatePicker(
                      context: context,
                      initialDate: _startDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (p != null) setState(() => _startDate = p);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.indigo.shade100),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("START DATE", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.indigo)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.calendar_month, size: 14, color: Colors.indigo),
                            const SizedBox(width: 6),
                            Text(_startDate == null ? "Select Date" : DateFormat('dd/MM/yyyy').format(_startDate!), style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final p = await showDatePicker(
                      context: context,
                      initialDate: _endDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (p != null) setState(() => _endDate = p);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.indigo.shade100),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("END DATE", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.indigo)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.calendar_month, size: 14, color: Colors.indigo),
                            const SizedBox(width: 6),
                            Text(_endDate == null ? "Select Date" : DateFormat('dd/MM/yyyy').format(_endDate!), style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              if (_startDate == null || _endDate == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select both Start and End dates")));
                return;
              }
              if (_endDate!.isBefore(_startDate!)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Galat Date! End date start date se pehle nahi ho sakti. Sai date daale."), backgroundColor: Colors.red),
                );
                return;
              }
              _loadData();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("VIEW DATA", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(title: const Text("DASHBOARD", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)), backgroundColor: Colors.indigo, iconTheme: const IconThemeData(color: Colors.white), actions: [IconButton(icon: const Icon(Icons.filter_list), onPressed: () { _resetTempFilters(); _scaffoldKey.currentState?.openEndDrawer(); }), IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData)]),
      drawer: _buildSideDrawer(),
      endDrawer: _buildFilterPanel(),
      body: Column(children: [
        _buildDateSelectionArea(),
        Expanded(
          child: (_startDate == null || _endDate == null)
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.category_outlined, size: 80, color: Colors.indigo),
                    SizedBox(height: 16),
                    Text("Select Category and Dates\nto view inventory data", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.indigo, fontWeight: FontWeight.w500)),
                  ],
                ),
              )
            : _isLoadingData 
              ? const Center(child: CircularProgressIndicator())
              : _filteredData.isEmpty 
                ? const Center(child: Text("No data found for the selected dates")) 
                // : RefreshIndicator(
                //     onRefresh: _loadData,

                    
                //     child: SingleChildScrollView(
                //       child: SingleChildScrollView(
                //         scrollDirection: Axis.horizontal,
                        
                        
                //         child: Padding(
                //           padding: const EdgeInsets.all(8.0),
                //           child: DataTable(
                //             headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50),
                //             dataRowMinHeight: 40,
                //             dataRowMaxHeight: double.infinity,
                //             columns: _getColumnsForTable(),
                //             rows: _prepareTableRows(),
                //           ),
                          
                //         ),
                //       ),
                //     ),
                //   ),

                : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    controller: _scrollController, // ✅ YAHI ADD KARNA HAI
                    child: Column(
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50),
                              dataRowMinHeight: 40,
                              dataRowMaxHeight: double.infinity,
                              columns: _getColumnsForTable(),
                              rows: _prepareTableRows(),
                            ),
                          ),
                        ),

                        // ✅ Load more loader
                        if (_isLoadingMore)
                          const Padding(
                            padding: EdgeInsets.all(10),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
                  ),
                )



        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, -2))]),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: _isDriveExporting ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cloud_upload, color: Colors.white, size: 18),
                  label: Text(_isDriveExporting ? "UPLOADING..." : "DRIVE UPLOAD", style: const TextStyle(fontSize: 10)),
                  onPressed: _isDriveExporting || _filteredData.isEmpty ? null : _handleDriveUpload,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }

Widget _buildSideDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
      UserAccountsDrawerHeader(accountName: const Text("Inventory Pro", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), accountEmail: const Text("Dashboard & Navigation", style: TextStyle(fontSize: 12)), currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.inventory, size: 36, color: Colors.indigo)), decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.indigo.shade700, Colors.indigo.shade400], begin: Alignment.topLeft, end: Alignment.bottomRight))),
      _buildDrawerListTile(icon: Icons.shopping_cart, title: "Purchase Entry", color: Colors.blue, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const Page1())).then((_) => _loadData())),
      _buildDrawerListTile(icon: Icons.inventory_2, title: "Packaging Material Entry", color: Colors.purple, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PackagingMaterialPage())).then((_) => _loadData())),
      _buildDrawerListTile(icon: Icons.update, title: "Stock Update", color: Colors.orange, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const Page2())).then((_) => _loadData())),
      _buildDrawerListTile(icon: Icons.trending_down, title: "B-Grade Sales", color: Colors.teal, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const Page3())).then((_) => _loadData())),
      _buildDrawerListTile(icon: Icons.point_of_sale, title: "Sales", color: Colors.green, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const Page4())).then((_) => _loadData())),
      _buildDrawerListTile(icon: Icons.cancel, title: "Rejection Received", color: Colors.red, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RejectionReceived())).then((_) => _loadData())),
      const Divider(),
      _buildDrawerListTile(icon: Icons.undo, title: "Vendor Rejection", color: Colors.purple, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const VendorRejectionPage())).then((_) => _loadData())),
      _buildDrawerListTile(icon: Icons.delete_sweep, title: "Dump Sale", color: Colors.brown, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DumpSale())).then((_) => _loadData())),
      _buildDrawerListTile(icon: Icons.store_mall_directory, title: "Mandi Resale", color: Colors.pink, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MandiResale())).then((_) => _loadData())),
      _buildDrawerListTile(icon: Icons.analytics_outlined, title: "Reports", color: Colors.indigo, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CheckInventory())).then((_) => _loadData())),
    ]));
  }

  Widget _buildDrawerListTile({required IconData icon, required String title, required VoidCallback onTap, required Color color}) { return ListTile(leading: Icon(icon, color: color), title: Text(title, style: const TextStyle(fontSize: 13)), onTap: () { Navigator.pop(context); onTap(); }); }

  Widget _buildFilterPanel() {
    return Drawer(
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 16, bottom: 16, left: 16, right: 16),
            color: Colors.indigo,
            width: double.infinity,
            child: const Text("Filters", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: [
                _buildFilterSection(icon: Icons.inventory_2_outlined, title: "Item", child: DropdownButtonFormField<String>(isExpanded: true, initialValue: _tempSelectedItem, hint: const Text("All Items", style: TextStyle(fontSize: 12)), items: [const DropdownMenuItem(value: null, child: Text("All Items", style: TextStyle(fontSize: 12))), ..._itemsForFilter.map((item) => DropdownMenuItem(value: item, child: Text(item, style: const TextStyle(fontSize: 12))))], onChanged: (val) => setState(() => _tempSelectedItem = val))),
                _buildFilterSection(icon: Icons.person_outline, title: "Client / Vendor", child: DropdownButtonFormField<String>(isExpanded: true, initialValue: _tempSelectedClientVendor, hint: const Text("All Clients/Vendors", style: TextStyle(fontSize: 12)), items: [const DropdownMenuItem(value: null, child: Text("All Clients/Vendors", style: TextStyle(fontSize: 12))), ..._clientsVendorsForFilter.map((name) => DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))))], onChanged: (val) => setState(() => _tempSelectedClientVendor = val))),
                _buildFilterSection(icon: Icons.receipt_long_outlined, title: "PO Number", child: TextField(
                  controller: _poNumberController, 
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(hintText: "Enter PO Number", hintStyle: TextStyle(fontSize: 12), contentPadding: EdgeInsets.symmetric(vertical: 8)),
                )),
                _buildFilterSection(icon: Icons.numbers, title: "PCS", child: TextField(
                  controller: _pcsController, 
                  style: const TextStyle(fontSize: 12),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: "Enter PCS", hintStyle: TextStyle(fontSize: 12), contentPadding: EdgeInsets.symmetric(vertical: 8)),
                )),
                _buildFilterSection(icon: Icons.tag, title: "Item Tag", child: TextField(
                  controller: _itemTagController, 
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(hintText: "Enter Item Tag", hintStyle: TextStyle(fontSize: 12), contentPadding: EdgeInsets.symmetric(vertical: 8)),
                )),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, -2))]),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () { 
                    setState(() { 
                      _startDate = _tempStartDate; 
                      _endDate = _tempEndDate; 
                      _selectedItem = _tempSelectedItem;
                      _selectedClientVendor = _tempSelectedClientVendor;
                      _poNumber = _poNumberController.text;
                      _pcs = _pcsController.text;
                      _itemTag = _itemTagController.text;
                    }); 
                    _applyFilters(); 
                    Navigator.pop(context); 
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 40), backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  child: const Text("Apply Filters", style: TextStyle(fontSize: 13)),
                ),
                TextButton(
                  onPressed: () { _clearAllFilters(); Navigator.pop(context); },
                  child: const Text("Clear All", style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection({required IconData icon, required String title, required Widget child}) { return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, size: 18, color: Colors.grey), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))]), const SizedBox(height: 8), child])); }

  Widget _buildEditDropdown(String key, TextEditingController ctrl, List<String> options, StateSetter setDialogState, Function calculate) {
    String? currentVal = options.contains(ctrl.text) ? ctrl.text : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: DropdownButtonFormField<String>(
        initialValue: currentVal,
        decoration: InputDecoration(labelText: key.replaceAll('_', ' ').toUpperCase(), border: const OutlineInputBorder()),
        items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (val) {
          if (val != null) {
            ctrl.text = val;
            calculate(setDialogState);
          }
        },
      ),
    );
  }

  Future<void> _handleDriveUpload() async {
    if (_isDriveExporting || _filteredData.isEmpty) return;

    setState(() => _isDriveExporting = true);
    try {
      final excelFile = excel.Excel.createExcel();
      final sheet = excelFile[excelFile.getDefaultSheet()!];

      // Headers from table columns (exclude Actions)
      final headers = _getColumnsForTable().map((c) => (c.label as Text).data!).where((t) => t != 'Actions').toList();
      sheet.appendRow(headers.map((h) => excel.TextCellValue(h)).toList());

      // Simple flat rows from _filteredData (handles grouped data flattening)
      for (var rowData in _filteredData) {
        final rowValues = headers.map<excel.CellValue>((header) {
          final key = header.toLowerCase().replaceAll(' ', '_').replaceAll(RegExp(r'[() ]'), '');
          dynamic value = rowData[key] ?? rowData[key.replaceAll('-', '_')] ?? '';
          if (value is num) value = value.toStringAsFixed(2);
          return excel.TextCellValue(value.toString());
        }).toList();
        sheet.appendRow(rowValues);
      }

      final fileBytes = excelFile.save()!;
      
      const String driveFolderId = "1GpkW87U4N2DpD_QxCM4re1jn90VJB52V";
      final uploadFileName = '${_selectedTable.name.toUpperCase().replaceAll('_', '')}_INVENTORY_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      
      await uploadFileToDrive(fileBytes, uploadFileName, driveFolderId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedTable.name.toUpperCase()} uploaded successfully to Drive'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Drive upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDriveExporting = false);
    }
  }
}
