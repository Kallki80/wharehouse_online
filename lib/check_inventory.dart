import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// const String apiBaseUrl = 'http://13.53.71.103:5000/';
// const String apiBaseUrl = 'http://10.0.2.2:5000';
const String apiBaseUrl = 'http://127.0.0.1:5000';

// API Helper Functions
Future<List<String>> getAllUniqueItems() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_items'));
  if (response.statusCode == 200) {
    return List<String>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load items');
  }
}

Future<double> getSingleValue({required String table, required String column, String? where, List<String>? whereArgs}) async {
  final queryParams = {
    'table': table,
    'column': column,
    if (where != null) 'where': where,
    if (whereArgs != null) ...whereArgs.asMap().map((i, arg) => MapEntry('where_args[$i]', arg)),
  };
  final uri = Uri.parse('$apiBaseUrl/get_single_value').replace(queryParameters: queryParams);
  final response = await http.get(uri);
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['total'] ?? 0.0;
  } else {
    throw Exception('Failed to get single value');
  }
}

Future<double> getStockUpdateTotalForDate({required String item, required String chosenDate}) async {
  final queryParams = {'item': item, 'chosen_date': chosenDate};
  final uri = Uri.parse('$apiBaseUrl/get_stock_update_total_for_date').replace(queryParameters: queryParams);
  final response = await http.get(uri);
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['total'] ?? 0.0;
  } else {
    throw Exception('Failed to get stock update total');
  }
}

class CheckInventory extends StatefulWidget {
  const CheckInventory({super.key});  @override
  State<CheckInventory> createState() => _CheckInventoryState();
}

class _CheckInventoryState extends State<CheckInventory> {
  final _formKey = GlobalKey<FormState>();

  // --- स्टेट वेरिएबल्स ---
  String? _selectedItem;
  DateTime? _selectedDate;
  List<String> _itemList = [];
  bool _isLoading = true;
  bool _isCalculating = false;

  // --- रिपोर्ट वैल्यूज ---
  String _totalQuantity = "0 Kg";
  String _totalConsumption = "0 Kg";
  String _checkStock = "0 Kg";
  String _stockUpdateToday = "0 Kg";
  String _stockUpdatePreviousDay = "0 Kg";

  // --- डीबग टेबल के लिए वेरिएबल्स ---
  List<Map<String, String>> _debugData = [];
  bool _showDebugTable = false;

  // ❗️ कलर थीम
  final Color primaryColor = const Color(0xFF3F51B5); // Indigo
  final Color accentColor = const Color(0xFF5C6BC0); // Light Indigo

  @override
  void initState() {
    super.initState();
    _loadUniqueItems();
  }

  Future<void> _loadUniqueItems() async {
    try {
      final items = await getAllUniqueItems();
      if (!mounted) return;
      setState(() {
        _itemList = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load items from API.')),
      );
    }
  }

  // ❗️❗️❗️ फंक्शन यहाँ ठीक किया गया है ❗️❗️❗️
  void _submit() async {
    final isFormValid = _formKey.currentState!.validate();
    if (!isFormValid || _selectedDate == null) {
      // Trigger validation display
      setState(() {});
      return;
    }

    setState(() {
      _isCalculating = true;
      _showDebugTable = false;
      _debugData = [];
    });

    try {
      final item = _selectedItem!;
      final date = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final previousDate = DateFormat('yyyy-MM-dd').format(_selectedDate!.subtract(const Duration(days: 1)));

      // ✅ 1. 'qty_accept' की जगह 'qty_receive' कर दिया गया है
      final purchaseReceived = await getSingleValue(table: 'purchases', column: 'qty_receive', where: 'item = ? AND ctrl_date = ?', whereArgs: [item, date]);
      final rejectionReceived = await getSingleValue(table: 'rejection_received', column: 'quantity', where: 'item = ? AND ctrl_date = ?', whereArgs: [item, date]);
      final vendorRejectionQty = await getSingleValue(table: 'vendor_rejections', column: 'quantity_sent', where: 'item = ? AND date = ?', whereArgs: [item, date]);
      final salesQty = await getSingleValue(table: 'sales', column: 'quantity', where: 'item = ? AND date = ?', whereArgs: [item, date]);
      final dumpSaleQty = await getSingleValue(table: 'dump_sales', column: 'quantity', where: 'item = ? AND date = ?', whereArgs: [item, date]);
      final mandiResaleQty = await getSingleValue(table: 'mandi_resales', column: 'quantity', where: 'item = ? AND date = ?', whereArgs: [item, date]);
      final bGradeSalesQty = await getSingleValue(table: 'b_grade_sales', column: 'quantity', where: 'item = ? AND date = ?', whereArgs: [item, date]);
      final stockUpdateTodayVal = await getStockUpdateTotalForDate(item: item, chosenDate: date);
      final stockUpdatePreviousDayVal = await getStockUpdateTotalForDate(item: item, chosenDate: previousDate);

      // ✅ 2. गणना में 'purchaseAccepted' की जगह 'purchaseReceived' का उपयोग
      final totalQty = stockUpdatePreviousDayVal + purchaseReceived + rejectionReceived - vendorRejectionQty;
      final totalConsume = salesQty + dumpSaleQty + mandiResaleQty + bGradeSalesQty;
      final checkStockVal = totalQty - totalConsume - stockUpdateTodayVal;

      final newDebugData = [
        {'source': 'Stock (Prev. Day)', 'value': stockUpdatePreviousDayVal.toStringAsFixed(2), 'category': 'Quantity (+)'},
        // ✅ डीबग टेबल में लेबल भी अपडेट कर दिया गया
        {'source': 'Purchase Received', 'value': purchaseReceived.toStringAsFixed(2), 'category': 'Quantity (+)'},
        {'source': 'Rejection Received', 'value': rejectionReceived.toStringAsFixed(2), 'category': 'Quantity (+)'},
        {'source': 'Vendor Rejection', 'value': vendorRejectionQty.toStringAsFixed(2), 'category': 'Quantity (-)'},
        {'source': 'Sales', 'value': salesQty.toStringAsFixed(2), 'category': 'Consumption'},
        {'source': 'Dump Sale', 'value': dumpSaleQty.toStringAsFixed(2), 'category': 'Consumption'},
        {'source': 'Mandi Resale', 'value': mandiResaleQty.toStringAsFixed(2), 'category': 'Consumption'},
        {'source': 'B-Grade Sales', 'value': bGradeSalesQty.toStringAsFixed(2), 'category': 'Consumption'},
        {'source': 'Stock (Today)', 'value': stockUpdateTodayVal.toStringAsFixed(2), 'category': 'Reference'},
      ];

      if (!mounted) return;
      setState(() {
        _totalQuantity = "${totalQty.toStringAsFixed(2)} Kg";
        _totalConsumption = "${totalConsume.toStringAsFixed(2)} Kg";
        _checkStock = "${checkStockVal.toStringAsFixed(2)} Kg";
        _stockUpdateToday = "${stockUpdateTodayVal.toStringAsFixed(2)} Kg";
        _stockUpdatePreviousDay = "${stockUpdatePreviousDayVal.toStringAsFixed(2)} Kg";
        _debugData = newDebugData..sort((a, b) => a['category']!.compareTo(b['category']!));
        _showDebugTable = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error during calculation: $e')));
    } finally {
      if (mounted) {
        setState(() { _isCalculating = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Check Item Report", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryColor, accentColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 4,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 8.0,
              shadowColor: primaryColor.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Text("Select Item and Date", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryColor), textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedItem,
                        hint: const Text("Select an Item"),
                        isExpanded: true,
                        items: _itemList.map((String item) => DropdownMenuItem<String>(value: item, child: Text(item, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (newValue) => setState(() { _selectedItem = newValue; }),
                        validator: (value) => value == null ? 'Please select an item' : null,
                        decoration: InputDecoration(
                          labelText: 'Item',
                          prefixIcon: Icon(Icons.inventory_2_outlined, color: accentColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, color: Colors.black54),
                        onPressed: () async {
                          DateTime? pickedDate = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            builder: (context, child) => Theme(
                              data: ThemeData.light().copyWith(colorScheme: ColorScheme.light(primary: primaryColor)),
                              child: child!,
                            ),
                          );
                          if (pickedDate != null) setState(() => _selectedDate = pickedDate);
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(55),
                          textStyle: const TextStyle(fontSize: 16),
                          side: BorderSide(color: _formKey.currentState?.validate() == false && _selectedDate == null ? Theme.of(context).colorScheme.error : Colors.grey.shade400),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        label: Text(_selectedDate == null ? "Select Date" : "Date: ${DateFormat('dd-MM-yyyy').format(_selectedDate!)}", style: const TextStyle(color: Colors.black87)),
                      ),
                      // Validation message for date
                      ValueListenableBuilder(
                        valueListenable: ValueNotifier(_formKey.currentState?.validate()),
                        builder: (context, isValid, child) {
                          if (isValid == false && _selectedDate == null) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                              child: Text('Please select a date', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: _isCalculating ? Container() : const Icon(Icons.analytics_outlined, color: Colors.white),
              onPressed: _isCalculating ? null : _submit,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 5,
              ),
              label: _isCalculating
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                  : const Text("Generate Report"),
            ),
            if (_showDebugTable) ...[
              const SizedBox(height: 24),
              const Divider(thickness: 1),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  int crossAxisCount = (constraints.maxWidth < 600) ? 2 : 3;
                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: (crossAxisCount == 2) ? 1.0 : 1.2,
                    children: [
                      _buildInfoCard(icon: Icons.add_shopping_cart, iconColor: Colors.green, title: "Total Quantity", value: _totalQuantity),
                      _buildInfoCard(icon: Icons.remove_shopping_cart, iconColor: Colors.red, title: "Total Sales", value: _totalConsumption),
                      _buildInfoCard(icon: Icons.inventory_2, iconColor: Colors.blue, title: "Check Stock", value: _checkStock),
                      _buildInfoCard(icon: Icons.update, iconColor: Colors.orange, title: "Stock (date)", value: _stockUpdateToday),
                      _buildInfoCard(icon: Icons.history, iconColor: Colors.purple, title: "Stock (Prev. Day)", value: _stockUpdatePreviousDay),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: primaryColor.withValues(alpha: 0.15),
                      child: const Text("Calculation Breakdown", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 24,
                        columns: const [
                          DataColumn(label: Text('Source', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Value', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: _debugData.map((data) {
                          return DataRow(
                              cells: [
                                DataCell(Text(data['source']!)),
                                DataCell(Text(data['value']!)),
                                DataCell(Text(data['category']!)),
                              ]);
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({required IconData icon, required Color iconColor, required String title, required String value}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32, color: iconColor),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 16, color: Colors.black54, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
