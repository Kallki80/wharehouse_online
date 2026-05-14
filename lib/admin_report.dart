import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'api_config.dart';

class AdminReport extends StatefulWidget {
  const AdminReport({super.key});

  @override
  State<AdminReport> createState() => _AdminReportState();
}

class _AdminReportState extends State<AdminReport> {
  final _formKey = GlobalKey<FormState>();

  List<String> _items = [];
  bool _loadingItems = true;

  DateTime? _selectedDate;
  String? _selectedItem;

  List<Map<String, dynamic>> _rows = [];
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
      throw Exception('get_single_value ${table}.${column} failed: ${res.body}');
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
      final previousDate = DateFormat('yyyy-MM-dd')
          .format(_selectedDate!.subtract(const Duration(days: 1)));

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
        whereArgs: [item, chosenDate],
      );

      bGradeSalesQty = await _getSingleValue(
        table: 'b_grade_sales',
        column: 'quantity',
        where: 'item = ? AND date = ?',
        whereArgs: [item, chosenDate],
      );

      stockNextDay = await _getStockUpdateTotalForDate(
        item: item,
        chosenDate: chosenDate,
      );

      stockToday = await _getStockUpdateTotalForDate(
        item: item,
        chosenDate: previousDate,
      );

      final totalQty = stockToday + purchaseReceived + rejectionReceived - vendorRejection;
      final totalConsume = salesQty + dumpSaleQty + mandiResaleQty + bGradeSalesQty;
      final checkStock = totalQty - totalConsume - stockNextDay;

      _rows = [
        {
          'date': chosenDate,
          'iteam': item,
          // columns mapping expects stock_today/stock_next_day
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


  @override
  Widget build(BuildContext context) {
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
                          value: _selectedItem,
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
                                rows: _rows.map((r) {
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

                                  double _getNum(dynamic v) {
                                    if (v == null) return 0.0;
                                    if (v is num) return v.toDouble();
                                    return double.tryParse(v.toString()) ?? 0.0;
                                  }

                                  final dateStr = fmtDate(r['date'] ?? r['chosen_date'] ?? r['ctrl_date']);
                                  final itemStr = (r['iteam'] ?? r['item'] ?? r['item_name'] ?? _selectedItem)?.toString() ?? '';

                                  final stockToday = _getNum(r['stock_today'] ?? r['stock (today)']);
                                  final purchaseReceived = _getNum(r['purchase_received'] ?? r['purchase resived']);
                                  final rejectionReceived = _getNum(r['rejection_received'] ?? r['rejection recived']);
                                  final vendorRejection = _getNum(r['vendor_rejection'] ?? r['vendor rejection'] ?? r['vendor_rejections_qty']);
                                  final stockNextDay = _getNum(r['stock_next_day'] ?? r['stock (next day)']);
                                  final salesQty = _getNum(r['sales'] ?? r['sales_qty']);
                                  final dumpSaleQty = _getNum(r['dump_sale'] ?? r['dump sale']);
                                  final mandiResaleQty = _getNum(r['mandi_resale'] ?? r['mandi resale']);
                                  final bGradeSalesQty = _getNum(r['b_grade_sales'] ?? r['b-grade sales']);

                                  final totalQty = _getNum(r['total_quantity'] ?? r['total quantity']);
                                  final totalSales = _getNum(r['total_sales'] ?? r['total sales']);
                                  final checkStock = _getNum(r['check_stock'] ?? r['check stock']);

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


