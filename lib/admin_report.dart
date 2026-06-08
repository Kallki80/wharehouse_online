import 'dart:convert';

import 'dart:io' as io;





import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';

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

  // List<Map<String, dynamic>> _rows = [];
  // bool _isLoading = false;
  // String? _error;

  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _savedRows = [];

  bool _showSavedData = false;
  bool _isLoading = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() {
      _loadingItems = true;
    });
    try {
      final res = await http.get(Uri.parse('$baseUrl/get_items'));
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        _items = List<String>.from(decoded);
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
      final chosenDate = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final nextDate = DateFormat('yyyy-MM-dd')
          .format(_selectedDate!.add(const Duration(days: 1)));

      double purchaseReceived = 0.0;
      double rejectionReceived = 0.0;
      double vendorRejection = 0.0;
      double salesQty = 0.0;
      double dumpSaleQty = 0.0;
      double mandiResaleQty = 0.0;
      double bGradeSalesQty = 0.0;
      double stockNextDay = 0.0;
      double stockToday = 0.0;

      // Fetch each piece independently; if one fails we still show others.
      purchaseReceived = await _getSingleValue(
        table: 'purchases',
        column: 'qty_receive',
        where: 'item = ? AND ctrl_date = ?',
        whereArgs: [item, chosenDate],
      );

      rejectionReceived = await _getSingleValue(
        table: 'rejection_received',
        column: 'quantity',
        where: 'item = ? AND ctrl_date = ?',
        whereArgs: [item, chosenDate],
      );

      vendorRejection = await _getSingleValue(
        table: 'vendor_rejections',
        column: 'quantity_sent',
        where: 'item = ? AND date = ?',
        whereArgs: [item, chosenDate],
      );

      salesQty = await _getSingleValue(
        table: 'sales',
        column: 'quantity',
        where: 'item = ? AND date = ?',
        whereArgs: [item, chosenDate],
      );

      dumpSaleQty = await _getSingleValue(
        table: 'dump_sales',
        column: 'quantity',
        where: 'item = ? AND date = ?',
        whereArgs: [item, chosenDate],
      );

      mandiResaleQty = await _getSingleValue(
        table: 'mandi_resales',
        column: 'quantity',
        where: 'item = ? AND date = ?',
        whereArgs: [item, nextDate],
      );

      bGradeSalesQty = await _getSingleValue(
        table: 'b_grade_sales',
        column: 'quantity',
        where: 'item = ? AND date = ?',
        whereArgs: [item, chosenDate],
      );

      stockNextDay = await _getStockUpdateTotalForDate(
        item: item,
        chosenDate: nextDate,
      );

      stockToday = await _getStockUpdateTotalForDate(
        item: item,
        chosenDate: chosenDate,
      );


      final totalQty = stockToday + purchaseReceived + rejectionReceived - vendorRejection;
      final totalConsume = salesQty + dumpSaleQty + mandiResaleQty + bGradeSalesQty;
      final checkStock = totalQty - totalConsume - stockNextDay;

      _rows = [
        {
          'date': chosenDate,
          'iteam': item,
          'stock_today': stockToday,
          'stock_next_day': stockNextDay,
          'purchase_received': purchaseReceived,
          'rejection_received': rejectionReceived,
          'vendor_rejection': vendorRejection,
          'sales': salesQty,
          'dump_sale': dumpSaleQty,
          'mandi_resale': mandiResaleQty,
          'b_grade_sales': bGradeSalesQty,
          'total_quantity': totalQty,
          'total_sales': totalConsume,
          'check_stock': checkStock,
        }
      ];
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
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


  Future<void> _loadSavedReports() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_admin_report'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _savedRows =
              List<Map<String, dynamic>>.from(data['data']);
          _showSavedData = true;
        });
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }


  List<Map<String, dynamic>> _getCurrentTableData() {
    return _showSavedData ? _savedRows : _rows;
  }



  Future<void> _exportToExcel() async {

    final data = _savedRows.isNotEmpty ? _savedRows : _rows;

    if (data.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No data to export'),
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
    for (int row = 0; row < data.length; row++) {
      final r = data[row];

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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Excel saved successfully\n${out.path}',
        ),
      ),
    );
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
                      onPressed: () async {
                        await _loadSavedReports();
                        setState(() {
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
                  onPressed: _isLoading || _getCurrentTableData().isEmpty
                      ? null
                      : () async {
                          await _exportToExcel();
                        },
                  icon: const Icon(Icons.download),
                  label: const Text('Export to Excel'),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _rows.isEmpty
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


