import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'api_config.dart';
import 'po_line_selector.dart';

// Get last rate for an item from packaging_materials
Future<double?> getLastPackagingRateForItem(String itemName) async {
  final queryParams = {'item_name': itemName, 'table': 'packaging_materials'};
  final uri = Uri.parse('$baseUrl/get_last_rate_for_item').replace(queryParameters: queryParams);
  final response = await http.get(uri);
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['rate'] != null ? (data['rate'] as num).toDouble() : null;
  }
  return null;
}

class PackagingItem {
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
  final TextEditingController rateController = TextEditingController(); // Rate for this item

  bool isOtherPo = false;
  bool isOtherItem = false;
  final TextEditingController otherItemController = TextEditingController();
  bool isOtherVendor = false;
  final TextEditingController otherVendorController = TextEditingController();

  double itemTotal = 0.0; // Total for this item (rate × qty_accept)

  // PO line selected for this item (rate, unit, vendor, PO number come from here)
  Map<String, dynamic>? poLine;

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
    rateController.dispose();
  }
}

class PackagingMaterialPage extends StatefulWidget {
  const PackagingMaterialPage({super.key});

  @override
  State<PackagingMaterialPage> createState() => _PackagingMaterialPageState();
}

class _PackagingMaterialPageState extends State<PackagingMaterialPage> {
  final _formKey = GlobalKey<FormState>();

  DateTime? ctrlDate;
  List<PackagingItem> packagingItems = [];
  Map<String, dynamic>? _paymentDetails;

  // Payment controllers
  final TextEditingController _amountPaidController = TextEditingController();
  final TextEditingController _amountDueController = TextEditingController();
  String? _selectedPaymentStatus = 'Unpaid';
  String? _selectedModeOfPayment;

  // Packaging PO lines for the selected CTRL date (from /get_pos_for_entry)
  List<Map<String, dynamic>> _poLines = [];
  bool _showOtherDates = false;
  bool _loadingPOs = false;
  int _poGeneration = 0;
  final List<String> _units = ["Kg", "g", "pcs", "L", "ml"];
  Future<List<Map<String, dynamic>>>? _latestPackagingMaterials;
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
      final packagingResponse = await http.get(Uri.parse('$baseUrl/get_latest_packaging_materials'));
      List<Map<String, dynamic>> latestPackagingMaterials = [];
      if (packagingResponse.statusCode == 200) {
        latestPackagingMaterials = List<Map<String, dynamic>>.from(json.decode(packagingResponse.body));
      }
      if (mounted) {
        setState(() {
          _latestPackagingMaterials = Future.value(latestPackagingMaterials);
          _isLoading = false;
        });
      }
      if (ctrlDate != null) await _loadPoLines();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error loading data: $e")));
      }
    }
  }

  /// Packaging PO lines expected on the CTRL date (plus other dates when switched on).
  /// Only items marked as packaging in Admin > Item Settings appear here.
  Future<void> _loadPoLines() async {
    if (ctrlDate == null) return;
    setState(() => _loadingPOs = true);
    try {
      final uri = Uri.parse('$baseUrl/get_pos_for_entry').replace(queryParameters: {
        'ctrl_date': DateFormat('yyyy-MM-dd').format(ctrlDate!),
        'kind': 'packaging',
        'include_other_dates': _showOtherDates ? '1' : '0',
      });
      final res = await http.get(uri);
      if (res.statusCode != 200) throw Exception(res.body);
      final lines = List<Map<String, dynamic>>.from(json.decode(res.body)['data'] as List);
      if (!mounted) return;
      setState(() {
        _poLines = lines;
        _poGeneration++;
        for (final item in packagingItems) {
          _onLineSelected(item, null, rebuild: false);
        }
        _loadingPOs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingPOs = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not load POs: $e")));
    }
  }

  void _onLineSelected(PackagingItem item, Map<String, dynamic>? line, {bool rebuild = true}) {
    void apply() {
      item.poLine = line;
      item.selectedVendor = line?['vendor_name']?.toString();
      item.selectedPoNumber = line?['po_number']?.toString();
      item.selectedItem = line?['item_name']?.toString();
      item.rateController.text = line == null ? '' : '${line['rate']}';
      final units = unitsForPoUnit(line?['unit']?.toString());
      item.selectedUnitReceive = units.first;
      item.selectedUnitAccept = units.first;
      item.selectedUnitReject = units.first;
    }
    if (rebuild) {
      setState(apply);
      _calculateAmountDue();
    } else {
      apply();
    }
  }

  List<String> _unitsFor(PackagingItem item) => unitsForPoUnit(item.poLine?['unit']?.toString());

  /// accepted qty (or received qty when accepted is empty) in PO unit x PO rate
  double _itemAmount(PackagingItem item) {
    final rate = double.tryParse(item.rateController.text) ?? 0.0;
    final poUnit = item.poLine?['unit']?.toString();
    final hasAccepted = item.qtyAcceptController.text.trim().isNotEmpty;
    final qty = hasAccepted
        ? qtyInPoUnit(_evaluateExpression(item.qtyAcceptController.text), item.selectedUnitAccept, poUnit)
        : qtyInPoUnit(_evaluateExpression(item.qtyReceiveController.text), item.selectedUnitReceive, poUnit);
    return (qty ?? 0.0) * rate;
  }

  @override
  void dispose() {
    for (var item in packagingItems) {
      item.dispose();
    }
    super.dispose();
  }

  void _addNewItem() {
    setState(() {
      packagingItems.add(PackagingItem());
    });
  }

  void _removeItem(int index) {
    if (packagingItems.length > 1) {
      packagingItems[index].dispose();
      setState(() {
        packagingItems.removeAt(index);
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

  void _calculateAmountDue() {
    double totalValue = 0.0;
    for (var packagingItem in packagingItems) {
      packagingItem.itemTotal = _itemAmount(packagingItem);
      totalValue += packagingItem.itemTotal;
    }
    double paid = _amountPaidController.text.isNotEmpty ? double.tryParse(_amountPaidController.text) ?? 0.0 : 0.0;
    double due = totalValue - paid;
    if (due < 0) due = 0;
    setState(() {
      _amountDueController.text = due.toStringAsFixed(2);
    });
  }

  void _calculateItemTotal(PackagingItem packagingItem) {
    setState(() {
      packagingItem.itemTotal = _itemAmount(packagingItem);
    });
  }

  Future<void> _generateTag(PackagingItem item) async {
    // 1. Vendor check
    if (item.selectedVendor == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select Vendor first")));
      return;
    }

    // 2. Item check
    if (item.selectedItem == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select Item first")));
      return;
    }

    // 3. Date logic: PO expected date, otherwise CTRL date
    DateTime? dateToUse = DateTime.tryParse(item.poLine?['expected_date']?.toString() ?? '') ?? ctrlDate;

    if (dateToUse == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select CTRL date and PO first")));
      return;
    }

    // --- Tag Generation Logic ---

    // Vendor Name से पहले 3 अक्षर लेना
    String vName = item.selectedVendor!;
    if (vName.length < 3) vName = vName.padRight(3, 'X');
    String vendorPrefix = vName.substring(0, 3).toUpperCase();

    // Item Name से पहले 3 अक्षर लेना
    String iName = item.selectedItem!;
    if (iName.length < 3) iName = iName.padRight(3, 'X');
    String itemPrefix = iName.substring(0, 3).toUpperCase();

    // Date part: ddMMyy
    String dayPart = DateFormat('ddMMyy').format(dateToUse);
    
    try {
      // API call: combined prefix (Vendor + Item) ताकि sequence unique रहे
      String combinedPrefix = "$vendorPrefix$itemPrefix";
      
      final response = await http.get(Uri.parse('$baseUrl/get_next_packaging_tag_sequence?vendor_prefix=$combinedPrefix&day_part=$dayPart'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        int sequence = data['sequence'];
        String paddedSequence = sequence.toString().padLeft(4, '0');
        
        setState(() {
          // Final Tag Format: VENDOR-ITEM-DATE-SERIAL
          // Example: SAM-MOB-020326-0001
          item.itemTagController.text = "$vendorPrefix-$itemPrefix-$dayPart-$paddedSequence";
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
    final allHavePo = packagingItems.every((p) => p.poLine != null && p.poLine!['problem'] == null);

    if (!isFormValid || !isDateSelected || !allHavePo) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Please select CTRL date, vendor, PO and item, and fill all required fields."),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    final String formattedTime = DateFormat('hh:mm a').format(DateTime.now());
    final double paidAmount = _amountPaidController.text.isNotEmpty
        ? double.tryParse(_amountPaidController.text) ?? 0.0
        : 0.0;

    final List<PackagingItem> saved = [];
    String? error;

    for (var packagingItem in packagingItems) {
      final line = packagingItem.poLine!;
      double? opt(TextEditingController c) => c.text.isNotEmpty ? _evaluateExpression(c.text) : null;
      final double itemTotalValue = _itemAmount(packagingItem);
      double amountDue = itemTotalValue - paidAmount;
      if (amountDue < 0) amountDue = 0;

      final Map<String, dynamic> dataToSave = {
        'item': line['item_name'],
        'vendor': line['vendor_name'],
        'po_number': line['po_number'],

        'qty_receive': _evaluateExpression(packagingItem.qtyReceiveController.text),
        'unit_receive': packagingItem.selectedUnitReceive,
        'pcs_receive': opt(packagingItem.pcsReceiveController),

        'qty_accept': opt(packagingItem.qtyAcceptController),
        'unit_accept': packagingItem.selectedUnitAccept,
        'pcs_accept': opt(packagingItem.pcsAcceptController),

        'qty_reject': opt(packagingItem.qtyRejectController),
        'unit_reject': packagingItem.selectedUnitReject,
        'pcs_reject': opt(packagingItem.pcsRejectController),

        'reason_for_rejection': packagingItem.rejectionReasonController.text,

        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'time': formattedTime,
        'ctrl_date': DateFormat('yyyy-MM-dd').format(ctrlDate!),

        'item_tag': packagingItem.itemTagController.text,

        // Rate always comes from the PO (the server also enforces this)
        'rate': line['rate'],
        'total_value': itemTotalValue,
        'amount_paid': paidAmount,
        'amount_due': amountDue,

        'payment_status': _selectedPaymentStatus ?? 'Unpaid',
        'mode_of_payment': _selectedModeOfPayment,
      };

      try {
        final res = await http.post(
          Uri.parse('$baseUrl/insert_packaging_material'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(dataToSave),
        );
        if (res.statusCode == 200 || res.statusCode == 201) {
          saved.add(packagingItem);
        } else {
          String msg = res.body;
          try {
            final b = json.decode(res.body);
            msg = (b['error'] ?? b['message'] ?? res.body).toString();
          } catch (_) {}
          error = "${line['item_name']}: $msg";
          break;
        }
      } catch (e) {
        error = "${line['item_name']}: $e";
        break;
      }
    }

    if (!mounted) return;

    if (error != null) {
      setState(() {
        for (final p in saved) {
          p.dispose();
        }
        packagingItems.removeWhere((p) => saved.contains(p));
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("${saved.isNotEmpty ? '${saved.length} saved. ' : ''}Not saved - $error"),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 8),
      ));
      _loadInitialData();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Packaging Material(s) Saved Successfully!"),
      backgroundColor: Colors.green,
    ));

    _formKey.currentState!.reset();
    for (var item in packagingItems) {
      item.dispose();
    }
    setState(() {
      packagingItems = [];
      _amountPaidController.clear();
      _amountDueController.clear();
    });
    _addNewItem();
    _loadInitialData();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Packaging Material Entry"),
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
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildCtrlDateButton(),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: const Text('Show POs of other dates (late / early delivery)', style: TextStyle(fontSize: 13)),
                              value: _showOtherDates,
                              onChanged: ctrlDate == null
                                  ? null
                                  : (v) {
                                      setState(() => _showOtherDates = v);
                                      _loadPoLines();
                                    },
                            ),
                            if (_loadingPOs) const LinearProgressIndicator(),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: packagingItems.length,
                              itemBuilder: (context, index) {
                                return _buildItemEntry(index);
                              },
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              icon: const Icon(Icons.add_circle_outline, color: Colors.indigo, size: 20),
                              label: const Text("Add More Items", style: TextStyle(color: Colors.indigo, fontSize: 13)),
                              onPressed: _addNewItem,
                            ),
                            const SizedBox(height: 24),
                            
                            // Direct Payment Section - Simple Fields
                            Card(
                              elevation: 0,
                              color: scheme.surfaceContainerHighest,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.payment, color: scheme.tertiary, size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          "Payment Details",
                                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurface),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            initialValue: _selectedPaymentStatus,
                                            decoration: InputDecoration(
                                              labelText: 'Payment Status',
                                              prefixIcon: Icon(Icons.payment, color: scheme.tertiary, size: 18),
                                            ),
                                            items: ['Unpaid', 'Paid', 'Partial Paid'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                            onChanged: (val) => setState(() => _selectedPaymentStatus = val),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            initialValue: _selectedModeOfPayment,
                                            decoration: InputDecoration(
                                              labelText: 'Mode of Payment',
                                              prefixIcon: Icon(Icons.account_balance_wallet, color: scheme.tertiary, size: 18),
                                            ),
                                            items: ['Cash', 'Online', 'Imprest'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                            onChanged: (val) => setState(() => _selectedModeOfPayment = val),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: TextFormField(
                                            controller: _amountPaidController,
                                            keyboardType: TextInputType.number,
                                            onChanged: (value) {
                                              _calculateAmountDue(); // Auto-calculate due when paid amount changes
                                            },
                                            decoration: InputDecoration(
                                              labelText: 'Amount Paid',
                                              prefixIcon: const Icon(Icons.check_circle, color: Colors.green, size: 18),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    // Show Grand Total
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.green),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text("Grand Total:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                          Builder(
                                            builder: (context) {
                                              double grandTotal = 0;
                                              for (var item in packagingItems) {
                                                grandTotal += _itemAmount(item);
                                              }
                                              return Text("₹ ${grandTotal.toStringAsFixed(2)}", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade800));
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _amountDueController,
                                      keyboardType: TextInputType.number,
                                      readOnly: true, // Auto-calculated from Total - Paid
                                      decoration: InputDecoration(
                                        labelText: 'Amount Due (Auto-calculated)',
                                        prefixIcon: Icon(Icons.money_off, color: Colors.red, size: 18),
                                        filled: true,
                                        fillColor: Colors.red.shade50,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.cloud_upload_outlined, size: 20),
                              label: const Text("Submit Packaging Material"),
                              onPressed: _handleSubmit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: scheme.primary,
                                foregroundColor: scheme.onPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text("Recent Packaging Materials", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo.shade800), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  _buildPackagingMaterialsTable(),
                ],
              ),
            ),
    );
  }

  Widget _buildItemEntry(int index) {
    final item = packagingItems[index];
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
              Text("Item #${index + 1}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo)),
              if (packagingItems.length > 1)
                IconButton(
                  icon: Icon(Icons.remove_circle_outline, color: Colors.red.shade400, size: 20),
                  onPressed: () => _removeItem(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const Divider(height: 20),

          PoLineSelector(
            key: ValueKey('po-$_poGeneration-${identityHashCode(item)}'),
            lines: _poLines,
            initialLine: item.poLine,
            enabled: ctrlDate != null && !_loadingPOs,
            disabledHint: 'Select CTRL date first. Only items marked as packaging (Admin > Item Settings) appear here.',
            onChanged: (line) => _onLineSelected(item, line),
          ),
          const SizedBox(height: 18),

          // Generate Item Tag Section
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: item.itemTagController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Item Tag',
                    labelStyle: const TextStyle(fontSize: 13),
                    prefixIcon: Icon(Icons.tag, color: Colors.orange.shade700, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.orange.shade50,
                  ),
                  validator: (val) => (val == null || val.isEmpty) ? "Generate tag" : null,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => _generateTag(item),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Generate", style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          _buildQuantityField(controller: item.qtyReceiveController, label: "Quantity Received", icon: Icons.move_to_inbox_outlined, units: _unitsFor(item), selectedUnit: item.selectedUnitReceive, onUnitChanged: (val) => setState(() => item.selectedUnitReceive = val!)),
          const SizedBox(height: 18),
          _buildExpressionField(controller: item.pcsReceiveController, label: "Pcs (Received)", icon: Icons.numbers, isOptional: true),
          const SizedBox(height: 18),
          _buildExpressionField(
            controller: item.qtyAcceptController,
            label: "Quantity Accepted (Optional)",
            icon: Icons.check_circle_outline,
            isOptional: true,
            onChanged: (value) {
              _calculateItemTotal(item);
              _calculateAmountDue();
            },
            suffixIcon: DropdownButtonHideUnderline(
              child: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: DropdownButton<String>(
                  value: item.selectedUnitAccept,
                  items: _unitsFor(item).map((String value) => DropdownMenuItem<String>(value: value, child: Text(value, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (val) => setState(() => item.selectedUnitAccept = val!),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _buildExpressionField(controller: item.pcsAcceptController, label: "Pcs (Accepted)", icon: Icons.numbers, isOptional: true),
          const SizedBox(height: 18),
          _buildQuantityField(controller: item.qtyRejectController, label: "Quantity Rejected (Optional)", icon: Icons.cancel_outlined, units: _unitsFor(item), selectedUnit: item.selectedUnitReject, onUnitChanged: (val) => setState(() => item.selectedUnitReject = val!), isOptional: true),
          const SizedBox(height: 18),
          _buildExpressionField(controller: item.pcsRejectController, label: "Pcs (Rejected)", icon: Icons.numbers, isOptional: true),
          const SizedBox(height: 18),
          TextFormField(
            controller: item.rejectionReasonController,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Reason for Rejection (Optional)',
              labelStyle: const TextStyle(fontSize: 13),
              prefixIcon: Icon(Icons.comment_outlined, color: Colors.red.shade300, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityField({required TextEditingController controller, required String label, required IconData icon, required String selectedUnit, required Function(String?) onUnitChanged, bool isOptional = false, List<String>? units}) {
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
          items: (units ?? _units).map((String value) => DropdownMenuItem<String>(value: value, child: Text(value, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: onUnitChanged,
        ),
      )),
    );
  }

  Widget _buildExpressionField({required TextEditingController controller, required String label, required IconData icon, Widget? suffixIcon, bool isOptional = false, Function(String)? onChanged}) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.text,
      style: const TextStyle(fontSize: 13),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.indigo.shade300, size: 20),
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
      icon: const Icon(Icons.calendar_month_outlined, color: Colors.teal, size: 20),
      onPressed: () async {
        DateTime? pickedDate = await showDatePicker(context: context, initialDate: ctrlDate ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
        if (pickedDate != null) {
          setState(() => ctrlDate = pickedDate);
          _loadPoLines();
        }
      },
      label: Text(ctrlDate == null ? 'Select CTRL Date' : 'CTRL: ${DateFormat('dd-MM-yy').format(ctrlDate!)}', style: TextStyle(color: ctrlDate == null ? Colors.black54 : Colors.teal.shade700, fontSize: 13)),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: BorderSide(color: ctrlDate == null ? Colors.grey.shade400 : Colors.teal), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    );
  }

  Widget _buildPackagingMaterialsTable() {
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _latestPackagingMaterials,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Padding(padding: const EdgeInsets.all(16.0), child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("No packaging material records found.")));
          }
          final packagingMaterials = snapshot.data!;
          const cellStyle = TextStyle(fontSize: 8);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              dataRowMinHeight: 30,
              dataRowMaxHeight: double.infinity,
              headingRowColor: WidgetStateProperty.all(Colors.indigo.shade100),
              columns: const [
                DataColumn(label: Text('Tag', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9))),
                DataColumn(label: Text('Item', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9))),
                DataColumn(label: Text('Vendor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9))),
                DataColumn(label: Text('PO Num', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9))),
                DataColumn(label: Text('Received', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9))),
                DataColumn(label: Text('Accepted', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9))),
                DataColumn(label: Text('Rejected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9))),
                DataColumn(label: Text('Rate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9))),
                DataColumn(label: Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9))),
                DataColumn(label: Text('Payment Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9))),
                DataColumn(label: Text('Paid', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9))),
                DataColumn(label: Text('Due', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9))),
                DataColumn(label: Text('Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9))),
                DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9))),
                DataColumn(label: Text('CTRL Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9))),
                DataColumn(label: Text('Reason', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9))),
              ],
              rows: packagingMaterials.map((row) {
                final rate = (row['rate'] as num?)?.toDouble() ?? 0.0;
                final qtyAccept = (row['qty_accept'] as num?)?.toDouble() ?? 0.0;
                final qtyReceive = (row['qty_receive'] as num?)?.toDouble() ?? 0.0;
                final qtyReject = (row['qty_reject'] as num?)?.toDouble() ?? 0.0;
                final unitReceive = row['unit_receive']?.toString() ?? '';
                final unitAccept = row['unit_accept']?.toString() ?? '';
                final unitReject = row['unit_reject']?.toString() ?? '';
                final totalValue = (row['total_value'] as num?)?.toDouble() ?? (rate * qtyAccept);
                
                // Calculate amount_paid and amount_due based on payment_status and total_value
                final paymentStatus = row['payment_status']?.toString() ?? 'Unpaid';
                final double dbAmountPaid = (row['amount_paid'] as num?)?.toDouble() ?? 0.0;
                final double paidAmount = paymentStatus == 'Paid' ? totalValue : (paymentStatus == 'Partial Paid' ? dbAmountPaid : 0.0);
                final double dueAmount = paymentStatus == 'Paid' ? 0.0 : (totalValue - paidAmount);
                
                return DataRow(cells: [
                  DataCell(Text(row['item_tag']?.toString() ?? '', style: cellStyle)),
                  DataCell(Text(row['item']?.toString() ?? '', style: cellStyle)),
                  DataCell(Text(row['vendor']?.toString() ?? '', style: cellStyle)),
                  DataCell(Text(row['po_number']?.toString() ?? '', style: cellStyle)),
                  DataCell(Text('${qtyReceive.toStringAsFixed(2)} $unitReceive', style: cellStyle)),
                  DataCell(Text('${qtyAccept.toStringAsFixed(2)} $unitAccept', style: cellStyle)),
                  DataCell(Text('${qtyReject.toStringAsFixed(2)} $unitReject', style: cellStyle)),
                  DataCell(Text(rate.toStringAsFixed(2), style: cellStyle)),
                  DataCell(Text(totalValue.toStringAsFixed(2), style: cellStyle)),
                  DataCell(
                    Text(
                      paymentStatus,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: paymentStatus == 'Paid' 
                            ? Colors.green 
                            : (paymentStatus == 'Partial Paid' ? Colors.orange : Colors.red),
                      ),
                    ),
                  ),
                  DataCell(Text(paidAmount.toStringAsFixed(2), style: const TextStyle(fontSize: 8, color: Colors.green))),
                  DataCell(Text(dueAmount.toStringAsFixed(2), style: const TextStyle(fontSize: 8, color: Colors.red))),
                  DataCell(Text(row['mode_of_payment']?.toString() ?? '-', style: cellStyle)),
                  DataCell(Text(row['date'] != null ? DateFormat('dd-MM-yy').format(DateTime.parse(row['date'])) : '', style: cellStyle)),
                  DataCell(Text(row['ctrl_date'] != null ? DateFormat('dd-MM-yy').format(DateTime.parse(row['ctrl_date'])) : '', style: cellStyle)),
                  DataCell(Text(row['reason_for_rejection']?.toString() ?? '-', style: cellStyle)),
                ]);
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}

