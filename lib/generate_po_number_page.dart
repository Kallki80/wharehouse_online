import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const String apiBaseUrl = 'http://13.53.71.103:5000/';
// const String apiBaseUrl = 'http://10.0.2.2:5000';

// API Helper Functions
Future<List<String>> getProductManagers() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_product_managers'));
  if (response.statusCode == 200) {
    return List<String>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load product managers');
  }
}

Future<List<String>> getItems() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_items'));
  if (response.statusCode == 200) {
    return List<String>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load items');
  }
}

Future<List<String>> getPurchaseVendors() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_purchase_vendors'));
  if (response.statusCode == 200) {
    return List<String>.from(json.decode(response.body));
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

Future<bool> deletePurchaseVendor(String name, String password) async {
  final response = await http.delete(
    Uri.parse('$apiBaseUrl/delete_purchase_vendor'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({'name': name, 'password': password}),
  );
  return response.statusCode == 200;
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
  List<TextEditingController> qualityPointsControllers = [TextEditingController()];

  void dispose() {
    qtyController.dispose();
    rateController.dispose();
    otherItemController.dispose();
    otherVendorController.dispose();
    noteController.dispose();
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
  final TextEditingController _poNumberController = TextEditingController();

  List<POItemEntry> _itemEntries = [];

  List<String> _productManagers = [];
  List<String> _items = [];
  List<String> _vendors = [];
  final List<String> _units = ['kg', 'pcs', 'box', 'bag', 'ton'];
  late Future<List<Map<String, dynamic>>> _latestPOs;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _addItemEntry();
    _loadInitialData();
  }

  void _addItemEntry() {
    setState(() {
      _itemEntries.add(POItemEntry());
    });
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
        _items = ['Other', ...items];
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

  String _generateNextPoNumber(String? lastPo) {
    if (lastPo == null || lastPo.isEmpty) return "PO-001";
    final match = RegExp(r'^(.*?)(\d+)$').firstMatch(lastPo);
    if (match != null) {
      String prefix = match.group(1) ?? "";
      String numberPart = match.group(2) ?? "";
      int nextNumber = int.parse(numberPart) + 1;
      return prefix + nextNumber.toString().padLeft(numberPart.length, '0');
    }
    return "$lastPo-1";
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
                child: Text('PO Number Options', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline, color: Colors.teal),
                title: const Text('Create PO Number (Auto-increment)'),
                onTap: () async {
                  Navigator.pop(context);
                  String? lastPo = await getLastPoNumber();
                  String nextPo = _generateNextPoNumber(lastPo);
                  setState(() {
                    _poNumberController.text = nextPo;
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Colors.orange),
                title: const Text('Enter PO Number (Manual)'),
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
          title: const Text('Enter PO Number'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'PO Number',
              hintText: 'e.g. PO-123',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _poNumberController.text = controller.text;
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _generateAndPreviewPdf() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all required fields first"), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      final pdf = pw.Document();
      final dateStr = DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now());
      final manager = _isOtherProductManager ? _otherProductManagerController.text : (_selectedProductManager ?? "N/A");
      final poNumber = _poNumberController.text.isEmpty ? "N/A" : _poNumberController.text;

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
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2.5),
                    1: const pw.FlexColumnWidth(1.5),
                    2: const pw.FlexColumnWidth(1.2),
                    3: const pw.FlexColumnWidth(2),
                    4: const pw.FlexColumnWidth(1.8),
                    5: const pw.FlexColumnWidth(3), // Specs + Note
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
          const SnackBar(content: Text("Error: Restart app to fix PDF plugin"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _submitForm() async {
    bool allDatesSelected = _itemEntries.every((entry) => entry.expectedDate != null);

    if (_formKey.currentState!.validate() && allDatesSelected) {
      String finalManager = _selectedProductManager!;
      if (_isOtherProductManager) {
        finalManager = _otherProductManagerController.text;
        await insertProductManager(finalManager);
      }

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

        final data = {
          'product_manager': finalManager,
          'item_name': finalItem,
          'po_number': _poNumberController.text,
          'qty_ordered': double.tryParse(entry.qtyController.text) ?? 0.0,
          'rate': double.tryParse(entry.rateController.text) ?? 0.0,
          'unit': entry.selectedUnit,
          'vendor_name': finalVendor,
          'expected_date': DateFormat('yyyy-MM-dd').format(entry.expectedDate!),
          'quality_specifications': qualitySpecs,
          'note': entry.noteController.text.trim(),
        };

        await insertGeneratedPO(data);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('POs Generated Successfully!'),
              backgroundColor: Colors.green),
        );
      }

      _formKey.currentState!.reset();
      setState(() {
        _selectedProductManager = null;
        _isOtherProductManager = false;
        _otherProductManagerController.clear();
        _poNumberController.clear();
        for (var entry in _itemEntries) {
          entry.dispose();
        }
        _itemEntries = [];
        _addItemEntry();
      });
      _loadInitialData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill all fields and select dates for all items.'),
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
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
                            _buildTextFormField(
                              controller: _poNumberController,
                              label: 'PO Number',
                              icon: Icons.receipt_long_outlined,
                              readOnly: true,
                              onTap: _showPoNumberOptions,
                              validator: (value) => (value == null || value.isEmpty) ? 'Please select or enter a PO number' : null,
                            ),
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
                      icon: const Icon(Icons.add),
                      label: const Text('Add More Items'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                            label: const Text('Preview Slip'),
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
                            icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white),
                            label: const Text('Submit All'),
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
                Text('Item #${index + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade800, fontSize: 16)),
                if (_itemEntries.length > 1)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                    onPressed: () => _removeItemEntry(index),
                  ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            _buildDropdownFormField(
              value: entry.selectedItem,
              label: 'Item Name',
              icon: Icons.inventory_2_outlined,
              items: _items,
              onChanged: (newValue) {
                setState(() {
                  entry.selectedItem = newValue;
                  entry.isOtherItem = newValue == 'Other';
                });
              },
              validator: (value) => value == null ? 'Please select an item' : null,
            ),
            if (entry.isOtherItem)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: _buildTextFormField(
                  controller: entry.otherItemController,
                  label: 'Enter New Item Name',
                  icon: Icons.edit_note_outlined,
                  validator: (val) => (entry.isOtherItem && (val == null || val.isEmpty)) ? 'Please enter item name' : null,
                ),
              ),
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
            Row(
              children: [
                Expanded(
                  child: _buildDropdownFormField(
                    value: entry.selectedVendor,
                    label: 'Vendor Name',
                    icon: Icons.store_mall_directory_outlined,
                    items: _vendors,
                    onChanged: (newValue) {
                      setState(() {
                        entry.selectedVendor = newValue;
                        entry.isOtherVendor = newValue == 'Other';
                      });
                    },
                    validator: (value) => value == null ? 'Please select a vendor' : null,
                  ),
                ),
                if (_vendors.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, left: 8.0),
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      onPressed: _showVendorListWithDelete,
                      tooltip: 'Manage Vendors',
                    ),
                  ),
              ],
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
        Text('Quality Specifications (Optional)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade800, fontSize: 14)),
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
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
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
            icon: const Icon(Icons.add_circle_outline, size: 20),
            label: const Text('Add Point'),
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
      decoration: InputDecoration(
        labelText: 'Quantity Ordered',
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
                  child: Text(unit, style: const TextStyle(fontSize: 14)),
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
      decoration: InputDecoration(
        labelText: label,
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
      items: items.map((String item) {
        return DropdownMenuItem<String>(
          value: item,
          child: Text(item, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
        );
      }).toList(),
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
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
            fontSize: 14,
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
            return Padding(padding: const EdgeInsets.all(16.0), child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("No PO records found.")));
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

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.teal.shade100),
              dataRowMinHeight: 48,
              dataRowMaxHeight: 150, 
              columns: const [
                DataColumn(label: Text('Manager', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('PO Number', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Item', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Rate', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Vendor', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Exp. Date', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Specs & Note', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: poOrder.map((poNum) {
                final group = grouped[poNum]!;
                final first = group.first;

                return DataRow(cells: [
                  DataCell(Text(first['product_manager']?.toString() ?? '')),
                  DataCell(Text(poNum)),
                  DataCell(_buildStackedCell(group, (item) => item['item_name']?.toString() ?? '')),
                  DataCell(_buildStackedCell(group, (item) => "${item['qty_ordered']} ${item['unit']}")),
                  DataCell(_buildStackedCell(group, (item) => "₹${item['rate']}")),
                  DataCell(_buildStackedCell(group, (item) => item['vendor_name']?.toString() ?? '')),
                  DataCell(_buildStackedCell(group, (item) => item['expected_date'] != null ? DateFormat('dd-MM-yy').format(DateTime.parse(item['expected_date'])) : '')),
                  DataCell(_buildStackedCell(group, (item) {
                    String specs = item['quality_specifications']?.toString() ?? '';
                    String note = item['note']?.toString() ?? '';
                    String display = specs;
                    if (note.isNotEmpty) {
                      display += "${display.isEmpty ? "" : "\n\n"}Note: $note";
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
            child: Text(labelMapper(item), style: const TextStyle(fontSize: 13)),
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
        title: const Text('Delete Vendor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Are you sure you want to delete "$vendorName"?'),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final password = passwordController.text;
      if (password.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter password'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      try {
        final success = await deletePurchaseVendor(vendorName, password);
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$vendorName deleted successfully!'), backgroundColor: Colors.green),
          );
          _loadInitialData();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete vendor'), backgroundColor: Colors.red),
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
                  child: Text('Manage Vendors', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _vendors.length,
                    itemBuilder: (context, index) {
                      final vendorName = _vendors[index];
                      if (vendorName == 'Other') return const SizedBox();
                      return ListTile(
                        leading: const Icon(Icons.store, color: Colors.teal),
                        title: Text(vendorName),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
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
