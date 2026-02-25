import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const String apiBaseUrl = 'http://13.53.71.103:5000/';
// const String apiBaseUrl = 'http://10.0.2.2:5000';

class MandiResaleItem {
  String? selectedItem;
  String selectedUnit = 'Kg';
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController pcsController = TextEditingController();
  final TextEditingController tagController = TextEditingController();
  bool isOtherItem = false;
  final TextEditingController otherItemController = TextEditingController();

  void dispose() {
    qtyController.dispose();
    pcsController.dispose();
    tagController.dispose();
    otherItemController.dispose();
  }
}

class MandiResale extends StatefulWidget {
  const MandiResale({super.key});

  @override
  State<MandiResale> createState() => _MandiResaleState();
}

class _MandiResaleState extends State<MandiResale> {
  final _formKey = GlobalKey<FormState>();
  List<MandiResaleItem> resaleItems = [];
  List<String> _items = [];
  final List<String> units = ["Kg", "g", "pcs", "L", "ml"];
  bool _isLoading = true;
  Future<List<Map<String, dynamic>>>? _latestMandiResales;

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
    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/get_purchased_items'));
      if (response.statusCode == 200 && mounted) {
        List<String> dbItems = List<String>.from(json.decode(response.body));
        setState(() {
          _items = ["Other", ...dbItems];
          _latestMandiResales = http.get(Uri.parse('$apiBaseUrl/get_latest_mandi_resales')).then((res) {
            if (res.statusCode == 200) {
              return List<Map<String, dynamic>>.from(json.decode(res.body));
            } else {
              return [];
            }
          });
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    for (var item in resaleItems) {
      item.dispose();
    }
    super.dispose();
  }

  void _addNewItem() {
    setState(() {
      resaleItems.add(MandiResaleItem());
    });
  }

  void _removeItem(int index) {
    if (resaleItems.length > 1) {
      final item = resaleItems.removeAt(index);
      item.dispose();
      setState(() {});
    }
  }

  double _evaluateExpression(String expression) {
    if (expression.trim().isEmpty) return 0.0;
    String sanitizedExpression = expression.replaceAll('x', '*').replaceAll('X', '*');
    if (sanitizedExpression.endsWith('+') || sanitizedExpression.endsWith('-') || sanitizedExpression.endsWith('*') || sanitizedExpression.endsWith('/')) {
      sanitizedExpression = sanitizedExpression.substring(0, sanitizedExpression.length - 1);
    }
    try {
      Parser p = Parser();
      Expression exp = p.parse(sanitizedExpression);
      ContextModel cm = ContextModel();
      return exp.evaluate(EvaluationType.REAL, cm);
    } catch (e) {
      return 0.0;
    }
  }

  void _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields.'), backgroundColor: Colors.redAccent));
      return;
    }

    setState(() => _isLoading = true);
    final String formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final String formattedTime = DateFormat('hh:mm a').format(DateTime.now());

    try {
      for (var resaleItem in resaleItems) {
        String finalItemName = resaleItem.selectedItem!;
        if (resaleItem.isOtherItem) {
          finalItemName = resaleItem.otherItemController.text;
          await http.post(Uri.parse('$apiBaseUrl/insert_item'), body: json.encode({'name': finalItemName}), headers: {'Content-Type': 'application/json'});
        }

        final double qty = _evaluateExpression(resaleItem.qtyController.text);
        final double? pcs = resaleItem.pcsController.text.isNotEmpty ? _evaluateExpression(resaleItem.pcsController.text) : null;

        Map<String, dynamic> dataToSave = {
          'item': finalItemName,
          'quantity': qty,
          'unit': resaleItem.selectedUnit,
          'pcs': pcs,
          'item_tag': resaleItem.tagController.text,
          'date': formattedDate,
          'time': formattedTime,
        };

        await http.post(Uri.parse('$apiBaseUrl/insert_mandi_resale'), body: json.encode(dataToSave), headers: {'Content-Type': 'application/json'});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mandi Resale Saved Successfully!'), backgroundColor: Colors.green));
        
        final oldItems = List<MandiResaleItem>.from(resaleItems);
        setState(() {
          resaleItems = [];
          _addNewItem();
        });
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (var item in oldItems) {
            item.dispose();
          }
        });
        
        _loadInitialData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey.shade50,
      appBar: AppBar(
        title: const Text('Mandi Resale', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.blueGrey.shade700,
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
                              itemCount: resaleItems.length,
                              itemBuilder: (context, index) => _buildItemEntry(index),
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              icon: Icon(Icons.add_circle_outline, color: Colors.blueGrey.shade700),
                              label: Text("Add More Items", style: TextStyle(color: Colors.blueGrey.shade700)),
                              onPressed: _addNewItem,
                            ),
                            const SizedBox(height: 30),
                            ElevatedButton(
                              onPressed: _submitForm,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                backgroundColor: Colors.blueGrey.shade800,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Submit Mandi Resale'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text("Recent Mandi Resales", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  const SizedBox(height: 8),
                  _buildMandiResalesTable(),
                ],
              ),
            ),
    );
  }

  Widget _buildItemEntry(int index) {
    if (index >= resaleItems.length) return const SizedBox.shrink();
    final resaleItem = resaleItems[index];
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: InputDecoration(labelText: "Select Item", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  value: resaleItem.selectedItem,
                  items: _items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
                  onChanged: (val) async {
                    if (val != null && mounted) {
                      setState(() {
                        resaleItem.selectedItem = val;
                        resaleItem.isOtherItem = (val == 'Other');
                      });
                      if (val != 'Other') {
                        try {
                          final response = await http.get(Uri.parse('$apiBaseUrl/get_purchased_tags_for_item?item=$val'));
                          if (response.statusCode == 200 && mounted && resaleItems.contains(resaleItem)) {
                            List<String> tags = List<String>.from(json.decode(response.body));
                            if (tags.isNotEmpty) {
                              setState(() => resaleItem.tagController.text = tags.first);
                            } else {
                              setState(() => resaleItem.tagController.clear());
                            }
                          }
                        } catch (e) {
                          debugPrint("Error fetching tags: $e");
                        }
                      }
                    }
                  },
                ),
              ),
              if (resaleItems.length > 1) IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => _removeItem(index)),
            ],
          ),
          if (resaleItem.isOtherItem)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: TextFormField(
                controller: resaleItem.otherItemController,
                decoration: InputDecoration(labelText: 'Enter New Item Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ),
          const SizedBox(height: 18),
          TextFormField(
            controller: resaleItem.tagController,
            decoration: InputDecoration(labelText: 'Item Tag', prefixIcon: const Icon(Icons.tag), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            validator: (val) => (val == null || val.isEmpty) ? "Item Tag is required" : null,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: resaleItem.qtyController,
                  decoration: InputDecoration(labelText: 'Quantity', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  validator: (val) => (val == null || val.isEmpty) ? "Required" : null,
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: resaleItem.selectedUnit,
                items: units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                onChanged: (val) => setState(() => resaleItem.selectedUnit = val!),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: resaleItem.pcsController,
            decoration: InputDecoration(labelText: 'Pcs (Optional)', prefixIcon: const Icon(Icons.numbers), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ],
      ),
    );
  }

  Widget _buildMandiResalesTable() {
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _latestMandiResales,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) return const Padding(padding: EdgeInsets.all(16.0), child: Text('No data available.'));
          
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Item')),
                DataColumn(label: Text('Tag')),
                DataColumn(label: Text('Qty')),
                DataColumn(label: Text('Date')),
              ],
              rows: snapshot.data!.map((sale) => DataRow(cells: [
                DataCell(Text(sale['item'] ?? '')),
                DataCell(Text(sale['item_tag'] ?? '')),
                DataCell(Text("${sale['quantity']} ${sale['unit']}")),
                DataCell(Text(sale['date'] ?? '')),
              ])).toList(),
            ),
          );
        },
      ),
    );
  }
}
