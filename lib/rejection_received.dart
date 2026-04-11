import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer' as developer;

import 'api_config.dart';

class RejectionItem {
  String? selectedItem;
  String selectedUnit = 'Kg';
  final TextEditingController itemTagController = TextEditingController();
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController pcsController = TextEditingController();
  final TextEditingController sampleQtyController = TextEditingController();
  final TextEditingController soNumberController = TextEditingController();
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

  DateTime? ctrlDate;
  DateTime? selectedSaleDate;
  String? _selectedClient;
  
  List<RejectionItem> rejectionItems = [];
  List<Map<String, dynamic>> _allSales = [];
  bool _isLoadingDateSales = false;  // NEW: Date-specific loading
  
  // 🔄 NEW: Fallback global lists
  List<String> _globalClients = [];
  List<String> _globalItems = [];
  bool _hasDateSalesData = false; // Track if date-specific data found
  List<String> _recentDates = []; // Recent dates with sales
  String? _dateLoadError;  // NEW: Date fetch error
  List<String> _dateClients = [];  // Date-specific clients
  List<String> _dateItems = [];    // Date-specific items
  
  final List<String> units = ["Kg", "g", "pcs", "L", "ml"];
  bool _isLoading = true;
  String? _apiError; // Error state

  Future<List<Map<String, dynamic>>>? _latestRejections;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  // 🔄 NEW: Load global lists + recent dates
  // Future<void> _loadGlobalData() async {
  //   try {
  //     final results = await Future.wait([
  //       http.get(Uri.parse('$baseUrl/get_b_grade_clients')),
  //       http.get(Uri.parse('$baseUrl/get_items')),
  //       _getRecentSalesDates(), // Custom method
  //     ]);

  //     if (results.every((r) => r.statusCode == 200) && mounted) {
  //       setState(() {
  //         _globalClients = List<String>.from(json.decode(results[0].body));
  //         _globalItems = List<String>.from(json.decode(results[1].body));
  //         _recentDates = List<String>.from(json.decode(results[2].body));
          
  //         // Ensure "Other" option
  //         if (!_globalClients.contains("Other")) _globalClients.insert(0, "Other");
  //         _globalItems.sort();
  //         _globalClients.sort();
          
  //         if (selectedSaleDate != null && rejectionItems.isEmpty) {
  //           _addNewItem();
  //         }
  //       });
  //     }
  //   } catch (e) {
  //     developer.log('Global data load error: $e');
  //   }
  // }


  Future<void> _loadGlobalData() async {
    try {
      final results = await Future.wait([
        http.get(Uri.parse('$baseUrl/get_b_grade_clients')),
        http.get(Uri.parse('$baseUrl/get_items')),
        _getRecentSalesDates(),
      ]);

      final response1 = results[0] as http.Response;
      final response2 = results[1] as http.Response;
      final response3 = results[2] as http.Response;

      if (response1.statusCode == 200 &&
          response2.statusCode == 200 &&
          response3.statusCode == 200 &&
          mounted) {
        setState(() {
          _globalClients = List<String>.from(json.decode(response1.body));
          _globalItems = List<String>.from(json.decode(response2.body));
          _recentDates = List<String>.from(json.decode(response3.body));

          if (!_globalClients.contains("Other")) _globalClients.insert(0, "Other");
          _globalItems.sort();
          _globalClients.sort();

          if (selectedSaleDate != null && rejectionItems.isEmpty) {
            _addNewItem();
          }
        });
      }
    } catch (e) {
      developer.log('Global data load error: $e');
    }
  }



  // 🔄 NEW: Get recent sales dates
  Future<List<String>> _getRecentSalesDates() async {
    try {
      // Using existing paginated endpoint for last 30 days
      final result = await http.get(Uri.parse('$baseUrl/get_all_sales?per_page=100'));
      if (result.statusCode == 200) {
        final data = json.decode(result.body);
        final dates = <String>{};
        for (var sale in (data['data'] ?? [])) {
          dates.add(sale['date'].split(' ')[0]); // YYYY-MM-DD
        }
        return dates.toList()..sort((a, b) => DateTime.parse(b).compareTo(DateTime.parse(a)));
      }
    } catch (e) {
      developer.log('Recent dates error: $e');
    }
    return [];
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    await Future.wait([_loadGlobalData(), _loadRejections()]);
    if (mounted) {
      setState(() => _isLoading = false);
      if (rejectionItems.isEmpty) _addNewItem();
    }
  }

  Future<void> _loadRejections() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/get_latest_rejection_received'));
      List<Map<String, dynamic>> latestRejections = [];
      if (response.statusCode == 200) {
        try {
          final rejData = json.decode(response.body);
          if (rejData is List) {
            latestRejections = rejData.cast<Map<String, dynamic>>();
          } else if (rejData['data'] != null) {
            latestRejections = List<Map<String, dynamic>>.from(rejData['data']);
          }
        } catch (e) {
          developer.log('Rejections JSON error: $e');
        }
      }
      if (mounted) {
        setState(() => _latestRejections = Future.value(latestRejections));
      }
    } catch (e) {
      developer.log('Load rejections error: $e');
    }
  }

Future<Map<String, dynamic>> _fetchPageSalesForDate(
    String dateStr, {
    int page = 1,
    int limit = 200,  // Increased for full data
    String? search,
  }) async {
    final queryParams = {
      'date': dateStr,
      'page': page.toString(),
      'limit': limit.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
    };

    final uri = Uri.parse('$baseUrl/get_sales_for_date').replace(queryParameters: queryParams);
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      try {
        return json.decode(response.body);
      } catch (e) {
        developer.log('Sales JSON error: $e');
      }
    } else {
      developer.log('Sales API error ${response.statusCode}');
    }
    return {'data': [], 'has_more': false};
  }

  Future<List<Map<String, dynamic>>> _fetchAllSalesForDate(
    String dateStr, {
    String? search,
    int maxPages = 100,  // Increased safety limit
  }) async {
    List<Map<String, dynamic>> allSales = [];
    int page = 1;
    const int limit = 200;
    bool hasMore = true;
    int totalPages = 0;

    while (hasMore && page <= maxPages) {
      final result = await _fetchPageSalesForDate(dateStr, page: page, limit: limit, search: search);
      final data = List<Map<String, dynamic>>.from(result['data'] ?? []);
      allSales.addAll(data);
      hasMore = (result['has_more'] ?? false) || data.length == limit;
      totalPages = page;
      developer.log('Page $page: ${data.length} sales, hasMore: $hasMore, total: ${allSales.length}');
      page++;
      await Future.delayed(const Duration(milliseconds: 100));
    }

    developer.log('✅ FULL FETCH: ${allSales.length} sales for $dateStr across $totalPages pages');
    return allSales;
  }

Future<void> _onSaleDateChanged(DateTime? date) async {
    if (date == null) return;
    
    setState(() {
      selectedSaleDate = date;
      _selectedClient = null;
      _hasDateSalesData = false;
      _allSales = [];
      _isLoadingDateSales = true;
      _dateLoadError = null;
      rejectionItems.clear();
      _dateClients.clear();
      _dateItems.clear();
    });

    final saleDateStr = DateFormat('yyyy-MM-dd').format(date);
    
    try {
      // Fetch ALL pages for date
      final allSalesForDate = await _fetchAllSalesForDate(saleDateStr);
      
      final uniqueClients = allSalesForDate
        .map((sale) => sale['clint']?.toString() ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()..sort();
      
      final uniqueItems = allSalesForDate
        .map((sale) => sale['item']?.toString() ?? '')
        .where((i) => i.isNotEmpty)
        .toSet()
        .toList()..sort();
      
      developer.log('✅ FULL LOAD: ${allSalesForDate.length} sales, ${uniqueClients.length} clients, ${uniqueItems.length} items for $saleDateStr');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Loaded ${allSalesForDate.length} sales, ${uniqueClients.length} clients'),
          duration: const Duration(seconds: 3),
        ));
        
        setState(() {
          _allSales = allSalesForDate;
          _hasDateSalesData = allSalesForDate.isNotEmpty;
          _isLoadingDateSales = false;
          _dateClients = ["Other", ...uniqueClients];
          _dateItems = uniqueItems;
        });
        
        _addNewItem();
      }
    } catch (e) {
      developer.log('Date sales fetch error: $e');
      if (mounted) {
        setState(() {
          _isLoadingDateSales = false;
          _dateLoadError = 'Failed to load date sales: $e';
        });
      }
    }
  }

  void _onClientChanged(String? client) {
    setState(() {
      _selectedClient = client;
      
      // Filter items for selected client from date sales
      List<String> clientItems = [];
      if (_allSales.isNotEmpty && client != null) {
        clientItems = _allSales
            .where((sale) => sale['clint']?.toString() == client)
            .map((sale) => sale['item']?.toString() ?? '')
            .where((i) => i.isNotEmpty)
            .toSet()
            .toList();
        developer.log('Client $client: Found ${clientItems.length} items in date sales');
      }
      
      // Fallback if no date/client specific items
      if (clientItems.isEmpty && _dateItems.isNotEmpty) {
        clientItems = List<String>.from(_dateItems);
      } else if (clientItems.isEmpty) {
        clientItems = List<String>.from(_globalItems);
      }
      
      clientItems.sort();
      
      // Update ALL rejection items
      for (var item in rejectionItems) {
        item.availableItems = clientItems;
        if (!clientItems.contains(item.selectedItem)) {
          item.selectedItem = null;
          item.itemTagController.clear();
          item.soNumberController.clear();
        }
      }
      
      developer.log('Updated ${_dateClients.length} clients, ${clientItems.length} items for UI');
    });
  }

  void _onItemChanged(RejectionItem item, String? itemName) {
    if (itemName == null || _selectedClient == null || _allSales.isEmpty) return;
    
    final sale = _allSales.firstWhere(
      (s) => s['clint']?.toString() == _selectedClient && s['item']?.toString() == itemName,
      orElse: () => <String, dynamic>{},
    );
    
    setState(() {
      item.itemTagController.text = sale['item_tag'] ?? '';
      item.soNumberController.text = sale['po_number'] ?? '';
    });
  }

  @override
  void dispose() {
    for (var item in rejectionItems) item.dispose();
    super.dispose();
  }

  void _addNewItem() {
    final newItem = RejectionItem();
    
    // Smart item list: date/client → date items → global
    List<String> clientItems = [];
    if (_selectedClient != null && _allSales.isNotEmpty) {
      clientItems = _allSales
          .where((sale) => sale['clint']?.toString() == _selectedClient)
          .map((sale) => sale['item']?.toString() ?? '')
          .where((i) => i.isNotEmpty)
          .toSet()
          .toList();
    }
    if (clientItems.isEmpty && _dateItems.isNotEmpty) {
      clientItems = List<String>.from(_dateItems);
    }
    if (clientItems.isEmpty) {
      clientItems = List<String>.from(_globalItems);
    }
    clientItems.sort();
    
    newItem.availableItems = clientItems;
    developer.log('New item availableItems: ${clientItems.length}');
    
    setState(() => rejectionItems.add(newItem));
  }

  void _removeItem(int index) {
    if (rejectionItems.length > 1) {
      rejectionItems[index].dispose();
      setState(() => rejectionItems.removeAt(index));
    }
  }

  double _evaluateExpression(String expression) {
    if (expression.trim().isEmpty) return 0.0;
    String sanitized = expression.replaceAll('x', '*').replaceAll('X', '*');
    if (['+','-','*','/'].any((op) => sanitized.endsWith(op))) {
      sanitized = sanitized.substring(0, sanitized.length - 1);
    }
    try {
      final exp = Parser().parse(sanitized);
      final cm = ContextModel();
      return exp.evaluate(EvaluationType.REAL, cm);
    } catch (e) {
      return 0.0;
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate() || ctrlDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill required fields and select CTRL date.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    final saleDateStr = selectedSaleDate != null ? DateFormat('yyyy-MM-dd').format(selectedSaleDate!) : '';
    if (saleDateStr.isEmpty || _selectedClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select Sale Date and Client.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    final formattedTime = TimeOfDay.now().format(context);

    for (var item in rejectionItems) {
      final qty = _evaluateExpression(item.qtyController.text);
      final pcs = item.pcsController.text.isNotEmpty ? _evaluateExpression(item.pcsController.text) : null;
      final sampleQty = item.sampleQtyController.text.isNotEmpty ? _evaluateExpression(item.sampleQtyController.text) : null;

      final data = {
        'client_name': _selectedClient,
        'item': item.selectedItem,
        'po_number': item.soNumberController.text,
        'item_tag': item.itemTagController.text,
        'quantity': qty,
        'unit': item.selectedUnit,
        'pcs': pcs,
        'sample_quantity': sampleQty,
        'reason': item.reasonController.text,
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'time': formattedTime,
        'ctrl_date': DateFormat('yyyy-MM-dd').format(ctrlDate!),
      };

      await http.post(
        Uri.parse('$baseUrl/insert_rejection_received'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Rejection saved successfully!'), backgroundColor: Colors.green),
      );
      
      _formKey.currentState!.reset();
      for (var item in rejectionItems) item.dispose();
      setState(() {
        rejectionItems = [];
        ctrlDate = null;
        _selectedClient = null;
      });
      _addNewItem();
      _loadRejections();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Rejection Received", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.red.shade600, Colors.pink.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 4,
      ),
  body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : RefreshIndicator(
              onRefresh: _loadInitialData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // NEW: Date-specific loading/error banner
                    if (_isLoadingDateSales)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text('Loading all sales for ${DateFormat('dd-MM-yyyy').format(selectedSaleDate!)}...', style: const TextStyle(fontSize: 14))),
                          ],
                        ),
                      )
                    else if (_dateLoadError != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_dateLoadError!, style: const TextStyle(fontSize: 13))),
                            TextButton(
                              onPressed: () => _onSaleDateChanged(selectedSaleDate),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    else if (selectedSaleDate != null && _allSales.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '✅ Loaded ${_allSales.length} sales for ${DateFormat('dd-MM-yyyy').format(selectedSaleDate!)}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                
                    // 🔄 NEW: Status Banner
                    if (_apiError != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.orange.shade800),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_apiError!, style: const TextStyle(fontSize: 13))),
                          ],
                        ),
                      ),
                    
                    // 🔄 NEW: Recent Dates Chip
                    if (_recentDates.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Recent Sales Dates:', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              children: _recentDates.take(7).map((dateStr) {
                                final date = DateTime.parse(dateStr);
                                return ChoiceChip(
                                  label: Text(DateFormat('dd-MM').format(date)),
                                  selected: selectedSaleDate?.toIso8601String().split('T')[0] == dateStr,
                                  onSelected: (_) => _onSaleDateChanged(date),
                                  backgroundColor: Colors.white,
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),

                    Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildTopSelectionSection(theme),
                              
                              // 🔄 ENHANCED: Warning Banner for Empty Date Data (now accurate with full fetch)
                              if (selectedSaleDate != null && !_hasDateSalesData && _globalClients.isNotEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.amber.shade300),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'ℹ️ No sales found for ${DateFormat('dd-MM-yyyy').format(selectedSaleDate!)}. Showing all available clients & items.',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              const Divider(height: 32, thickness: 1),
                              
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: rejectionItems.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 16),
                                itemBuilder: (context, index) => _buildItemEntry(index, theme),
                              ),
                              
                              const SizedBox(height: 16),
                              if (rejectionItems.isNotEmpty)
                                TextButton.icon(
                                  icon: const Icon(Icons.add_circle_outline, color: Colors.red),
                                  label: const Text("Add More Items", style: TextStyle(fontSize: 14)),
                                  onPressed: _addNewItem,
                                ),
                              
                              const SizedBox(height: 24),
                              _buildCtrlDateButton(theme),
                              const SizedBox(height: 30),
                              
                              ElevatedButton.icon(
                                icon: const Icon(Icons.send_outlined, color: Colors.white),
                                label: const Text("Submit Rejection", style: TextStyle(fontWeight: FontWeight.bold)),
                                onPressed: _submitForm,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  backgroundColor: Colors.red.shade700,
                                  foregroundColor: Colors.white,
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
                    Text(
                      "Recent Rejections",
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    _buildRejectionsTable(theme),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTopSelectionSection(ThemeData theme) {
    return Column(
      children: [
        // Sale Date Picker
        Card(
          child: ListTile(
            leading: const Icon(Icons.calendar_today, color: Colors.red),
            title: Text(
              selectedSaleDate == null 
                ? 'Select Sale Date' 
                : 'Sale Date: ${DateFormat('dd-MM-yyyy').format(selectedSaleDate!)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            trailing: const Icon(Icons.arrow_drop_down),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: selectedSaleDate ?? DateTime.now(),
                firstDate: DateTime(2024),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) _onSaleDateChanged(picked);
            },
          ),
        ),
        const SizedBox(height: 18),
        
        // Client Dropdown - Date-specific first
        DropdownButtonFormField<String>(
          decoration: InputDecoration(
            labelText: "Select Client",
            labelStyle: const TextStyle(fontSize: 13),
            prefixIcon: const Icon(Icons.person_outline, color: Colors.red),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
            hintText: (_dateClients.isEmpty && _globalClients.isEmpty) ? 'Loading...' : null,
            hintStyle: TextStyle(color: Colors.grey.shade500),
          ),
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          value: _selectedClient,
          items: (_dateClients.isNotEmpty 
            ? _dateClients 
            : [..._globalClients, "Other"]
          ).map((c) => 
            DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))
          ).toList(),
          onChanged: _onClientChanged,
          validator: (val) => val == null ? "Select client" : null,
          isExpanded: true,
          isDense: true,
        ),
      ],
    );
  }

  Widget _buildItemEntry(int index, ThemeData theme) {
    final item = rejectionItems[index];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 4)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: "Item",
                    labelStyle: const TextStyle(fontSize: 13),
                    prefixIcon: const Icon(Icons.inventory_2, color: Colors.red, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    hintText: item.availableItems.isEmpty ? 'Loading items...' : null,
                  ),
                  value: item.selectedItem,
                  items: item.availableItems.map((e) => 
                    DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))
                  ).toList(),
                  onChanged: (val) => _onItemChanged(item, val),
                  validator: (val) => val == null || val!.isEmpty ? "Select item" : null,
                  isDense: true,
                ),
              ),
              if (rejectionItems.length > 1)
                IconButton(
                  icon: const Icon(Icons.remove_circle, color: Colors.red),
                  onPressed: () => _removeItem(index),
                ),
            ],
          ),
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(child: _buildExpressionField(item.itemTagController, 'Item Tag', Icons.tag, isOptional: true)),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(
                controller: item.soNumberController,
                decoration: InputDecoration(
                  labelText: 'SO # (Auto)',
                  labelStyle: TextStyle(fontSize: 13),
                  prefixIcon: Icon(Icons.receipt, color: Colors.green, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: Colors.green.shade50,
                ),
                readOnly: true,
              )),
            ],
          ),
          const SizedBox(height: 16),
          _buildQuantityField(item.qtyController, item, 'Quantity'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildExpressionField(item.pcsController, 'Pcs', Icons.numbers, isOptional: true)),
              const SizedBox(width: 12),
              Expanded(child: _buildExpressionField(item.sampleQtyController, 'Sample Qty', Icons.science, isOptional: true)),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: item.reasonController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Reason *',
              labelStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(Icons.comment, color: Colors.red),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: (val) => val?.trim().isEmpty ?? true ? 'Reason required' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityField(TextEditingController controller, RejectionItem item, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        prefixIcon: const Icon(Icons.numbers, color: Colors.blue),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: Colors.grey.shade50,
        suffixIcon: DropdownButtonHideUnderline(
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: DropdownButton<String>(
              value: item.selectedUnit,
              items: units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
              onChanged: (val) => setState(() => item.selectedUnit = val ?? 'Kg'),
              iconSize: 20,
            ),
          ),
        ),
      ),
      validator: (val) {
        if (val?.trim().isEmpty ?? true) return 'Quantity required';
        final qty = _evaluateExpression(val!);
        if (qty <= 0) return 'Valid quantity required';
        return null;
      },
    );
  }

  Widget _buildExpressionField(TextEditingController controller, String label, IconData icon, {bool isOptional = false}) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.red.shade400),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      validator: (val) {
        if (val == null || val.isEmpty) return isOptional ? null : 'Required';
        try {
          _evaluateExpression(val);
        } catch (e) {
          return 'Invalid expression';
        }
        return null;
      },
    );
  }

  Widget _buildCtrlDateButton(ThemeData theme) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_month, color: Colors.teal),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: ctrlDate ?? DateTime.now(),
          firstDate: DateTime(2024),
          lastDate: DateTime.now().add(const Duration(days: 30)),
        );
        if (picked != null) setState(() => ctrlDate = picked);
      },
      label: Text(
        ctrlDate == null ? 'Select CTRL Date *' : 'CTRL: ${DateFormat('dd-MM-yy').format(ctrlDate!)}',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: Colors.teal),
      ),
    );
  }

  Widget _buildRejectionsTable(ThemeData theme) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _latestRejections,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          
          final rejections = snapshot.data ?? [];
          if (rejections.isEmpty) {
            return const SizedBox(
              height: 80,
              child: Center(child: Text('No recent rejections')),
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.red.shade100),
              dataRowColor: WidgetStateProperty.resolveWith((states) => 
                states.contains(WidgetState.selected) ? Colors.blue.shade50 : null
              ),
              columns: const [
                DataColumn(label: Text('Client', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                DataColumn(label: Text('Item', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                DataColumn(label: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                DataColumn(label: Text('Reason', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
              ],
              rows: rejections.take(10).map((row) => DataRow(
                cells: [
                  DataCell(Text(row['client_name'] ?? '', style: const TextStyle(fontSize: 11))),
                  DataCell(Text(row['item'] ?? '', style: const TextStyle(fontSize: 11))),
                  DataCell(Text('${row['quantity'] ?? 0} ${row['unit'] ?? ''}', style: const TextStyle(fontSize: 11))),
                  DataCell(Text(row['reason'] ?? '', style: const TextStyle(fontSize: 11), maxLines: 2)),
                  DataCell(Text(DateFormat('dd-MM').format(DateTime.parse(row['date'] ?? '')), style: const TextStyle(fontSize: 11))),
                ],
              )).toList(),
            ),
          );
        },
      ),
    );
  }
}

