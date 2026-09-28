import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
// SocketException
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'api_config.dart';
import 'admin_report.dart';
import 'auth/auth_manager.dart';
import 'admin/admin_data_pager.dart';
import 'admin/admin_excel_export.dart';
import 'admin/admin_virtual_table.dart';
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
  List<Map<String, dynamic>> _filteredData = [];
  bool _isLoadingData = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _perPage = 25;
  // Sliding window over server pages: at most 3 pages stay in memory — older
  // pages are evicted while scrolling down and re-fetched when scrolling back
  // up (dynamic page loader, shared with the saved-report table).
  final AdminPageWindow _window = AdminPageWindow(maxPages: 3);
  bool _isLoadingPrev = false;
  // Bumped on every reset so stale in-flight responses can be dropped.
  int _loadGeneration = 0;
  int _totalRecords = 0;
  bool _initialLoadStarted = false;
  bool _isExporting = false;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _searchQuery;
  Timer? _searchDebounce;
  final TextEditingController _searchFieldController = TextEditingController();
  final ScrollController _tableScrollController = ScrollController();

  // Row height used by the virtualized table (drives the windowed rendering).
  static const double _tableRowHeight = 42;

  // Overview stats (row counts across all tables)
  Map<String, dynamic>? _stats;
  bool _isLoadingStats = false;

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

  
  
  
  
  
  
  
  String _getGroupKey(Map<String, dynamic> row) {
    switch (_selectedTable) {
      case AdminTableType.purchases:
        return '${row['po_number'] ?? ''}';

      case AdminTableType.sales:
        return '${row['so_number'] ?? row['po_number'] ?? ''}';

      case AdminTableType.bGradeSales:
        return '${row['so_number'] ?? row['po_number'] ?? ''}';

      case AdminTableType.rejectionReceived:
        return '${row['so_number'] ?? row['po_number'] ?? ''}';

      case AdminTableType.vendorRejections:
        return '${row['so_number'] ?? row['po_number'] ?? ''}';

      case AdminTableType.dumpSales:
        return '${row['tag'] ?? ''}';

      case AdminTableType.mandiResales:
        return '${row['tag'] ?? ''}';

      default:
        return '';
    }
  }


  @override
  void initState() {
    super.initState();
    // _tableScrollController.addListener(_onTableScroll);
    _loadStats();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchFieldController.dispose();
    // _tableScrollController.removeListener(_onTableScroll);
    _tableScrollController.dispose();
    super.dispose();
  }

  /// First load happens once the table viewport size is known, so the first
  /// request fetches exactly as many rows as fit on screen (+ a small buffer).
  void _startInitialLoadIfNeeded(double viewportHeight) {
    if (_initialLoadStarted) return;
    _initialLoadStarted = true;
    final fitsOnScreen = ((viewportHeight - 40) / _tableRowHeight).ceil() + 5;
    _perPage = fitsOnScreen.clamp(15, 100);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() => _isLoadingStats = true);
    try {
      final response = await http
          .get(Uri.parse('$apiBaseUrl/get_admin_stats'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (mounted) {
          setState(() => _stats = Map<String, dynamic>.from(decoded));
        }
      }
    } catch (e) {
      debugPrint('AdminDashboard: _loadStats failed: $e');
    } finally {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  /// Extra query params some endpoints need (items de-duplicates names).
  Map<String, String> get _extraQueryParams =>
      _selectedTable == AdminTableType.items ? const {'distinct': '1'} : const {};

  /// Loads one page of the selected table.
  ///
  /// [reset] = true clears the list and loads page 1 again (table switch,
  /// filter change, refresh, after edit/delete). [reset] = false appends the
  /// next page while the user scrolls (infinite scroll).
  Future<void> _loadData({bool reset = true}) async {
    if (!mounted) return;

    if (!reset) {
      if (_isLoadingMore || _isLoadingData || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _isLoadingData = true;
        _isLoadingMore = false;
        _isLoadingPrev = false;
        _hasMore = false;
        _loadGeneration++;
        _filteredData = [];
        _window.resetAll();
      });
      if (_tableScrollController.hasClients) {
        _tableScrollController.jumpTo(0);
      }
    }

    final gen = _loadGeneration;
    final requestedPage = reset ? 1 : _window.lastPage + 1;
    final result = await AdminDataPager.fetchPage(AdminDataQuery(
      endpoint: _getEndpoint(_selectedTable),
      page: requestedPage,
      limit: _perPage,
      startDate: _startDate,
      endDate: _endDate,
      search: _searchQuery,
      extraParams: _extraQueryParams,
    ));

    // Drop responses of an older table/filter/search query.
    if (!mounted || gen != _loadGeneration) return;

    if (!result.success) {
      setState(() {
        _isLoadingData = false;
        _isLoadingMore = false;
        if (reset) {
          _filteredData = [];
          _totalRecords = 0;
          _hasMore = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load ${_selectedTable.name}: ${result.error}'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _loadData(reset: reset),
          ),
        ),
      );
      return;
    }

    int evictedFront = 0;
    setState(() {
      if (reset) {
        _filteredData = result.rows;
        _window.reset(page: requestedPage, rowCount: result.rows.length);
      } else {
        _filteredData.addAll(result.rows);
        _window.recordAppend(page: requestedPage, rowCount: result.rows.length);
        // Dynamic page loader: once more than 3 pages are loaded, the top
        // page is freed while the user scrolls down.
        evictedFront = _window.evictFront(_filteredData);
      }
      _hasMore = result.hasMore && result.rows.isNotEmpty;
      _totalRecords =
          result.total > _filteredData.length ? result.total : _filteredData.length;
      _isLoadingData = false;
      _isLoadingMore = false;
    });
    // Keep the visible rows stable after evicting rows from the top.
    if (evictedFront > 0) {
      AdminPageWindow.compensateTopChange(
          _tableScrollController, -evictedFront, _tableRowHeight);
    }
    debugPrint('AdminDashboard: ${_selectedTable.name} -> '
        '${_filteredData.length}/$_totalRecords rows (hasMore: $_hasMore, '
        'pages: ${_window.firstPage}-${_window.lastPage})');
  }

  /// Called by the virtualized table whenever the user scrolls near the end.
  // Future<void> _loadMore() => _loadData(reset: false);

  // /// Scroll listener: when the top of the list is reached again, the evicted
  // /// page above the window is re-fetched (pages 2..N-1 are not kept forever).
  // void _onTableScroll() {
  //   if (!mounted || _isLoadingPrev || _isLoadingData || _isLoadingMore) return;
  //   if (!_window.canLoadPrevious) return;
  //   if (!_tableScrollController.hasClients) return;
  //   if (_tableScrollController.position.pixels <= _perPage * _tableRowHeight) {
  //     _loadPreviousPage();
  //   }
  // }


  Future<void> _loadMore() async {
    debugPrint('========== LOAD MORE CALLED ==========');
    debugPrint('_hasMore: $_hasMore');
    debugPrint('_isLoadingMore: $_isLoadingMore');
    debugPrint('current rows: ${_filteredData.length}');
    debugPrint('last page: ${_window.lastPage}');

    if (_isLoadingMore || !_hasMore) {
      debugPrint('LOAD MORE BLOCKED');
      return;
    }

    await _loadData(reset: false);

    debugPrint('========== LOAD MORE FINISHED ==========');
    debugPrint('rows after load: ${_filteredData.length}');
    debugPrint('last page after load: ${_window.lastPage}');
  }




  /// Prepends the page above the current window and (if needed) evicts the
  /// bottom page again so memory stays bounded to [_window.maxPages] pages.
  Future<void> _loadPreviousPage() async {
    if (_isLoadingPrev || _isLoadingData || _isLoadingMore) return;
    if (!_window.canLoadPrevious) return;
    setState(() => _isLoadingPrev = true);
    final gen = _loadGeneration;
    final target = _window.prevFirstPage;

    final result = await AdminDataPager.fetchPage(AdminDataQuery(
      endpoint: _getEndpoint(_selectedTable),
      page: target,
      limit: _perPage,
      startDate: _startDate,
      endDate: _endDate,
      search: _searchQuery,
      extraParams: _extraQueryParams,
    ));
    if (!mounted || gen != _loadGeneration) return;
    if (!result.success) {
      setState(() => _isLoadingPrev = false);
      debugPrint('AdminDashboard: previous page $target failed: ${result.error}');
      return;
    }

    setState(() {
      _filteredData.insertAll(0, result.rows);
      _window.recordPrepend(page: target, rowCount: result.rows.length);
      if (_window.evictBack(_filteredData) > 0) {
        // Rows exist again after the new last page → allow loading forward.
        _hasMore = true;
      }
      _isLoadingPrev = false;
    });
    if (result.rows.isNotEmpty) {
      AdminPageWindow.compensateTopChange(
          _tableScrollController, result.rows.length, _tableRowHeight);
    }
  }

  /// Debounced search: the term goes to the server so it searches the whole
  /// data set, not only the pages that happen to be loaded.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() => _searchQuery = value.trim().isEmpty ? null : value.trim());
      _loadData();
    });
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

    if (!mounted) return;

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
      final start = r['s'] as DateTime;
      final end = r['e'] as DateTime;
      final tableName = _getTableName(_selectedTable);

      // Count on the server so the delete covers the *whole* data set and not
      // only the pages that happen to be loaded in the table.
      final count = await AdminDataPager.countByDateRange(
        table: tableName,
        start: start,
        end: end,
      );

      if (!mounted) return;
      if (count == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not count entries for that date range'),
          backgroundColor: Colors.red,
        ));
        return;
      }
      if (count == 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No data found in this date range'),
          backgroundColor: Colors.orange,
        ));
        return;
      }

      final cfm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text("Confirm"),
        content: Text(
          "Delete $count entries between "
          "${DateFormat('dd/MM/yyyy').format(start)} and ${DateFormat('dd/MM/yyyy').format(end)}?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("DELETE ALL")),
        ],
      ));
      if (cfm != true) return;

      try {
        final deleted = await AdminDataPager.deleteByDateRange(
          table: tableName,
          start: start,
          end: end,
        );
        if (!mounted) return;
        if (deleted == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Bulk delete failed'),
            backgroundColor: Colors.red,
          ));
          return;
        }
        _loadData();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("$deleted deleted"),
          backgroundColor: Colors.green,
        ));
      } catch (e) {
        debugPrint('🔥 BULK ERROR: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Bulk delete error: $e"),
            backgroundColor: Colors.red,
          ));
        }
      }
    });
  }

  /// Exports *the whole data set* of the selected table (not only the pages
  /// currently loaded) and respects the active date-range / search filters.
  Future<void> _exportToExcel() async {
    debugPrint('AdminDashboard: export start (table=${_selectedTable.name}, '
        'start=$_startDate, end=$_endDate, search=$_searchQuery)');
    setState(() => _isExporting = true);
    try {
      // Walk the endpoint page by page so even 100k+ rows are exported.
      final result = await AdminDataPager.fetchAll(
        endpoint: _getEndpoint(_selectedTable),
        pageSize: 1000,
        startDate: _startDate,
        endDate: _endDate,
        search: _searchQuery,
        extraParams: _extraQueryParams,
      );

      if (result.error != null && result.rows.isEmpty) {
        throw Exception(result.error);
      }

      // Safety net for tables without a date column: rows that carry no date
      // are kept, dated rows outside the range are dropped.
      final rows = AdminDataPager.filterByDateRange(
        result.rows,
        _startDate,
        _endDate,
      );
      debugPrint('AdminDashboard: export rows: ${rows.length}');

      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No data to export for the selected filters.'),
            backgroundColor: Colors.orange,
          ));
        }
        return;
      }

      final path = await AdminExcelExporter.exportRows(
        rows: rows,
        filePrefix: _getTableName(_selectedTable),
        sheetName: _getTableName(_selectedTable),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Excel saved (${rows.length} rows)'
            '${result.truncated ? ' [truncated]' : ''}\n$path',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 6),
        ));
      }
    } catch (e) {
      debugPrint('AdminDashboard: export failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // List<AdminTableColumn> _buildVirtualColumns() {
  //   if (_filteredData.isEmpty) return const [];
  //   final keys = <String>[];
  //   for (final row in _filteredData) {
  //     for (final key in row.keys) {
  //       if (!keys.contains(key)) keys.add(key);
  //     }
  //   }
  //   final columns = keys
  //       .map((k) => AdminTableColumn(
  //             key: k,
  //             label: k.toString().replaceAll('_', ' ').toUpperCase(),
  //             width: _columnWidthFor(k),
  //           ))
  //       .toList();
  //   columns.add(const AdminTableColumn(key: '__actions', label: 'ACTIONS', width: 110));
  //   return columns;
  // }


  List<AdminTableColumn> _buildVirtualColumns() {
    if (_filteredData.isEmpty) return const [];

    final keys = <String>[];

    for (final row in _filteredData) {
      for (final key in row.keys) {
        if (!keys.contains(key)) keys.add(key);
      }
    }

    final columns = keys
        .map(
          (k) => AdminTableColumn(
            key: k,
            label: k == 'po_number'
                ? 'PO/SO'
                : k.toString().replaceAll('_', ' ').toUpperCase(),
            width: _columnWidthFor(k),
          ),
        )
        .toList();

    columns.add(
      const AdminTableColumn(
        key: '__actions',
        label: 'ACTIONS',
        width: 110,
      ),
    );

    return columns;
  }







  /// Slightly wider columns for long text fields, narrow for ids/numbers.
  double _columnWidthFor(String key) {
    final k = key.toLowerCase();
    if (k == 'id' || k.endsWith('_id') || k == 'so_id' || k == 'item_id') return 80;
    if (k.contains('date') || k.contains('time')) return 130;
    if (k.contains('name') || k.contains('item') || k.contains('vendor') || k.contains('client')) return 170;
    if (k.contains('remark') || k.contains('address') || k.contains('location')) return 190;
    return 130;
  }

  // List<Widget> _buildVirtualRowCells(BuildContext context, Map<String, dynamic> row, int index) {
  //   final columns = _buildVirtualColumns();
  //   return [
  //     for (final column in columns)
  //       if (column.key == '__actions')
  //         Row(mainAxisSize: MainAxisSize.min, children: [
  //           IconButton(
  //             icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
  //             padding: EdgeInsets.zero,
  //             constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
  //             onPressed: () => _editEntry(row),
  //           ),
  //           IconButton(
  //             icon: const Icon(Icons.delete, size: 18, color: Colors.red),
  //             padding: EdgeInsets.zero,
  //             constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
  //             onPressed: () {
  //               final identifier = _selectedTable == AdminTableType.purchaseVendors
  //                   ? (row['name'] ?? '')
  //                   : (_selectedTable == AdminTableType.items
  //                       ? ((row['id']?.toString().isNotEmpty ?? false) ? row['id'].toString() : (row['name'] ?? ''))
  //                       : (row['id']?.toString() ?? ''));
  //               if (identifier.toString().isNotEmpty) {
  //                 _deleteEntry(identifier);
  //               } else if (mounted) {
  //                 ScaffoldMessenger.of(context).showSnackBar(
  //                   const SnackBar(content: Text('Missing ID/Name'), backgroundColor: Colors.red),
  //                 );
  //               }
  //             },
  //           ),
  //         ])
  //       else
  //         Text(
  //           row[column.key]?.toString() ?? '',
  //           style: const TextStyle(fontSize: 10),
  //           maxLines: 2,
  //           overflow: TextOverflow.ellipsis,
  //         ),
  //   ];
  // }



  List<Widget> _buildVirtualRowCells(
    BuildContext context,
    Map<String, dynamic> row,
    int index,
  ) {
    final columns = _buildVirtualColumns();

    // Check whether this row belongs to the same group
    // as the previous row.
    bool sameGroupAsPrevious = false;

    if (index > 0) {
      final previousRow = _filteredData[index - 1];

      final previousGroup = _getGroupKey(previousRow).trim();
      final currentGroup = _getGroupKey(row).trim();

      sameGroupAsPrevious =
          previousGroup.isNotEmpty &&
          currentGroup.isNotEmpty &&
          previousGroup == currentGroup;
    }

    // Columns whose values should be shown only once
    // inside the same group.
    bool hideRepeatedValue(String key) {
      if (!sameGroupAsPrevious) {
        return false;
      }

      switch (_selectedTable) {
        case AdminTableType.purchases:
          return [
            'vendor',
            'vendor_name',
            'po_number',
            'date',
            'ctrl_date',
            'control_date',
          ].contains(key);

        case AdminTableType.sales:
          return [
            'vendor',
            'vendor_name',
            'so_number',
            'po_number',
            'date',
            'ctrl_date',
            'control_date',
          ].contains(key);

        case AdminTableType.bGradeSales:
        case AdminTableType.rejectionReceived:
        case AdminTableType.vendorRejections:
          return [
            'vendor',
            'vendor_name',
            'so_number',
            'po_number',
            'date',
            'ctrl_date',
            'control_date',
          ].contains(key);

        case AdminTableType.dumpSales:
        case AdminTableType.mandiResales:
          return [
            'tag',
            'date',
            'ctrl_date',
            'control_date',
          ].contains(key);

        default:
          return false;
      }
    }

    return [
      for (final column in columns)
        if (column.key == '__actions')
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.edit,
                  size: 18,
                  color: Colors.blue,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                onPressed: () => _editEntry(row),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete,
                  size: 18,
                  color: Colors.red,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                onPressed: () {
                  final identifier =
                      _selectedTable == AdminTableType.purchaseVendors
                          ? (row['name'] ?? '')
                          : (_selectedTable == AdminTableType.items
                              ? ((row['id']?.toString().isNotEmpty ?? false)
                                  ? row['id'].toString()
                                  : (row['name'] ?? ''))
                              : (row['id']?.toString() ?? ''));

                  if (identifier.toString().isNotEmpty) {
                    _deleteEntry(identifier);
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Missing ID/Name'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              ),
            ],
          )
        else
          Text(
            hideRepeatedValue(column.key)
                ? ''
                : (row[column.key]?.toString() ?? ''),
            style: const TextStyle(fontSize: 10),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
    ];
  }




  /// Server-driven table area: virtualized rows + infinite scroll.
  ///
  /// Pehle screen par jitni rows fit hoti hain utni load hoti hain
  /// ([_startInitialLoadIfNeeded] page size set karta hai), neeche scroll karne
  /// par agle pages auto-load hote hain. 2-3 pages load hone ke baad se top
  /// page memory se evict hota hai (sliding [_window]) aur wapas upar scroll
  /// karne par dobara fetch ho jata hai — true dynamic page loader.
  Widget _buildTableArea() {
    if (_isLoadingData && _filteredData.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_isLoadingData && _filteredData.isEmpty) {
      return const Center(child: Text("No data"));
    }
    final columns = _buildVirtualColumns();
    if (columns.isEmpty) {
      return const Center(child: Text("No data"));
    }
    return Column(
      children: [
        if (_isLoadingData)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: AdminVirtualTable(
            columns: columns,
            rows: _filteredData,
            rowBuilder: _buildVirtualRowCells,
            verticalController: _tableScrollController,
            isLoading: _isLoadingData,
            isLoadingMore: _isLoadingMore,
            hasMore: _hasMore,
            onLoadMore: _loadMore,
            rowHeight: _tableRowHeight,
            groupKey: _getGroupKey,
          
          ),
        ),
      ],
    );
  }

  void _applyFilters() {
    // Date-range and search filters always need a fresh load from page 1.
    // (Older UI code called this directly, so keep it as a thin alias.)
    _loadData();
  }

  // ignore: unused_element
  List<DataColumn> _getDataColumnsLegacy() {
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
        title: Text("Edit ${_getTableName(_selectedTable)} - ID: ${row['id'] ?? ''}"),

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

  // ignore: unused_element
  List<DataRow> _getDataRowsLegacy() {
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
    _searchFieldController.clear();
    setState(() {
      _startDate = null;
      _endDate = null;
      _searchQuery = null;
      _applyFilters();
    });
  }

  /// Compact overview card showing total records + a few key table counts.
  Widget _buildStatsOverview() {
    if (_isLoadingStats && _stats == null) {
      return const SizedBox(
        height: 64,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_stats == null) return const SizedBox.shrink();

    final tables = (_stats!['tables'] as Map<String, dynamic>?) ?? {};
    final totalRecords = _stats!['total_records'] ?? 0;

    final highlights = <MapEntry<String, dynamic>>[
      MapEntry('Purchases', tables['purchases'] ?? 0),
      MapEntry('Sales', tables['sales'] ?? 0),
      MapEntry('Stock', tables['stock_updates'] ?? 0),
      MapEntry('LMD', tables['lmd_data'] ?? 0),
      MapEntry('Items', tables['items'] ?? 0),
      MapEntry('Vendors', tables['vendors'] ?? 0),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade400, Colors.indigo.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              const Text(
                'DATABASE OVERVIEW',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const Spacer(),
              Text(
                'Total: $totalRecords',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: highlights.map((e) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${e.key}: ${e.value}',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            )).toList(),
          ),
        ],
      ),
    );
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
              final navigator = Navigator.of(context);
              await AuthManager.clearAllTokens();
              if (mounted) {
                navigator.pushReplacement(
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
                final navigator = Navigator.of(context);
                Navigator.pop(context);
                await AuthManager.clearAllTokens();
                if (mounted) {
                  navigator.pushReplacement(
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
              _buildStatsOverview(),
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
                  controller: _searchFieldController,
                  decoration: InputDecoration(
                    hintText: "Search...",
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery == null || _searchQuery!.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchFieldController.clear();
                              _onSearchChanged('');
                            },
                          ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _totalRecords > 0
                          ? "Records: ${_filteredData.length} / $_totalRecords"
                          : "Records: ${_filteredData.length}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (_startDate != null || _endDate != null || _searchQuery != null)
                      TextButton(onPressed: _clearFilters, child: const Text("Clear")),
                  ],
                ),
              ),
              // First load: ask for exactly as many rows as fit on the screen.
              // Afterwards this scrollable area owns the viewport used to size it.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _startInitialLoadIfNeeded(constraints.maxHeight);
                    return _buildTableArea();
                  },
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

