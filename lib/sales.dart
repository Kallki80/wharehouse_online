import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:math_expressions/math_expressions.dart';

const String apiBaseUrl = 'http://13.53.71.103:5000/';
// const String apiBaseUrl = 'http://10.0.2.2:5000';

// API Helper Functions
Future<List<String>> getVendors() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_vendors'));
  if (response.statusCode == 200) {
    return List<String>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load vendors');
  }
}

Future<List<Map<String, dynamic>>> getAllPurchases() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_all_purchases'));
  if (response.statusCode == 200) {
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load purchases');
  }
}

Future<List<Map<String, dynamic>>> getAvailableSOsForSale() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_available_sos_for_sale'));
  if (response.statusCode == 200) {
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load available SOs');
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

Future<void> insertSaleToWaitlist(Map<String, dynamic> data) async {
  final response = await http.post(
    Uri.parse('$apiBaseUrl/insert_sale_to_waitlist'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(data),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to insert sale to waitlist');
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

Future<void> deleteWaitlistedSale(int id) async {
  final response = await http.delete(
    Uri.parse('$apiBaseUrl/delete_waitlisted_sale'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({'id': id}),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to delete waitlisted sale');
  }
}

Future<void> insertSale(Map<String, dynamic> data) async {
  final response = await http.post(
    Uri.parse('$apiBaseUrl/insert_sale'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(data),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to insert sale');
  }
}

Future<List<Map<String, dynamic>>> getWaitlistedSales() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_waitlisted_sales'));
  if (response.statusCode == 200) {
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load waitlisted sales');
  }
}

Future<List<Map<String, dynamic>>> getLatestSales() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_latest_sales'));
  if (response.statusCode == 200) {
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load latest sales');
  }
}

class SaleItem {
  String? selectedItem;
  String? selectedTag;
  List<String> availableTags = [];
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController pcsController = TextEditingController();
  String? poFromTag; // To store the PO number associated with the tag
  String selectedUnit = 'Kg';
  bool isOtherItem = false;
  final TextEditingController otherItemController = TextEditingController();
  bool isReadOnly = false;

  void dispose() {
    qtyController.dispose();
    pcsController.dispose();
    otherItemController.dispose();
  }
}

class Page4 extends StatefulWidget {
  const Page4({super.key});

  @override
  State<Page4> createState() => _SalesPageState();
}

class _SalesPageState extends State<Page4> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedClient;
  bool _isOtherClient = false;
  final TextEditingController _otherClientController = TextEditingController();
  
  String? _selectedSO;
  List<String> _availableSOs = [];
  List<Map<String, dynamic>> _allAvailableSoData = [];

  List<SaleItem> saleItems = [];
  int? _editingWaitlistId;

  List<String> _items = [];
  List<String> _clients = [];
  List<Map<String, dynamic>> _allPurchaseData = [];
  final List<String> _units = ["Kg", "g", "pcs", "L", "ml"];

  bool _isLoading = true;

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

    final dbClients = await getVendors();
    final dbPurchases = await getAllPurchases();
    final dbSOs = await getAvailableSOsForSale();

    // items should come from SOs as requested
    final Set<String> uniqueSoItems = dbSOs
        .where((so) => so['item_name'] != null)
        .map((so) => so['item_name'] as String)
        .toSet();

    if (mounted) {
      setState(() {
        _clients = ["Other", ...dbClients..sort()];
        _allAvailableSoData = dbSOs;
        _items = uniqueSoItems.toList()..sort();
        _allPurchaseData = dbPurchases;
        _availableSOs = dbSOs.map((so) => so['so_number'] as String).toSet().toList();
        _isLoading = false;
      });
    }
  }

  void _updateAvailableSOsAndItems() {
    setState(() {
      // 1. Filter SOs based on selected client
      if (_selectedClient == null || _selectedClient == 'Other') {
        _availableSOs = _allAvailableSoData
            .map((so) => so['so_number'] as String)
            .toSet()
            .toList();
      } else {
        _availableSOs = _allAvailableSoData
            .where((so) => so['client_name'] == _selectedClient)
            .map((so) => so['so_number'] as String)
            .toSet()
            .toList();
      }

      // 2. Reset selected SO if it's no longer valid
      if (_selectedSO != null && !_availableSOs.contains(_selectedSO)) {
        _selectedSO = null;
      }

      // 3. Update items list based on selected SO or client
      if (_selectedSO != null) {
        _items = _allAvailableSoData
            .where((so) => so['so_number'] == _selectedSO && so['item_name'] != null)
            .map((so) => so['item_name'] as String)
            .toSet()
            .toList()
          ..sort();
      } else if (_selectedClient != null && _selectedClient != 'Other') {
        _items = _allAvailableSoData
            .where((so) => so['client_name'] == _selectedClient && so['item_name'] != null)
            .map((so) => so['item_name'] as String)
            .toSet()
            .toList()
          ..sort();
      } else {
        _items = _allAvailableSoData
            .where((so) => so['item_name'] != null)
            .map((so) => so['item_name'] as String)
            .toSet()
            .toList()
          ..sort();
      }

      // 4. Clear invalid selections in current sale items
      for (var item in saleItems) {
        if (item.selectedItem != null && !_items.contains(item.selectedItem)) {
          item.selectedItem = null;
          item.qtyController.clear();
          item.pcsController.clear();
          item.selectedTag = null;
          item.availableTags = [];
          item.poFromTag = null;
        }
      }
    });
  }

  @override
  void dispose() {
    _otherClientController.dispose();
    for (var item in saleItems) {
      item.dispose();
    }
    super.dispose();
  }

  void _addNewItem() {
    final newItem = SaleItem();
    setState(() {
      saleItems.add(newItem);
    });
  }

  void _removeItem(int index) {
    if (saleItems.length > 1) {
      setState(() {
        saleItems[index].dispose();
        saleItems.removeAt(index);
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
      final p = GrammarParser();
      Expression exp = p.parse(sanitized);
      ContextModel cm = ContextModel();
      return exp.evaluate(EvaluationType.REAL, cm);
    } catch (e) {
      return 0.0;
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _otherClientController.clear();
    for (var item in saleItems) {
      item.dispose();
    }
    setState(() {
      saleItems = [];
      _editingWaitlistId = null;
      _selectedClient = null;
      _isOtherClient = false;
      _selectedSO = null;
    });
    _addNewItem();
    _loadInitialData();
  }

  Future<void> _handleAddToWaitlist() async {
    final isFormValid = _formKey.currentState!.validate();
    if (!isFormValid) return;

    String finalClient = _isOtherClient ? _otherClientController.text : (_selectedClient ?? '');

    for (var saleItem in saleItems) {
      Map<String, dynamic> dataToSave = {
        'item': saleItem.selectedItem,
        'clint': finalClient,
        'po_number': _selectedSO ?? saleItem.poFromTag ?? '',
        'quantity': _evaluateExpression(saleItem.qtyController.text),
        'unit': saleItem.selectedUnit,
        'pcs': saleItem.pcsController.text.isNotEmpty ? _evaluateExpression(saleItem.pcsController.text) : null,
        'item_tag': saleItem.selectedTag,
      };
      await insertSaleToWaitlist(dataToSave);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sale added to Waitlist!"), backgroundColor: Colors.blueAccent));
    }
    _resetForm();
  }

  void _handleSubmit() async {
    final isFormValid = _formKey.currentState!.validate();

    if (!isFormValid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all required fields"), backgroundColor: Colors.redAccent));
      return;
    }

    final String formattedTime = DateFormat('hh:mm a').format(DateTime.now());
    String finalClient = _isOtherClient ? _otherClientController.text : (_selectedClient ?? '');
    
    if (_isOtherClient && finalClient.isNotEmpty) {
      await insertVendor(finalClient);
    }

    for (var saleItem in saleItems) {
      Map<String, dynamic> dataToSave = {
        'item': saleItem.selectedItem,
        'clint': finalClient,
        'po_number': _selectedSO ?? saleItem.poFromTag ?? '',
        'quantity': _evaluateExpression(saleItem.qtyController.text),
        'unit': saleItem.selectedUnit,
        'pcs': saleItem.pcsController.text.isNotEmpty ? _evaluateExpression(saleItem.pcsController.text) : null,
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'time': formattedTime,
        'item_tag': saleItem.selectedTag,
        'payment_status': 'Unpaid',
        'rate': 0.0,
        'total_value': 0.0,
      };

      await insertSale(dataToSave);
    }

    if (_editingWaitlistId != null) {
      await deleteWaitlistedSale(_editingWaitlistId!);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sale Saved Successfully!"), backgroundColor: Colors.green));
    }

    _resetForm();
  }

  void _onItemChanged(SaleItem saleItem, String? val) {
    setState(() {
      saleItem.selectedItem = val;
      saleItem.selectedTag = null;
      saleItem.poFromTag = null;
      
      if (val != null) {
        // If SO is selected, we can auto-fill the quantity
        if (_selectedSO != null) {
          final soMatch = _allAvailableSoData.firstWhere(
            (so) => so['so_number'] == _selectedSO && so['item_name'] == val,
            orElse: () => {},
          );
          if (soMatch.isNotEmpty) {
            saleItem.qtyController.text = soMatch['quantity_kg']?.toString() ?? '';
            saleItem.pcsController.text = soMatch['quantity_pcs']?.toString() ?? '';
          }
        }

        final itemPurchases = _allPurchaseData.where((p) => p['item'] == val).toList();
        saleItem.availableTags = itemPurchases
            .map((p) => p['item_tag'] as String?)
            .where((tag) => tag != null)
            .cast<String>()
            .toSet()
            .toList();
            
        if (saleItem.availableTags.length == 1) {
          _onTagChanged(saleItem, saleItem.availableTags.first);
        }
      } else {
        saleItem.availableTags = [];
      }
    });
  }

  void _onTagChanged(SaleItem saleItem, String? tag) {
    setState(() {
      saleItem.selectedTag = tag;
      if (tag != null && saleItem.selectedItem != null) {
        final match = _allPurchaseData.firstWhere(
          (p) => p['item'] == saleItem.selectedItem && p['item_tag'] == tag,
          orElse: () => {},
        );
        if (match.isNotEmpty) {
          saleItem.poFromTag = match['po_number'] ?? '';
        }
      }
    });
  }

  void _editWaitlistedItem(Map<String, dynamic> row) async {
    setState(() => _isLoading = true);
    List<String> tags = await getPurchasedTagsForItem(row['item']);

    setState(() {
      _editingWaitlistId = row['id'];
      String rowClient = row['clint'] ?? '';
      if (_clients.contains(rowClient)) {
        _selectedClient = rowClient;
        _isOtherClient = false;
      } else {
        _selectedClient = 'Other';
        _isOtherClient = true;
        _otherClientController.text = rowClient;
      }

      saleItems.clear();
      final newItem = SaleItem();
      newItem.selectedItem = row['item'];
      newItem.availableTags = tags;
      newItem.selectedTag = row['item_tag'];
      newItem.qtyController.text = row['quantity'].toString();
      newItem.selectedUnit = row['unit'] ?? 'Kg';
      newItem.pcsController.text = row['pcs']?.toString() ?? '';
      newItem.poFromTag = row['po_number'] ?? '';
      saleItems.add(newItem);
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Sales Entry", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.green.shade600, Colors.lightGreen.shade500], begin: Alignment.topLeft, end: Alignment.bottomRight),
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
                            const SizedBox(height: 18),
                            _buildSOSection(),
                            const SizedBox(height: 18),
                            const Divider(thickness: 1),
                            const SizedBox(height: 12),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: saleItems.length,
                              itemBuilder: (context, index) => _buildItemEntry(index),
                            ),
                            const SizedBox(height: 12),
                            if (_editingWaitlistId == null)
                              TextButton.icon(
                                icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                                label: const Text("Add More Items", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                onPressed: _addNewItem,
                              ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: Icon(_editingWaitlistId != null ? Icons.upgrade : Icons.send_outlined, color: Colors.white),
                                    label: Text(_editingWaitlistId != null ? "Update Sale" : "Submit Sale"),
                                    onPressed: _handleSubmit,
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                      foregroundColor: Colors.white,
                                      backgroundColor: Colors.green.shade700,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      elevation: 5,
                                    ),
                                  ),
                                ),
                                if (_editingWaitlistId == null)
                                  const SizedBox(width: 12),
                                if (_editingWaitlistId == null)
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.playlist_add, color: Colors.white),
                                      label: const Text("To Waitlist"),
                                      onPressed: _handleAddToWaitlist,
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                        foregroundColor: Colors.white,
                                        backgroundColor: Colors.blue.shade600,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        elevation: 5,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildWaitlistTable(),
                  const SizedBox(height: 24),
                  Text("Recent Sales", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green.shade800), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
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
              prefixIcon: Icon(Icons.person_outline, color: Colors.green.shade300),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50),
          isExpanded: true,
          initialValue: _selectedClient,
          items: _clients.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (val) {
            setState(() {
              _selectedClient = val;
              _isOtherClient = (val == 'Other');
            });
            _updateAvailableSOsAndItems();
          },
          validator: (val) => val == null ? "Please Select Client" : null,
        ),
        if (_isOtherClient) ...[
          const SizedBox(height: 18),
          _buildOtherTextField(
            controller: _otherClientController,
            label: "Enter New Client Name",
            validator: (val) => (_isOtherClient && (val == null || val.isEmpty)) ? "Please enter client name" : null,
          ),
        ],
      ],
    );
  }

  Widget _buildSOSection() {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
          labelText: "Select SO Number (Optional)",
          prefixIcon: Icon(Icons.receipt_long_outlined, color: Colors.green.shade300),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey.shade50),
      isExpanded: true,
      initialValue: _selectedSO,
      items: [
        const DropdownMenuItem(value: null, child: Text("None")),
        ..._availableSOs.map((so) => DropdownMenuItem(value: so, child: Text(so, overflow: TextOverflow.ellipsis)))
      ],
      onChanged: (val) {
        setState(() {
          _selectedSO = val;
        });
        _updateAvailableSOsAndItems();
      },
    );
  }

  Widget _buildItemEntry(int index) {
    final saleItem = saleItems[index];
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
              Text("Item #${index + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              if (saleItems.length > 1 && _editingWaitlistId == null)
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
              prefixIcon: Icon(Icons.inventory_2_outlined, color: Colors.green.shade300),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            isExpanded: true,
            initialValue: saleItem.selectedItem,
            items: _items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (val) => _onItemChanged(saleItem, val),
            validator: (val) => val == null ? "Required" : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: "Select Item Tag",
              prefixIcon: Icon(Icons.tag, color: Colors.green.shade300),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            isExpanded: true,
            initialValue: saleItem.selectedTag,
            items: saleItem.availableTags.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (val) => _onTagChanged(saleItem, val),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: saleItem.qtyController,
                  decoration: InputDecoration(
                    labelText: "Qty",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  keyboardType: TextInputType.text,
                  validator: (val) => (val == null || val.isEmpty) ? "Required" : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  initialValue: saleItem.selectedUnit,
                  items: _units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                  onChanged: (val) => setState(() => saleItem.selectedUnit = val!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: saleItem.pcsController,
            decoration: InputDecoration(
              labelText: "Pcs",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            keyboardType: TextInputType.text,
          ),
        ],
      ),
    );
  }

  Widget _buildOtherTextField({required TextEditingController controller, required String label, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: validator,
    );
  }

  Widget _buildWaitlistTable() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: getWaitlistedSales(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            Text("Waitlisted Sales", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
            const SizedBox(height: 8),
            Card(
              elevation: 4,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text("Item")),
                    DataColumn(label: Text("Client")),
                    DataColumn(label: Text("Qty")),
                    DataColumn(label: Text("Actions")),
                  ],
                  rows: snapshot.data!.map((row) => DataRow(cells: [
                    DataCell(Text(row['item'])),
                    DataCell(Text(row['clint'])),
                    DataCell(Text("${row['quantity']} ${row['unit']}")),
                    DataCell(Row(
                      children: [
                        IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _editWaitlistedItem(row)),
                        IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => deleteWaitlistedSale(row['id']).then((_) => setState(() {}))),
                      ],
                    )),
                  ])).toList(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSalesTable() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: getLatestSales(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("No recent sales"));
        return Card(
          elevation: 4,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text("Item")),
                DataColumn(label: Text("Client")),
                DataColumn(label: Text("Qty")),
                DataColumn(label: Text("Date")),
              ],
              rows: snapshot.data!.map((row) => DataRow(cells: [
                DataCell(Text(row['item'] ?? '')),
                DataCell(Text(row['clint'] ?? '')),
                DataCell(Text("${row['quantity'] ?? ''} ${row['unit'] ?? ''}")),
                DataCell(Text(row['date'] ?? '')),
              ])).toList(),
            ),
          ),
        );
      },
    );
  }
}
