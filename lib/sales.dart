import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:math_expressions/math_expressions.dart';

import 'api_config.dart';

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
    final data = json.decode(response.body);
    return List<Map<String, dynamic>>.from(data['data'] ?? []);
  } else {
    throw Exception('Failed to load purchases: ${response.statusCode}');
  }
}


// Get last rate for an item from a specific table
Future<double?> getLastRateForItem(String itemName, {String table = 'sales'}) async {
  final queryParams = {'item_name': itemName, 'table': table};
  final uri = Uri.parse('$apiBaseUrl/get_last_rate_for_item').replace(queryParameters: queryParams);
  final response = await http.get(uri);
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['rate'] != null ? (data['rate'] as num).toDouble() : null;
  }
  return null;
}

// Get all related data for an item (tags, PO numbers, rates)
Future<Map<String, dynamic>> getRelatedDataForItem(String itemName) async {
  final queryParams = {'item_name': itemName};
  final uri = Uri.parse('$apiBaseUrl/get_related_data_for_item').replace(queryParameters: queryParams);
  final response = await http.get(uri);
  if (response.statusCode == 200) {
    return json.decode(response.body);
  }
  return {};
}

// Updated to fetch ALL generated SOs to ensure nothing is missed
Future<List<Map<String, dynamic>>> getAvailableSOsForSale() async {
  // Using the more comprehensive endpoint to get all SOs
  final response = await http.get(Uri.parse('$apiBaseUrl/get_all_generated_sos_with_items'));
  if (response.statusCode == 200) {
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  } else {
    // Fallback if the above fails, try the old one
    final fallbackResponse = await http.get(Uri.parse('$apiBaseUrl/get_available_sos_for_sale'));
    if (fallbackResponse.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(fallbackResponse.body));
    }
    throw Exception('Failed to load SOs');
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
  final TextEditingController rateController = TextEditingController();
  String? poFromTag; // To store the PO number associated with the tag
  String selectedUnit = 'Kg';
  double itemTotal = 0.0;
  bool isOtherItem = false;
  final TextEditingController otherItemController = TextEditingController();
  bool isReadOnly = false;
  bool isLoadingRate = false;

  void dispose() {
    qtyController.dispose();
    pcsController.dispose();
    rateController.dispose();
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

  // ctrl date (mandatory)
  DateTime? _ctrlDate;
  String? _ctrlDateError;


  String? _selectedClient;
  bool _isOtherClient = false;
  final TextEditingController _otherClientController = TextEditingController();
  // bool _showLoadingOverlay = false;

  void _showLoadingOverlay() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
    // Note: Will hide via Navigator.pop when done
  }

  void _hideLoadingOverlay() {
    if (!mounted) return;
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }
  
  String? _selectedSO;
  List<String> _availableSOs = [];
  List<Map<String, dynamic>> _allAvailableSoData = [];

  List<SaleItem> saleItems = [];
  bool _isSubmitting = false;
int? _editingWaitlistId;
  Map<String, dynamic>? _paymentDetails;
  
  // Payment controllers
  final TextEditingController _rateController = TextEditingController();
  final TextEditingController _amountPaidController = TextEditingController();
  final TextEditingController _amountDueController = TextEditingController();
  String? _selectedPaymentStatus = 'Unpaid';
  String? _selectedModeOfPayment;

  List<String> _items = [];
  List<String> _clients = [];
  List<Map<String, dynamic>> _allPurchaseData = [];
  final List<String> _units = ["Kg", "g", "pcs", "L", "ml"];

  bool _isLoading = true;
  bool _noClientsWarning = false;
  final bool _refreshEnabled = true;


@override
  void initState() {
    super.initState();
    // Initialize amount due to show 0.0 initially
    _amountDueController.text = '0.00';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData().then((_) {
        if (mounted) {
          _addNewItem();
          // Calculate initial totals
          _calculateAmountDueSales();
        }
      });
    });
  }

Future<void> _loadInitialData() async {
    _showLoadingOverlay();
    if (!mounted) {
      _hideLoadingOverlay();
      return;
    }
    setState(() => _isLoading = true);

    try {
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
          // Merge clients from vendor table and SOs to ensure all show up
          final Set<String> allClientNames = {...dbClients};
          for (var so in dbSOs) {
            if (so['client_name'] != null) {
              allClientNames.add(so['client_name'].toString());
            }
          }
          
          _clients = ["Other", ...allClientNames.toList()..sort()];
          debugPrint('Loaded ${_clients.length} clients: ${_clients.take(5).toList()}...');  // Debug
          _noClientsWarning = _clients.length <= 1; // Only Other
          _allAvailableSoData = dbSOs;
          _items = uniqueSoItems.toList()..sort();
          _allPurchaseData = dbPurchases;
          // Initial list of SOs
          _availableSOs = dbSOs
              .map((so) => so['so_number']?.toString() ?? "")
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()..sort();
          _isLoading = false;
        });

      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      _hideLoadingOverlay();
    }
  }

void _autofillItemsFromSO(String soNumber) {
    final soItemsData = _allAvailableSoData.where((so) => so['so_number'] == soNumber).toList();
    
    setState(() {
      saleItems.clear();
      for (var data in soItemsData) {
        final newItem = SaleItem();
        newItem.selectedItem = data['item_name'];
        newItem.qtyController.text = data['quantity_kg']?.toString() ?? '';
        newItem.pcsController.text = data['quantity_pcs']?.toString() ?? '';
        newItem.selectedUnit = 'Kg';
        
        // Load tags for this item
        final itemPurchases = _allPurchaseData.where((p) => p['item'] == data['item_name']).toList();
        newItem.availableTags = itemPurchases
            .map((p) => p['item_tag'] as String?)
            .where((tag) => tag != null)
            .cast<String>()
            .toSet()
            .toList();
            
        if (newItem.availableTags.length == 1) {
          final tag = newItem.availableTags.first;
          newItem.selectedTag = tag;
          final match = _allPurchaseData.firstWhere(
            (p) => p['item'] == newItem.selectedItem && p['item_tag'] == tag,
            orElse: () => {},
          );
          if (match.isNotEmpty) {
            newItem.poFromTag = match['po_number'] ?? '';
          }
        }
        
        // Auto-fill rate for this item
        _autofillRateForItemOnLoad(newItem, data['item_name']);
        
        // Calculate initial item total after rate is set (or use default)
        double qty = double.tryParse(newItem.qtyController.text) ?? 0.0;
        double rate = double.tryParse(newItem.rateController.text) ?? 0.0;
        newItem.itemTotal = qty * rate;
        
        saleItems.add(newItem);
      }
      if (saleItems.isEmpty) {
        _addNewItem();
      }
      // Recalculate grand total after all items are added
      _calculateAmountDueSales();
    });
  }
  
  // Auto-fill rate when item is loaded (not async)
  Future<void> _autofillRateForItemOnLoad(SaleItem saleItem, String itemName) async {
    if (!mounted) return;
    setState(() => saleItem.isLoadingRate = true);
    try {
      final rate = await getLastRateForItem(itemName, table: 'sales');
      if (rate != null && mounted) {
        setState(() {
          saleItem.rateController.text = rate.toString();
          saleItem.isLoadingRate = false;
        });
      } else {
        if (mounted) setState(() => saleItem.isLoadingRate = false);
      }
    } catch (e) {
      debugPrint("Error autofilling rate: $e");
      if (mounted) setState(() => saleItem.isLoadingRate = false);
    }
  }

  void _updateAvailableSOsAndItems({bool autoSelect = false}) {
    setState(() {
      // 1. Filter SOs based on selected client
      if (_selectedClient == null || _selectedClient == 'Other') {
        _availableSOs = _allAvailableSoData
            .map((so) => so['so_number']?.toString() ?? "")
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()..sort();
      } else {
        _availableSOs = _allAvailableSoData
            .where((so) => so['client_name'] == _selectedClient)
            .map((so) => so['so_number']?.toString() ?? "")
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()..sort();
      }

      // 2. Autofill logic: If only one SO exists for this client, select it automatically
      if (autoSelect && _availableSOs.length == 1) {
        _selectedSO = _availableSOs.first;
        _autofillItemsFromSO(_selectedSO!);
      } else if (_selectedSO != null && !_availableSOs.contains(_selectedSO)) {
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

      // 4. Clear invalid selections in current sale items if not just autofilled
      if (!autoSelect || _availableSOs.length != 1) {
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

  void _calculateAmountDueSales() {
    // Calculate total from all sale items (using individual item rates if available)
    double totalValue = 0.0;
    double totalQty = 0.0;
    
    for (var saleItem in saleItems) {
      double qty = 0.0;
      if (saleItem.qtyController.text.isNotEmpty) {
        qty = _evaluateExpression(saleItem.qtyController.text);
        totalQty += qty;
      }
      
      // Use item-specific rate if available, otherwise use global rate
      double rate = 0.0;
      if (saleItem.rateController.text.isNotEmpty) {
        rate = double.tryParse(saleItem.rateController.text) ?? 0.0;
      } else if (_rateController.text.isNotEmpty) {
        rate = double.tryParse(_rateController.text) ?? 0.0;
      }
      
      // Calculate item total (rate × qty)
      double itemTotal = qty * rate;
      saleItem.itemTotal = itemTotal;
      totalValue += itemTotal;
    }
    
    double paid = _amountPaidController.text.isNotEmpty ? double.tryParse(_amountPaidController.text) ?? 0.0 : 0.0;
    double due = totalValue - paid;
    if (due < 0) due = 0;
    
    setState(() {
      _amountDueController.text = due.toStringAsFixed(2);
    });
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

  List<Map<String, dynamic>> _collectSaleData(String finalClient, String formattedTime) {
    List<Map<String, dynamic>> batchData = [];
    for (var saleItem in saleItems) {
      if (saleItem.selectedItem == null || saleItem.selectedItem!.isEmpty) continue; // Skip invalid items

      double itemRate = saleItem.rateController.text.isNotEmpty 
          ? double.tryParse(saleItem.rateController.text) ?? 0.0 
          : (_rateController.text.isNotEmpty ? double.tryParse(_rateController.text) ?? 0.0 : 0.0);
      
      double itemQty = saleItem.qtyController.text.isNotEmpty 
          ? _evaluateExpression(saleItem.qtyController.text) 
          : 0.0;
      
      if (itemQty <= 0) continue; // Skip zero qty

      double itemTotalValue = itemRate * itemQty;
      
      batchData.add({
        'item': saleItem.selectedItem,
        'clint': finalClient,
        'po_number': _selectedSO ?? saleItem.poFromTag ?? '',
        'quantity': itemQty,
        'unit': saleItem.selectedUnit,
        'pcs': saleItem.pcsController.text.isNotEmpty ? _evaluateExpression(saleItem.pcsController.text) : null,
        'date': DateFormat('yyyy-MM-dd').format(_ctrlDate ?? DateTime.now()),

        'time': formattedTime,
        'item_tag': saleItem.selectedTag,
        'payment_status': _selectedPaymentStatus ?? 'Unpaid',
        'rate': itemRate,
        'total_value': itemTotalValue,
        'mode_of_payment': _selectedModeOfPayment,
        'amount_paid': _amountPaidController.text.isNotEmpty ? double.tryParse(_amountPaidController.text) ?? 0.0 : 0.0,
        'amount_due': _amountDueController.text.isNotEmpty ? double.tryParse(_amountDueController.text) ?? 0.0 : 0.0,
      });
    }
    debugPrint('Collected ${batchData.length} items for submit');
    return batchData;
  }

  void _handleSubmit() async {
    if (_ctrlDate == null) {
      setState(() => _ctrlDateError = 'Required');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select ctrl date'),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    final isFormValid = _formKey.currentState!.validate();
    if (!isFormValid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all required fields"), backgroundColor: Colors.redAccent));
      return;
    }

    final batchData = _collectSaleData(
      _isOtherClient ? _otherClientController.text : (_selectedClient ?? ''),
      DateFormat('hh:mm a').format(DateTime.now())
    );

    if (batchData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No valid items to save"), backgroundColor: Colors.orange));
      return;
    }

    _showLoadingOverlay();
    setState(() => _isSubmitting = true);

    try {
      if (_isOtherClient && batchData.isNotEmpty) {
        final clientName = batchData[0]['clint'] as String;
        if (clientName.isNotEmpty) await insertVendor(clientName);
      }

      final results = await Future.wait(
        batchData.map((data) => insertSale(data).then((_) => true).catchError((e) {
          debugPrint('Failed to save item ${data['item']}: $e');
          return false;
        }))
      );

      final successCount = results.where((r) => r == true).length;
      if (_editingWaitlistId != null) {
        await deleteWaitlistedSale(_editingWaitlistId!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Saved $successCount/${batchData.length} items successfully!"),
          backgroundColor: successCount == batchData.length ? Colors.green : Colors.orange,
        ));
      }

      _resetForm();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Submit failed: $e"), backgroundColor: Colors.red));
      }
    } finally {
      _hideLoadingOverlay();
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _onItemChanged(SaleItem saleItem, String? val) async {
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
        
        // Auto-fill rate from previous sales
        _autofillRateForItem(saleItem, val);
      } else {
        saleItem.availableTags = [];
        saleItem.rateController.clear();
      }
    });
  }
  
  Future<void> _autofillRateForItem(SaleItem saleItem, String itemName) async {
    if (!mounted) return;
    setState(() => saleItem.isLoadingRate = true);
    try {
      final rate = await getLastRateForItem(itemName, table: 'sales');
      if (rate != null && mounted) {
        setState(() {
          saleItem.rateController.text = rate.toString();
          saleItem.isLoadingRate = false;
        });
        // Also update the global rate controller if it's empty
        if (_rateController.text.isEmpty) {
          _rateController.text = rate.toString();
          _calculateAmountDueSales();
        }
      } else {
        if (mounted) setState(() => saleItem.isLoadingRate = false);
      }
    } catch (e) {
      debugPrint("Error autofilling rate: $e");
      if (mounted) setState(() => saleItem.isLoadingRate = false);
    }
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
    _showLoadingOverlay();
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
    });
    _hideLoadingOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Sales Entry"),
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
                    elevation: 4,
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
                            _buildCtrlDateSection(),
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
                                icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 20),
                                label: const Text("Add More Items", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                                onPressed: _addNewItem,
                              ),
const SizedBox(height: 24),
                            // Payment Section - Direct Fields
                            Card(
                              elevation: 0,
                              color: scheme.surfaceContainerHighest,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    // Horizontal overflow fix: ensure content never exceeds width.
                                    final maxW = constraints.maxWidth;
                                    return SingleChildScrollView(
                                      scrollDirection: Axis.vertical,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(maxWidth: maxW),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.payment, color: scheme.tertiary, size: 20),
                                                const SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(
                                                    "Payment Details",
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w700,
                                                      color: scheme.onSurface,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
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
                                                      _calculateAmountDueSales();
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
                                                    isExpanded: true,
                                                    initialValue: _selectedPaymentStatus,
                                                    decoration: InputDecoration(
                                                      labelText: 'Payment Status',
                                                      prefixIcon: Icon(Icons.payment, color: scheme.tertiary, size: 18),
                                                    ),
                                                    items: ['Unpaid', 'Paid', 'Partial Paid']
                                                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                                        .toList(),
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
                                                    isExpanded: true,
                                                    initialValue: _selectedModeOfPayment,
                                                    decoration: InputDecoration(
                                                      labelText: 'Mode of Payment',
                                                      prefixIcon: Icon(Icons.account_balance_wallet, color: scheme.tertiary, size: 18),
                                                    ),
                                                    items: ['Cash', 'Online', 'Imprest']
                                                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                                        .toList(),
                                                    onChanged: (val) => setState(() => _selectedModeOfPayment = val),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: TextFormField(
                                                    controller: _amountPaidController,
                                                    keyboardType: TextInputType.number,
                                                    onChanged: (value) {
                                                      _calculateAmountDueSales(); // Auto-calculate due when paid amount changes
                                                    },
                                                    decoration: InputDecoration(
                                                      labelText: 'Amount Paid',
                                                      prefixIcon: Icon(Icons.check_circle, color: Colors.green, size: 18),
                                                    ),
                                                  ),
                                                ),
                                              ],
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
                                            const SizedBox(height: 16),
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
                                                  const Flexible(
                                                    child: Text(
                                                      "Grand Total:",
                                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Builder(
                                                    builder: (context) {
                                                      double grandTotal = 0;
                                                      for (var item in saleItems) {
                                                        grandTotal += item.itemTotal;
                                                      }
                                                      return Text(
                                                        "₹ ${grandTotal.toStringAsFixed(2)}",
                                                        style: TextStyle(
                                                          fontSize: 18,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.green.shade800,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: (_isSubmitting 
                                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : Icon(_editingWaitlistId != null ? Icons.upgrade : Icons.send_outlined, color: Colors.white, size: 20)
                                    ),
                                    label: Text(_isSubmitting ? "Submitting..." : (_editingWaitlistId != null ? "Update Sale" : "Submit Sale")),
                                    onPressed: _isSubmitting ? null : _handleSubmit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: scheme.primary,
                                      foregroundColor: scheme.onPrimary,
                                    ),
                                  ),
                                ),
                                if (_editingWaitlistId == null)
                                  const SizedBox(width: 12),
                                if (_editingWaitlistId == null)
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.playlist_add, color: Colors.white, size: 20),
                                      label: const Text("To Waitlist"),
                                      onPressed: _handleAddToWaitlist,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: scheme.secondary,
                                        foregroundColor: scheme.onSecondary,
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
                  Text("Recent Sales", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade800), textAlign: TextAlign.center),
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
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                decoration: InputDecoration(
                    labelText: "Select Client",
                    labelStyle: const TextStyle(fontSize: 13),
                    prefixIcon: Icon(Icons.person_outline, color: Colors.green.shade300, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50),
                style: const TextStyle(fontSize: 13, color: Colors.black),
                isExpanded: true,
                initialValue: _selectedClient,
                items: _clients.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedClient = val;
                    _isOtherClient = (val == 'Other');
                    _noClientsWarning = false;
                  });
                  _updateAvailableSOsAndItems(autoSelect: true);
                },
                validator: (val) => val == null ? "Please Select Client" : null,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.green),
              onPressed: _refreshEnabled ? _loadInitialData : null,
              tooltip: 'Refresh Clients/SOs',
            ),
          ],
        ),
        if (_noClientsWarning) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('No clients loaded. Tap refresh icon.', style: TextStyle(fontSize: 12))),
              ],
            ),
          ),
        ],
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


  Widget _buildCtrlDateSection() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ctrl Date',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      errorText: _ctrlDateError,
                    ),
                    child: Text(
                      _ctrlDate == null
                          ? 'Select date'
                          : DateFormat('yyyy-MM-dd').format(_ctrlDate!),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.calendar_today, color: Colors.green),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _ctrlDate ?? now,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (!mounted) return;
                    if (picked != null) {
                      setState(() {
                        _ctrlDate = picked;
                        _ctrlDateError = null;
                      });
                    }
                  },
                  tooltip: 'Pick date',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSOSection() {
    return DropdownButtonFormField<String?>(

      decoration: InputDecoration(
          labelText: "Select SO Number (Optional)",
          labelStyle: const TextStyle(fontSize: 13),
          prefixIcon: Icon(Icons.receipt_long_outlined, color: Colors.green.shade300, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey.shade50),
      style: const TextStyle(fontSize: 13, color: Colors.black),
      isExpanded: true,
      initialValue: _selectedSO,
      items: [
        const DropdownMenuItem(value: null, child: Text("None", style: TextStyle(fontSize: 13))),
        ..._availableSOs.map((so) => DropdownMenuItem(value: so, child: Text(so, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))))
      ],
      onChanged: (val) {
        setState(() {
          _selectedSO = val;
        });
        if (val != null) {
          _autofillItemsFromSO(val);
        }
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
              Text("Item #${index + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14)),
              if (saleItems.length > 1 && _editingWaitlistId == null)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                  onPressed: () => _removeItem(index),
                ),
            ],
          ),
          const Divider(),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: "Select Item",
              labelStyle: const TextStyle(fontSize: 13),
              prefixIcon: Icon(Icons.inventory_2_outlined, color: Colors.green.shade300, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            style: const TextStyle(fontSize: 13, color: Colors.black),
            isExpanded: true,
            initialValue: saleItem.selectedItem,
            items: _items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (val) => _onItemChanged(saleItem, val),
            validator: (val) => val == null ? "Required" : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: "Select Item Tag",
              labelStyle: const TextStyle(fontSize: 13),
              prefixIcon: Icon(Icons.tag, color: Colors.green.shade300, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            style: const TextStyle(fontSize: 13, color: Colors.black),
            isExpanded: true,
            initialValue: saleItem.selectedTag,
            items: saleItem.availableTags.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (val) => _onTagChanged(saleItem, val),
          ),
          const SizedBox(height: 12),
          // Rate field for each item - auto-filled from previous sales
          saleItem.isLoadingRate 
            ? Row(
                children: [
                  Expanded(child: Container()),
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              )
            : TextFormField(
                controller: saleItem.rateController,
                onChanged: (value) {
                  _calculateItemTotal(saleItem);
                  _calculateAmountDueSales();
                },
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  labelText: "Rate (Auto-filled from previous)",
                  labelStyle: const TextStyle(fontSize: 13),
                  prefixIcon: Icon(Icons.currency_rupee, color: Colors.green.shade300, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                keyboardType: TextInputType.number,
              ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: saleItem.qtyController,
                  onChanged: (value) {
                    _calculateItemTotal(saleItem);
                    _calculateAmountDueSales();
                  },
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: "Qty",
                    labelStyle: const TextStyle(fontSize: 13),
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
                  items: _units.map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (val) => setState(() => saleItem.selectedUnit = val!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: saleItem.pcsController,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: "Pcs",
              labelStyle: const TextStyle(fontSize: 13),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 8),
          // Show item total
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Item Total:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Text("₹ ${saleItem.itemTotal.toStringAsFixed(2)}", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
void _calculateItemTotal(SaleItem saleItem) {
    final qty = _evaluateExpression(saleItem.qtyController.text);
    final rate = double.tryParse(saleItem.rateController.text) ?? 0.0;
    setState(() {
      saleItem.itemTotal = qty * rate;
    });
    // Also call the main calculation to update total and due amounts
    _calculateAmountDueSales();
  }

  Widget _buildOtherTextField({required TextEditingController controller, required String label, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
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
        const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 10);
        const cellStyle = TextStyle(fontSize: 9);
        return Column(
          children: [
            Text("Waitlisted Sales", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
            const SizedBox(height: 8),
            Card(
              elevation: 4,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  dataRowMinHeight: 30,
                  dataRowMaxHeight: double.infinity,
                  columns: const [
                    DataColumn(label: Text("Item", style: headerStyle)),
                    DataColumn(label: Text("Client", style: headerStyle)),
                    DataColumn(label: Text("Qty", style: headerStyle)),
                    DataColumn(label: Text("Actions", style: headerStyle)),
                  ],
                  rows: snapshot.data!.map((row) => DataRow(cells: [
                    DataCell(Text(row['item'], style: cellStyle)),
                    DataCell(Text(row['clint'], style: cellStyle)),
                    DataCell(Text("${row['quantity']} ${row['unit']}", style: cellStyle)),
                    DataCell(Row(
                      children: [
                        IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 18), onPressed: () => _editWaitlistedItem(row)),
                        IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => deleteWaitlistedSale(row['id']).then((_) => setState(() {}))),
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
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("No recent sales", style: TextStyle(fontSize: 12)));
        const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 10);
        const cellStyle = TextStyle(fontSize: 9);
        return Card(
          elevation: 4,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              dataRowMinHeight: 30,
              dataRowMaxHeight: double.infinity,
              columns: const [
                DataColumn(label: Text("Item", style: headerStyle)),
                DataColumn(label: Text("Client", style: headerStyle)),
                DataColumn(label: Text("Qty", style: headerStyle)),
                DataColumn(label: Text("Rate", style: headerStyle)),
                DataColumn(label: Text("Total", style: headerStyle)),
                DataColumn(label: Text("Payment Status", style: headerStyle)),
                DataColumn(label: Text("Paid", style: headerStyle)),
                DataColumn(label: Text("Due", style: headerStyle)),
                DataColumn(label: Text("Mode", style: headerStyle)),
                DataColumn(label: Text("Ctrl Date", style: headerStyle)),
              ],
              rows: snapshot.data!.map((row) => DataRow(cells: [
                DataCell(Text(row['item'] ?? '', style: cellStyle)),
                DataCell(Text(row['clint'] ?? '', style: cellStyle)),
                DataCell(Text("${row['quantity'] ?? ''} ${row['unit'] ?? ''}", style: cellStyle)),
                DataCell(Text(row['rate']?.toString() ?? '0.0', style: cellStyle)),
                DataCell(Text(row['total_value']?.toString() ?? '0.0', style: cellStyle)),
                DataCell(
                  Text(
                    row['payment_status']?.toString() ?? 'Unpaid',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: row['payment_status'] == 'Paid' 
                          ? Colors.green 
                          : (row['payment_status'] == 'Partial Paid' ? Colors.orange : Colors.red),
                    ),
                  ),
                ),
                DataCell(Text(row['amount_paid']?.toString() ?? '0.0', style: const TextStyle(fontSize: 9, color: Colors.green))),
                DataCell(Text(row['amount_due']?.toString() ?? '0.0', style: const TextStyle(fontSize: 9, color: Colors.red))),
                DataCell(Text(row['mode_of_payment']?.toString() ?? '-', style: cellStyle)),
                DataCell(Text(row['date'] ?? '', style: cellStyle)),
              ])).toList(),
            ),
          ),
        );
      },
    );
  }
}
