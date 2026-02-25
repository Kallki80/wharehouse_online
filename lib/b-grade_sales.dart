import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// const String apiBaseUrl = 'http://13.53.71.103:5000/';
const String apiBaseUrl = 'http://10.0.2.2:5000';

// API Helper Functions
Future<List<Map<String, dynamic>>> getAllPurchases() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_all_purchases'));
  if (response.statusCode == 200) {
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load purchases');
  }
}

Future<List<String>> getBGradeClients() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_b_grade_clients'));
  if (response.statusCode == 200) {
    return List<String>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load b-grade clients');
  }
}

Future<void> insertVendor(String name) async {
  final response = await http.post(
    Uri.parse('$apiBaseUrl/insert_vendor'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({'name': name}),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to insert vendor');
  }
}

Future<void> insertBGradeSale(Map<String, dynamic> data) async {
  final response = await http.post(
    Uri.parse('$apiBaseUrl/insert_b_grade_sale'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(data),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to insert b-grade sale');
  }
}

Future<List<Map<String, dynamic>>> getLatestBGradeSales() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_latest_b_grade_sales'));
  if (response.statusCode == 200) {
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load latest b-grade sales');
  }
}

class BGradeSaleItem {
  String? selectedItem;
  String? selectedTag;
  List<String> availableTags = [];
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController rateController = TextEditingController();
  final TextEditingController pcsController = TextEditingController();
  final TextEditingController poNumberController = TextEditingController();
  String selectedUnit = 'Kg';
  double itemTotal = 0.0;

  void dispose() {
    qtyController.dispose();
    rateController.dispose();
    pcsController.dispose();
    poNumberController.dispose();
  }
}

class Page3 extends StatefulWidget {
  const Page3({super.key});

  @override
  State<Page3> createState() => _Page3State();
}

class _Page3State extends State<Page3> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedClient;
  bool _isOtherClient = false;
  final TextEditingController _otherClientController = TextEditingController();
  
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  List<BGradeSaleItem> _saleItems = [];
  
  final List<String> _predefinedClients = [
    "bittu", "swaraj", "monu", "raju", "hari", 
    "kailash", "kamlash", "vipin", "prashant", "pawan", 
    "walk in customers"
  ];
  
  List<String> _clients = [];
  List<String> _itemsFromPurchases = [];
  List<Map<String, dynamic>> _allPurchaseData = [];
  
  final List<String> _units = ["Kg", "g", "pcs", "L", "ml"];
  bool _isLoading = true;
  double _grandTotal = 0.0;

  // Payment fields
  String _paymentStatus = 'Unpaid';
  String? _selectedMode;
  final _amountPaidController = TextEditingController();
  double _amountDue = 0.0;

  @override
  void initState() {
    super.initState();
    _loadInitialData().then((_) {
      if (mounted) {
        _addNewItem();
      }
    });
    _amountPaidController.addListener(_calculateAmountDue);
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final purchases = await getAllPurchases();
    final dbClients = await getBGradeClients();

    final Set<String> uniqueItems = purchases
        .where((p) => p['item'] != null)
        .map((p) => p['item'] as String)
        .toSet();

    if (mounted) {
      setState(() {
        _clients = ["Other", ..._predefinedClients, ...dbClients];
        _itemsFromPurchases = uniqueItems.toList()..sort();
        _allPurchaseData = purchases;
        _isLoading = false;
      });
    }
  }

  void _addNewItem() {
    final newItem = BGradeSaleItem();
    newItem.qtyController.addListener(_calculateTotals);
    newItem.rateController.addListener(_calculateTotals);
    setState(() {
      _saleItems.add(newItem);
    });
  }

  void _removeItem(int index) {
    if (_saleItems.length > 1) {
      _saleItems[index].dispose();
      setState(() {
        _saleItems.removeAt(index);
        _calculateTotals();
      });
    }
  }

  double _evaluateExpression(String expression) {
    if (expression.trim().isEmpty) return 0.0;
    String sanitized = expression.replaceAll('x', '*').replaceAll('X', '*');
    if (sanitized.endsWith('+') || sanitized.endsWith('-') || sanitized.endsWith('*') || sanitized.endsWith('/')) {
      sanitized = sanitized.substring(0, sanitized.length - 1);
    }
    try {
      Parser p = Parser();
      Expression exp = p.parse(sanitized);
      ContextModel cm = ContextModel();
      return exp.evaluate(EvaluationType.REAL, cm);
    } catch (e) {
      return 0.0;
    }
  }

  void _calculateTotals() {
    double total = 0.0;
    for (var item in _saleItems) {
      final qty = _evaluateExpression(item.qtyController.text);
      final rate = _evaluateExpression(item.rateController.text);
      item.itemTotal = qty * rate;
      total += item.itemTotal;
    }
    setState(() {
      _grandTotal = total;
      _calculateAmountDue();
    });
  }

  void _calculateAmountDue() {
    if (_paymentStatus == 'Partial Paid') {
      double paid = double.tryParse(_amountPaidController.text) ?? 0.0;
      setState(() {
        _amountDue = _grandTotal - paid;
      });
    } else if (_paymentStatus == 'Paid') {
      setState(() => _amountDue = 0.0);
    } else {
      setState(() => _amountDue = _grandTotal);
    }
  }

  void _onItemChanged(BGradeSaleItem item, String? itemName) {
    setState(() {
      item.selectedItem = itemName;
      item.selectedTag = null;
      item.poNumberController.clear();
      
      if (itemName != null) {
        final itemPurchases = _allPurchaseData.where((p) => p['item'] == itemName).toList();
        item.availableTags = itemPurchases
            .map((p) => p['item_tag'] as String?)
            .where((tag) => tag != null)
            .cast<String>()
            .toSet()
            .toList();
            
        if (item.availableTags.length == 1) {
          _onTagChanged(item, item.availableTags.first);
        }
      } else {
        item.availableTags = [];
      }
    });
  }

  void _onTagChanged(BGradeSaleItem item, String? tag) {
    setState(() {
      item.selectedTag = tag;
      if (tag != null && item.selectedItem != null) {
        final match = _allPurchaseData.firstWhere(
          (p) => p['item'] == item.selectedItem && p['item_tag'] == tag,
          orElse: () => {},
        );
        if (match.isNotEmpty) {
          item.poNumberController.text = match['po_number'] ?? '';
        }
      }
    });
  }

  @override
  void dispose() {
    _otherClientController.dispose();
    _amountPaidController.dispose();
    for (var item in _saleItems) {
      item.dispose();
    }
    super.dispose();
  }

  void _handleSubmit() async {
    final isFormValid = _formKey.currentState!.validate();
    final isDateSelected = _selectedDate != null && _selectedTime != null;

    if (!isFormValid || !isDateSelected || _selectedClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Please fill all required fields and select client/date/time"),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    final String formattedTime = _selectedTime!.format(context);
    String finalClient = _selectedClient!;
    if (_isOtherClient) {
      finalClient = _otherClientController.text;
      await insertVendor(finalClient);
    }

    double totalPaid = double.tryParse(_amountPaidController.text) ?? 0.0;
    if (_paymentStatus == 'Paid') totalPaid = _grandTotal;

    for (var item in _saleItems) {
      final double? pcsValue = item.pcsController.text.isNotEmpty
          ? _evaluateExpression(item.pcsController.text)
          : null;

      double itemPaidShare = 0.0;
      double itemDueShare = item.itemTotal;
      if (_grandTotal > 0) {
        itemPaidShare = (item.itemTotal / _grandTotal) * totalPaid;
        itemDueShare = item.itemTotal - itemPaidShare;
      }

      Map<String, dynamic> dataToSave = {
        'item': item.selectedItem,
        'clint': finalClient,
        'quantity': _evaluateExpression(item.qtyController.text),
        'rate': _evaluateExpression(item.rateController.text),
        'unit': item.selectedUnit,
        'total_value': item.itemTotal,
        'po_number': item.poNumberController.text,
        'pcs': pcsValue,
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate!),
        'time': formattedTime,
        'item_tag': item.selectedTag,
        'payment_status': _paymentStatus,
        'mode_of_payment': _selectedMode,
        'amount_paid': itemPaidShare,
        'amount_due': itemDueShare,
      };

      await insertBGradeSale(dataToSave);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("B-Grade Sales Saved Successfully!"),
        backgroundColor: Colors.green,
      ));
    }

    _resetForm();
    _loadInitialData();
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _otherClientController.clear();
    _amountPaidController.clear();
    for (var item in _saleItems) {
      item.dispose();
    }
    setState(() {
      _saleItems = [];
      _selectedClient = null;
      _isOtherClient = false;
      _selectedDate = null;
      _selectedTime = null;
      _grandTotal = 0.0;
      _paymentStatus = 'Unpaid';
      _selectedMode = null;
      _amountDue = 0.0;
    });
    _addNewItem();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("B-Grade Sales Entry",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade600, Colors.cyan.shade500],
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
                            _buildClientSection(),
                            const SizedBox(height: 24),
                            const Divider(thickness: 1),
                            const SizedBox(height: 12),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _saleItems.length,
                              itemBuilder: (context, index) {
                                return _buildItemEntry(index);
                              },
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              icon: const Icon(Icons.add_circle_outline, color: Colors.teal),
                              label: const Text("Add More Items", style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
                              onPressed: _addNewItem,
                            ),
                            const SizedBox(height: 24),
                            _buildSummarySection(),
                            const SizedBox(height: 24),
                            _buildPaymentSection(),
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
                              icon: const Icon(Icons.send_outlined, color: Colors.white),
                              label: const Text("Submit All Sales"),
                              onPressed: _handleSubmit,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.teal.shade700,
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
                  _buildSalesTable(),
                ],
              ),
            ),
    );
  }

  Widget _buildClientSection() {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          decoration: InputDecoration(
            labelText: "Select Client",
            prefixIcon: Icon(Icons.person_outline, color: Colors.teal.shade300),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          isExpanded: true,
          initialValue: _selectedClient,
          items: ["Other", ..._predefinedClients].map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (val) {
            setState(() {
              _selectedClient = val;
              _isOtherClient = (val == "Other");
            });
          },
          validator: (val) => val == null ? "Please select client" : null,
        ),
        if (_isOtherClient)
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: TextFormField(
              controller: _otherClientController,
              decoration: InputDecoration(
                labelText: "Enter New Client Name",
                prefixIcon: Icon(Icons.edit_note_outlined, color: Colors.orange.shade300),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              validator: (val) => (_isOtherClient && (val == null || val.isEmpty)) ? "Please enter client name" : null,
            ),
          ),
      ],
    );
  }

  Widget _buildItemEntry(int index) {
    final item = _saleItems[index];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Item #${index + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
              if (_saleItems.length > 1)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                  onPressed: () => _removeItem(index),
                ),
            ],
          ),
          const Divider(),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: "Select Item",
              prefixIcon: Icon(Icons.inventory_2_outlined, color: Colors.teal.shade300),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            isExpanded: true,
            initialValue: item.selectedItem,
            items: _itemsFromPurchases.map((i) => DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (val) => _onItemChanged(item, val),
            validator: (val) => val == null ? "Select item" : null,
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: "Select Item Tag",
              prefixIcon: Icon(Icons.tag, color: Colors.orange.shade300),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            isExpanded: true,
            initialValue: item.selectedTag,
            items: item.availableTags.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (val) => _onTagChanged(item, val),
            validator: (val) => val == null ? "Select tag" : null,
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: item.poNumberController,
            decoration: InputDecoration(
              labelText: "PO Number",
              prefixIcon: Icon(Icons.receipt_long_outlined, color: Colors.teal.shade300),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            readOnly: true,
          ),
          const SizedBox(height: 18),
          _buildQuantityField(item),
          const SizedBox(height: 18),
          _buildRateField(item),
          const SizedBox(height: 18),
          _buildExpressionField(
            controller: item.pcsController,
            label: "Pcs (Optional)",
            icon: Icons.numbers,
            isOptional: true,
          ),
          const SizedBox(height: 12),
          Text("Item Total: ₹ ${item.itemTotal.toStringAsFixed(2)}", 
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
        ],
      ),
    );
  }

  Widget _buildPaymentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text("Payment Details", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _paymentStatus,
          decoration: InputDecoration(
            labelText: "Payment Status",
            prefixIcon: const Icon(Icons.payments_outlined, color: Colors.indigo),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: ['Paid', 'Unpaid', 'Partial Paid'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: (val) {
            setState(() {
              _paymentStatus = val!;
              if (_paymentStatus == 'Unpaid') {
                _selectedMode = null;
                _amountPaidController.clear();
              }
              _calculateAmountDue();
            });
          },
        ),
        if (_paymentStatus != 'Unpaid') ...[
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: _selectedMode,
            decoration: InputDecoration(
              labelText: "Mode of Payment",
              prefixIcon: const Icon(Icons.account_balance_wallet_outlined, color: Colors.indigo),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: ['Online', 'Cash', 'Imprest'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: (val) => setState(() => _selectedMode = val),
            validator: (val) => (_paymentStatus != 'Unpaid' && val == null) ? "Select mode" : null,
          ),
        ],
        if (_paymentStatus == 'Partial Paid') ...[
          const SizedBox(height: 18),
          TextFormField(
            controller: _amountPaidController,
            decoration: InputDecoration(
              labelText: "Amount Paid",
              prefixIcon: const Icon(Icons.attach_money, color: Colors.indigo),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            keyboardType: TextInputType.number,
            validator: (val) => (_paymentStatus == 'Partial Paid' && (val == null || val.isEmpty)) ? "Enter amount" : null,
          ),
          const SizedBox(height: 12),
          Text("Remaining Due: ₹ ${_amountDue.toStringAsFixed(2)}", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        ],
      ],
    );
  }

  Widget _buildQuantityField(BGradeSaleItem item) {
    return TextFormField(
      controller: item.qtyController,
      decoration: InputDecoration(
        labelText: "Quantity",
        prefixIcon: Icon(Icons.format_list_numbered, color: Colors.teal.shade300),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade50,
        suffixIcon: DropdownButtonHideUnderline(
          child: Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: DropdownButton<String>(
              value: item.selectedUnit,
              items: _units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
              onChanged: (val) => setState(() => item.selectedUnit = val!),
            ),
          ),
        ),
      ),
      validator: (val) {
        if (val == null || val.isEmpty) return "Required";
        try {
          String sanitized = val.replaceAll('x', '*').replaceAll('X', '*').trim();
          if (sanitized.endsWith('+') || sanitized.endsWith('-') || sanitized.endsWith('*') || sanitized.endsWith('/')) {
            sanitized = sanitized.substring(0, sanitized.length - 1);
          }
          Parser().parse(sanitized);
        } catch (e) {
          return 'Invalid';
        }
        return null;
      },
    );
  }

  Widget _buildRateField(BGradeSaleItem item) {
    return _buildExpressionField(
      controller: item.rateController,
      label: "Rate",
      icon: Icons.price_change_outlined,
    );
  }

  Widget _buildExpressionField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isOptional = false,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.teal.shade300),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      validator: (val) {
        if (val == null || val.isEmpty) return isOptional ? null : 'Required';
        try {
          String sanitized = val.replaceAll('x', '*').replaceAll('X', '*').trim();
          if (sanitized.endsWith('+') || sanitized.endsWith('-') || sanitized.endsWith('*') || sanitized.endsWith('/')) {
            sanitized = sanitized.substring(0, sanitized.length - 1);
          }
          Parser().parse(sanitized);
        } catch (e) {
          return 'Invalid';
        }
        return null;
      },
    );
  }

  Widget _buildSummarySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Grand Total Value:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text("₹ ${_grandTotal.toStringAsFixed(2)}", 
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
        ],
      ),
    );
  }

  Widget _buildDateButton() {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today, color: Colors.teal),
      label: Text(_selectedDate == null ? "Select Date" : DateFormat('dd-MM-yy').format(_selectedDate!)),
      onPressed: () async {
        final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
        if (date != null) setState(() => _selectedDate = date);
      },
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    );
  }

  Widget _buildTimeButton() {
    return OutlinedButton.icon(
      icon: const Icon(Icons.access_time, color: Colors.teal),
      label: Text(_selectedTime == null ? "Select Time" : _selectedTime!.format(context)),
      onPressed: () async {
        final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
        if (time != null) setState(() => _selectedTime = time);
      },
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    );
  }

  Widget _buildStackedText(List<Map<String, dynamic>> items, String Function(Map<String, dynamic>) mapper) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: items.map((i) => Text(mapper(i), style: const TextStyle(fontSize: 11))).toList(),
    );
  }

  Widget _buildSalesTable() {
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: getLatestBGradeSales(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Padding(padding: const EdgeInsets.all(16.0), child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("No b-grade sales records found.")));
          }
          
          final sales = snapshot.data!;
          Map<String, List<Map<String, dynamic>>> grouped = {};
          for (var row in sales) {
            String key = "${row['clint']}_${row['po_number']}_${row['date']}_${row['time']}";
            grouped.putIfAbsent(key, () => []).add(row);
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.teal.shade100),
              columns: const [
                DataColumn(label: Text('PO Num', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('Client', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('Item', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('Paid', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('Due', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ],
              rows: grouped.entries.map((entry) {
                final items = entry.value;
                final first = items.first;
                double totalSubValue = items.fold(0, (sum, i) => sum + (i['total_value'] as num).toDouble());
                double totalSubPaid = items.fold(0, (sum, i) => sum + (i['amount_paid'] as num? ?? 0).toDouble());
                double totalSubDue = items.fold(0, (sum, i) => sum + (i['amount_due'] as num? ?? 0).toDouble());

                return DataRow(cells: [
                  DataCell(Text(first['po_number']?.toString() ?? '', style: const TextStyle(fontSize: 11))),
                  DataCell(Text(first['payment_status'] ?? 'Unpaid', 
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, 
                      color: first['payment_status'] == 'Paid' ? Colors.green : (first['payment_status'] == 'Partial Paid' ? Colors.orange : Colors.red)))),
                  DataCell(Text(first['clint']?.toString() ?? '', style: const TextStyle(fontSize: 11))),
                  DataCell(_buildStackedText(items, (i) => i['item']?.toString() ?? '')),
                  DataCell(_buildStackedText(items, (i) => '${i['quantity']} ${i['unit']}')),
                  DataCell(Text(totalSubValue.toStringAsFixed(2), style: const TextStyle(fontSize: 11))),
                  DataCell(Text(totalSubPaid.toStringAsFixed(2), style: const TextStyle(fontSize: 11, color: Colors.green))),
                  DataCell(Text(totalSubDue.toStringAsFixed(2), style: const TextStyle(fontSize: 11, color: Colors.red))),
                  DataCell(Text(_formatDate(first['date']), style: const TextStyle(fontSize: 11))),
                ]);
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(String? s) { if (s == null || s.isEmpty) return ''; try { return DateFormat('dd-MM-yy').format(DateTime.parse(s)); } catch (e) { return s; } }
}
