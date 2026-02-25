import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RejectionItem {
  String? selectedItem;
  String selectedUnit = 'Kg';
  final TextEditingController itemTagController = TextEditingController(); // Controller for Tag
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController pcsController = TextEditingController();
  final TextEditingController sampleQtyController = TextEditingController();
  final TextEditingController soNumberController = TextEditingController(); // Controller for SO Number
  final TextEditingController reasonController = TextEditingController();
  
  List<String> availableItems = [];

  void dispose() {
    itemTagController.dispose();
    qtyController.dispose();
    pcsController.dispose();
    sampleQtyController.dispose();
    soNumberController.dispose();
    reasonController.dispose();
  }
}

class RejectionReceived extends StatefulWidget {
  const RejectionReceived({super.key});

  @override
  State<RejectionReceived> createState() => _RejectionReceivedPageState();
}

class _RejectionReceivedPageState extends State<RejectionReceived> {
  final _formKey = GlobalKey<FormState>();
  final String baseUrl = 'https://api.shabari.ai';

  DateTime? ctrlDate;
  String? _selectedDate;
  String? _selectedClient;
  
  List<RejectionItem> rejectionItems = [];
  List<Map<String, dynamic>> _allSales = [];
  List<String> _availableDates = [];
  List<String> _availableClients = [];
  
  final List<String> units = ["Kg", "g", "pcs", "L", "ml"];
  bool _isLoading = true;

  Future<List<Map<String, dynamic>>>? _latestRejections;

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
      final salesResponse = await http.get(Uri.parse('$baseUrl/get_all_sales'));
      if (salesResponse.statusCode == 200) {
        _allSales = List<Map<String, dynamic>>.from(json.decode(salesResponse.body));

        // Get unique dates from sales
        _availableDates = _allSales
            .map((sale) => sale['date'] as String)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));

        final rejectionsResponse = await http.get(Uri.parse('$baseUrl/get_latest_rejection_received'));
        List<Map<String, dynamic>> latestRejections = [];
        if (rejectionsResponse.statusCode == 200) {
          latestRejections = List<Map<String, dynamic>>.from(json.decode(rejectionsResponse.body));
        }

        if (mounted) {
          setState(() {
            _latestRejections = Future.value(latestRejections);
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to load data")));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  void _onDateChanged(String? date) {
    setState(() {
      _selectedDate = date;
      _selectedClient = null;
      _availableClients = [];
      rejectionItems.clear();
      _addNewItem();

      if (date != null) {
        _availableClients = _allSales
            .where((sale) => sale['date'] == date)
            .map((sale) => sale['clint'] as String)
            .toSet()
            .toList()
          ..sort();
      }
    });
  }

  void _onClientChanged(String? client) {
    setState(() {
      _selectedClient = client;
      
      List<String> clientItems = [];
      if (_selectedDate != null && client != null) {
        clientItems = _allSales
            .where((sale) => sale['date'] == _selectedDate && sale['clint'] == client)
            .map((sale) => sale['item'] as String)
            .toSet()
            .toList()
          ..sort();
      }

      for (var item in rejectionItems) {
        item.availableItems = clientItems;
        item.selectedItem = null;
        item.itemTagController.clear();
        item.soNumberController.clear();
      }
    });
  }

  void _onItemChanged(RejectionItem item, String? itemName) {
    setState(() {
      item.selectedItem = itemName;
      if (itemName != null && _selectedDate != null && _selectedClient != null) {
        final sale = _allSales.firstWhere(
          (s) => s['date'] == _selectedDate && s['clint'] == _selectedClient && s['item'] == itemName,
          orElse: () => {},
        );
        if (sale.isNotEmpty) {
          item.itemTagController.text = sale['item_tag'] ?? '';
          item.soNumberController.text = sale['po_number'] ?? '';
        }
      }
    });
  }

  @override
  void dispose() {
    for (var item in rejectionItems) {
      item.dispose();
    }
    super.dispose();
  }

  void _addNewItem() {
    final newItem = RejectionItem();
    if (_selectedDate != null && _selectedClient != null) {
      newItem.availableItems = _allSales
          .where((sale) => sale['date'] == _selectedDate && sale['clint'] == _selectedClient)
          .map((sale) => sale['item'] as String)
          .toSet()
          .toList()
        ..sort();
    }
    setState(() {
      rejectionItems.add(newItem);
    });
  }

  void _removeItem(int index) {
    if (rejectionItems.length > 1) {
      rejectionItems[index].dispose();
      setState(() {
        rejectionItems.removeAt(index);
      });
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
    final isFormValid = _formKey.currentState!.validate();
    final isCtrlDateSelected = ctrlDate != null;

    if (!isFormValid || !isCtrlDateSelected || _selectedDate == null || _selectedClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields and select Dates/Client.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final String formattedTime = TimeOfDay.now().format(context);

    for (var rejectionItem in rejectionItems) {
      final double qty = _evaluateExpression(rejectionItem.qtyController.text);
      final double? pcs = rejectionItem.pcsController.text.isNotEmpty ? _evaluateExpression(rejectionItem.pcsController.text) : null;
      final double? sampleQty = rejectionItem.sampleQtyController.text.isNotEmpty ? _evaluateExpression(rejectionItem.sampleQtyController.text) : null;

      Map<String, dynamic> dataToSave = {
        'client_name': _selectedClient,
        'item': rejectionItem.selectedItem,
        'po_number': rejectionItem.soNumberController.text, // Saving SO Number
        'item_tag': rejectionItem.itemTagController.text, 
        'quantity': qty,
        'unit': rejectionItem.selectedUnit,
        'pcs': pcs,
        'sample_quantity': sampleQty,
        'reason': rejectionItem.reasonController.text,
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'time': formattedTime,
        'ctrl_date': DateFormat('yyyy-MM-dd').format(ctrlDate!),
      };

      await http.post(Uri.parse('$baseUrl/insert_rejection_received'), headers: {'Content-Type': 'application/json'}, body: json.encode(dataToSave));
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rejection Record Saved!'), backgroundColor: Colors.green));
    }

    _formKey.currentState!.reset();
    for (var item in rejectionItems) { item.dispose(); }
    setState(() {
      rejectionItems = [];
      ctrlDate = null;
      _selectedDate = null;
      _selectedClient = null;
    });
    _addNewItem();
    _loadInitialData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Rejection Received", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.red.shade600, Colors.pink.shade400], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        ),
        elevation: 4,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            _buildTopSelectionSection(),
                            const Divider(height: 32, thickness: 1),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: rejectionItems.length,
                              itemBuilder: (context, index) => _buildItemEntry(index),
                            ),
                            const SizedBox(height: 12),
                            if (_selectedDate != null && _selectedClient != null)
                              TextButton.icon(
                                icon: const Icon(Icons.add_circle_outline, color: Colors.red),
                                label: const Text("Add More Items"),
                                onPressed: _addNewItem,
                              ),
                            const SizedBox(height: 24),
                            _buildCtrlDateButton(),
                            const SizedBox(height: 30),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.send_outlined, color: Colors.white),
                              label: const Text("Submit Rejection"),
                              onPressed: _submitForm,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.red.shade700,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text("Recent Rejections", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red.shade900), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  _buildRejectionsTable(),
                ],
              ),
            ),
    );
  }

  Widget _buildTopSelectionSection() {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          decoration: InputDecoration(
            labelText: "Select Sale Date",
            prefixIcon: const Icon(Icons.calendar_today, color: Colors.red),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          initialValue: _selectedDate,
          items: _availableDates.map((d) {
            final displayDate = DateFormat('dd-MM-yyyy').format(DateTime.parse(d));
            return DropdownMenuItem(value: d, child: Text(displayDate));
          }).toList(),
          onChanged: _onDateChanged,
          validator: (val) => val == null ? "Select date" : null,
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          decoration: InputDecoration(
            labelText: "Select Client",
            prefixIcon: const Icon(Icons.person, color: Colors.red),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          initialValue: _selectedClient,
          items: _availableClients.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: _onClientChanged,
          validator: (val) => val == null ? "Select client" : null,
          isExpanded: true,
        ),
      ],
    );
  }

  Widget _buildItemEntry(int index) {
    final rejectionItem = rejectionItems[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: "Select Item",
                    prefixIcon: const Icon(Icons.inventory_2_outlined, color: Colors.red),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  initialValue: rejectionItem.selectedItem,
                  items: rejectionItem.availableItems.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (val) => _onItemChanged(rejectionItem, val),
                  validator: (val) => val == null ? "Select item" : null,
                ),
              ),
              if (rejectionItems.length > 1)
                IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => _removeItem(index)),
            ],
          ),
          const SizedBox(height: 18),
          
          _buildExpressionField(
            controller: rejectionItem.itemTagController,
            label: 'Item Tag (Optional)',
            icon: Icons.tag,
            isExpression: false,
            isOptional: true,
          ),
          const SizedBox(height: 18),

          _buildExpressionField(
            controller: rejectionItem.soNumberController,
            label: 'SO Number (Autofill)',
            icon: Icons.receipt_long_outlined,
            isExpression: false,
            // readOnly: true,
          ),
          const SizedBox(height: 18),

          _buildQuantityField(
            controller: rejectionItem.qtyController,
            label: 'Quantity',
            selectedUnit: rejectionItem.selectedUnit,
            onUnitChanged: (val) => setState(() => rejectionItem.selectedUnit = val!),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildExpressionField(controller: rejectionItem.pcsController, label: 'Pcs (Optional)', icon: Icons.numbers, isOptional: true),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildExpressionField(controller: rejectionItem.sampleQtyController, label: 'Sample Qty', icon: Icons.science_outlined, isOptional: true),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: rejectionItem.reasonController,
            decoration: InputDecoration(labelText: 'Reason', prefixIcon: const Icon(Icons.comment_outlined, color: Colors.red), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.grey.shade50, labelStyle: const TextStyle(fontSize: 14)),
            maxLines: 2,
            validator: (val) => val == null || val.isEmpty ? 'Enter reason' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityField({required TextEditingController controller, required String label, required String selectedUnit, required Function(String?) onUnitChanged}) {
    return _buildExpressionField(
      controller: controller,
      label: label,
      icon: Icons.format_list_numbered,
      suffixIcon: DropdownButtonHideUnderline(
        child: Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: DropdownButton<String>(
            value: selectedUnit,
            items: units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
            onChanged: onUnitChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildExpressionField({required TextEditingController controller, required String label, required IconData icon, Widget? suffixIcon, bool isOptional = false, bool isExpression = true, bool readOnly = false}) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, color: Colors.red.shade300), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: readOnly ? Colors.grey.shade100 : Colors.grey.shade50, suffixIcon: suffixIcon, labelStyle: const TextStyle(fontSize: 14)),
      style: const TextStyle(fontSize: 14),
      validator: (val) {
        if (val == null || val.isEmpty) return isOptional ? null : 'Required';
        if (isExpression) {
          try {
            String sanitized = val.replaceAll('x', '*').replaceAll('X', '*').trim();
            if (sanitized.endsWith('+') || sanitized.endsWith('-') || sanitized.endsWith('*') || sanitized.endsWith('/')) {
              sanitized = sanitized.substring(0, sanitized.length - 1);
            }
            Parser().parse(sanitized);
          } catch (e) { return 'Invalid'; }
        }
        return null;
      },
    );
  }

  Widget _buildCtrlDateButton() {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_month, color: Colors.teal),
      onPressed: () async {
        DateTime? picked = await showDatePicker(context: context, initialDate: ctrlDate ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
        if (picked != null) setState(() => ctrlDate = picked);
      },
      label: Text(ctrlDate == null ? 'Select CTRL Date' : 'CTRL: ${DateFormat('dd-MM-yy').format(ctrlDate!)}'),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    );
  }

  Widget _buildRejectionsTable() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _latestRejections,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
          if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text("No records.")));
          final rejections = snapshot.data!;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.red.shade100),
              columns: const [
                DataColumn(label: Text('Tag')), DataColumn(label: Text('Client')), DataColumn(label: Text('Item')), DataColumn(label: Text('SO Num')), DataColumn(label: Text('Qty')), DataColumn(label: Text('Pcs')), DataColumn(label: Text('Sample')), DataColumn(label: Text('Reason')), DataColumn(label: Text('Date')), DataColumn(label: Text('CTRL')),
              ],
              rows: rejections.map((row) => DataRow(cells: [
                DataCell(Text(row['item_tag'] ?? '')),
                DataCell(Text(row['client_name'] ?? '')), 
                DataCell(Text(row['item'] ?? '')), 
                DataCell(Text(row['po_number'] ?? '')), 
                DataCell(Text('${row['quantity']} ${row['unit']}')), 
                DataCell(Text(row['pcs']?.toString() ?? '')), 
                DataCell(Text(row['sample_quantity']?.toString() ?? '')), 
                DataCell(Text(row['reason'] ?? '')), 
                DataCell(Text(DateFormat('dd-MM-yy').format(DateTime.parse(row['date'])))), 
                DataCell(Text(DateFormat('dd-MM-yy').format(DateTime.parse(row['ctrl_date'])))),
              ])).toList(),
            ),
          );
        },
      ),
    );
  }
}
