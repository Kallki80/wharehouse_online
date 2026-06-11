import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'api_config.dart';

// Get last rate for an item from purchases
Future<double?> getLastPurchaseRateForItem(String itemName) async {
  final queryParams = {'item_name': itemName, 'table': 'purchases'};
  final uri = Uri.parse('$baseUrl/get_last_rate_for_item').replace(queryParameters: queryParams);
  final response = await http.get(uri);
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['rate'] != null ? (data['rate'] as num).toDouble() : null;
  }
  return null;
}

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
  final TextEditingController rateController = TextEditingController(); // Rate for this item

  bool isOtherPo = false;
  bool isOtherItem = false;
  final TextEditingController otherItemController = TextEditingController();
  bool isOtherVendor = false;
  final TextEditingController otherVendorController = TextEditingController();

  double itemTotal = 0.0; // Total for this item (rate × qty_accept)

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

class Page1 extends StatefulWidget {
  const Page1({super.key});

  @override
  State<Page1> createState() => _Page1State();
}

class _Page1State extends State<Page1> {
  final _formKey = GlobalKey<FormState>();

  DateTime? ctrlDate;
  List<PurchaseItem> purchaseItems = [];
  Map<String, dynamic>? _paymentDetails;

  // Payment controllers
  final TextEditingController _rateController = TextEditingController();
  final TextEditingController _amountPaidController = TextEditingController();
  final TextEditingController _amountDueController = TextEditingController();
  String? _selectedPaymentStatus = 'Unpaid';
  String? _selectedModeOfPayment;

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
            _items = [...poItems.toList()..sort()];
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

  void _calculateAmountDue() {
    // Calculate total from all purchase items (using individual item rates if available)
    double totalValue = 0.0;
    double totalQty = 0.0;
    
    for (var purchaseItem in purchaseItems) {
      double qty = 0.0;
      if (purchaseItem.qtyAcceptController.text.isNotEmpty) {
        qty = _evaluateExpression(purchaseItem.qtyAcceptController.text);
        totalQty += qty;
      }
      
      // Use item-specific rate if available, otherwise use global rate
      double rate = 0.0;
      if (purchaseItem.rateController.text.isNotEmpty) {
        rate = double.tryParse(purchaseItem.rateController.text) ?? 0.0;
      } else if (_rateController.text.isNotEmpty) {
        rate = double.tryParse(_rateController.text) ?? 0.0;
      }
      
      // Calculate item total (rate × qty_accept)
      double itemTotal = qty * rate;
      purchaseItem.itemTotal = itemTotal;
      totalValue += itemTotal;
    }
    
    double paid = _amountPaidController.text.isNotEmpty ? double.tryParse(_amountPaidController.text) ?? 0.0 : 0.0;
    double due = totalValue - paid;
    if (due < 0) due = 0;
    
    setState(() {
      _amountDueController.text = due.toStringAsFixed(2);
    });
  }
  
  void _calculateItemTotal(PurchaseItem purchaseItem) {
    final qty = _evaluateExpression(purchaseItem.qtyAcceptController.text);
    final rate = double.tryParse(purchaseItem.rateController.text) ?? 0.0;
    setState(() {
      purchaseItem.itemTotal = qty * rate;
    });
  }
  
  Future<void> _autofillRateForItem(PurchaseItem purchaseItem, String itemName) async {
    try {
      final rate = await getLastPurchaseRateForItem(itemName);
      if (rate != null && mounted) {
        setState(() {
          purchaseItem.rateController.text = rate.toString();
        });
        // Also update the global rate controller if it's empty
        if (_rateController.text.isEmpty) {
          _rateController.text = rate.toString();
          _calculateAmountDue();
        }
      }
    } catch (e) {
      debugPrint("Error autofilling rate: $e");
    }
  }


  Future<void> _generateTag(PurchaseItem item) async {
    // 1. Vendor check
    if (item.selectedVendor == null && !item.isOtherVendor) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select Vendor first")));
      return;
    }

    // 2. Item check
    if (item.selectedItem == null && !item.isOtherItem) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select Item first")));
      return;
    }

    // 3. Date logic
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

    // --- Tag Generation Logic ---

    // Vendor Name से पहले 3 अक्षर लेना
    String vName = item.isOtherVendor ? item.otherVendorController.text : item.selectedVendor!;
    if (vName.length < 3) vName = vName.padRight(3, 'X');
    String vendorPrefix = vName.substring(0, 3).toUpperCase();

    // Item Name से पहले 3 अक्षर लेना
    String iName = item.isOtherItem ? item.otherItemController.text : item.selectedItem!;
    if (iName.length < 3) iName = iName.padRight(3, 'X');
    String itemPrefix = iName.substring(0, 3).toUpperCase();

    // Date part: ddMMyy
    String dayPart = DateFormat('ddMMyy').format(dateToUse);
    
    try {
      // API call: combined prefix (Vendor + Item) ताकि sequence unique रहे
      String combinedPrefix = "$vendorPrefix$itemPrefix";
      
      final response = await http.get(Uri.parse('$baseUrl/get_next_item_tag_sequence?vendor_prefix=$combinedPrefix&day_part=$dayPart'));
      
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




  // Future<void> _handleSubmit() async {
  //   final isFormValid = _formKey.currentState!.validate();
  //   final isDateSelected = ctrlDate != null;

  //   if (!isFormValid || !isDateSelected) {
  //     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
  //       content: Text("Please fill all required fields and select CTRL date."),
  //       backgroundColor: Colors.redAccent,
  //     ));
  //     return;
  //   }

  //   final String formattedTime = DateFormat('hh:mm a').format(DateTime.now());

  //   for (var purchaseItem in purchaseItems) {
  //     String finalPoNumber = purchaseItem.isOtherPo
  //         ? purchaseItem.poNumberController.text
  //         : purchaseItem.selectedPoNumber?.split(' (').first ?? '';

  //     String finalItem = purchaseItem.selectedItem!;
  //     if (purchaseItem.isOtherItem) {
  //       finalItem = purchaseItem.otherItemController.text;
  //       await http.post(Uri.parse('$baseUrl/insert_item'), headers: {'Content-Type': 'application/json'}, body: json.encode({'name': finalItem}));
  //     }

  //     String finalVendor = purchaseItem.selectedVendor!;
  //     if (purchaseItem.isOtherVendor) {
  //       finalVendor = purchaseItem.otherVendorController.text;
  //       await http.post(Uri.parse('$baseUrl/insert_purchase_vendor'), headers: {'Content-Type': 'application/json'}, body: json.encode({'name': finalVendor}));
  //     }

  //     final double? pcsReceive = purchaseItem.pcsReceiveController.text.isNotEmpty ? _evaluateExpression(purchaseItem.pcsReceiveController.text) : null;
  //     final double? pcsAccept = purchaseItem.pcsAcceptController.text.isNotEmpty ? _evaluateExpression(purchaseItem.pcsAcceptController.text) : null;
  //     final double? pcsReject = purchaseItem.pcsRejectController.text.isNotEmpty ? _evaluateExpression(purchaseItem.pcsRejectController.text) : null;

  //     // Use item-specific rate if available, otherwise use global rate
  //     double itemRate = purchaseItem.rateController.text.isNotEmpty 
  //         ? double.tryParse(purchaseItem.rateController.text) ?? 0.0 
  //         : (_rateController.text.isNotEmpty ? double.tryParse(_rateController.text) ?? 0.0 : 0.0);
      
  //     double itemQty = purchaseItem.qtyAcceptController.text.isNotEmpty 
  //         ? _evaluateExpression(purchaseItem.qtyAcceptController.text) 
  //         : 0.0;
      
  //     double itemTotalValue = itemRate * itemQty;

  //     Map<String, dynamic> dataToSave = {
  //       'item': finalItem,
  //       'vendor': finalVendor,
  //       'po_number': finalPoNumber,
  //       'qty_receive': _evaluateExpression(purchaseItem.qtyReceiveController.text),
  //       'unit_receive': purchaseItem.selectedUnitReceive,
  //       'pcs_receive': pcsReceive,
  //       'qty_accept': purchaseItem.qtyAcceptController.text.isNotEmpty ? _evaluateExpression(purchaseItem.qtyAcceptController.text) : null,
  //       'unit_accept': purchaseItem.selectedUnitAccept,
  //       'pcs_accept': pcsAccept,
  //       'qty_reject': purchaseItem.qtyRejectController.text.isNotEmpty ? _evaluateExpression(purchaseItem.qtyRejectController.text) : null,
  //       'unit_reject': purchaseItem.selectedUnitReject,
  //       'pcs_reject': pcsReject,
  //       'reason_for_rejection': purchaseItem.rejectionReasonController.text,
  //       'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
  //       'time': formattedTime,
  //       'ctrl_date': DateFormat('yyyy-MM-dd').format(ctrlDate!),
  //       'item_tag': purchaseItem.itemTagController.text,
  //       'rate': itemRate,
  //       'total_value': itemTotalValue,
  //       'amount_paid': _amountPaidController.text.isNotEmpty ? double.tryParse(_amountPaidController.text) ?? 0.0 : 0.0,
  //       'payment_status': _selectedPaymentStatus ?? 'Unpaid',
  //       'mode_of_payment': _selectedModeOfPayment,
  //     };

  //     await http.post(Uri.parse('$baseUrl/insert_purchase'), headers: {'Content-Type': 'application/json'}, body: json.encode(dataToSave));
  //   }

  //   if (mounted) {
  //     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
  //       content: Text("Purchase(s) Saved Successfully!"),
  //       backgroundColor: Colors.green,
  //     ));
  //   }

  //   _formKey.currentState!.reset();
  //   for (var item in purchaseItems) {
  //     item.dispose();
  //   }
  //   setState(() {
  //     purchaseItems = [];
  //     ctrlDate = null;
  //   });
  //   _addNewItem();
  //   _loadInitialData();
  // }


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

    double paidAmount = _amountPaidController.text.isNotEmpty
        ? double.tryParse(_amountPaidController.text) ?? 0.0
        : 0.0;

    for (var purchaseItem in purchaseItems) {

      String finalPoNumber = purchaseItem.isOtherPo
          ? purchaseItem.poNumberController.text
          : purchaseItem.selectedPoNumber?.split(' (').first ?? '';

      String finalItem = purchaseItem.selectedItem!;
      if (purchaseItem.isOtherItem) {
        finalItem = purchaseItem.otherItemController.text;
        await http.post(
          Uri.parse('$baseUrl/insert_item'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'name': finalItem}),
        );
      }

      String finalVendor = purchaseItem.selectedVendor!;
      if (purchaseItem.isOtherVendor) {
        finalVendor = purchaseItem.otherVendorController.text;
        await http.post(
          Uri.parse('$baseUrl/insert_purchase_vendor'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'name': finalVendor}),
        );
      }

      final double? pcsReceive = purchaseItem.pcsReceiveController.text.isNotEmpty
          ? _evaluateExpression(purchaseItem.pcsReceiveController.text)
          : null;

      final double? pcsAccept = purchaseItem.pcsAcceptController.text.isNotEmpty
          ? _evaluateExpression(purchaseItem.pcsAcceptController.text)
          : null;

      final double? pcsReject = purchaseItem.pcsRejectController.text.isNotEmpty
          ? _evaluateExpression(purchaseItem.pcsRejectController.text)
          : null;

      /// RATE
      double itemRate = purchaseItem.rateController.text.isNotEmpty
          ? double.tryParse(purchaseItem.rateController.text) ?? 0.0
          : (_rateController.text.isNotEmpty
              ? double.tryParse(_rateController.text) ?? 0.0
              : 0.0);

      /// QTY ACCEPT
      // double itemQty = purchaseItem.qtyAcceptController.text.isNotEmpty
      //     ? _evaluateExpression(purchaseItem.qtyAcceptController.text)
      //     : 0.0;

      double itemQty = purchaseItem.qtyAcceptController.text.isNotEmpty
      ? _evaluateExpression(purchaseItem.qtyAcceptController.text)
      : _evaluateExpression(purchaseItem.qtyReceiveController.text);

      /// TOTAL
      double itemTotalValue = itemRate * itemQty;

      /// DUE CALCULATION
      double amountDue = itemTotalValue - paidAmount;

      if (amountDue < 0) {
        amountDue = 0;
      }

      Map<String, dynamic> dataToSave = {
        'item': finalItem,
        'vendor': finalVendor,
        'po_number': finalPoNumber,

        'qty_receive': _evaluateExpression(purchaseItem.qtyReceiveController.text),
        'unit_receive': purchaseItem.selectedUnitReceive,
        'pcs_receive': pcsReceive,

        'qty_accept': purchaseItem.qtyAcceptController.text.isNotEmpty
            ? _evaluateExpression(purchaseItem.qtyAcceptController.text)
            : null,
        'unit_accept': purchaseItem.selectedUnitAccept,
        'pcs_accept': pcsAccept,

        'qty_reject': purchaseItem.qtyRejectController.text.isNotEmpty
            ? _evaluateExpression(purchaseItem.qtyRejectController.text)
            : null,
        'unit_reject': purchaseItem.selectedUnitReject,
        'pcs_reject': pcsReject,

        'reason_for_rejection': purchaseItem.rejectionReasonController.text,

        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'time': formattedTime,
        'ctrl_date': DateFormat('yyyy-MM-dd').format(ctrlDate!),

        'item_tag': purchaseItem.itemTagController.text,

        /// PRICE VALUES
        'rate': itemRate,
        'total_value': itemTotalValue,
        'amount_paid': paidAmount,
        'amount_due': amountDue,

        'payment_status': _selectedPaymentStatus ?? 'Unpaid',
        'mode_of_payment': _selectedModeOfPayment,
      };

      await http.post(
        Uri.parse('$baseUrl/insert_purchase'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(dataToSave),
      );
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Purchase Entry"),
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
                              icon: const Icon(Icons.add_circle_outline, color: Colors.indigo, size: 20),
                              label: const Text("Add More Items", style: TextStyle(color: Colors.indigo, fontSize: 13)),
                              onPressed: _addNewItem,
                            ),
const SizedBox(height: 24),
                            _buildCtrlDateButton(),
                            const SizedBox(height: 30),
                            
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
                                          child: TextFormField(
controller: _rateController,
                                            keyboardType: TextInputType.number,
                                            onChanged: (value) {
                                              _calculateAmountDue();
                                            },
                                            decoration: InputDecoration(
                                              labelText: 'Rate',
                                              prefixIcon: Icon(Icons.currency_rupee, color: scheme.tertiary, size: 18),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
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
                                              for (var item in purchaseItems) {
                                                double itemRate = item.rateController.text.isNotEmpty 
                                                    ? double.tryParse(item.rateController.text) ?? 0.0 
                                                    : (_rateController.text.isNotEmpty ? double.tryParse(_rateController.text) ?? 0.0 : 0.0);
                                                double itemQty = item.qtyAcceptController.text.isNotEmpty 
                                                    ? _evaluateExpression(item.qtyAcceptController.text) 
                                                    : 0.0;
                                                grandTotal += itemRate * itemQty;
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
                              label: const Text("Submit Purchase"),
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
                  Text("Recent Purchases", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo.shade800), textAlign: TextAlign.center),
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
              Text("Item #${index + 1}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo)),
              if (purchaseItems.length > 1)
                IconButton(
                  icon: Icon(Icons.remove_circle_outline, color: Colors.red.shade400, size: 20),
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
            onChanged: (val) {
              setState(() {
                item.selectedItem = val;
                item.isOtherItem = (val == "Other");
                if (val != "Other") {
                  item.selectedVendor = null;
                  item.selectedPoNumber = null;
                }
              });
              // Auto-fill rate from previous purchase
              if (val != null && val != "Other") {
                _autofillRateForItem(item, val);
              }
            },
          ),
          // if (item.isOtherItem)
          //   _buildOtherTextField(
          //     controller: item.otherItemController,
          //     label: "Enter New Item Name",
          //     validator: (val) => (item.isOtherItem && (val == null || val.isEmpty)) ? "Please enter item name" : null,
          //   ),
          const SizedBox(height: 18),

          // Rate field for each item - auto-filled from previous purchases
          TextFormField(
            controller: item.rateController,
            onChanged: (value) {
              _calculateItemTotal(item);
              _calculateAmountDue();
            },
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: "Rate (Auto-filled from previous)",
              labelStyle: const TextStyle(fontSize: 13),
              prefixIcon: Icon(Icons.currency_rupee, color: Colors.indigo.shade300, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            keyboardType: TextInputType.number,
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
          _buildQuantityField(controller: item.qtyReceiveController, label: "Quantity Received", icon: Icons.move_to_inbox_outlined, selectedUnit: item.selectedUnitReceive, onUnitChanged: (val) => setState(() => item.selectedUnitReceive = val!)),
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
                  items: _units.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (val) => setState(() => item.selectedUnitAccept = val!),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _buildExpressionField(controller: item.pcsAcceptController, label: "Pcs (Accepted)", icon: Icons.numbers, isOptional: true),
          const SizedBox(height: 18),
          _buildQuantityField(controller: item.qtyRejectController, label: "Quantity Rejected (Optional)", icon: Icons.cancel_outlined, selectedUnit: item.selectedUnitReject, onUnitChanged: (val) => setState(() => item.selectedUnitReject = val!), isOptional: true),
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
            labelStyle: const TextStyle(fontSize: 13),
            prefixIcon: Icon(Icons.receipt_long_outlined, color: Colors.indigo.shade300, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          style: const TextStyle(fontSize: 13, color: Colors.black),
          initialValue: finalSuggestions.contains(item.selectedPoNumber) ? item.selectedPoNumber : null,
          items: finalSuggestions.map((po) => DropdownMenuItem(value: po, child: Text(po, style: const TextStyle(fontSize: 13)))).toList(),
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
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Enter Other PO Number',
                labelStyle: const TextStyle(fontSize: 13),
                prefixIcon: Icon(Icons.edit_note_outlined, color: Colors.teal.shade300, size: 20),
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
              labelStyle: const TextStyle(fontSize: 13),
              prefixIcon: Icon(Icons.store_mall_directory_outlined, color: Colors.indigo.shade300, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50),
          style: const TextStyle(fontSize: 13, color: Colors.black),
          initialValue: filteredVendors.contains(item.selectedVendor) ? item.selectedVendor : null,
          items: filteredVendors.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))).toList(),
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
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                  labelText: 'Enter New Vendor Name',
                  labelStyle: const TextStyle(fontSize: 13),
                  prefixIcon: Icon(Icons.edit_note_outlined, color: Colors.teal.shade300, size: 20),
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
          labelStyle: const TextStyle(fontSize: 13),
          prefixIcon: Icon(icon, color: Colors.indigo.shade300, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey.shade50),
      style: const TextStyle(fontSize: 13, color: Colors.black),
      initialValue: value,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))).toList(),
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
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(fontSize: 13),
            prefixIcon: Icon(Icons.edit_note_outlined, color: Colors.teal.shade300, size: 20),
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
          items: _units.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value, style: const TextStyle(fontSize: 12)))).toList(),
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
        if (pickedDate != null) setState(() => ctrlDate = pickedDate);
      },
      label: Text(ctrlDate == null ? 'Select CTRL Date' : 'CTRL: ${DateFormat('dd-MM-yy').format(ctrlDate!)}', style: TextStyle(color: ctrlDate == null ? Colors.black54 : Colors.teal.shade700, fontSize: 13)),
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
              rows: purchases.map((row) {
                final rate = (row['rate'] as num?)?.toDouble() ?? 0.0;
                final qtyAccept = (row['qty_accept'] as num?)?.toDouble() ?? 0.0;
                final qtyReceive = (row['qty_receive'] as num?)?.toDouble() ?? 0.0;
                final qtyReject = (row['qty_reject'] as num?)?.toDouble() ?? 0.0;
                final unitReceive = row['unit_receive']?.toString() ?? '';
                final unitAccept = row['unit_accept']?.toString() ?? '';
                final unitReject = row['unit_reject']?.toString() ?? '';
                final totalValue = (row['total_value'] as num?)?.toDouble() ?? (rate * qtyAccept);
                
                // Calculate amount_paid and amount_due based on payment_status and total_value
                // If "Paid": Paid = total_value, Due = 0
                // If "Unpaid": Paid = 0, Due = total_value
                // If "Partial Paid": Paid = amount_paid from DB, Due = total_value - amount_paid
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
