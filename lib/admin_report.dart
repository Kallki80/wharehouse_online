import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart';
import 'admin/admin_data_pager.dart';
import 'admin/admin_virtual_table.dart';
import 'api_config.dart';

class AdminReport extends StatefulWidget {
  const AdminReport({super.key});

  @override
  State<AdminReport> createState() => _AdminReportState();
}

class _AdminReportState extends State<AdminReport> {

  // Excel cell values for numeric/text.

  final _formKey = GlobalKey<FormState>();

  List<String> _items = [];
  bool _loadingItems = true;

  DateTime? _selectedDate;
  String? _selectedItem;

  // Manual date range used for the saved-report view + its Excel export.
  DateTime? _filterStart;
  DateTime? _filterEnd;
  // Free-text search (applies to the saved-report view + its Excel export).
  String? _filterSearch;
  Timer? _searchDebounce;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _tableScrollController = ScrollController();

  // Saved admin_report table: screen-fit first page + scroll pagination with
  // a sliding page window (older pages are evicted while scrolling down and
  // re-fetched when scrolling back up — dynamic page loader).
  List<Map<String, dynamic>> _savedFiltered = [];
  bool _savedLoading = false;
  bool _savedLoadingMore = false;
  bool _savedHasMore = false;
  int _savedTotal = 0;
  int _savedPerPage = 40;
  static const double _rowHeight = 42;

  final AdminPageWindow _savedWindow = AdminPageWindow(maxPages: 3);
  bool _isLoadingPrevSaved = false;
  // Bumped on every reset so stale in-flight responses can be dropped.
  int _savedGeneration = 0;
  // True after the first (attempted) load — distinguishes "loading" from
  // "loaded nothing".
  bool _savedLoaded = false;

  bool _savedInitialLoadStarted = false;
  bool _isExporting = false;

  // List<Map<String, dynamic>> _rows = [];
  // bool _isLoading = false;
  // String? _error;

  List<Map<String, dynamic>> _rows = [];

  bool _showSavedData = false;
  bool _isLoading = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _tableScrollController.addListener(_onSavedTableScroll);
    _loadItems();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _tableScrollController.removeListener(_onSavedTableScroll);
    _tableScrollController.dispose();
    super.dispose();
  }

  // Future<void> _loadItems() async {
  //   setState(() {
  //     _loadingItems = true;
  //   });
  //   try {
  //     final res = await http.get(Uri.parse('$baseUrl/get_items'));
  //     if (res.statusCode == 200) {
  //       final decoded = json.decode(res.body);
  //       _items = List<String>.from(decoded);
  //     }
  //   } catch (e) {
  //     _error = e.toString();
  //   } finally {
  //     if (mounted) {
  //       setState(() {
  //         _loadingItems = false;
  //       });
  //     }
  //   }
  // }

  Future<void> _loadItems() async {
    setState(() {
      _loadingItems = true;
    });

    try {
      final res = await http.get(Uri.parse('$baseUrl/get_items'));

      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);

        _items = List<String>.from(
          decoded.map((item) => item['name'].toString()),
        );
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loadingItems = false;
        });
      }
    }
  }






  Future<double> _getSingleValue({
    required String table,
    required String column,
    required String where,
    required List<String> whereArgs,
  }) async {
    final uri = Uri.parse('$baseUrl/get_single_value').replace(queryParameters: {
      'table': table,
      'column': column,
      'where': where,
      for (int i = 0; i < whereArgs.length; i++) 'where_args[$i]': whereArgs[i],
    });

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('get_single_value $table.$column failed: ${res.body}');
    }

    final decoded = json.decode(res.body);
    return (decoded['total'] ?? 0.0).toDouble();
  }

  Future<double> _getStockUpdateTotalForDate({
    required String item,
    required String chosenDate,
  }) async {
    final uri = Uri.parse('$baseUrl/get_stock_update_total_for_date')
        .replace(queryParameters: {
      'item': item,
      'chosen_date': chosenDate,
    });

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('get_stock_update_total_for_date failed: ${res.body}');
    }

    final decoded = json.decode(res.body);
    return (decoded['total'] ?? 0.0).toDouble();
  }

  // Future<void> _submit() async {
  //   final valid = _formKey.currentState?.validate() ?? false;
  //   if (!valid || _selectedDate == null || _selectedItem == null) {
  //     return;
  //   }

  //   setState(() {
  //     _isLoading = true;
  //     _error = null;
  //     _rows = [];
  //   });

  //   try {
  //     final item = _selectedItem!;
  //     final chosenDate = DateFormat('yyyy-MM-dd').format(_selectedDate!);
  //     final nextDate = DateFormat('yyyy-MM-dd')
  //         .format(_selectedDate!.add(const Duration(days: 1)));

  //     double purchaseReceived = 0.0;
  //     double rejectionReceived = 0.0;
  //     double vendorRejection = 0.0;
  //     double salesQty = 0.0;
  //     double dumpSaleQty = 0.0;
  //     double mandiResaleQty = 0.0;
  //     double bGradeSalesQty = 0.0;
  //     double stockNextDay = 0.0;
  //     double stockToday = 0.0;

  //     // Fetch each piece independently; if one fails we still show others.
  //     purchaseReceived = await _getSingleValue(
  //       table: 'purchases',
  //       column: 'qty_receive',
  //       where: 'item = ? AND ctrl_date = ?',
  //       whereArgs: [item, chosenDate],
  //     );

  //     rejectionReceived = await _getSingleValue(
  //       table: 'rejection_received',
  //       column: 'quantity',
  //       where: 'item = ? AND ctrl_date = ?',
  //       whereArgs: [item, chosenDate],
  //     );

  //     vendorRejection = await _getSingleValue(
  //       table: 'vendor_rejections',
  //       column: 'quantity_sent',
  //       where: 'item = ? AND date = ?',
  //       whereArgs: [item, chosenDate],
  //     );

  //     salesQty = await _getSingleValue(
  //       table: 'sales',
  //       column: 'quantity',
  //       where: 'item = ? AND date = ?',
  //       whereArgs: [item, chosenDate],
  //     );

  //     dumpSaleQty = await _getSingleValue(
  //       table: 'dump_sales',
  //       column: 'quantity',
  //       where: 'item = ? AND date = ?',
  //       whereArgs: [item, chosenDate],
  //     );

  //     mandiResaleQty = await _getSingleValue(
  //       table: 'mandi_resales',
  //       column: 'quantity',
  //       where: 'item = ? AND date = ?',
  //       whereArgs: [item, nextDate],
  //     );

  //     bGradeSalesQty = await _getSingleValue(
  //       table: 'b_grade_sales',
  //       column: 'quantity',
  //       where: 'item = ? AND date = ?',
  //       whereArgs: [item, chosenDate],
  //     );

  //     stockNextDay = await _getStockUpdateTotalForDate(
  //       item: item,
  //       chosenDate: nextDate,
  //     );

  //     stockToday = await _getStockUpdateTotalForDate(
  //       item: item,
  //       chosenDate: chosenDate,
  //     );


  //     final totalQty = stockToday + purchaseReceived + rejectionReceived - vendorRejection;
  //     final totalConsume = salesQty + dumpSaleQty + mandiResaleQty + bGradeSalesQty;
  //     final checkStock = totalQty - totalConsume - stockNextDay;

  //     _rows = [
  //       {
  //         'date': chosenDate,
  //         'iteam': item,
  //         'stock_today': stockToday,
  //         'stock_next_day': stockNextDay,
  //         'purchase_received': purchaseReceived,
  //         'rejection_received': rejectionReceived,
  //         'vendor_rejection': vendorRejection,
  //         'sales': salesQty,
  //         'dump_sale': dumpSaleQty,
  //         'mandi_resale': mandiResaleQty,
  //         'b_grade_sales': bGradeSalesQty,
  //         'total_quantity': totalQty,
  //         'total_sales': totalConsume,
  //         'check_stock': checkStock,
  //       }
  //     ];
  //   } catch (e) {
  //     setState(() {
  //       _error = e.toString();
  //     });
  //   } finally {
  //     if (mounted) {
  //       setState(() {
  //         _isLoading = false;
  //       });
  //     }
  //   }

  // }






  Future<void> _submit() async {
    final valid = _formKey.currentState?.validate() ?? false;

    if (!valid || _selectedDate == null || _selectedItem == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _rows = [];
    });

    try {
      final item = _selectedItem!;
      final chosenDate =
          DateFormat('yyyy-MM-dd').format(_selectedDate!);

      final uri = Uri.parse(
        '$baseUrl/get_admin_report_rows',
      ).replace(
        queryParameters: {
          'item': item,
          'chosen_date': chosenDate,
        },
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception(
          'get_admin_report_rows failed: ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body);
      final data = decoded['data'];

      if (data is! List || data.isEmpty) {
        throw Exception('No report data found');
      }

      _rows = List<Map<String, dynamic>>.from(
        data.map(
          (e) => Map<String, dynamic>.from(e),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }


  Future<void> _saveReportToDatabase() async {
    if (_rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No report data to save')),
      );
      return;
    }

    try {
      for (final row in _rows) {
        final response = await http.post(
          Uri.parse('$baseUrl/insert_admin_report'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'date': row['date'],
            'item': row['iteam'],
            'stock_today': row['stock_today'],
            'stock_next_day': row['stock_next_day'],
            'purchase_received': row['purchase_received'],
            'rejection_received': row['rejection_received'],
            'vendor_rejection': row['vendor_rejection'],
            'sales': row['sales'],
            'dump_sale': row['dump_sale'],
            'mandi_resale': row['mandi_resale'],
            'b_grade_sales': row['b_grade_sales'],
            'total_quantity': row['total_quantity'],
            'total_sales': row['total_sales'],
            'check_stock': row['check_stock'],
          }),
        );

        if (response.statusCode == 409) {
          final data = jsonDecode(response.body);
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message']),
              backgroundColor: Colors.orange,
            ),
          );

          return;
        }

        if (response.statusCode != 200) {
          throw Exception(response.body);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Report saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Future<void> _loadSavedReports({bool reset = true}) async {
    if (!mounted) return;
    if (!reset) {
      if (_savedLoadingMore || _savedLoading || !_savedHasMore) return;
      setState(() => _savedLoadingMore = true);
    } else {
      setState(() {
        _savedLoading = true;
        _savedLoadingMore = false;
        _savedHasMore = false;
        _savedGeneration++;
        _isLoadingPrevSaved = false;
        _savedFiltered = [];
        _savedTotal = 0;
        _savedWindow.resetAll();
      });
      if (_tableScrollController.hasClients) {
        _tableScrollController.jumpTo(0);
      }
    }

    final gen = _savedGeneration;
    final requestedPage = reset ? 1 : _savedWindow.lastPage + 1;
    final result = await AdminDataPager.fetchPage(AdminDataQuery(
      endpoint: '/get_admin_report',
      page: requestedPage,
      limit: _savedPerPage,
      startDate: _filterStart,
      endDate: _filterEnd,
      search: _filterSearch,
    ));

    // Drop responses of an older filter/search query.
    if (!mounted || gen != _savedGeneration) return;
    if (!result.success) {
      setState(() {
        _savedLoading = false;
        _savedLoadingMore = false;
        _savedLoaded = true;
        if (reset) {
          _savedFiltered = [];
          _savedTotal = 0;
          _savedHasMore = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load saved reports: ${result.error}'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _loadSavedReports(reset: reset),
          ),
        ),
      );
      return;
    }

    int evictedFront = 0;
    setState(() {
      if (reset) {
        _savedFiltered = result.rows;
        _savedWindow.reset(page: requestedPage, rowCount: result.rows.length);
        _showSavedData = true;
      } else {
        _savedFiltered.addAll(result.rows);
        _savedWindow.recordAppend(page: requestedPage, rowCount: result.rows.length);
        // Dynamic page loader: top page is freed after 2-3 pages down.
        evictedFront = _savedWindow.evictFront(_savedFiltered);
      }
      _savedHasMore = result.hasMore && result.rows.isNotEmpty;
      _savedTotal =
          result.total > _savedFiltered.length ? result.total : _savedFiltered.length;
      _savedLoading = false;
      _savedLoadingMore = false;
      _savedLoaded = true;
    });
    // Keep the visible rows stable after evicting rows from the top.
    if (evictedFront > 0) {
      AdminPageWindow.compensateTopChange(
          _tableScrollController, -evictedFront, _rowHeight);
    }
  }

  /// Called by the virtualized table whenever the user scrolls near the end.
  Future<void> _loadSavedMore() => _loadSavedReports(reset: false);

  void _startSavedInitialLoadIfNeeded(double viewportHeight) {
    if (_savedInitialLoadStarted) return;
    _savedInitialLoadStarted = true;
    // First page exactly fills the visible table area (+5 rows of runway for
    // the load-more threshold).
    final fits = ((viewportHeight - 40) / _rowHeight).ceil() + 5;
    _savedPerPage = fits < 15 ? 15 : (fits > 100 ? 100 : fits);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showSavedData) _loadSavedReports();
    });
  }

  /// Debounced free-text search over the whole saved-report table.
  void _onSavedSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() => _filterSearch = value.trim().isEmpty ? null : value.trim());
      if (_showSavedData) _loadSavedReports();
    });
  }

  /// Date-range dialog: APPLY filters the saved table (and its Excel export),
  /// CLEAR removes the range again.
  Future<void> _showSavedDateFilter() async {
    DateTime? start = _filterStart;
    DateTime? end = _filterEnd;
    final picked = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          title: const Text('Filter saved reports by date'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 18),
              onPressed: () async {
                final p = await showDatePicker(
                  context: context,
                  initialDate: start ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (p != null) setDS(() => start = p);
              },
              label: Text(start == null
                  ? 'Select start date'
                  : DateFormat('dd-MM-yyyy').format(start!)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 18),
              onPressed: () async {
                final p = await showDatePicker(
                  context: context,
                  initialDate: end ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (p != null) setDS(() => end = p);
              },
              label: Text(end == null
                  ? 'Select end date'
                  : DateFormat('dd-MM-yyyy').format(end!)),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, {'start': null, 'end': null, '__clear': start}),
              child: const Text('CLEAR'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, {'start': start, 'end': end}),
              child: const Text('APPLY'),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    if (!mounted) return;
    if (picked.containsKey('__clear')) {
      setState(() {
        _filterStart = null;
        _filterEnd = null;
      });
    } else {
      setState(() {
        _filterStart = picked['start'];
        _filterEnd = picked['end'];
      });
    }
    if (_showSavedData) _loadSavedReports();
  }

  void _clearSavedFilters() {
    _searchController.clear();
    setState(() {
      _filterStart = null;
      _filterEnd = null;
      _filterSearch = null;
    });
    if (_showSavedData) _loadSavedReports();
  }

  /// Scroll listener: re-fetches the evicted page above the window when the
  /// user scrolls back to the top (sliding-window page eviction).
  void _onSavedTableScroll() {
    if (!mounted || _isLoadingPrevSaved || _savedLoading || _savedLoadingMore) {
      return;
    }
    if (!_savedWindow.canLoadPrevious) return;
    if (!_tableScrollController.hasClients) return;
    if (_tableScrollController.position.pixels <= _savedPerPage * _rowHeight) {
      _loadSavedPreviousPage();
    }
  }

  /// Prepends the page above the current window (and evicts the bottom one
  /// when the window grows past [AdminPageWindow.maxPages] pages).
  Future<void> _loadSavedPreviousPage() async {
    if (_isLoadingPrevSaved || _savedLoading || _savedLoadingMore) return;
    if (!_savedWindow.canLoadPrevious) return;
    setState(() => _isLoadingPrevSaved = true);
    final gen = _savedGeneration;
    final target = _savedWindow.prevFirstPage;

    final result = await AdminDataPager.fetchPage(AdminDataQuery(
      endpoint: '/get_admin_report',
      page: target,
      limit: _savedPerPage,
      startDate: _filterStart,
      endDate: _filterEnd,
      search: _filterSearch,
    ));
    if (!mounted || gen != _savedGeneration) return;
    if (!result.success) {
      setState(() => _isLoadingPrevSaved = false);
      debugPrint('AdminReport: previous page $target failed: ${result.error}');
      return;
    }

    setState(() {
      _savedFiltered.insertAll(0, result.rows);
      _savedWindow.recordPrepend(page: target, rowCount: result.rows.length);
      if (_savedWindow.evictBack(_savedFiltered) > 0) {
        // Rows exist again after the new last page → allow loading forward.
        _savedHasMore = true;
      }
      _isLoadingPrevSaved = false;
    });
    if (result.rows.isNotEmpty) {
      AdminPageWindow.compensateTopChange(
          _tableScrollController, result.rows.length, _rowHeight);
    }
  }

  /// Columns of the saved-report virtual table: union of every key found on
  /// the currently loaded window of rows (same approach as the dashboard).
  List<AdminTableColumn> _buildSavedColumns() {
    if (_savedFiltered.isEmpty) return const [];
    final keys = <String>[];
    final seen = <String>{};
    for (final row in _savedFiltered) {
      for (final key in row.keys) {
        if (seen.add(key)) keys.add(key);
      }
    }
    return keys
        .map((k) => AdminTableColumn(
              key: k,
              label: k.replaceAll('_', ' ').toUpperCase(),
              width: _savedColumnWidth(k),
            ))
        .toList();
  }

  /// Slightly wider columns for long text fields, narrow for ids/dates.
  double _savedColumnWidth(String key) {
    final k = key.toLowerCase();
    if (k == 'id' || k.endsWith('_id')) return 80;
    if (k.contains('date')) return 110;
    if (k.contains('item') || k.contains('iteam')) return 170;
    return 130;
  }

  List<Widget> _buildSavedRowCells(
      BuildContext context, Map<String, dynamic> row, int index) {
    final columns = _buildSavedColumns();
    return [
      for (final column in columns)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '${row[column.key] ?? ''}',
            style: const TextStyle(fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
  }

  /// Saved-report table: virtualized rows with viewport-sized initial load,
  /// infinite scroll and sliding-window page eviction.
  Widget _buildSavedTableArea() {
    if (_savedFiltered.isEmpty) {
      if (_savedLoading || !_savedLoaded) {
        return const Center(child: CircularProgressIndicator());
      }
      return const Center(child: Text('No saved reports found'));
    }
    final columns = _buildSavedColumns();
    if (columns.isEmpty) {
      return const Center(child: Text('No saved reports found'));
    }
    return Column(
      children: [
        if (_savedLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: AdminVirtualTable(
            columns: columns,
            rows: _savedFiltered,
            rowBuilder: _buildSavedRowCells,
            verticalController: _tableScrollController,
            isLoading: _savedLoading,
            isLoadingMore: _savedLoadingMore,
            hasMore: _savedHasMore,
            onLoadMore: _loadSavedMore,
            rowHeight: _rowHeight,
            emptyMessage: 'No saved reports found',
          ),
        ),
      ],
    );
  }


  List<Map<String, dynamic>> _getCurrentTableData() {
    return _showSavedData ? _savedFiltered : _rows;
  }



  /// Exports the *whole* saved admin_report data set (not just the loaded
  /// pages) and honours the active date-range / search filters.
  Future<void> _exportToExcel() async {
    if (!mounted) return;
    setState(() => _isExporting = true);
    try {
      // Single-day "view data" rows (not saved yet) export as-is.
      List<Map<String, dynamic>> rows;
      bool truncated = false;
      if (!_showSavedData) {
        rows = List<Map<String, dynamic>>.from(_rows);
      } else {
        // Pull every page from the server so the file holds the full set.
        final result = await AdminDataPager.fetchAll(
          endpoint: '/get_admin_report',
          pageSize: 1000,
          startDate: _filterStart,
          endDate: _filterEnd,
          search: _filterSearch,
        );
        if (result.error != null && result.rows.isEmpty) {
          throw Exception(result.error);
        }
        rows = AdminDataPager.filterByDateRange(
          result.rows,
          _filterStart,
          _filterEnd,
        );
        truncated = result.truncated;
      }

    if (rows.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No data to export for the selected filters.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final excel = Excel.createExcel();

    // Remove default sheet and rename it
    final defaultSheet = excel.getDefaultSheet();

    if (defaultSheet != null) {
      excel.rename(defaultSheet, 'AdminReport');
    }

    final sheet = excel['AdminReport'];

    const headers = [
      'Date',
      'Item',
      'Stock Today',
      'Purchase Received',
      'Rejection Received',
      'Vendor Rejection',
      'Stock Next Day',
      'Sales',
      'Dump Sale',
      'Mandi Resale',
      'B Grade Sales',
      'Total Quantity',
      'Total Sales',
      'Check Stock',
    ];

    // Header Row
    for (int col = 0; col < headers.length; col++) {
      sheet
          .cell(
            CellIndex.indexByColumnRow(
              columnIndex: col,
              rowIndex: 0,
            ),
          )
          .value = TextCellValue(headers[col]);
    }

    String formatDate(dynamic value) {
      if (value == null) return '';

      try {
        return DateFormat(
          'dd-MM-yyyy',
        ).format(
          DateTime.parse(value.toString()),
        );
      } catch (_) {
        return value.toString();
      }
    }

    double getNumber(dynamic value) {
      if (value == null) return 0.0;

      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value.toString()) ?? 0.0;
    }

    // Data Rows
    for (int row = 0; row < rows.length; row++) {
      final r = rows[row];

      final values = [
        formatDate(r['date']),
        (r['item'] ?? r['iteam'] ?? '').toString(),
        getNumber(r['stock_today']),
        getNumber(r['purchase_received']),
        getNumber(r['rejection_received']),
        getNumber(r['vendor_rejection']),
        getNumber(r['stock_next_day']),
        getNumber(r['sales']),
        getNumber(r['dump_sale']),
        getNumber(r['mandi_resale']),
        getNumber(r['b_grade_sales']),
        getNumber(r['total_quantity']),
        getNumber(r['total_sales']),
        getNumber(r['check_stock']),
      ];

      for (int col = 0; col < values.length; col++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: col,
            rowIndex: row + 1,
          ),
        );

        final value = values[col];

        if (value is num) {
          cell.value = DoubleCellValue(value.toDouble());
        } else {
          cell.value = TextCellValue(value.toString());
        }
      }
    }

    final bytes = excel.encode();

    if (bytes == null) {
      throw Exception("Failed to generate excel file");
    }

    final fileName =
        'admin_report_${DateTime.now().millisecondsSinceEpoch}.xlsx';

    final out = await _getOutputFilePath(fileName);

    await out.writeAsBytes(
      bytes,
      flush: true,
    );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Excel saved (${rows.length} rows)'
          '${truncated ? ' [truncated]' : ''}\n${out.path}',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      debugPrint('AdminReport: export failed: $e');
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

  Future<io.File> _getOutputFilePath(String fileName) async {
    if (kIsWeb) {
      throw UnsupportedError('Web export not supported in this build');
    }

    // ignore: avoid_web_libraries_in_flutter
    final baseDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final outPath = '${baseDir.path}/$fileName';
    // ignore: unnecessary_import
    // dart:io is only used on non-web targets.
    return io.File(outPath);
  }

  @override
  Widget build(BuildContext context) {
    final tableData = _getCurrentTableData();
    return Scaffold(

      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Admin Report',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        const Text(
                          'Date + Item based report (Table view)',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _selectedItem,
                          items: _loadingItems
                              ? [
                                  const DropdownMenuItem(value: null, child: Text('Loading items...')),
                                ]
                              : _items
                                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                  .toList(),
                          onChanged: (v) => setState(() => _selectedItem = v),
                          validator: (v) => v == null ? 'Please select item' : null,
                          decoration: const InputDecoration(
                            labelText: 'Item',
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() => _selectedDate = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            _selectedDate == null
                                ? 'Select Date'
                                : DateFormat('dd-MM-yyyy').format(_selectedDate!),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _submit,
                            icon: const Icon(Icons.search),
                            label: const Text('View Data'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    _saveReportToDatabase();
                                  },
                            icon: const Icon(Icons.picture_as_pdf),
                            label: const Text('Generate report'),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // Re-arm the viewport-sized initial load; the table's
                        // LayoutBuilder triggers it once it has its height.
                        setState(() {
                          _savedInitialLoadStarted = false;
                          _showSavedData = true;
                        });
                      },
                      icon: const Icon(Icons.assessment),
                      label: const Text('Show All Report'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading
                        ? null
                        : () async {
                          await _submit();

                          setState(() {
                            _showSavedData = false;
                          });
                        },
                      icon: const Icon(Icons.table_view),
                      label: const Text('View Data'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isExporting ||
                          _isLoading ||
                          _getCurrentTableData().isEmpty
                      ? null
                      : _exportToExcel,
                  icon: _isExporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: const Text('Export to Excel'),
                ),
              ),
              if (_showSavedData) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search saved reports...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: (_filterSearch == null || _filterSearch!.isEmpty)
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onSavedSearchChanged('');
                            },
                          ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                  ),
                  onChanged: _onSavedSearchChanged,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      _savedTotal > 0
                          ? 'Records: ${_savedFiltered.length} / $_savedTotal'
                          : 'Records: ${_savedFiltered.length}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Filter by date',
                      icon: const Icon(Icons.date_range, size: 20),
                      onPressed: _showSavedDateFilter,
                    ),
                    if (_filterStart != null ||
                        _filterEnd != null ||
                        _filterSearch != null)
                      TextButton(
                        onPressed: _clearSavedFilters,
                        child: const Text('Clear'),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Expanded(
                child: _showSavedData
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          _startSavedInitialLoadIfNeeded(
                              constraints.maxHeight);
                          return _buildSavedTableArea();
                        },
                      )
                    : _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : tableData.isEmpty
                            ? const Center(child: Text('No data found'))
                            : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: DataTable(
                                headingRowColor:
                                    WidgetStateProperty.all(Colors.indigo.shade50),
                                dataRowMinHeight: 40,
                                columns: const [
                                  DataColumn(label: Text('date')),
                                  DataColumn(label: Text('iteam')),
                                  DataColumn(label: Text('stock (today)')),
                                  DataColumn(label: Text('purchase resived')),
                                  DataColumn(label: Text('rejection recived')),
                                  DataColumn(label: Text('vendor rejection')),
                                  DataColumn(label: Text('stock (next day)')),
                                  DataColumn(label: Text('sales')),
                                  DataColumn(label: Text('dump sale')),
                                  DataColumn(label: Text('mandi resale')),
                                  DataColumn(label: Text('b-grade sales')),
                                  DataColumn(label: Text('PCS')),
                                  DataColumn(label: Text('total quantity')),
                                  DataColumn(label: Text('total sales')),
                                  DataColumn(label: Text('check stock')),
                                ],
                                rows: tableData.map((r) {
                                // rows: _rows.map((r) {
                                  String fmtDate(dynamic v) {
                                    if (v == null) return '';
                                    final s = v.toString().trim();
                                    if (s.isEmpty) return '';
                                    try {
                                      return DateFormat('dd-MM-yyyy')
                                          .format(DateTime.parse(s));
                                    } catch (_) {
                                      return s;
                                    }
                                  }
                                  double getNum(dynamic v) {
                                    if (v == null) return 0.0;
                                    if (v is num) return v.toDouble();
                                    return double.tryParse(v.toString()) ?? 0.0;
                                  }
                                  final dateStr = fmtDate(r['date'] ?? r['chosen_date'] ?? r['ctrl_date']);
                                  final itemStr = (r['iteam'] ?? r['item'] ?? r['item_name'] ?? _selectedItem)?.toString() ?? '';

                                  final stockToday = getNum(r['stock_today'] ?? r['stock (today)']);
                                  final purchaseReceived = getNum(r['purchase_received'] ?? r['purchase resived']);
                                  final rejectionReceived = getNum(r['rejection_received'] ?? r['rejection recived']);
                                  final vendorRejection = getNum(r['vendor_rejection'] ?? r['vendor rejection'] ?? r['vendor_rejections_qty']);
                                  final stockNextDay = getNum(r['stock_next_day'] ?? r['stock (next day)']);
                                  final salesQty = getNum(r['sales'] ?? r['sales_qty']);
                                  final dumpSaleQty = getNum(r['dump_sale'] ?? r['dump sale']);
                                  final mandiResaleQty = getNum(r['mandi_resale'] ?? r['mandi resale']);
                                  final bGradeSalesQty = getNum(r['b_grade_sales'] ?? r['b-grade sales']);
                                  final pcs = getNum(r['total_quantity_pcs']);
                                  final totalQty = getNum(r['total_quantity'] ?? r['total quantity']);
                                  final totalSales = getNum(r['total_sales'] ?? r['total sales']);
                                  final checkStock = getNum(r['check_stock'] ?? r['check stock']);

                                  return DataRow(cells: [
                                    DataCell(Text(dateStr)),
                                    DataCell(Text(itemStr)),
                                    DataCell(Text(stockToday == 0.0 && r['stock_today'] == null ? '' : stockToday.toString())),
                                    DataCell(Text(purchaseReceived == 0.0 && r['purchase_received'] == null ? '' : purchaseReceived.toString())),
                                    DataCell(Text(rejectionReceived == 0.0 && r['rejection_received'] == null ? '' : rejectionReceived.toString())),
                                    DataCell(Text(vendorRejection == 0.0 && r['vendor_rejection'] == null ? '' : vendorRejection.toString())),
                                    DataCell(Text(stockNextDay == 0.0 && r['stock_next_day'] == null ? '' : stockNextDay.toString())),
                                    DataCell(Text(salesQty == 0.0 && r['sales'] == null ? '' : salesQty.toString())),
                                    DataCell(Text(dumpSaleQty == 0.0 && r['dump_sale'] == null ? '' : dumpSaleQty.toString())),
                                    DataCell(Text(mandiResaleQty == 0.0 && r['mandi_resale'] == null ? '' : mandiResaleQty.toString())),
                                    DataCell(Text(bGradeSalesQty == 0.0 && r['b_grade_sales'] == null ? '' : bGradeSalesQty.toString())),
                                    DataCell(Text(pcs == 0.0 && r['total_quantity_pcs'] == null ? '' : pcs.toString())),
                                    DataCell(Text(totalQty == 0.0 && r['total_quantity'] == null ? '' : totalQty.toString())),
                                    DataCell(Text(totalSales == 0.0 && r['total_sales'] == null ? '' : totalSales.toString())),
                                    DataCell(Text(checkStock == 0.0 && r['check_stock'] == null ? '' : checkStock.toString())),
                                  ]);
                                }).toList(),
                              ),
                            ),
                          ),
              ),

            ],
          ),
        ),
      ),
    );
  }
}


