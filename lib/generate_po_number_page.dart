import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'package:math_expressions/math_expressions.dart';
import 'dart:convert';

import 'api_config.dart';

// API Helper Functions
Future<List<String>> getProductManagers() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_product_managers'));
  if (response.statusCode == 200) {
    final decoded = json.decode(response.body);
    // API returns: [{"id":..., "name":...}, ...]
    if (decoded is List) {
      return decoded
          .map((e) {
            if (e is Map<String, dynamic>) return e['name']?.toString();
            return e?.toString();
          })
          .whereType<String>()
          .toList();
    }
    throw Exception('Unexpected get_product_managers response format');
  } else {
    throw Exception('Failed to load product managers');
  }
}

// Future<List<String>> getItems() async {
//   final response = await http.get(Uri.parse('$apiBaseUrl/get_items'));
//   print(response.body);
//   if (response.statusCode == 200) {
//     return List<String>.from(json.decode(response.body));
//   } else {
//     throw Exception('Failed to load items');
//   }
// }

Future<List<String>> getItems() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_items'));

  if (response.statusCode == 200) {
    final List<dynamic> data = json.decode(response.body);

    return data
        .map((item) => item['name'].toString())
        .toList();
  } else {
    throw Exception('Failed to load items');
  }
}

// Future<List<String>> getPurchaseVendors() async {
//   final response = await http.get(Uri.parse('$apiBaseUrl/get_purchase_vendors'));


//   print("VENDORS RESPONSE:");
//   print(response.body);


//   if (response.statusCode == 200) {
//     return List<String>.from(json.decode(response.body));
//   } else {
//     throw Exception('Failed to load purchase vendors');
//   }
// }


Future<List<String>> getPurchaseVendors() async {
  final response =
      await http.get(Uri.parse('$apiBaseUrl/get_purchase_vendors'));

  if (response.statusCode == 200) {
    final List<dynamic> data = json.decode(response.body);

    return data
        .map<String>((vendor) => vendor['name'].toString())
        .toList();
  } else {
    throw Exception('Failed to load purchase vendors');
  }
}

Future<String?> getLastPoNumber() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_last_po_number'));
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['po_number'];
  } else {
    throw Exception('Failed to load last PO number');
  }
}

Future<String> getNextPoNumber() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/generate_next_po'));
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['po_number'];
  } else {
    throw Exception('Failed to generate next PO number: ${response.body}');
  }
}

Future<List<String>> getExistingPONumbers() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_all_po_numbers'));
  if (response.statusCode == 200) {
    return List<String>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load PO numbers');
  }
}

Future<void> insertProductManager(String name) async {
  final response = await http.post(
    Uri.parse('$apiBaseUrl/insert_product_manager'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({'name': name}),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to insert product manager');
  }
}

Future<void> insertItem(String name) async {
  final response = await http.post(
    Uri.parse('$apiBaseUrl/insert_item'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({'name': name}),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to insert item');
  }
}

Future<void> insertPurchaseVendor(String name) async {
  final response = await http.post(
    Uri.parse('$apiBaseUrl/insert_purchase_vendor'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({'name': name}),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to insert purchase vendor');
  }
}

Future<bool> deleteItem(String name, String password) async {
  final response = await http.delete(
    Uri.parse('$apiBaseUrl/delete_item'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({'name': name, 'password': password}),
  );
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['success'] == true;
  }
  return false;
}

Future<bool> deletePurchaseVendor(String name, String password) async {
  final response = await http.delete(
    Uri.parse('$apiBaseUrl/delete_purchase_vendor'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({'name': name, 'password': password}),
  );
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['success'] == true;
  }
  return false;
}

Future<bool> deleteProductManager(String name, String password) async {
  final response = await http.delete(
    Uri.parse('$apiBaseUrl/delete_product_manager'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({'name': name, 'password': password}),
  );
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['success'] == true;
  }
  return false;
}

Future<void> insertGeneratedPO(Map<String, dynamic> data) async {
  final response = await http.post(
    Uri.parse('$apiBaseUrl/insert_generated_po'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(data),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to insert generated PO');
  }
}

Future<List<Map<String, dynamic>>> getLatestGeneratedPOs() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_latest_generated_pos'));
  if (response.statusCode == 200) {
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load latest generated POs');
  }
}

class POItemEntry {
  String? selectedItem;
  String? selectedVendor;
  String? selectedUnit = 'kg'; // Default set to kg
  DateTime? expectedDate;
  bool isOtherItem = false;
  bool isOtherVendor = false;
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController rateController = TextEditingController();
  final TextEditingController otherItemController = TextEditingController();
  final TextEditingController otherVendorController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  // Search controllers for filtering items and vendors
  final TextEditingController itemSearchController = TextEditingController();
  final TextEditingController vendorSearchController = TextEditingController();
  List<TextEditingController> qualityPointsControllers = [TextEditingController()];

  void dispose() {
    qtyController.dispose();
    rateController.dispose();
    otherItemController.dispose();
    otherVendorController.dispose();
    noteController.dispose();
    itemSearchController.dispose();
    vendorSearchController.dispose();
    for (var controller in qualityPointsControllers) {
      controller.dispose();
    }
  }

  void addQualityPoint() {
    qualityPointsControllers.add(TextEditingController());
  }

  void removeQualityPoint(int index) {
    if (qualityPointsControllers.length > 1) {
      qualityPointsControllers[index].dispose();
      qualityPointsControllers.removeAt(index);
    } else {
      qualityPointsControllers[0].clear();
    }
  }
}

class GeneratePoPage extends StatefulWidget {
  const GeneratePoPage({super.key});

  @override
  State<GeneratePoPage> createState() => _GeneratePoPageState();
}

class _GeneratePoPageState extends State<GeneratePoPage> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedProductManager;
  final TextEditingController _otherProductManagerController = TextEditingController();
  bool _isOtherProductManager = false;

  // PO Number state
  final TextEditingController _poNumberController = TextEditingController();
  final bool _isNewPoNumber = true;

  // Optional PO-level fields
  // Vendor ID (optional)
  final TextEditingController _vendorIdController = TextEditingController();

  // Advanced payment (optional)
  final TextEditingController _advancedPaymentController = TextEditingController();

  // Advanced payment date (optional)
  DateTime? _advancedPaymentDate;

  // Extra expenses field
  final TextEditingController _extraExpensesController = TextEditingController();

  List<POItemEntry> _itemEntries = [];

  List<String> _productManagers = [];
  List<String> _items = [];
  List<String> _vendors = [];
  final List<String> _units = ['kg', 'pcs', 'box', 'bag', 'ton'];
  late Future<List<Map<String, dynamic>>> _latestPOs;
  bool _isLoading = true;
  bool _isSubmitting = false; // Flag to prevent duplicate submissions

final TextEditingController _manageItemCtrl = TextEditingController();
final TextEditingController _manageVendorCtrl = TextEditingController();
  final TextEditingController _manageProductManagerCtrl = TextEditingController();

@override
  void initState() {
    super.initState();
    _addItemEntry();
    _loadInitialData();
    // Add listener for extra expenses to update totals live
    _extraExpensesController.addListener(_calculateTotals);
  }

void _addItemEntry() {
    setState(() {
      _itemEntries.add(POItemEntry());
    });
    // Add listeners to new entry for total calculation
    _itemEntries.last.qtyController.addListener(_calculateTotals);
    _itemEntries.last.rateController.addListener(_calculateTotals);
  }

  void _calculateTotals() {
    // This will be used to show live totals
    setState(() {});
  }

  String _incrementPoNumber(String? lastPo) {
    if (lastPo == null || lastPo.isEmpty) {
      return 'PO-001';
    }
    final regExp = RegExp(r'^(.*?)(\d+)$');
    final match = regExp.firstMatch(lastPo);
    if (match != null) {
      final prefix = match.group(1)!;
      final num = int.parse(match.group(2)!);
      final newNum = num + 1;
      final digits = match.group(2)!.length;
      return '$prefix${newNum.toString().padLeft(digits, '0')}';
    }
    return '${lastPo}1';
  }

  int _comparePoNumbers(String a, String b) {
    final regExp = RegExp(r'^(.*?)(\d+)$');
    final matchA = regExp.firstMatch(a);
    final matchB = regExp.firstMatch(b);
    if (matchA != null && matchB != null) {
      final prefixA = matchA.group(1)!;
      final prefixB = matchB.group(1)!;
      if (prefixA != prefixB) {
        return prefixA.compareTo(prefixB);
      }
      final numA = int.parse(matchA.group(2)!);
      final numB = int.parse(matchB.group(2)!);
      return numA.compareTo(numB);
    }
    return a.compareTo(b);
  }

  Future<void> _generateNextPoClientSide() async {
    try {
      String? lastPo = await getLastPoNumber();
      String candidate = _incrementPoNumber(lastPo);
      
      // Fetch all existing PO numbers to validate uniqueness
      List<String> allPOs = await getExistingPONumbers();
      
      // Loop until we find a unique PO number
      int attempts = 0;
      while ((allPOs.contains(candidate) || _comparePoNumbers(candidate, lastPo ?? '') <= 0) && attempts < 100) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PO number $candidate already exists, regenerating...'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 1),
            ),
          );
        }
        candidate = _incrementPoNumber(candidate);
        attempts++;
      }
      
      if (attempts >= 100) {
        throw Exception('Unable to generate unique PO number after 100 attempts');
      }
      
      if (mounted) {
        setState(() {
          _poNumberController.text = candidate;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generated: $candidate'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Helper method to calculate item total
  double _getItemTotal(POItemEntry entry) {
    double qty = double.tryParse(entry.qtyController.text) ?? 0.0;
    double rate = double.tryParse(entry.rateController.text) ?? 0.0;
    return qty * rate;
  }

  // Helper method to calculate grand total
  double _getGrandTotal() {
    double itemsTotal = 0.0;
    for (var entry in _itemEntries) {
      itemsTotal += _getItemTotal(entry);
    }
    double extraExpenses = _evaluateExpression(_extraExpensesController.text);
    return itemsTotal + extraExpenses;
  }

  double _evaluateExpression(String expression) {
    if (expression.trim().isEmpty) return 0.0;
    String sanitized = expression.replaceAll('x', '*').replaceAll('X', '*');
    if (sanitized.endsWith('+') || sanitized.endsWith('-') || sanitized.endsWith('*') || sanitized.endsWith('/')) {
      sanitized = sanitized.substring(0, sanitized.length - 1);
    }
    try {
      final p = Parser();
      Expression exp = p.parse(sanitized);
      ContextModel cm = ContextModel();
      return exp.evaluate(EvaluationType.REAL, cm);
    } catch (e) {
      return 0.0;
    }
  }

  Widget _buildTotalDisplay() {
    double itemsTotal = 0.0;
    for (var entry in _itemEntries) {
      itemsTotal += _getItemTotal(entry);
    }
    double extraExpenses = _evaluateExpression(_extraExpensesController.text);
    double advancedPayment = double.tryParse(_advancedPaymentController.text) ?? 0.0;

    double grandTotal = itemsTotal + extraExpenses - advancedPayment;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Items Subtotal:', style: TextStyle(fontSize: 13, color: Colors.teal.shade700)),
              Text('₹ ${itemsTotal.toStringAsFixed(2)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
            ],
          ),


          if (advancedPayment > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Advanced Payment:', style: TextStyle(fontSize: 13, color: Colors.orange.shade700)),
                Text('- ₹ ${advancedPayment.toStringAsFixed(2)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
              ],
            ),
          ],



          if (extraExpenses > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Extra Expenses:', style: TextStyle(fontSize: 13, color: Colors.orange.shade700)),
                Text('+ ₹ ${extraExpenses.toStringAsFixed(2)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
              ],
            ),
          ],


          


          const Divider(color: Colors.teal),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Grand Total:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
              Text('₹ ${grandTotal.toStringAsFixed(2)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
            ],
          ),
        ],
      ),
    );
  }

  void _removeItemEntry(int index) {
    if (_itemEntries.length > 1) {
      setState(() {
        _itemEntries[index].dispose();
        _itemEntries.removeAt(index);
      });
    }
  }

Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final managers = await getProductManagers();
    final items = await getItems();
    final vendors = await getPurchaseVendors();
    if (mounted) {
      setState(() {
        _productManagers = ['Other', ...managers];
        _items = [...items];
        _vendors = ['Other', ...vendors];
        _latestPOs = getLatestGeneratedPOs();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _otherProductManagerController.dispose();
    _poNumberController.dispose();
    _vendorIdController.dispose();
    _advancedPaymentController.dispose();
    _extraExpensesController.dispose();
_manageItemCtrl.dispose();
    _manageVendorCtrl.dispose();
    _manageProductManagerCtrl.dispose();
    for (var entry in _itemEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  void _refreshLatestPOs() {
    setState(() {
      _latestPOs = getLatestGeneratedPOs();
    });
  }

  void _showPoNumberOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('PO Number Options', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline, color: Colors.teal, size: 20),
                title: const Text('Generate Next PO', style: TextStyle(fontSize: 14)),
                subtitle: const Text('Fetch last + 1 with duplicate check', style: TextStyle(fontSize: 12, color: Colors.grey)),
                onTap: () async {
                  Navigator.pop(context);
                  await _generateNextPoClientSide();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Colors.orange, size: 20),
                title: const Text('Enter PO Number (Manual)', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(context);
                  _showManualPoEntry();
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _showManualPoEntry() {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: _poNumberController.text);
        return AlertDialog(
          title: const Text('Enter PO Number', style: TextStyle(fontSize: 16)),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              labelText: 'PO Number',
              labelStyle: TextStyle(fontSize: 14),
              hintText: 'e.g. PO-123',
              hintStyle: TextStyle(fontSize: 14),
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(fontSize: 13))),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _poNumberController.text = controller.text;
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              child: const Text('OK', style: TextStyle(fontSize: 13)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _generateAndPreviewPdf() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all required fields first", style: TextStyle(fontSize: 12)), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      final pdf = pw.Document();
      final dateStr = DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now());
      final manager = _isOtherProductManager ? _otherProductManagerController.text : (_selectedProductManager ?? "N/A");
      String poNumber = _poNumberController.text.isEmpty ? "N/A" : _poNumberController.text;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("SHABARI.AI WAREHOUSE",
                          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.teal)),
                        pw.Text("Purchase Order Slip", style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.teal, width: 2)),
                      child: pw.Text("PO: $poNumber", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                    ),
                  ],
                ),
                pw.SizedBox(height: 30),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("Product Manager:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.Text(manager, style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text("Date & Time:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.Text(dateStr, style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 25),
                pw.TableHelper.fromTextArray(
                  border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.teal),
                  cellHeight: 30,
                  cellStyle: const pw.TextStyle(fontSize: 10),
                  headerHeight: 35,
                  cellPadding: const pw.EdgeInsets.all(4), // Add padding for better text wrapping
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2.5),
                    1: const pw.FlexColumnWidth(1.5),
                    2: const pw.FlexColumnWidth(1.2),
                    3: const pw.FlexColumnWidth(2),
                    4: const pw.FlexColumnWidth(1.8),
                    5: const pw.FixedColumnWidth(120), // Fixed width for Specs + Note column - allows vertical expansion
                  },
                  headers: ['Item Name', 'Quantity', 'Rate', 'Vendor', 'Exp. Date', 'Specs & Note'],
                  data: _itemEntries.map((e) {
                    String specs = e.qualityPointsControllers
                        .map((c) => c.text.trim())
                        .where((t) => t.isNotEmpty)
                        .toList()
                        .asMap()
                        .entries
                        .map((entry) => "${entry.key + 1}. ${entry.value}")
                        .join('\n');

                    String fullSpecs = specs;
                    if (e.noteController.text.trim().isNotEmpty) {
                      fullSpecs += "${fullSpecs.isEmpty ? "" : "\n\n"}Note: ${e.noteController.text.trim()}";
                    }

                    return [
                      e.isOtherItem ? e.otherItemController.text : (e.selectedItem ?? ""),
                      "${e.qtyController.text} ${e.selectedUnit ?? ''}",
                      "Rs. ${e.rateController.text}",
                      e.isOtherVendor ? e.otherVendorController.text : (e.selectedVendor ?? ""),
                      e.expectedDate != null ? DateFormat('dd-MM-yy').format(e.expectedDate!) : "N/A",
                      fullSpecs.isEmpty ? "N/A" : fullSpecs,
                    ];
                  }).toList(),
                ),
                pw.Spacer(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      children: [
                        pw.SizedBox(width: 140, child: pw.Divider(thickness: 1, color: PdfColors.grey400)),
                        pw.Text("Authorized Signature", style: const pw.TextStyle(fontSize: 10)),
                      ]
                    ),
                    pw.Column(
                      children: [
                        pw.SizedBox(width: 140, child: pw.Divider(thickness: 1, color: PdfColors.grey400)),
                        pw.Text("Receiver Signature", style: const pw.TextStyle(fontSize: 10)),
                      ]
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Center(
                  child: pw.Text("This is a computer generated slip.",
                    style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500, fontStyle: pw.FontStyle.italic)),
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'PO_Slip_$poNumber',
      );
    } catch (e) {
      debugPrint("PDF Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error: Restart app to fix PDF plugin", style: TextStyle(fontSize: 12)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _submitForm() async {
    // Prevent duplicate submissions
    if (_isSubmitting) {
      return;
    }

    bool allDatesSelected = _itemEntries.every((entry) => entry.expectedDate != null);

    if (_formKey.currentState!.validate() && allDatesSelected) {
      // Set submitting flag to prevent duplicate clicks
      setState(() {
        _isSubmitting = true;
      });

      // Validate PO number uniqueness before submitting
      List<String> allPOs = await getExistingPONumbers();
      if (allPOs.contains(_poNumberController.text)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PO number already exists! Please generate a new one.', style: TextStyle(fontSize: 12)),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        setState(() {
          _isSubmitting = false;
        });
        return;
      }

      String finalManager = _selectedProductManager!;
      if (_isOtherProductManager) {
        finalManager = _otherProductManagerController.text;
        await insertProductManager(finalManager);
      }
      final String currentDate =
        DateFormat('yyyy-MM-dd').format(DateTime.now());

      final String currentTime =
        DateFormat('hh:mm a').format(DateTime.now());


      for (var entry in _itemEntries) {
        String finalItem = entry.selectedItem!;
        if (entry.isOtherItem) {
          finalItem = entry.otherItemController.text;
          await insertItem(finalItem);
        }

        String finalVendor = entry.selectedVendor!;
        if (entry.isOtherVendor) {
          finalVendor = entry.otherVendorController.text;
          await insertPurchaseVendor(finalVendor);
        }

        String qualitySpecs = entry.qualityPointsControllers
            .map((c) => c.text.trim())
            .where((t) => t.isNotEmpty)
            .toList()
            .asMap()
            .entries
            .map((e) => "${e.key + 1}. ${e.value}")
            .join('\n');


        

        String finalPoNumber = _poNumberController.text;
        final String? vendorId = _vendorIdController.text.trim().isEmpty ? null : _vendorIdController.text.trim();
        final String? advancedPayment = _advancedPaymentController.text.trim().isEmpty ? null : _advancedPaymentController.text.trim();
        final String? advancedPaymentDate = _advancedPaymentDate == null ? null : DateFormat('yyyy-MM-dd').format(_advancedPaymentDate!);

        final data = {
          'product_manager': finalManager,
          'item_name': finalItem,
          'po_number': finalPoNumber,
          'qty_ordered': double.tryParse(entry.qtyController.text) ?? 0.0,
          'rate': double.tryParse(entry.rateController.text) ?? 0.0,
          'unit': entry.selectedUnit,
          'vendor_name': finalVendor,
          'vendor_id': vendorId,
          'advanced_payment': advancedPayment,
          'advanced_payment_date': advancedPaymentDate,
          'expected_date': DateFormat('yyyy-MM-dd').format(entry.expectedDate!),
          'quality_specifications': qualitySpecs,
          'note': entry.noteController.text.trim(),
          'date': currentDate,
          'time': currentTime,
        };
        // print("DATA BEING SENT => $data");
        await insertGeneratedPO(data);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('POs Generated Successfully!', style: TextStyle(fontSize: 12)),
              backgroundColor: Colors.green),
        );
      }

      _formKey.currentState!.reset();
      setState(() {
        _selectedProductManager = null;
        _isOtherProductManager = false;
        _otherProductManagerController.clear();
        _poNumberController.clear();
        _isSubmitting = false; // Reset flag after successful submission
        for (var entry in _itemEntries) {
          entry.dispose();
        }
        _itemEntries = [];
        _addItemEntry();
      });
      _loadInitialData();
    } else {
      // Reset flag in case of validation failure
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill all fields and select dates for all items.', style: TextStyle(fontSize: 12)),
            backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Generate PO Number',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        backgroundColor: Colors.teal,
        elevation: 4,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Card(
                      elevation: 4.0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
_buildDropdownFormField(
                              value: _selectedProductManager,
                              label: 'Product Manager',
                              icon: Icons.person_outline,
                              items: _productManagers,
                              onChanged: (newValue) {
                                setState(() {
                                  _selectedProductManager = newValue;
                                  _isOtherProductManager = newValue == 'Other';
                                });
                              },
                              validator: (value) => value == null ? 'Please select a manager' : null,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
Expanded(child: Text('Manage Product Managers (${_productManagers.length - 1})', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade700, fontSize: 14))),
IconButton(
  icon: Icon(Icons.people_outline, color: Colors.purple[600]!),
  onPressed: () => _manageProductManagersDialog(context),
  tooltip: 'Manage Product Managers (${_productManagers.length - 1})',
),
                              ],
                            ),
                            if (_isOtherProductManager)
                              Padding(
                                padding: const EdgeInsets.only(top: 18.0),
                                child: _buildTextFormField(
                                  controller: _otherProductManagerController,
                                  label: 'Enter New Manager Name',
                                  icon: Icons.edit_note_outlined,
                                  validator: (val) => (_isOtherProductManager && (val == null || val.isEmpty))
                                      ? 'Please enter manager name'
                                      : null,
                                ),
                              ),
                            const SizedBox(height: 18.0),

                            // Vendor ID (Optional - can be filled anytime)
                            _buildTextFormField(
                              controller: _vendorIdController,
                              label: 'Vendor ID',
                              icon: Icons.badge, 
                              keyboardType: TextInputType.text,
                            ),

                            const SizedBox(height: 12),

                            Row(
                              children: [
                                Expanded(
                                  child: _buildTextFormField(
                                    controller: _poNumberController,
                                    label: 'PO Number',
                                    icon: Icons.receipt_long_outlined,
                                    validator: (val) => (val == null || val.isEmpty) ? 'PO Number required' : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: _showPoNumberOptions,
                                  icon: const Icon(Icons.add_circle_outline, color: Colors.teal),
                                  tooltip: 'Create PO Number',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _itemEntries.length,
                      itemBuilder: (context, index) {
                        return _buildItemCard(index);
                      },
                    ),
const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _addItemEntry,
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Add More Items', style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Extra Expenses Section
                    Card(
                      elevation: 2.0,
                      color: Colors.orange.shade50,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.orange.shade200)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.add_card, color: Colors.orange.shade700, size: 20),
                                const SizedBox(width: 8),
                                Text('Extra Expenses (Optional)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800, fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Advanced Payment (Optional)
                            _buildTextFormField(
                              controller: _advancedPaymentController,
                              label: 'Advanced Payment',
                              icon: Icons.payments_outlined,
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 12),

                            // Advanced Payment Date (Optional)
                            InkWell(
                              onTap: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: _advancedPaymentDate ?? DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2101),
                                );
                                if (picked != null && picked != _advancedPaymentDate) {
                                  setState(() {
                                    _advancedPaymentDate = picked;
                                  });
                                }
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Advanced Payment Date',
                                  labelStyle: const TextStyle(fontSize: 13),
                                  prefixIcon: Icon(Icons.calendar_month_outlined, color: Colors.teal.shade700, size: 20),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                ),
                                child: Text(
                                  _advancedPaymentDate == null
                                      ? 'Select Date'
                                      : DateFormat('dd-MM-yyyy').format(_advancedPaymentDate!),
                                  style: TextStyle(
                                    color: _advancedPaymentDate == null ? Colors.black54 : Colors.black,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _extraExpensesController,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'Enter Extra Expenses',
                                labelStyle: const TextStyle(fontSize: 13),
                                prefixIcon: Icon(Icons.currency_rupee, color: Colors.orange.shade700, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                filled: true,
                                fillColor: Colors.white,
                                hintText: 'e.g. 500 or 100+200',
                                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                              ),
                              keyboardType: TextInputType.text,
                            ),
                            const SizedBox(height: 12),
                            _buildTotalDisplay(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
                            label: const Text('Preview Slip', style: TextStyle(fontSize: 13)),
                            onPressed: _generateAndPreviewPdf,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.blueGrey,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 20),
                            label: const Text('Submit All', style: TextStyle(fontSize: 13)),
                            onPressed: _submitForm,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildPOsTable(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildItemCard(int index) {
    final entry = _itemEntries[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0), side: BorderSide(color: Colors.teal.shade100)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('Item #${index + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade800, fontSize: 14)),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.inventory_2_outlined, color: Colors.orange[600]!),
                      onPressed: () => _manageItemsDialog(context),
                      tooltip: 'Manage Items (${_items.length - 1})',
                    ),
                    IconButton(
                      icon: Icon(Icons.store_mall_directory_outlined, color: Colors.teal[600]!),
                      onPressed: () => _manageVendorsDialog(context),
                      tooltip: 'Manage Vendors (${_vendors.length - 1})',
                    ),
                    if (_itemEntries.length > 1)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                        onPressed: () => _removeItemEntry(index),
                      ),
                  ],
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
_buildSearchableDropdown(
              value: entry.selectedItem ?? '',
              label: 'Item Name',
              icon: Icons.inventory_2_outlined,
              items: _items,
              onChanged: (newValue) {
                setState(() {
                  entry.selectedItem = newValue;
                  entry.isOtherItem = newValue == 'Other';
                });
              },
              validator: (value) => entry.selectedItem == null ? 'Please select an item' : null,
              isItem: true,
              entry: entry,
            ),
            // if (entry.isOtherItem)
            //   Padding(
            //     padding: const EdgeInsets.only(top: 12.0),
            //     child: _buildTextFormField(
            //       controller: entry.otherItemController,
            //       label: 'Enter New Item Name',
            //       icon: Icons.edit_note_outlined,
            //       validator: (val) => (entry.isOtherItem && (val == null || val.isEmpty)) ? 'Please enter item name' : null,
            //     ),
            //   ),
            const SizedBox(height: 12),
            _buildQuantityWithUnitField(entry),
            const SizedBox(height: 12),
            _buildTextFormField(
              controller: entry.rateController,
              label: 'Rate',
              icon: Icons.currency_rupee,
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) return 'Rate required';
                if (double.tryParse(value) == null) return 'Invalid';
                return null;
              },
            ),
            const SizedBox(height: 12),
_buildSearchableDropdown(
              value: entry.selectedVendor ?? '',
              label: 'Vendor Name',
              icon: Icons.store_mall_directory_outlined,
              items: _vendors,
              onChanged: (newValue) {
                setState(() {
                  entry.selectedVendor = newValue;
                  entry.isOtherVendor = newValue == 'Other';
                });
              },
              validator: (value) => entry.selectedVendor == null ? 'Please select a vendor' : null,
              isItem: false,
              entry: entry,
            ),
            if (entry.isOtherVendor)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: _buildTextFormField(
                  controller: entry.otherVendorController,
                  label: 'Enter New Vendor Name',
                  icon: Icons.edit_note_outlined,
                  validator: (val) => (entry.isOtherVendor && (val == null || val.isEmpty)) ? 'Please enter vendor name' : null,
                ),
              ),
            const SizedBox(height: 12),
            _buildQualityPointsList(entry),
            const SizedBox(height: 12),
            _buildTextFormField(
              controller: entry.noteController,
              label: 'Note (Optional)',
              icon: Icons.note_add_outlined,
            ),
            const SizedBox(height: 12),
            _buildDatePicker(entry),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityPointsList(POItemEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quality Specifications (Optional)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade800, fontSize: 13)),
        const SizedBox(height: 8),
        ...entry.qualityPointsControllers.asMap().entries.map((item) {
          int idx = item.key;
          TextEditingController controller = item.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: _buildTextFormField(
                    controller: controller,
                    label: 'Point ${idx + 1}',
                    icon: Icons.high_quality_outlined,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                  onPressed: () {
                    setState(() {
                      entry.removeQualityPoint(idx);
                    });
                  },
                ),
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                entry.addQualityPoint();
              });
            },
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('Add Point', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: Colors.teal),
          ),
        ),
      ],
    );
  }

  Widget _buildQuantityWithUnitField(POItemEntry entry) {
    return TextFormField(
      controller: entry.qtyController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: 'Quantity Ordered',
        labelStyle: const TextStyle(fontSize: 13),
        prefixIcon: Icon(Icons.format_list_numbered, color: Colors.teal.shade700, size: 20),
        suffixIcon: Container(
          width: 80,
          padding: const EdgeInsets.only(right: 8.0),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: entry.selectedUnit,
              items: _units.map((String unit) {
                return DropdownMenuItem<String>(
                  value: unit,
                  child: Text(unit, style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  entry.selectedUnit = newValue;
                });
              },
              hint: const Text('Unit', style: TextStyle(fontSize: 12)),
              isExpanded: false,
            ),
          ),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Qty required';
        if (double.tryParse(value) == null) return 'Invalid';
        if (entry.selectedUnit == null) return 'Select Unit';
        return null;
      },
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.teal.shade700, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      keyboardType: keyboardType,
      validator: validator,
    );
  }

  Widget _buildDropdownFormField({
    required String? value,
    required String label,
    required IconData icon,
    required List<String> items,
    required void Function(String?)? onChanged,
    required String? Function(String?)? validator,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.teal.shade700, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      style: const TextStyle(fontSize: 13, color: Colors.black),
      items: items.map((String item) {
        return DropdownMenuItem<String>(
          value: item,
          child: Text(item, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
        );
      }).toList(),
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
    );
  }

  Widget _buildSearchableDropdown({
    required String? value,
    required String label,
    required IconData icon,
    required List<String> items,
    required void Function(String?)? onChanged,
    required String? Function(String?)? validator,
    required bool isItem,
    required POItemEntry entry,
  }) {
    String searchQuery = '';
    List<String> filteredItems = items;

    void updateFilter(String query) {
      setState(() {
        searchQuery = query;
        filteredItems = items.where((item) => 
          item.toLowerCase().contains(query.toLowerCase())
        ).toList();
      });
    }

    void showSearchOverlay() {
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(label),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (query) {
                      setDialogState(() => updateFilter(query));
                    },
                    decoration: InputDecoration(
                      hintText: 'Search $label...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        return ListTile(
                          leading: Icon(icon, color: Colors.teal),
                          title: Text(item),
                          onTap: () {
                            Navigator.pop(context);
                            onChanged!(item);
                            if (isItem) {
                              entry.selectedItem = item;
                              entry.isOtherItem = item == 'Other';
                            } else {
                              entry.selectedVendor = item;
                              entry.isOtherVendor = item == 'Other';
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: showSearchOverlay,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.teal.shade700),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
        child: Row(
          children: [
            Expanded(child: Text(value ?? 'Tap to select $label')),
            Icon(Icons.arrow_drop_down, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildDatePicker(POItemEntry entry) {
    return InkWell(
      onTap: () async {
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: entry.expectedDate ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2101),
        );
        if (picked != null && picked != entry.expectedDate) {
          setState(() {
            entry.expectedDate = picked;
          });
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Expected Date of Receiving',
          labelStyle: const TextStyle(fontSize: 13),
          prefixIcon: Icon(Icons.calendar_today, color: Colors.teal.shade700, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
        child: Text(
          entry.expectedDate == null ? 'Select Date' : DateFormat('dd-MM-yyyy').format(entry.expectedDate!),
          style: TextStyle(
            color: entry.expectedDate == null ? Colors.black54 : Colors.black,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildPOsTable() {
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _latestPOs,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Padding(padding: const EdgeInsets.all(16.0), child: Text("Error: ${snapshot.error}", style: const TextStyle(fontSize: 12)));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("No PO records found.", style: TextStyle(fontSize: 12))));
          }

          final pos = snapshot.data!;
          Map<String, List<Map<String, dynamic>>> grouped = {};
          List<String> poOrder = [];
          for (var po in pos) {
            String poNum = po['po_number']?.toString() ?? 'N/A';
            if (!grouped.containsKey(poNum)) {
              grouped[poNum] = [];
              poOrder.add(poNum);
            }
            grouped[poNum]!.add(po);
          }

          const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 10);
          const cellStyle = TextStyle(fontSize: 9);

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.teal.shade100),
              dataRowMinHeight: 48,
              dataRowMaxHeight: 150,
              columns: const [
                DataColumn(label: Text('Manager', style: headerStyle)),
                DataColumn(label: Text('PO Number', style: headerStyle)),
                DataColumn(label: Text('Vendor ID', style: headerStyle)),
                DataColumn(label: Text('Item', style: headerStyle)),
                DataColumn(label: Text('Qty', style: headerStyle)),
                DataColumn(label: Text('Rate', style: headerStyle)),
                DataColumn(label: Text('Vendor', style: headerStyle)),
                DataColumn(label: Text('Advanced Payment', style: headerStyle)),
                DataColumn(label: Text('Adv. Payment Date', style: headerStyle)),
                DataColumn(label: Text('Exp. Date', style: headerStyle)),
                DataColumn(label: Text('Specs & Note', style: headerStyle)),
              ],
              rows: poOrder.map((poNum) {
                final group = grouped[poNum]!;
                final first = group.first;

                // return DataRow(cells: [
                //   DataCell(Text(first['product_manager']?.toString() ?? '', style: cellStyle)),
                //   DataCell(Text(poNum, style: cellStyle)),
                //   DataCell(_buildStackedCell(group, (item) => item['item_name']?.toString() ?? '')),
                //   DataCell(_buildStackedCell(group, (item) => "${item['qty_ordered']} ${item['unit']}")),
                //   DataCell(_buildStackedCell(group, (item) => "₹${item['rate']}")),
                //   DataCell(_buildStackedCell(group, (item) => item['vendor_name']?.toString() ?? '')),
                //   DataCell(_buildStackedCell(group, (item) => item['expected_date'] != null ? DateFormat('dd-MM-yy').format(DateTime.parse(item['expected_date'])) : '')),
                //   DataCell(_buildStackedCell(group, (item) {
                //     String specs = item['quality_specifications']?.toString() ?? '';
                //     String note = item['note']?.toString() ?? '';
                //     String display = specs;
                //     if (note.isNotEmpty) {
                //       display += "${display.isEmpty ? "" : "\n\n"}Note: $note";
                //     }
                //     return display.isEmpty ? "-" : display;
                //   })),
                // ]);


                return DataRow(cells: [
                  DataCell(Text(
                      first['product_manager']?.toString() ?? '',
                      style: cellStyle)),

                  DataCell(Text(poNum, style: cellStyle)),

                  // Vendor ID
                  DataCell(Text(
                      first['vendor_id']?.toString() ?? '-',
                      style: cellStyle)),

                  // Item
                  DataCell(_buildStackedCell(
                      group,
                      (item) => item['item_name']?.toString() ?? '')),

                  // Qty
                  DataCell(_buildStackedCell(
                      group,
                      (item) => "${item['qty_ordered']} ${item['unit']}")),

                  // Rate
                  DataCell(_buildStackedCell(
                      group,
                      (item) => "₹${item['rate']}")),

                  // Vendor
                  DataCell(_buildStackedCell(
                      group,
                      (item) => item['vendor_name']?.toString() ?? '')),

                  // Advanced Payment
                  DataCell(Text(
                      first['advanced_payment']?.toString() ?? '-',
                      style: cellStyle)),

                  // Advanced Payment Date
                  DataCell(Text(
                      first['advanced_payment_date']?.toString() ?? '-',
                      style: cellStyle)),

                  // Expected Date
                  DataCell(_buildStackedCell(group, (item) =>
                      item['expected_date'] != null
                          ? DateFormat('dd-MM-yy')
                              .format(DateTime.parse(item['expected_date']))
                          : '')),

                  // Specs & Note
                  DataCell(_buildStackedCell(group, (item) {
                    String specs =
                        item['quality_specifications']?.toString() ?? '';
                    String note =
                        item['note']?.toString() ?? '';

                    String display = specs;

                    if (note.isNotEmpty) {
                      display +=
                          "${display.isEmpty ? "" : "\n\n"}Note: $note";
                    }

                    return display.isEmpty ? "-" : display;
                  })),
                ]);




              }).toList(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStackedCell(List<Map<String, dynamic>> group, String Function(Map<String, dynamic>) labelMapper) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: group.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Text(labelMapper(item), style: const TextStyle(fontSize: 9)),
          )).toList(),
        ),
      ),
    );
  }

Future<void> _deleteVendor(String vendorName) async {
    final passwordController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Vendor', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Are you sure you want to delete "$vendorName"?', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Password',
                labelStyle: TextStyle(fontSize: 14),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(fontSize: 13)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final password = passwordController.text;
      if (password.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter password', style: TextStyle(fontSize: 12)), backgroundColor: Colors.red),
          );
        }
        return;
      }
      try {
        final success = await deletePurchaseVendor(vendorName, password);
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$vendorName deleted successfully!', style: const TextStyle(fontSize: 12)), backgroundColor: Colors.green),
          );
          _loadInitialData();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete vendor', style: TextStyle(fontSize: 12)), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e', style: const TextStyle(fontSize: 12)), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

Future<void> _manageItemsDialog(BuildContext context) async {
  final TextEditingController passCtrl = TextEditingController();
  
  showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => Center(
    child: Container(
      width: MediaQuery.of(context).size.width * 0.95,
      margin: const EdgeInsets.only(top: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: DraggableScrollableSheet(
          expand: false,
  initialChildSize: 0.7,
  minChildSize: 0.4,
  maxChildSize: 0.9,
  builder: (context, scrollCtrl) => Column(
            children: [

              // Header
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.orange.shade50,
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    const Text(
                      'Manage Items',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Add Item Section
              Container(
                color: Colors.teal.shade50,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [

                    TextField(
                      controller: _manageItemCtrl,
                      decoration: InputDecoration(
                        labelText: 'New Item Name',
                        prefixIcon: const Icon(Icons.add,
                            color: Colors.teal),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {

                              final name =
                                  _manageItemCtrl.text.trim();

                              if (name.isEmpty) return;

                              try {

                                await insertItem(name);
                                await _loadInitialData();

                                _manageItemCtrl.clear();

                                if (mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(
                                      content:
                                          Text('$name added!'),
                                      backgroundColor:
                                          Colors.green,
                                    ),
                                  );
                                }

                              } catch (e) {

                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('Failed: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );

                              }
                            },
                            icon: const Icon(Icons.add_circle,
                                color: Colors.white),

                            label: const Text('Add Item'),

                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Items List
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: _items.length,
                  itemBuilder: (context, i) {

                    final item = _items[i];

                    if (item == 'Other') {
                      return const SizedBox();
                    }

                    return ListTile(
                      leading: const Icon(
                        Icons.inventory_2_outlined,
                        color: Colors.orange,
                      ),

                      title: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      trailing: IconButton(
                        icon: const Icon(Icons.delete,
                            color: Colors.red),

                        onPressed: () async {

                          final confirmed =
                              await showDialog<bool>(
                            context: context,

                            builder: (ctx) => AlertDialog(
                              title: Text('Delete $item?'),

                              content: TextField(
                                controller: passCtrl,
                                obscureText: true,
                                decoration:
                                    const InputDecoration(
                                  labelText:
                                      'Password',
                                ),
                              ),

                              actions: [

                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(
                                          ctx, false),
                                  child: const Text(
                                      'Cancel'),
                                ),

                                ElevatedButton(
                                  style:
                                      ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.red,
                                  ),

                                  onPressed: () =>
                                      Navigator.pop(
                                          ctx, true),

                                  child:
                                      const Text('Delete'),
                                ),
                              ],
                            ),
                          );

                          if (confirmed == true &&
                              mounted) {

                            final success =
                                await deleteItem(
                                    item, passCtrl.text);

                            if (success) {

                              await _loadInitialData();

                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '$item deleted!'),
                                  backgroundColor:
                                      Colors.green,
                                ),
                              );

                            } else {

                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Delete failed'),
                                  backgroundColor:
                                      Colors.red,
                                ),
                              );

                            }
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
}

Future<void> _manageProductManagersDialog(BuildContext context) async {
  final TextEditingController passCtrl = TextEditingController();
  
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        margin: const EdgeInsets.only(top: 40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (context, scrollCtrl) => Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.purple.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.people_outline, color: Colors.purple.shade700),
                      const SizedBox(width: 12),
                      const Text(
                        'Manage Product Managers',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                // Add Manager Section
                Container(
                  color: Colors.teal.shade50,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _manageProductManagerCtrl,
                        decoration: InputDecoration(
                          labelText: 'New Product Manager Name',
                          prefixIcon: const Icon(Icons.add, color: Colors.teal),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final name = _manageProductManagerCtrl.text.trim();
                                if (name.isEmpty) return;
                                try {
                                  await insertProductManager(name);
                                  await _loadInitialData();
                                  _manageProductManagerCtrl.clear();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('$name added!'), backgroundColor: Colors.green),
                                    );
                                  }
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
                                  );
                                }
                              },
                              icon: const Icon(Icons.add_circle, color: Colors.white),
                              label: const Text('Add Manager'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Managers List
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    itemCount: _productManagers.length,
                    itemBuilder: (context, i) {
                      final managerName = _productManagers[i];
                      if (managerName == 'Other') return const SizedBox();
                      return ListTile(
                        leading: Icon(Icons.people_outline, color: Colors.purple),
                        title: Text(managerName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('Delete $managerName?'),
                                content: TextField(
                                  controller: passCtrl,
                                  obscureText: true,
                                  decoration: const InputDecoration(labelText: 'Password'),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true && mounted) {
                              final success = await deleteProductManager(managerName, passCtrl.text);
                              if (success) {
                                await _loadInitialData();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('$managerName deleted!'), backgroundColor: Colors.green),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Delete failed'), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _manageVendorsDialog(BuildContext context) async {
  final TextEditingController passCtrl = TextEditingController();
  
  showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => Center(
    child: Container(
      width: MediaQuery.of(context).size.width * 0.95,
      margin: const EdgeInsets.only(top: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: DraggableScrollableSheet(
          expand: false,
  initialChildSize: 0.7,
  minChildSize: 0.4,
  maxChildSize: 0.9,
  builder: (context, scrollCtrl) => Column(
            children: [

              // Header
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.teal.shade50,
                child: Row(
                  children: [
                    Icon(Icons.store_mall_directory_outlined,
                        color: Colors.teal.shade700),
                    const SizedBox(width: 12),
                    const Text(
                      'Manage Vendors',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Add Vendor Section
              Container(
                color: Colors.orange.shade50,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [

                    TextField(
                      controller: _manageVendorCtrl,
                      decoration: InputDecoration(
                        labelText: 'New Vendor Name',
                        prefixIcon: const Icon(Icons.add,
                            color: Colors.orange),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {

                              final name =
                                  _manageVendorCtrl.text.trim();

                              if (name.isEmpty) return;

                              try {

                                await insertPurchaseVendor(name);
                                await _loadInitialData();

                                _manageVendorCtrl.clear();

                                if (mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(
                                      content:
                                          Text('$name added!'),
                                      backgroundColor:
                                          Colors.green,
                                    ),
                                  );
                                }

                              } catch (e) {

                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('Failed: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );

                              }
                            },
                            icon: const Icon(Icons.add_circle,
                                color: Colors.white),

                            label: const Text('Add Vendor'),

                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Vendors List
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: _vendors.length,
                  itemBuilder: (context, i) {

                    final vendorName = _vendors[i];

                    if (vendorName == 'Other') {
                      return const SizedBox();
                    }

                    return ListTile(
                      leading: const Icon(
                        Icons.store_mall_directory_outlined,
                        color: Colors.teal,
                      ),

                      title: Text(
                        vendorName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      trailing: IconButton(
                        icon: const Icon(Icons.delete,
                            color: Colors.red),

                        onPressed: () async {

                          final confirmed =
                              await showDialog<bool>(
                            context: context,

                            builder: (ctx) => AlertDialog(
                              title: Text('Delete $vendorName?'),

                              content: TextField(
                                controller: passCtrl,
                                obscureText: true,
                                decoration:
                                    const InputDecoration(
                                  labelText:
                                      'Password (1008)',
                                ),
                              ),

                              actions: [

                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(
                                          ctx, false),
                                  child: const Text(
                                      'Cancel'),
                                ),

                                ElevatedButton(
                                  style:
                                      ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.red,
                                  ),

                                  onPressed: () =>
                                      Navigator.pop(
                                          ctx, true),

                                  child:
                                      const Text('Delete'),
                                ),
                              ],
                            ),
                          );

                          if (confirmed == true &&
                              mounted) {

                            final success =
                                await deletePurchaseVendor(
                                    vendorName, passCtrl.text);

                            if (success) {

                              await _loadInitialData();

                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '$vendorName deleted!'),
                                  backgroundColor:
                                      Colors.green,
                                ),
                              );

                            } else {

                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Delete failed'),
                                  backgroundColor:
                                      Colors.red,
                                ),
                              );

                            }
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);







//   showModalBottomSheet(
//   context: context,
//   isScrollControlled: true,
//   backgroundColor: Colors.transparent,
//   builder: (context) => Center(
//     child: Container(
//       width: MediaQuery.of(context).size.width * 0.95, // width thodi kam
//       margin: const EdgeInsets.only(top: 40),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(25), // rounded corners
//       ),
//       child: ClipRRect(
//         borderRadius: BorderRadius.circular(25),
//         child: DraggableScrollableSheet(
//           expand: false,
//           initialChildSize: 0.7,
//           minChildSize: 0.4,
//           maxChildSize: 0.9,
//           builder: (context, scrollCtrl) => Column(
//             children: [

//               // Header
//               Container(
//                 padding: const EdgeInsets.all(16),
//                 color: Colors.orange.shade50,
//                 child: Row(
//                   children: [
//                     Icon(Icons.inventory_2_outlined,
//                         color: Colors.orange.shade700),
//                     const SizedBox(width: 12),
//                     const Text(
//                       'Manage Items',
//                       style: TextStyle(
//                         fontSize: 18,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),

//               // Add Item Section
//               Container(
//                 color: Colors.teal.shade50,
//                 padding: const EdgeInsets.all(16),
//                 child: Column(
//                   children: [

//                     TextField(
//                       controller: _manageItemCtrl,
//                       decoration: InputDecoration(
//                         labelText: 'New Item Name',
//                         prefixIcon: const Icon(Icons.add,
//                             color: Colors.teal),
//                         border: OutlineInputBorder(
//                           borderRadius:
//                               BorderRadius.circular(12),
//                         ),
//                         filled: true,
//                         fillColor: Colors.white,
//                       ),
//                     ),

//                     const SizedBox(height: 12),

//                     Row(
//                       children: [
//                         Expanded(
//                           child: ElevatedButton.icon(
//                             onPressed: () async {

//                               final name =
//                                   _manageItemCtrl.text.trim();

//                               if (name.isEmpty) return;

//                               try {

//                                 await insertItem(name);
//                                 await _loadInitialData();

//                                 _manageItemCtrl.clear();

//                                 if (mounted) {
//                                   ScaffoldMessenger.of(context)
//                                       .showSnackBar(
//                                     SnackBar(
//                                       content:
//                                           Text('$name added!'),
//                                       backgroundColor:
//                                           Colors.green,
//                                     ),
//                                   );
//                                 }

//                               } catch (e) {

//                                 ScaffoldMessenger.of(context)
//                                     .showSnackBar(
//                                   SnackBar(
//                                     content:
//                                         Text('Failed: $e'),
//                                     backgroundColor:
//                                         Colors.red,
//                                   ),
//                                 );

//                               }
//                             },
//                             icon: const Icon(Icons.add_circle,
//                                 color: Colors.white),
//                             label: const Text('Add Item'),
//                             style: ElevatedButton.styleFrom(
//                               backgroundColor: Colors.teal,
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),

//               // Items List
//               Expanded(
//                 child: ListView.builder(
//                   controller: scrollCtrl,
//                   itemCount: _items.length,
//                   itemBuilder: (context, i) {

//                     final item = _items[i];

//                     if (item == 'Other') {
//                       return const SizedBox();
//                     }

//                     return ListTile(
//                       leading: const Icon(
//                         Icons.inventory_2_outlined,
//                         color: Colors.orange,
//                       ),

//                       title: Text(
//                         item,
//                         style: const TextStyle(
//                           fontSize: 14,
//                           fontWeight: FontWeight.w500,
//                         ),
//                       ),

//                       trailing: IconButton(
//                         icon: const Icon(Icons.delete,
//                             color: Colors.red),

//                         onPressed: () async {

//                           final confirmed =
//                               await showDialog<bool>(
//                             context: context,

//                             builder: (ctx) => AlertDialog(
//                               title: Text('Delete $item?'),

//                               content: TextField(
//                                 controller: passCtrl,
//                                 obscureText: true,
//                                 decoration:
//                                     const InputDecoration(
//                                   labelText:
//                                       'Password (1008)',
//                                 ),
//                               ),

//                               actions: [

//                                 TextButton(
//                                   onPressed: () =>
//                                       Navigator.pop(
//                                           ctx, false),
//                                   child: const Text(
//                                       'Cancel'),
//                                 ),

//                                 ElevatedButton(
//                                   style:
//                                       ElevatedButton
//                                           .styleFrom(
//                                     backgroundColor:
//                                         Colors.red,
//                                   ),

//                                   onPressed: () =>
//                                       Navigator.pop(
//                                           ctx, true),

//                                   child:
//                                       const Text('Delete'),
//                                 ),
//                               ],
//                             ),
//                           );

//                           if (confirmed == true &&
//                               mounted) {

//                             final success =
//                                 await deleteItem(
//                                     item,
//                                     passCtrl.text);

//                             if (success) {

//                               await _loadInitialData();

//                               ScaffoldMessenger.of(context)
//                                   .showSnackBar(
//                                 SnackBar(
//                                   content: Text(
//                                       '$item deleted!'),
//                                   backgroundColor:
//                                       Colors.green,
//                                 ),
//                               );

//                             } else {

//                               ScaffoldMessenger.of(context)
//                                   .showSnackBar(
//                                 const SnackBar(
//                                   content: Text(
//                                       'Delete failed'),
//                                   backgroundColor:
//                                       Colors.red,
//                                 ),
//                               );

//                             }
//                           }
//                         },
//                       ),
//                     );
//                   },
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     ),
//   ),
// );






}

void _showVendorListWithDelete() {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Manage Vendors', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _vendors.length,
                  itemBuilder: (context, index) {
                    final vendorName = _vendors[index];
                    if (vendorName == 'Other') return const SizedBox();
                    return ListTile(
                      leading: const Icon(Icons.store, color: Colors.teal, size: 20),
                      title: Text(vendorName, style: const TextStyle(fontSize: 14)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteVendor(vendorName);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
}
