import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class PurchaseItem {
  String? selectedPoNumber;
  String? selectedItem;
  String? selectedVendor;
  String selectedUnitReceive = 'Kg';
  String selectedUnitAccept = 'Kg';
  String selectedUnitReject = 'Kg';

  final TextEditingController qtyReceiveController = TextEditingController();
  final TextEditingController qtyAcceptController = TextEditingController();
  final TextEditingController qtyRejectController = TextEditingController();
  final TextEditingController poNumberController = TextEditingController(); // For 'Other' PO
  final TextEditingController pcsReceiveController = TextEditingController();
  final TextEditingController pcsAcceptController = TextEditingController();
  final TextEditingController pcsRejectController = TextEditingController();
  final TextEditingController rejectionReasonController = TextEditingController();
  final TextEditingController itemTagController = TextEditingController();

  bool isOtherPo = false;
  bool isOtherItem = false;
  final TextEditingController otherItemController = TextEditingController();
  bool isOtherVendor = false;
  final TextEditingController otherVendorController = TextEditingController();

  void dispose() {
    qtyReceiveController.dispose();
    qtyAcceptController.dispose();
    qtyRejectController.dispose();
    poNumberController.dispose();
    pcsReceiveController.dispose();
    pcsAcceptController.dispose();
    pcsRejectController.dispose();
    rejectionReasonController.dispose();
    otherItemController.dispose();
    otherVendorController.dispose();
    itemTagController.dispose();
  }
}

class Page1 extends StatefulWidget {
  const Page1({super.key});

  @override
  State<Page1> createState() => _Page1State();
}

class _Page1State extends State<Page1> {
  final _formKey = GlobalKey<FormState>();
  // final String baseUrl = 'http://13.53.71.103:5000/';
  // final String baseUrl = 'http://10.0.2.2:5000/';
  final String baseUrl = 'http://127.0.0.1:5000/';

  DateTime? ctrlDate;
  List<PurchaseItem> purchaseItems = [];

  List<Map<String, dynamic>> _availablePOs = [];
  List<String> _items = [];
  List<String> _vendors = [];
  final List<String> _units = ["Kg", "g", "pcs", "L", "ml"];
  Future<List<Map<String, dynamic>>>? _latestPurchases;
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

    try {
      final response = await http.get(Uri.parse('$baseUrl/get_available_pos_for_purchase'));
      if (response.statusCode == 200) {
        final List<Map<String, dynamic>> dbPOs = List<Map<String, dynamic>>.from(json.decode(response.body));

        // Filter POs: Only those with Expected Date >= Today
        final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final List<Map<String, dynamic>> filteredPOs = dbPOs.where((po) {
          String? expDate = po['expected_date'];
          if (expDate == null) return false;
          return expDate.compareTo(todayStr) >= 0;
        }).toList();

        final Set<String> poItems = {};
        final Set<String> poVendors = {};

        for (var po in filteredPOs) {
          if (po['item_name'] != null) poItems.add(po['item_name']);
          if (po['vendor_name'] != null) poVendors.add(po['vendor_name']);
        }

        final purchasesResponse = await http.get(Uri.parse('$baseUrl/get_latest_purchases'));
        List<Map<String, dynamic>> latestPurchases = [];
        if (purchasesResponse.statusCode == 200) {
          latestPurchases = List<Map<String, dynamic>>.from(json.decode(purchasesResponse.body));
        }

        if (mounted) {
          setState(() {
            _items = ["Other", ...poItems.toList()..sort()];
            _vendors = ["Other", ...poVendors.toList()..sort()];
            _availablePOs = filteredPOs;
            _latestPurchases = Future.value(latestPurchases);
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

  @override
  void dispose() {
    for (var item in purchaseItems) {
      item.dispose();
    }
    super.dispose();
  }

  void _addNewItem() {
    setState(() {
      purchaseItems.add(PurchaseItem());
    });
  }

  void _removeItem(int index) {
    if (purchaseItems.length > 1) {
      purchaseItems[index].dispose();
      setState(() {
        purchaseItems.removeAt(index);
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

  Future<void> _generateTag(PurchaseItem item) async {
    if (item.selectedVendor == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select Vendor first")));
      return;
    }

    DateTime? dateToUse;
    if (item.isOtherPo) {
      dateToUse = ctrlDate ?? DateTime.now();
    } else if (item.selectedPoNumber != null) {
      final poNumOnly = item.selectedPoNumber!.split(' (').first;
      final poData = _availablePOs.firstWhere(
        (p) => p['po_number'] == poNumOnly && p['item_name'] == item.selectedItem,
        orElse: () => _availablePOs.firstWhere((p) => p['po_number'] == poNumOnly, orElse: () => {})
      );
      if (poData.isNotEmpty && poData['expected_date'] != null) {
        dateToUse = DateTime.tryParse(poData['expected_date']);
      }
    }

    if (dateToUse == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select PO or CTRL Date")));
      return;
    }

    String vendorName = item.isOtherVendor ? item.otherVendorController.text : item.selectedVendor!;
    if (vendorName.length < 2) vendorName = vendorName.padRight(2, 'X');
    
    String vendorPrefix = vendorName.substring(0, 2).toUpperCase();
    String dayPart = DateFormat('dd').format(dateToUse);
    
    try {
      final response = await http.get(Uri.parse('$baseUrl/get_next_item_tag_sequence?vendor_prefix=$vendorPrefix&day_part=$dayPart'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        int sequence = data['sequence'];
        String paddedSequence = sequence.toString().padLeft(4, '0');
        setState(() {
          item.itemTagController.text = "$vendorPrefix-$dayPart-$paddedSequence";
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to generate tag")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error generating tag: $e")));
    }
  }

  Future<void> _handleSubmit() async {
    final isFormValid = _formKey.currentState!.validate();
    final isDateSelected = ctrlDate != null;

    if (!isFormValid || !isDateSelected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Please fill all required fields and select CTRL date."),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    final String formattedTime = DateFormat('hh:mm a').format(DateTime.now());

    for (var purchaseItem in purchaseItems) {
      String finalPoNumber = purchaseItem.isOtherPo
          ? purchaseItem.poNumberController.text
          : purchaseItem.selectedPoNumber?.split(' (').first ?? '';

      String finalItem = purchaseItem.selectedItem!;
      if (purchaseItem.isOtherItem) {
        finalItem = purchaseItem.otherItemController.text;
        await http.post(Uri.parse('$baseUrl/insert_item'), headers: {'Content-Type': 'application/json'}, body: json.encode({'name': finalItem}));
      }

      String finalVendor = purchaseItem.selectedVendor!;
      if (purchaseItem.isOtherVendor) {
        finalVendor = purchaseItem.otherVendorController.text;
        await http.post(Uri.parse('$baseUrl/insert_purchase_vendor'), headers: {'Content-Type': 'application/json'}, body: json.encode({'name': finalVendor}));
      }

      final double? pcsReceive = purchaseItem.pcsReceiveController.text.isNotEmpty ? _evaluateExpression(purchaseItem.pcsReceiveController.text) : null;
      final double? pcsAccept = purchaseItem.pcsAcceptController.text.isNotEmpty ? _evaluateExpression(purchaseItem.qtyAcceptController.text) : null;
      final double? pcsReject = purchaseItem.pcsRejectController.text.isNotEmpty ? _evaluateExpression(purchaseItem.qtyRejectController.text) : null;

      Map<String, dynamic> dataToSave = {
        'item': finalItem,
        'vendor': finalVendor,
        'po_number': finalPoNumber,
        'qty_receive': _evaluateExpression(purchaseItem.qtyReceiveController.text),
        'unit_receive': purchaseItem.selectedUnitReceive,
        'pcs_receive': pcsReceive,
        'qty_accept': purchaseItem.qtyAcceptController.text.isNotEmpty ? _evaluateExpression(purchaseItem.qtyAcceptController.text) : null,
        'unit_accept': purchaseItem.selectedUnitAccept,
        'pcs_accept': pcsAccept,
        'qty_reject': purchaseItem.qtyRejectController.text.isNotEmpty ? _evaluateExpression(purchaseItem.qtyRejectController.text) : null,
        'unit_reject': purchaseItem.selectedUnitReject,
        'pcs_reject': pcsReject,
        'reason_for_rejection': purchaseItem.rejectionReasonController.text,
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'time': formattedTime,
        'ctrl_date': DateFormat('yyyy-MM-dd').format(ctrlDate!),
        'item_tag': purchaseItem.itemTagController.text,
      };

      await http.post(Uri.parse('$baseUrl/insert_purchase'), headers: {'Content-Type': 'application/json'}, body: json.encode(dataToSave));
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Purchase(s) Saved Successfully!"),
        backgroundColor: Colors.green,
      ));
    }

    _formKey.currentState!.reset();
    for (var item in purchaseItems) {
      item.dispose();
    }
    setState(() {
      purchaseItems = [];
      ctrlDate = null;
    });
    _addNewItem();
    _loadInitialData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Purchase Entry", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Colors.indigo, Colors.blue], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
        elevation: 4,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
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
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: purchaseItems.length,
                              itemBuilder: (context, index) {
                                return _buildItemEntry(index);
                              },
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              icon: const Icon(Icons.add_circle_outline, color: Colors.indigo),
                              label: const Text("Add More Items", style: TextStyle(color: Colors.indigo)),
                              onPressed: _addNewItem,
                            ),
                            const SizedBox(height: 24),
                            _buildCtrlDateButton(),
                            const SizedBox(height: 30),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white),
                              label: const Text("Submit Purchase"),
                              onPressed: _handleSubmit,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.indigo,
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
                  Text("Recent Purchases", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo.shade800), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  _buildPurchasesTable(),
                ],
              ),
            ),
    );
  }

  Widget _buildItemEntry(int index) {
    final item = purchaseItems[index];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Item #${index + 1}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
              if (purchaseItems.length > 1)
                IconButton(
                  icon: Icon(Icons.remove_circle_outline, color: Colors.red.shade400),
                  onPressed: () => _removeItem(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const Divider(height: 20),

          _buildDropdown(
            label: "Select Item",
            icon: Icons.inventory_2_outlined,
            value: item.selectedItem,
            items: _items,
            onChanged: (val) => setState(() {
              item.selectedItem = val;
              item.isOtherItem = (val == "Other");
              if (val != "Other") {
                item.selectedVendor = null;
                item.selectedPoNumber = null;
              }
            }),
          ),
          if (item.isOtherItem)
            _buildOtherTextField(
              controller: item.otherItemController,
              label: "Enter New Item Name",
              validator: (val) => (item.isOtherItem && (val == null || val.isEmpty)) ? "Please enter item name" : null,
            ),
          const SizedBox(height: 18),

          _buildVendorDropdown(item),
          const SizedBox(height: 18),

          _buildPoDropdown(item),
          const SizedBox(height: 18),

          // Generate Item Tag Section
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: item.itemTagController,
                  decoration: InputDecoration(
                    labelText: 'Item Tag',
                    prefixIcon: Icon(Icons.tag, color: Colors.orange.shade700),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.orange.shade50,
                  ),
                  validator: (val) => (val == null || val.isEmpty) ? "Generate tag" : null,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: () => _generateTag(item),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Generate"),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          _buildQuantityField(controller: item.qtyReceiveController, label: "Quantity Received", icon: Icons.move_to_inbox_outlined, selectedUnit: item.selectedUnitReceive, onUnitChanged: (val) => setState(() => item.selectedUnitReceive = val!)),
          const SizedBox(height: 18),
          _buildExpressionField(controller: item.pcsReceiveController, label: "Pcs (Received)", icon: Icons.numbers, isOptional: true),
          const SizedBox(height: 18),
          _buildQuantityField(controller: item.qtyAcceptController, label: "Quantity Accepted (Optional)", icon: Icons.check_circle_outline, selectedUnit: item.selectedUnitAccept, onUnitChanged: (val) => setState(() => item.selectedUnitAccept = val!), isOptional: true),
          const SizedBox(height: 18),
          _buildExpressionField(controller: item.pcsAcceptController, label: "Pcs (Accepted)", icon: Icons.numbers, isOptional: true),
          const SizedBox(height: 18),
          _buildQuantityField(controller: item.qtyRejectController, label: "Quantity Rejected (Optional)", icon: Icons.cancel_outlined, selectedUnit: item.selectedUnitReject, onUnitChanged: (val) => setState(() => item.selectedUnitReject = val!), isOptional: true),
          const SizedBox(height: 18),
          _buildExpressionField(controller: item.pcsRejectController, label: "Pcs (Rejected)", icon: Icons.numbers, isOptional: true),
          const SizedBox(height: 18),
          TextFormField(
            controller: item.rejectionReasonController,
            decoration: InputDecoration(
              labelText: 'Reason for Rejection (Optional)',
              prefixIcon: Icon(Icons.comment_outlined, color: Colors.red.shade300),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoDropdown(PurchaseItem item) {
    List<Map<String, dynamic>> filteredPOs = _availablePOs;
    if (item.selectedItem != null && item.selectedItem != 'Other') {
      filteredPOs = filteredPOs.where((po) => po['item_name'] == item.selectedItem).toList();
    }
    if (item.selectedVendor != null && item.selectedVendor != 'Other') {
      filteredPOs = filteredPOs.where((po) => po['vendor_name'] == item.selectedVendor).toList();
    }

    Set<String> suggestionSet = filteredPOs.map((po) {
      final date = DateFormat('dd-MM-yy').format(DateTime.parse(po['expected_date']));
      return "${po['po_number']} ($date)";
    }).toSet();

    List<String> finalSuggestions = ['Other', ...suggestionSet.toList()..sort()];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          decoration: InputDecoration(
            labelText: "Select PO Number",
            prefixIcon: Icon(Icons.receipt_long_outlined, color: Colors.indigo.shade300),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          initialValue: finalSuggestions.contains(item.selectedPoNumber) ? item.selectedPoNumber : null,
          items: finalSuggestions.map((po) => DropdownMenuItem(value: po, child: Text(po))).toList(),
          onChanged: (val) {
            setState(() {
              item.selectedPoNumber = val;
              item.isOtherPo = (val == 'Other');
              if (val != 'Other' && val != null) {
                final poNumber = val.split(' (').first;
                final poDataList = _availablePOs.where((po) => po['po_number'] == poNumber).toList();
                if (poDataList.isNotEmpty) {
                  var match = poDataList.firstWhere(
                    (po) => item.selectedItem == null || po['item_name'] == item.selectedItem,
                    orElse: () => poDataList.first
                  );
                  item.selectedItem = match['item_name'];
                  item.isOtherItem = false;
                  item.selectedVendor = match['vendor_name'];
                  item.isOtherVendor = false;
                }
              }
            });
          },
          isExpanded: true,
        ),
        if (item.isOtherPo)
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: TextFormField(
              controller: item.poNumberController,
              decoration: InputDecoration(
                labelText: 'Enter Other PO Number',
                prefixIcon: Icon(Icons.edit_note_outlined, color: Colors.teal.shade300),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVendorDropdown(PurchaseItem item) {
    List<String> filteredVendors = _vendors;
    if (item.selectedItem != null && item.selectedItem != 'Other') {
      final vendorsForSelectedItem = _availablePOs
          .where((po) => po['item_name'] == item.selectedItem)
          .map((po) => po['vendor_name'] as String)
          .toSet();
      filteredVendors = ["Other", ...vendorsForSelectedItem.toList()..sort()];
    }

    return Column(
      children: [
        DropdownButtonFormField<String>(
          decoration: InputDecoration(
              labelText: "Select Vendor",
              prefixIcon: Icon(Icons.store_mall_directory_outlined, color: Colors.indigo.shade300),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50),
          initialValue: filteredVendors.contains(item.selectedVendor) ? item.selectedVendor : null,
          items: filteredVendors.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (val) => setState(() {
            item.selectedVendor = val;
            item.isOtherVendor = (val == "Other");
            item.selectedPoNumber = null;
          }),
          validator: (val) => val == null ? "Please Select Vendor" : null,
          isExpanded: true,
        ),
        if (item.isOtherVendor)
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: TextFormField(
              controller: item.otherVendorController,
              decoration: InputDecoration(
                  labelText: 'Enter New Vendor Name',
                  prefixIcon: Icon(Icons.edit_note_outlined, color: Colors.teal.shade300),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey.shade50),
              validator: (val) => (item.isOtherVendor && (val == null || val.isEmpty)) ? 'Please enter a vendor name' : null,
            ),
          ),
      ],
    );
  }

  Widget _buildDropdown({required String label, required IconData icon, String? value, required List<String> items, required Function(String?) onChanged}) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.indigo.shade300),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey.shade50),
      initialValue: value,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
      validator: (val) => val == null ? "Please $label" : null,
      isExpanded: true,
    );
  }

  Widget _buildOtherTextField({required TextEditingController controller, required String label, required String? Function(String?) validator}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(Icons.edit_note_outlined, color: Colors.teal.shade300),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50),
        validator: validator,
      ),
    );
  }

  Widget _buildQuantityField({required TextEditingController controller, required String label, required IconData icon, required String selectedUnit, required Function(String?) onUnitChanged, bool isOptional = false}) {
    return _buildExpressionField(
      controller: controller,
      label: label,
      icon: icon,
      isOptional: isOptional,
      suffixIcon: DropdownButtonHideUnderline(
          child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: DropdownButton<String>(
          value: selectedUnit,
          items: _units.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
          onChanged: onUnitChanged,
        ),
      )),
    );
  }

  Widget _buildExpressionField({required TextEditingController controller, required String label, required IconData icon, Widget? suffixIcon, bool isOptional = false}) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.indigo.shade300),
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
          String sanitizedExpression = val.replaceAll('x', '*').replaceAll('X', '*').trim();
          if (sanitizedExpression.endsWith('+') || sanitizedExpression.endsWith('-') || sanitizedExpression.endsWith('*') || sanitizedExpression.endsWith('/')) {
            sanitizedExpression = sanitizedExpression.substring(0, sanitizedExpression.length - 1);
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

  Widget _buildCtrlDateButton() {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_month_outlined, color: Colors.teal),
      onPressed: () async {
        DateTime? pickedDate = await showDatePicker(context: context, initialDate: ctrlDate ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
        if (pickedDate != null) setState(() => ctrlDate = pickedDate);
      },
      label: Text(ctrlDate == null ? 'Select CTRL Date' : 'CTRL: ${DateFormat('dd-MM-yy').format(ctrlDate!)}', style: TextStyle(color: ctrlDate == null ? Colors.black54 : Colors.teal.shade700)),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: BorderSide(color: ctrlDate == null ? Colors.grey.shade400 : Colors.teal), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    );
  }

  Widget _buildPurchasesTable() {
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _latestPurchases,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Padding(padding: const EdgeInsets.all(16.0), child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("No purchase records found.")));
          }
          final purchases = snapshot.data!;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.indigo.shade100),
              columns: const [
                DataColumn(label: Text('Tag', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Item', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Vendor', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('PO Num', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Receive', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Pcs (Rec)', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Accept', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Pcs (Acc)', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Reject', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Pcs (Rej)', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Reason', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Time', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('CTRL Date', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: purchases.map((row) {
                return DataRow(cells: [
                  DataCell(Text(row['item_tag']?.toString() ?? '')),
                  DataCell(Text(row['item']?.toString() ?? '')),
                  DataCell(Text(row['vendor']?.toString() ?? '')),
                  DataCell(Text(row['po_number']?.toString() ?? '')),
                  DataCell(Text('${row['qty_receive']} ${row['unit_receive']}')),
                  DataCell(Text(row['pcs_receive']?.toString() ?? '')),
                  DataCell(Text('${row['qty_accept']} ${row['unit_accept']}')),
                  DataCell(Text(row['pcs_accept']?.toString() ?? '')),
                  DataCell(Text('${row['qty_reject']} ${row['unit_reject']}')),
                  DataCell(Text(row['pcs_reject']?.toString() ?? '')),
                  DataCell(Text(row['reason_for_rejection']?.toString() ?? '')),
                  DataCell(Text(DateFormat('dd-MM-yy').format(DateTime.parse(row['date'])))),
                  DataCell(Text(row['time']?.toString() ?? '')),
                  DataCell(Text(DateFormat('dd-MM-yy').format(DateTime.parse(row['ctrl_date'])))),
                ]);
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}
