import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'payment_page.dart';

// const String apiBaseUrl = 'http://13.53.71.103:5000/';
const String apiBaseUrl = 'http://10.0.2.2:5000';

// API Helper Functions
Future<List<String>> getPurchaseVendors() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_purchase_vendors'));
  if (response.statusCode == 200) {
    return List<String>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load purchase vendors');
  }
}

Future<List<Map<String, dynamic>>> getLatestGeneratedPOs({int limit = 10}) async {
  final queryParams = {'limit': limit.toString()};
  final uri = Uri.parse('$apiBaseUrl/get_latest_generated_pos').replace(queryParameters: queryParams);
  final response = await http.get(uri);
  if (response.statusCode == 200) {
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load latest generated POs');
  }
}

Future<List<Map<String, dynamic>>> getLatestFmdData() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_latest_fmd_data'));
  if (response.statusCode == 200) {
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load latest FMD data');
  }
}

Future<void> insertPurchaseVendor(String name) async {
  final response = await http.post(
    Uri.parse('$apiBaseUrl/insert_purchase_vendor'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({'name': name}),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to insert purchase vendor');
  }
}

Future<void> updateFmdData(Map<String, dynamic> data) async {
  final response = await http.put(
    Uri.parse('$apiBaseUrl/update_fmd_data'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(data),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to update FMD data');
  }
}

Future<void> insertFmdData(Map<String, dynamic> data) async {
  final response = await http.post(
    Uri.parse('$apiBaseUrl/insert_fmd_data'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(data),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to insert FMD data');
  }
}

class FmdPage extends StatefulWidget {
  final Map<String, dynamic>? dataToEdit;
  const FmdPage({super.key, this.dataToEdit});

  @override
  State<FmdPage> createState() => _FmdPageState();
}

class _FmdEntry {
  String? selectedVendor;
  bool isOtherVendor = false;
  final vendorNameController = TextEditingController(); 
  final poNumberController = TextEditingController(); 
  final itemsController = TextEditingController();

  void dispose() {
    vendorNameController.dispose();
    poNumberController.dispose();
    itemsController.dispose();
  }

  void clear() {
    selectedVendor = null;
    isOtherVendor = false;
    vendorNameController.clear();
    poNumberController.clear();
    itemsController.clear();
  }
}

class _FmdPageState extends State<FmdPage> {
  final _formKey = GlobalKey<FormState>();
  late Future<List<Map<String, dynamic>>> _fmdDataFuture;

  final _vehicleNumberController = TextEditingController();
  final _driverNameController = TextEditingController();
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();

  DateTime? ctrlDate;

  final List<_FmdEntry> _entries = [];
  List<String> _vendorList = [];
  List<Map<String, dynamic>> _availablePOs = []; 
  bool _isLoading = true;

  Map<String, dynamic>? _paymentDetails;
  bool get _isEditMode => widget.dataToEdit != null;

  @override
  void initState() {
    super.initState();
    _entries.add(_FmdEntry());

    _loadInitialData().then((_) {
      if (_isEditMode) {
        _populateFields(widget.dataToEdit!);
      } else {
        _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
        _timeController.text = DateFormat('HH:mm:ss').format(DateTime.now());
      }
      _refreshData();
    });
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final vendors = await getPurchaseVendors();
      final pos = await getLatestGeneratedPOs(limit: 100);
      setState(() {
        _vendorList = ["Other", ...vendors.where((v) => v != "Other")].toSet().toList();
        _availablePOs = pos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _autoFillPO(int index) {
    final entry = _entries[index];
    final vendor = entry.selectedVendor;
    final date = _dateController.text;

    if (vendor != null && vendor != "Other" && date.isNotEmpty) {
      try {
        final match = _availablePOs.firstWhere((po) {
          final poVendor = (po['vendor_name'] ?? '').toString();
          final poDate = (po['date'] ?? '').toString();
          return poVendor.toLowerCase() == vendor.toLowerCase() && poDate.contains(date);
        });
        setState(() {
          entry.poNumberController.text = match['po_number'] ?? '';
          entry.itemsController.text = match['item_name'] ?? '';
        });
      } catch (e) {
        // No match found
      }
    }
  }

  void _populateFields(Map<String, dynamic> data) {
    _vehicleNumberController.text = data['vehicle_number'] ?? '';
    _driverNameController.text = data['driver_name'] ?? '';
    _dateController.text = data['date'] ?? '';
    _timeController.text = data['time'] ?? '';

    // Populate ctrl_date if exists
    if (data['ctrl_date'] != null && data['ctrl_date'].toString().isNotEmpty) {
      try {
        ctrlDate = DateTime.parse(data['ctrl_date']);
      } catch (e) {
        ctrlDate = null;
      }
    }

    String vendorName = data['vendor_name'] ?? '';
    if (_vendorList.contains(vendorName)) {
      _entries.first.selectedVendor = vendorName;
    } else {
      _entries.first.selectedVendor = "Other";
      _entries.first.isOtherVendor = true;
      _entries.first.vendorNameController.text = vendorName;
    }

    _entries.first.poNumberController.text = data['po_number'] ?? '';
    _entries.first.itemsController.text = data['items'] ?? '';

    _paymentDetails = data;
  }

  void _refreshData() {
    setState(() {
      _fmdDataFuture = getLatestFmdData();
    });
  }

  @override
  void dispose() {
    _vehicleNumberController.dispose();
    _driverNameController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  void _addEntry() {
    setState(() {
      _entries.add(_FmdEntry());
    });
  }

  void _removeEntry(int index) {
    if (_entries.length > 1) {
      setState(() {
        _entries[index].dispose();
        _entries.removeAt(index);
      });
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _vehicleNumberController.clear();
    _driverNameController.clear();

    for (int i = _entries.length - 1; i > 0; i--) {
      _entries[i].dispose();
      _entries.removeAt(i);
    }
    _entries.first.clear();

    setState(() {
      _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _timeController.text = DateFormat('HH:mm:ss').format(DateTime.now());
      _paymentDetails = null;
    });
  }

  void _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (ctrlDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Please select CTRL date."),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    List<String> finalVendorNames = [];
    for (var entry in _entries) {
      String name = entry.isOtherVendor ? entry.vendorNameController.text.trim() : entry.selectedVendor ?? '';
      if (entry.isOtherVendor && name.isNotEmpty) {
        await insertPurchaseVendor(name);
      }
      finalVendorNames.add(name);
    }

    final vendorNamesStr = finalVendorNames.where((s) => s.isNotEmpty).join(', ');
    final poNumbers = _entries.map((e) => e.poNumberController.text.trim()).where((s) => s.isNotEmpty).join(', ');
    final items = _entries.map((e) => e.itemsController.text.trim()).where((s) => s.isNotEmpty).join(', ');

    final data = {
      'vehicle_number': _vehicleNumberController.text,
      'driver_name': _driverNameController.text,
      'date': _dateController.text,
      'time': _timeController.text,
      'vendor_name': vendorNamesStr,
      'vendor_location': '', 
      'po_number': poNumbers,
      'items': items,
      'vehicle_type': _paymentDetails?['vehicle_type'],
      'booking_person': _paymentDetails?['booking_person'],
      'km': _paymentDetails?['km'],
      'price_per_km': _paymentDetails?['price_per_km'],
      'extra_expenses': _paymentDetails?['extra_expenses'],
      'reason': _paymentDetails?['reason'],
      'total_amount': _paymentDetails?['total_amount'],
      'payment_status': _paymentDetails?['payment_status'],
      'mode_of_payment': _paymentDetails?['mode_of_payment'],
      'amount_paid': _paymentDetails?['amount_paid'],
      'amount_due': _paymentDetails?['amount_due'],
      'ctrl_date': ctrlDate != null ? DateFormat('yyyy-MM-dd').format(ctrlDate!) : null,
    };

    if (_isEditMode) {
      data['id'] = widget.dataToEdit!['id'];
      await updateFmdData(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('FMD Data Updated Successfully!'), backgroundColor: Colors.blue));
        Navigator.of(context).pop();
      }
    } else {
      await insertFmdData(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('FMD Data Saved Successfully!'), backgroundColor: Colors.green));
      }
      _resetForm();
      _loadInitialData();
      _refreshData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit FMD Entry' : 'FMD - Book Logistics (PO Link)'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildForm(theme),
            ),
          ),
          if (!_isEditMode) ...[
            const SizedBox(height: 24),
            Text('Recent Entries', style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 10),
            _buildDataTable(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        children: <Widget>[
          _buildTextFormField(_vehicleNumberController, 'Vehicle Number', Icons.local_shipping, theme, isRequired: true),
          const SizedBox(height: 16),
          _buildTextFormField(_driverNameController, 'Driver Name', Icons.person_pin_rounded, theme, isRequired: true),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildTextFormField(
                  _dateController, 
                  'Date', 
                  Icons.calendar_today, 
                  theme, 
                  isRequired: true, 
                  readOnly: true,
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
                      });
                      for (int i = 0; i < _entries.length; i++) {
                        _autoFillPO(i);
                      }
                    }
                  }
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: _buildTextFormField(_timeController, 'Time', Icons.access_time, theme, isRequired: true, readOnly: true)),
            ],
          ),
          const SizedBox(height: 16),
          _buildCtrlDateButton(theme),
          const SizedBox(height: 24),
          ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: _entries.length,
            itemBuilder: (context, index) => _buildFmdEntry(index, theme),
          ),
          const SizedBox(height: 16),
          if (!_isEditMode)
            TextButton.icon(icon: const Icon(Icons.add_business_outlined), label: const Text('Add Another Vendor'), onPressed: _addEntry),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.payment),
            label: const Text('Proceed to Payment'),
            onPressed: () async {
              final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => PaymentPage(initialData: _paymentDetails)));
              if (result != null) setState(() => _paymentDetails = result);
            },
            style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.secondary, foregroundColor: theme.colorScheme.onSecondary, minimumSize: const Size(double.infinity, 50)),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _submitForm, style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)), child: Text(_isEditMode ? 'Update' : 'Submit')),
        ],
      ),
    );
  }

  Widget _buildFmdEntry(int index, ThemeData theme) {
    final entry = _entries[index];
    final poNumbers = _availablePOs.map((e) => e['po_number']?.toString() ?? "").where((s) => s.isNotEmpty).toSet().toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(side: BorderSide(color: theme.dividerColor), borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Vendor Entry ${index + 1}', style: theme.textTheme.titleMedium),
                if (index > 0 && !_isEditMode) IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => _removeEntry(index)),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: entry.selectedVendor,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Vendor Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.business)),
              items: _vendorList.map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (val) => setState(() { 
                entry.selectedVendor = val; 
                entry.isOtherVendor = val == "Other"; 
                _autoFillPO(index);
              }),
              validator: (val) => val == null ? 'Required' : null,
            ),
            if (entry.isOtherVendor)
              Padding(padding: const EdgeInsets.only(top: 16.0), child: _buildTextFormField(entry.vendorNameController, 'Enter New Vendor Name', Icons.edit_note, theme, isRequired: true)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: poNumbers.contains(entry.poNumberController.text) ? entry.poNumberController.text : "",
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Linked PO Number', border: OutlineInputBorder(), prefixIcon: Icon(Icons.receipt_long)),
              items: [const DropdownMenuItem(value: "", child: Text("None")), ...poNumbers.map((s) => DropdownMenuItem(value: s, child: Text(s)))],
              onChanged: (val) {
                setState(() {
                  entry.poNumberController.text = val ?? "";
                  if (val != null && val.isNotEmpty) {
                    final poMatch = _availablePOs.firstWhere((e) => e['po_number'] == val, orElse: () => {});
                    entry.itemsController.text = poMatch['item_name'] ?? '';
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            _buildTextFormField(entry.itemsController, 'Items', Icons.inventory_2, theme, isRequired: true),
          ],
        ),
      ),
    );
  }

  Widget _buildCtrlDateButton(ThemeData theme) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_month_outlined, color: Colors.teal),
      onPressed: () async {
        DateTime? pickedDate = await showDatePicker(
          context: context,
          initialDate: ctrlDate ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (pickedDate != null) {
          setState(() => ctrlDate = pickedDate);
        }
      },
      label: Text(
        ctrlDate == null ? 'Select CTRL Date' : 'CTRL: ${DateFormat('dd-MM-yy').format(ctrlDate!)}',
        style: TextStyle(color: ctrlDate == null ? Colors.black54 : Colors.teal.shade700),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: BorderSide(color: ctrlDate == null ? Colors.grey.shade400 : Colors.teal),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildTextFormField(TextEditingController controller, String label, IconData icon, ThemeData theme, {bool isRequired = false, bool readOnly = false, VoidCallback? onTap}) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), prefixIcon: Icon(icon, color: theme.colorScheme.primary)),
      validator: (value) => (isRequired && (value == null || value.isEmpty)) ? 'Required' : null,
      readOnly: readOnly,
      onTap: onTap,
    );
  }

  Widget _buildDataTable(ThemeData theme) {
    return Card(
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fmdDataFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text('No entries found.')));
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: ['Vehicle', 'Driver', 'Vendors', 'PO Linked', 'Due'].map((col) => DataColumn(label: Text(col, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
              rows: snapshot.data!.map((row) => DataRow(cells: [
                DataCell(Text(row['vehicle_number'] ?? '')),
                DataCell(Text(row['driver_name'] ?? '')),
                DataCell(Text(row['vendor_name'] ?? '')),
                DataCell(Text(row['po_number'] ?? '-')),
                DataCell(Text(row['amount_due']?.toString() ?? '0.0')),
              ])).toList(),
            ),
          );
        },
      ),
    );
  }
}
