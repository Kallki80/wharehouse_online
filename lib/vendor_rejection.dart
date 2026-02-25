import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class VendorRejectionPage extends StatefulWidget {
  const VendorRejectionPage({super.key});

  @override
  State<VendorRejectionPage> createState() => _VendorRejectionPageState();
}

class _VendorRejectionPageState extends State<VendorRejectionPage> {
  final _formKey = GlobalKey<FormState>();
  final String baseUrl = 'https://api.shabari.ai';

  // --- फॉर्म के लिए ड्रॉपडाउन और "Other" की स्टेट ---
  String? _selectedItem;
  String? _selectedVendor;
  final TextEditingController _otherItemController = TextEditingController();
  final TextEditingController _otherVendorController = TextEditingController();

  // --- बाकी फॉर्म फील्ड्स के लिए कंट्रोलर्स ---
  final TextEditingController _poNumberController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _pcsController = TextEditingController(); // PCS के लिए

  DateTime? selectedDate;
  TimeOfDay? selectedTime;
  String selectedUnit = 'Kg';
  final List<String> units = ["Kg", "g", "pcs", "L", "ml"];

  Future<List<Map<String, dynamic>>>? _latestRejections;

  // --- ड्रॉपडाउन के लिए डायनामिक लिस्ट ---
  List<String> _itemList = [];
  List<String> _vendorList = [];
  bool _isLoadingDropdowns = true;

  // --- "Other" फील्ड को दिखाने के लिए फ्लैग्स ---
  bool _showOtherItemField = false;
  bool _showOtherVendorField = false;

  @override
  void initState() {
    super.initState();
    // डेटाबेस से डेटा लोड करें
    _loadDropdownData();
  }

  Future<void> _loadDropdownData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingDropdowns = true;
    });

    try {
      final itemsResponse = await http.get(Uri.parse('$baseUrl/get_items'));
      List<String> dbItems = [];
      if (itemsResponse.statusCode == 200) {
        dbItems = List<String>.from(json.decode(itemsResponse.body));
      }

      final vendorsResponse = await http.get(Uri.parse('$baseUrl/get_purchase_vendors'));
      List<String> dbVendors = [];
      if (vendorsResponse.statusCode == 200) {
        dbVendors = List<String>.from(json.decode(vendorsResponse.body));
      }

      final rejectionsResponse = await http.get(Uri.parse('$baseUrl/get_latest_vendor_rejections'));
      List<Map<String, dynamic>> latestRejections = [];
      if (rejectionsResponse.statusCode == 200) {
        latestRejections = List<Map<String, dynamic>>.from(json.decode(rejectionsResponse.body));
      }

      if (mounted) {
        setState(() {
          _itemList = ["Other", ...dbItems];
          _vendorList = ["Other", ...dbVendors];
          _latestRejections = Future.value(latestRejections);
          _isLoadingDropdowns = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingDropdowns = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  @override
  void dispose() {
    _otherItemController.dispose();
    _otherVendorController.dispose();
    _poNumberController.dispose();
    _quantityController.dispose();
    _pcsController.dispose();
    super.dispose();
  }

  // एक्सप्रेशन को कैलकुलेट करने के लिए हेल्पर फंक्शन
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
      GrammarParser p = GrammarParser();
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
    final isDateSelected = selectedDate != null && selectedTime != null;

    if (!isFormValid || !isDateSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill all required fields and select Date & Time.'),
            backgroundColor: Colors.redAccent),
      );
      return;
    }

    // Capture context dependent values before async gaps
    final String formattedTime = selectedTime!.format(context);

    String finalItem = _selectedItem!;
    String finalVendor = _selectedVendor!;

    if (_showOtherItemField) {
      finalItem = _otherItemController.text;
      await http.post(Uri.parse('$baseUrl/insert_item'), headers: {'Content-Type': 'application/json'}, body: json.encode({'name': finalItem}));
    }
    if (_showOtherVendorField) {
      finalVendor = _otherVendorController.text;
      await http.post(Uri.parse('$baseUrl/insert_purchase_vendor'), headers: {'Content-Type': 'application/json'}, body: json.encode({'name': finalVendor}));
    }

    final double? pcs = _pcsController.text.isNotEmpty
          ? _evaluateExpression(_pcsController.text)
          : null;

    Map<String, dynamic> dataToSave = {
      'item': finalItem,
      'vendor': finalVendor,
      'po_number': _poNumberController.text,
      'quantity_sent': _evaluateExpression(_quantityController.text),
      'unit': selectedUnit,
      'pcs': pcs,
      'date': DateFormat('yyyy-MM-dd').format(selectedDate!),
      'time': formattedTime,
    };

    await http.post(Uri.parse('$baseUrl/insert_vendor_rejection'), headers: {'Content-Type': 'application/json'}, body: json.encode(dataToSave));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Vendor Rejection Saved Successfully!'),
            backgroundColor: Colors.green),
      );
    }

    _formKey.currentState!.reset();
    _poNumberController.clear();
    _quantityController.clear();
    _pcsController.clear();
    _otherItemController.clear();
    _otherVendorController.clear();
    setState(() {
      selectedDate = null;
      selectedTime = null;
      selectedUnit = 'Kg';
      _selectedItem = null;
      _selectedVendor = null;
      _showOtherItemField = false;
      _showOtherVendorField = false;
    });

    _loadDropdownData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Vendor Rejection",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.purple.shade600, Colors.deepPurple.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 4,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 8.0,
              shadowColor: Colors.purple.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildDropdownWithOther(
                        label: 'Item Name',
                        icon: Icons.inventory_2_outlined,
                        selectedValue: _selectedItem,
                        items: _itemList,
                        onChanged: (value) {
                          setState(() {
                            _selectedItem = value;
                            _showOtherItemField = value == 'Other';
                          });
                        },
                        otherController: _otherItemController,
                        showOtherField: _showOtherItemField,
                      ),
                      const SizedBox(height: 18),
                      _buildDropdownWithOther(
                        label: 'Vendor Name',
                        icon: Icons.business_center_outlined,
                        selectedValue: _selectedVendor,
                        items: _vendorList,
                        onChanged: (value) {
                          setState(() {
                            _selectedVendor = value;
                            _showOtherVendorField = value == 'Other';
                          });
                        },
                        otherController: _otherVendorController,
                        showOtherField: _showOtherVendorField,
                      ),
                      const SizedBox(height: 18),
                      _buildTextFormField(
                        controller: _poNumberController,
                        label: 'PO Number',
                        icon: Icons.receipt_long_outlined,
                        isOptional: true,
                      ),
                      const SizedBox(height: 18),
                      _buildQuantityField(
                        controller: _quantityController,
                        label: 'Quantity Sent',
                        selectedUnit: selectedUnit,
                        onUnitChanged: (val) => setState(() => selectedUnit = val!),
                      ),
                      const SizedBox(height: 18),
                      _buildExpressionField(controller: _pcsController, label: 'Pcs (Optional)', icon: Icons.numbers, isOptional: true),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(child: _buildDateButton()),
                          const SizedBox(width: 12),
                          Expanded(child: _buildTimeButton()),
                        ],
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.undo_outlined, color: Colors.white),
                        label: const Text("Submit Rejection"),
                        onPressed: _submitForm,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.purple.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "Recent Vendor Rejections",
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            _buildRejectionsTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownWithOther({
    required String label,
    required IconData icon,
    required String? selectedValue,
    required List<String> items,
    required Function(String?) onChanged,
    required TextEditingController otherController,
    required bool showOtherField,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: selectedValue,
          hint: Text('Select $label'),
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: Colors.purple.shade300),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          items: _isLoadingDropdowns
              ? [
                  const DropdownMenuItem(
                      value: null,
                      enabled: false,
                      child: Row(
                        children: [
                          SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text("Loading..."),
                        ],
                      ))
                ]
              : items.map((String item) {
                  return DropdownMenuItem<String>(
                    value: item,
                    child: Text(item, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
          onChanged: _isLoadingDropdowns ? null : onChanged,
          validator: (value) {
            if (value == null || value.isEmpty) return 'Please select a $label';
            return null;
          },
        ),
        if (showOtherField)
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: TextFormField(
              controller: otherController,
              decoration: InputDecoration(
                labelText: 'Enter Other $label',
                prefixIcon: Icon(Icons.edit_note_outlined,
                    color: Colors.orange.shade300),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              validator: (val) {
                if (showOtherField && (val == null || val.isEmpty)) {
                  return 'Please enter a value';
                }
                return null;
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isOptional = false,
  }) {
    return _buildExpressionField(controller: controller, label: label, icon: icon, isOptional: isOptional, isExpression: false);
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
          items: units.map((String value) {
            return DropdownMenuItem<String>(
                value: value, child: Text(value));
          }).toList(),
          onChanged: onUnitChanged,
        ),
      )),
    );
  }

   Widget _buildExpressionField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    Widget? suffixIcon,
    bool isOptional = false,
    bool isExpression = true,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.purple.shade300),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade50,
        suffixIcon: suffixIcon,
      ),
      validator: (val) {
        if (val == null || val.isEmpty) {
          return isOptional ? null : 'This field is required';
        }
         if (isExpression) {
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
            GrammarParser p = GrammarParser();
            p.parse(sanitizedExpression);
          } catch (e) {
            return 'Invalid expression';
          }
        }
        return null;
      },
    );
  }

  Widget _buildDateButton() {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today_outlined),
      onPressed: () async {
        DateTime? pickedDate = await showDatePicker(
            context: context,
            initialDate: DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100));
        if (pickedDate != null) {
          setState(() => selectedDate = pickedDate);
        }
      },
      label: Text(selectedDate == null
          ? "Date"
          : DateFormat('dd-MM-yy').format(selectedDate!)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: BorderSide(color: Colors.grey.shade400),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildTimeButton() {
    return OutlinedButton.icon(
      icon: const Icon(Icons.access_time_outlined),
      onPressed: () async {
        TimeOfDay? pickedTime =
            await showTimePicker(context: context, initialTime: TimeOfDay.now());
        if (pickedTime != null) {
          setState(() => selectedTime = pickedTime);
        }
      },
      label: Text(
          selectedTime == null ? "Time" : selectedTime!.format(context)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: BorderSide(color: Colors.grey.shade400),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildRejectionsTable() {
    return Card(
      elevation: 4.0,
      margin: const EdgeInsets.symmetric(horizontal: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _latestRejections,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text("Error: ${snapshot.error}")));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text("No vendor rejection records found.")));
          }
          final rejections = snapshot.data!;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.purple.shade100),
              columns: const [
                DataColumn(label: Text('Item', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Vendor', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('PO Num', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Qty Sent', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Pcs', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Time', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: rejections.map((row) {
                return DataRow(cells: [
                  DataCell(Text(row['item']?.toString() ?? '')),
                  DataCell(Text(row['vendor']?.toString() ?? '')),
                  DataCell(Text(row['po_number']?.toString() ?? '')),
                  DataCell(Text('${row['quantity_sent']} ${row['unit']}')),
                  DataCell(Text(row['pcs']?.toString() ?? '')),
                  DataCell(Text(DateFormat('dd-MM-yy').format(DateTime.parse(row['date'])))),
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
