import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const String apiBaseUrl = 'http://13.53.71.103:5000/';
// const String apiBaseUrl = 'http://10.0.2.2:5000';

// API Helper Functions
Future<List<String>> getPurchasedItems() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_purchased_items'));
  if (response.statusCode == 200) {
    return List<String>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load purchased items');
  }
}

Future<List<Map<String, dynamic>>> getLatestDumpSales() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_latest_dump_sales'));
  if (response.statusCode == 200) {
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load latest dump sales');
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

Future<void> insertDumpSale(Map<String, dynamic> data) async {
  final response = await http.post(
    Uri.parse('$apiBaseUrl/insert_dump_sale'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(data),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to insert dump sale');
  }
}

Future<List<String>> getPurchasedTagsForItem(String itemName) async {
  final queryParams = {'item_name': itemName};
  final uri = Uri.parse('$apiBaseUrl/get_purchased_tags_for_item').replace(queryParameters: queryParams);
  final response = await http.get(uri);
  if (response.statusCode == 200) {
    return List<String>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load tags for item');
  }
}

// हर डंप आइटम का डेटा रखने के लिए क्लास
class DumpItem {
  String? selectedItem;
  String selectedUnit = 'Kg';
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController pcsController = TextEditingController(); // Pcs के लिए
  final TextEditingController tagController = TextEditingController(); // Item Tag के लिए
  bool isOtherItem = false;
  final TextEditingController otherItemController = TextEditingController();

  void dispose() {
    qtyController.dispose();
    pcsController.dispose();
    tagController.dispose();
    otherItemController.dispose();
  }
}

class DumpSale extends StatefulWidget {
  const DumpSale({super.key});

  @override
  State<DumpSale> createState() => _DumpSaleState();
}

class _DumpSaleState extends State<DumpSale> {
  final _formKey = GlobalKey<FormState>();

  // --- Form State ---
  List<DumpItem> dumpItems = []; // कई आइटम्स के लिए लिस्ट

  // --- Dynamic Dropdown Lists ---
  List<String> _items = [];
  final List<String> units = ["Kg", "g", "pcs", "L", "ml"];
  bool _isLoading = true;

  Future<List<Map<String, dynamic>>>? _latestDumpSales;

  @override
  void initState() {
    super.initState();
    _loadInitialData().then((_) {
      if (mounted) {
        _addNewItem();
      }
    });
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    // Only fetch items that have been purchased
    List<String> dbItems = await getPurchasedItems();
    if (mounted) {
      setState(() {
        _items = ["Other", ...dbItems];
        _latestDumpSales = getLatestDumpSales();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    for (var item in dumpItems) {
      item.dispose();
    }
    super.dispose();
  }

  void _addNewItem() {
    setState(() {
      dumpItems.add(DumpItem());
    });
  }

  void _removeItem(int index) {
    if (dumpItems.length > 1) {
      dumpItems[index].dispose();
      setState(() {
        dumpItems.removeAt(index);
      });
    }
  }

  double _evaluateExpression(String expression) {
    if (expression.trim().isEmpty) return 0.0;

    String sanitizedExpression =
        expression.replaceAll('x', '*').replaceAll('X', '*');

    // Handle trailing operators for user convenience
    if (sanitizedExpression.endsWith('+') ||
        sanitizedExpression.endsWith('-') ||
        sanitizedExpression.endsWith('*') ||
        sanitizedExpression.endsWith('/')) {
      sanitizedExpression =
          sanitizedExpression.substring(0, sanitizedExpression.length - 1);
    }

    try {
      Parser p = Parser();
      Expression exp = p.parse(sanitizedExpression);
      ContextModel cm = ContextModel();
      double eval = exp.evaluate(EvaluationType.REAL, cm);
      return eval;
    } catch (e) {
      return 0.0; // Return 0 if expression is invalid
    }
  }

  void _submitForm() async {
    final isFormValid = _formKey.currentState!.validate();

    if (!isFormValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Capture context dependent values before async gaps
    final String formattedTime = TimeOfDay.now().format(context);

    for (var dumpItem in dumpItems) {
      String finalItemName = dumpItem.selectedItem!;
      if (dumpItem.isOtherItem) {
        finalItemName = dumpItem.otherItemController.text;
        await insertItem(finalItemName);
      }

      final double qty = _evaluateExpression(dumpItem.qtyController.text);
      final double? pcs = dumpItem.pcsController.text.isNotEmpty
          ? _evaluateExpression(dumpItem.pcsController.text)
          : null;

      Map<String, dynamic> dataToSave = {
        'item': finalItemName,
        'quantity': qty,
        'unit': dumpItem.selectedUnit,
        'pcs': pcs,
        'item_tag': dumpItem.tagController.text,
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'time': formattedTime,
      };

      await insertDumpSale(dataToSave);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dump Sale Saved Successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }

    _formKey.currentState!.reset();
    for (var item in dumpItems) {
      item.dispose();
    }
    setState(() {
      dumpItems = [];
    });
    _addNewItem();

    _loadInitialData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Dump Sale', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.brown.shade600, Colors.brown.shade400],
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
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Card(
                    elevation: 8.0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: dumpItems.length,
                              itemBuilder: (context, index) {
                                return _buildItemEntry(index);
                              },
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              icon: const Icon(Icons.add_circle_outline, color: Colors.brown),
                              label: const Text("Add More Items", style: TextStyle(color: Colors.brown)),
                              onPressed: _addNewItem,
                            ),
                            const SizedBox(height: 30),
                            ElevatedButton(
                              onPressed: _submitForm,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.brown.shade700,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 5,
                              ),
                              child: const Text('Submit Dump Sale'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Recent Dump Sales",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.brown),
                  ),
                  const SizedBox(height: 8),
                  _buildDumpSalesTable(),
                ],
              ),
            ),
    );
  }

  Widget _buildItemEntry(int index) {
    final dumpItem = dumpItems[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildDropdown(
                  label: "Select Item",
                  value: dumpItem.selectedItem,
                  items: _items,
                  onChanged: (val) async {
                    if (val != null) {
                      setState(() {
                        dumpItem.selectedItem = val;
                        dumpItem.isOtherItem = (val == 'Other');
                      });
                      if (val != 'Other') {
                        List<String> tags = await getPurchasedTagsForItem(val);
                        if (tags.isNotEmpty) {
                          setState(() {
                            dumpItem.tagController.text = tags.first;
                          });
                        } else {
                          setState(() {
                            dumpItem.tagController.clear();
                          });
                        }
                      } else {
                         setState(() {
                            dumpItem.tagController.clear();
                          });
                      }
                    }
                  },
                ),
              ),
              if (dumpItems.length > 1)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                  child: IconButton(
                    icon: Icon(Icons.remove_circle_outline, color: Colors.red.shade400),
                    onPressed: () => _removeItem(index),
                  ),
                ),
            ],
          ),
          if (dumpItem.isOtherItem)
            _buildOtherTextField(
              controller: dumpItem.otherItemController,
              label: 'Enter New Item Name',
            ),
          const SizedBox(height: 18),
          // Item Tag Field
          TextFormField(
            controller: dumpItem.tagController,
            decoration: InputDecoration(
              labelText: 'Item Tag',
              prefixIcon: Icon(Icons.tag, color: Colors.brown.shade300),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: (val) => (val == null || val.isEmpty) ? "Item Tag is required" : null,
          ),
          const SizedBox(height: 18),
          _buildQuantityField(
            controller: dumpItem.qtyController,
            label: 'Quantity',
            selectedUnit: dumpItem.selectedUnit,
            onUnitChanged: (val) => setState(() => dumpItem.selectedUnit = val!),
          ),
          const SizedBox(height: 18),
          _buildExpressionField(
            controller: dumpItem.pcsController,
            label: 'Pcs (Optional)',
            icon: Icons.numbers,
            isOptional: true,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    String? value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(Icons.inventory_2_outlined, color: Colors.brown.shade300),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      initialValue: value,
      isExpanded: true,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
      validator: (val) => val == null ? "Please select an item" : null,
    );
  }

  Widget _buildOtherTextField({
    required TextEditingController controller,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(Icons.edit_note_outlined, color: Colors.orange.shade300),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
        validator: (val) => (val == null || val.isEmpty) ? 'Please enter item name' : null,
      ),
    );
  }

  Widget _buildQuantityField({
    required TextEditingController controller,
    required String label,
    required String selectedUnit,
    required Function(String?) onUnitChanged,
  }) {
    return _buildExpressionField(
        controller: controller,
        label: label,
        icon: Icons.format_list_numbered,
        isOptional: false,
        suffixIcon: DropdownButtonHideUnderline(
          child: Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: DropdownButton<String>(
              value: selectedUnit,
              items: units.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
              onChanged: onUnitChanged,
            ),
          ),
        ));
  }

  Widget _buildExpressionField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    Widget? suffixIcon,
    bool isOptional = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.brown.shade300),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade50,
        suffixIcon: suffixIcon,
      ),
      validator: (val) {
        if (val == null || val.isEmpty) {
          return isOptional ? null : 'This field is required';
        }
        try {
            String sanitizedExpression =
                val.replaceAll('x', '*').replaceAll('X', '*').trim();
            if (sanitizedExpression.endsWith('+') ||
                sanitizedExpression.endsWith('-') ||
                sanitizedExpression.endsWith('*') ||
                sanitizedExpression.endsWith('/')) {
              sanitizedExpression = sanitizedExpression.substring(
                  0, sanitizedExpression.length - 1);
            }
            if (sanitizedExpression.isEmpty) {
              return isOptional ? null : 'This field is required';
            }
            Parser p = Parser();
            p.parse(sanitizedExpression);
          } catch (e) {
            return 'Invalid expression';
          }
        return null;
      },
    );
  }

  Widget _buildDumpSalesTable() {
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _latestDumpSales,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text('No dump sales recorded yet.')));
          }
          final sales = snapshot.data!;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.brown.shade100),
              columns: const [
                DataColumn(label: Text('Item', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Item Tag', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Quantity', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Pcs', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Time', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: sales.map((row) {
                final pcsValue = row['pcs']?.toString() ?? '';
                final itemTag = row['item_tag']?.toString() ?? '';
                return DataRow(cells: [
                  DataCell(Text(row['item']?.toString() ?? '')),
                  DataCell(Text(itemTag)),
                  DataCell(Text("${row['quantity']} ${row['unit']}")),
                  DataCell(Text(pcsValue)),
                  DataCell(Text(row['date']?.toString() ?? '')),
                  DataCell(Text(row['time']?.toString() ?? '')),
                ]);
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}
