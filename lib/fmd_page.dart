import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'payment_page.dart';

import 'api_config.dart';

// API Helper Functions
// Future<List<String>> getPurchaseVendors() async {
//   final response = await http.get(Uri.parse('$apiBaseUrl/get_purchase_vendors'));


//   debugPrint("Vendor Body: ${response.body}");


//   if (response.statusCode == 200) {
//     return List<String>.from(json.decode(response.body));
//   } else {
//     throw Exception('Failed to load purchase vendors');
//   }
// }

Future<List<String>> getPurchaseVendors() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_purchase_vendors'));

  if (response.statusCode == 200) {
    final data = json.decode(response.body) as List;

    return data
        .map((e) => e['name'].toString())
        .toList();
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
  final _newDriverCtrl = TextEditingController();
  final _newVehicleCtrl = TextEditingController();
  bool _isOtherDriver = false;
  bool _isOtherVehicle = false;
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();

  final _gateNumberController = TextEditingController();
  DateTime? ctrlDate;

  final List<_FmdEntry> _entries = [];
  List<String> _vendorList = [];
  List<Map<String, dynamic>> _availablePOs = []; 
  List<String> _driverList = [];
  List<String> _vehicleList = [];
  bool _isLoading = true;

  Map<String, dynamic>? _paymentDetails;
  bool get _isEditMode => widget.dataToEdit != null;

  // @override
  // void initState() {
  //   super.initState();
  //   _entries.add(_FmdEntry());

  //   _loadInitialData().then((_) {
  //     if (_isEditMode) {
  //       _populateFields(widget.dataToEdit!);
  //     } else {
  //       _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
  //       _timeController.text = DateFormat('HH:mm:ss').format(DateTime.now());
  //     }
  //     _refreshData();
  //   });
  // }

  @override
  void initState() {
    super.initState();

    _entries.add(_FmdEntry());

    _loadInitialData().then((_) {
      if (_isEditMode) {
        _populateFields(widget.dataToEdit!);
      } else {
        // Current Date & Time automatically set
        final now = DateTime.now();
        _dateController.text = DateFormat('yyyy-MM-dd').format(now);
        _timeController.text = DateFormat('HH:mm:ss').format(now);
      }

      // Data table refresh
      _refreshData();
    });
  }





  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final List<Future> futures = [
        getPurchaseVendors(),
        getLatestGeneratedPOs(limit: 100),
        http.get(Uri.parse('$apiBaseUrl/get_drivers')),
        http.get(Uri.parse('$apiBaseUrl/get_vehicles')),
      ];
      
      // final results = await Future.wait(futures);

      final results = await Future.wait(futures);

      debugPrint("results[0] = ${results[0].runtimeType}");
      debugPrint("results[1] = ${results[1].runtimeType}");
      debugPrint("results[2] = ${results[2].runtimeType}");
      debugPrint("results[3] = ${results[3].runtimeType}");
      
      final vendors = results[0] as List<String>;
      final pos = results[1] as List<Map<String, dynamic>>;
      final driversResponse = results[2] as http.Response;
      final vehiclesResponse = results[3] as http.Response;
      
      final driversJson = json.decode(driversResponse.body);
      final vehiclesJson = json.decode(vehiclesResponse.body);


      debugPrint("Drivers Body: ${driversResponse.body}");
      debugPrint("Vehicles Body: ${vehiclesResponse.body}");
      debugPrint("Drivers Type: ${driversJson.runtimeType}");
      debugPrint("Vehicles Type: ${vehiclesJson.runtimeType}");
      
      
      final drivers = List<String>.from(driversJson).where((d) => d.isNotEmpty).toList();
      final vehicles = List<String>.from(vehiclesJson).where((v) => v.isNotEmpty).toList();
      debugPrint('FMD Loaded drivers: $drivers');
      debugPrint('FMD Loaded vehicles: $vehicles');
      
      setState(() {
        _vendorList = {"Other", ...vendors.where((v) => v != "Other")}.toList();
        _driverList = drivers.isEmpty ? ["Other"] : ["Other", ...drivers];
        _vehicleList = vehicles.isEmpty ? ["Other"] : ["Other", ...vehicles];
        _availablePOs = pos;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('FMD _loadInitialData error: $e');
      setState(() => _isLoading = false);
    }
  }

  void _autoFillPO(int index) {
    final entry = _entries[index];
    final vendor = entry.selectedVendor;
    final date = _dateController.text;

    if (vendor != null && vendor != "Other" && date.isNotEmpty) {
      // Filter POs by vendor and expected_date
      final matchingPOs = _availablePOs.where((po) {
        final poVendor = (po['vendor_name'] ?? '').toString().toLowerCase();
        final poExpectedDate = (po['expected_date'] ?? '').toString();
        return poVendor == vendor.toLowerCase() && poExpectedDate == date;
      }).toList();

      if (matchingPOs.isNotEmpty) {
        // Auto-fill the first one if there's only one match
        if (matchingPOs.length == 1) {
          setState(() {
            entry.poNumberController.text = matchingPOs.first['po_number'] ?? '';
            entry.itemsController.text = matchingPOs.first['item_name'] ?? '';
          });
        }
      }
    }
  }

  void _populateFields(Map<String, dynamic> data) {
    String vehicleNum = data['vehicle_number'] ?? '';
    if (_vehicleList.contains(vehicleNum) && vehicleNum.isNotEmpty) {
      _vehicleNumberController.text = vehicleNum;
    } else {
      _isOtherVehicle = true;
      _newVehicleCtrl.text = vehicleNum;
    }

    String driverName = data['driver_name'] ?? '';
    if (_driverList.contains(driverName) && driverName.isNotEmpty) {
      _driverNameController.text = driverName;
    } else {
      _isOtherDriver = true;
      _newDriverCtrl.text = driverName;
    }

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

    final gate = data['gate_number'];
    _gateNumberController.text = gate == null ? '' : gate.toString();

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
    _newDriverCtrl.dispose();
    _newVehicleCtrl.dispose();
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
    _newDriverCtrl.clear();
    _newVehicleCtrl.clear();
    _isOtherDriver = false;
    _isOtherVehicle = false;

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

    String finalVehicle = _isOtherVehicle ? _newVehicleCtrl.text.trim() : _vehicleNumberController.text;
    String finalDriver = _isOtherDriver ? _newDriverCtrl.text.trim() : _driverNameController.text;

    if (_isOtherVehicle && finalVehicle.isNotEmpty) {
      await http.post(Uri.parse('$apiBaseUrl/insert_vehicle'), body: json.encode({'number': finalVehicle}), headers: {'Content-Type': 'application/json'});
    }
    if (_isOtherDriver && finalDriver.isNotEmpty) {
      await http.post(Uri.parse('$apiBaseUrl/insert_driver'), body: json.encode({'name': finalDriver}), headers: {'Content-Type': 'application/json'});
    }

    final data = {
'vehicle_number': finalVehicle,
'gate_number': _gateNumberController.text.trim().isEmpty ? null : _gateNumberController.text.trim(),
      'driver_name': finalDriver,
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
        title: Text(_isEditMode ? 'Edit FMD Entry' : 'FMD - Book Logistics (PO Link)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            Text('Recent Entries', style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary, fontSize: 18)),
            const SizedBox(height: 10),
            _buildDataTable(theme),
          ],
        ],
      ),
    );
  }

  // Widget _buildDropdownField(
  //   TextEditingController controller,
  //   List<String> items,
  //   String label,
  //   IconData icon,
  //   ThemeData theme, {
  //   String? Function(String?)? validator,
  // }) {
  //   String? currentValue = controller.text.isEmpty ? null : controller.text;
  //   return DropdownButtonFormField<String>(
  //     initialValue: currentValue != null && items.contains(currentValue) ? currentValue : null,
  //     decoration: InputDecoration(
  //       labelText: label,
  //       labelStyle: const TextStyle(fontSize: 13),
  //       border: const OutlineInputBorder(),
  //       prefixIcon: Icon(icon, color: theme.colorScheme.primary, size: 20),
  //     ),
  //     style: const TextStyle(fontSize: 13, color: Colors.black),
  //     items: items.map((item) => DropdownMenuItem(
  //       value: item,
  //       child: Text(item, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
  //     )).toList(),
  //     onChanged: (String? newValue) {
  //       setState(() {
  //         controller.text = newValue ?? '';
  //       });
  //     },
  // validator: validator,
  //   );
  // }

  Widget _buildVehicleDropdown() {
    String? currentValue = _vehicleNumberController.text.isEmpty ? null : _vehicleNumberController.text;
    return DropdownButtonFormField<String>(
      initialValue: currentValue != null && _vehicleList.contains(currentValue) ? currentValue : null,
      decoration: InputDecoration(
        labelText: 'Vehicle Number *',
        labelStyle: const TextStyle(fontSize: 13),
        border: const OutlineInputBorder(),
        prefixIcon: Icon(Icons.local_shipping, color: Theme.of(context).colorScheme.primary, size: 20),
      ),
      style: const TextStyle(fontSize: 13, color: Colors.black),
      items: _vehicleList.map((item) => DropdownMenuItem(
        value: item,
        child: Text(item, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
      )).toList(),
      onChanged: (String? newValue) {
        setState(() {
          _vehicleNumberController.text = newValue ?? '';
          _isOtherVehicle = newValue == 'Other';
          if (newValue != 'Other') {
            _newVehicleCtrl.clear();
          }
        });
      },
      validator: (value) => value == null || value.isEmpty ? 'Vehicle required' : null,
    );
  }

  Widget _buildDriverDropdown() {
    String? currentValue = _driverNameController.text.isEmpty ? null : _driverNameController.text;
    return DropdownButtonFormField<String>(
      initialValue: currentValue != null && _driverList.contains(currentValue) ? currentValue : null,
      decoration: InputDecoration(
        labelText: 'Driver Name *',
        labelStyle: const TextStyle(fontSize: 13),
        border: const OutlineInputBorder(),
        prefixIcon: Icon(Icons.person_pin_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
      ),
      style: const TextStyle(fontSize: 13, color: Colors.black),
      items: _driverList.map((item) => DropdownMenuItem(
        value: item,
        child: Text(item, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
      )).toList(),
      onChanged: (String? newValue) {
        setState(() {
          _driverNameController.text = newValue ?? '';
          _isOtherDriver = newValue == 'Other';
          if (newValue != 'Other') {
            _newDriverCtrl.clear();
          }
        });
      },
      validator: (value) => value == null || value.isEmpty ? 'Driver required' : null,
    );
  }


  Widget _buildForm(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildVehicleDropdown(),
              if (_isOtherVehicle)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: _buildTextFormField(
                    _newVehicleCtrl,
                    'New Vehicle Number *',
                    Icons.add,
                    theme,
                    isRequired: true,
                    validator: (value) => value == null || value.isEmpty ? 'New vehicle number required' : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextFormField(
                _gateNumberController,
                'Gate Number',
                Icons.confirmation_num,
                theme,
                readOnly: false,
                isRequired: false,
                validator: (value) => null,
              ),
              const SizedBox(height: 16),
              _buildDriverDropdown(),
              if (_isOtherDriver)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: _buildTextFormField(
                    _newDriverCtrl,
                    'New Driver Name *',
                    Icons.person_add,
                    theme,
                    isRequired: true,
                    validator: (value) => value == null || value.isEmpty ? 'New driver name required' : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Row(
          //   children: [
          //     Expanded(
          //       child: _buildTextFormField(
          //         _dateController,
          //         'Date',
          //         Icons.calendar_today,
          //         theme,
          //         isRequired: true,
          //         readOnly: true,
          //         onTap: () async {
          //           DateTime? picked = await showDatePicker(
          //             context: context,
          //             initialDate: DateTime.now(),
          //             firstDate: DateTime(2000),
          //             lastDate: DateTime(2100),
          //           );
          //           if (picked != null) {
          //             setState(() {
          //               _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
          //             });
          //             for (int i = 0; i < _entries.length; i++) {
          //               _autoFillPO(i);
          //             }
          //           }
          //         }
          //       ),
          //     ),
          //     const SizedBox(width: 16),
          //     Expanded(child: _buildTextFormField(_timeController, 'Time', Icons.access_time, theme, isRequired: true, readOnly: true)),
          //   ],
          // ),
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
            TextButton.icon(icon: const Icon(Icons.add_business_outlined, size: 20), label: const Text('Add Another Vendor', style: TextStyle(fontSize: 13)), onPressed: _addEntry),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.payment, size: 20),
            label: const Text('Proceed to Payment', style: TextStyle(fontSize: 15)),
            onPressed: () async {
              final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => PaymentPage(initialData: _paymentDetails)));
              if (result != null) setState(() => _paymentDetails = result);
            },
            style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.secondary, foregroundColor: theme.colorScheme.onSecondary, minimumSize: const Size(double.infinity, 50)),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _submitForm, style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)), child: Text(_isEditMode ? 'Update' : 'Submit', style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }

  Widget _buildFmdEntry(int index, ThemeData theme) {
    final entry = _entries[index];

    // Filter POs based on selected vendor and date
    final selectedVendor = entry.selectedVendor;
    final selectedDate = _dateController.text;
    
    List<Map<String, dynamic>> filteredPOs = [];
    if (selectedVendor != null && selectedVendor != "Other" && selectedDate.isNotEmpty) {
      filteredPOs = _availablePOs.where((po) {
        final poVendor = (po['vendor_name'] ?? '').toString().toLowerCase();
        final poExpectedDate = (po['expected_date'] ?? '').toString();
        return poVendor == selectedVendor.toLowerCase() && poExpectedDate == selectedDate;
      }).toList();
    } else if (selectedVendor != null && selectedVendor != "Other") {
      // If only vendor is selected, filter by vendor only
      filteredPOs = _availablePOs.where((po) {
        final poVendor = (po['vendor_name'] ?? '').toString().toLowerCase();
        return poVendor == selectedVendor.toLowerCase();
      }).toList();
    } else {
      // Show all POs if no vendor selected
      filteredPOs = _availablePOs;
    }
    
    // Get unique PO numbers from filtered POs
    final poNumbers = filteredPOs.map((e) => e['po_number']?.toString() ?? "").where((s) => s.isNotEmpty).toSet().toList();

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
                Text('Vendor Entry ${index + 1}', style: theme.textTheme.titleMedium?.copyWith(fontSize: 14)),
                if (index > 0 && !_isEditMode) IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20), onPressed: () => _removeEntry(index)),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: entry.selectedVendor,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Vendor Name', labelStyle: TextStyle(fontSize: 13), border: OutlineInputBorder(), prefixIcon: Icon(Icons.business, size: 20)),
              style: const TextStyle(fontSize: 13, color: Colors.black),
              items: _vendorList.map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))).toList(),
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
              initialValue: poNumbers.contains(entry.poNumberController.text) ? entry.poNumberController.text : "",
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Linked PO Number', labelStyle: TextStyle(fontSize: 13), border: OutlineInputBorder(), prefixIcon: Icon(Icons.receipt_long, size: 20)),
              style: const TextStyle(fontSize: 13, color: Colors.black),
              items: [const DropdownMenuItem(value: "", child: Text("None", style: TextStyle(fontSize: 13))), ...poNumbers.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13))))],
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
      icon: const Icon(Icons.calendar_month_outlined, color: Colors.teal, size: 20),
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
        style: TextStyle(color: ctrlDate == null ? Colors.black54 : Colors.teal.shade700, fontSize: 13),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: BorderSide(color: ctrlDate == null ? Colors.grey.shade400 : Colors.teal),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

Widget _buildTextFormField(TextEditingController controller, String label, IconData icon, ThemeData theme, {bool isRequired = false, bool readOnly = false, VoidCallback? onTap, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 13), border: const OutlineInputBorder(), prefixIcon: Icon(icon, color: theme.colorScheme.primary, size: 20)),
      validator: validator ?? (value) => (isRequired && (value == null || value.isEmpty)) ? 'Required' : null,
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
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Text('No entries found.', style: TextStyle(fontSize: 12)),
              ),
            );
          }
          const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 10);
          const cellStyle = TextStyle(fontSize: 9);

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                'Vehicle',
                'Driver',
                'Vendors',
                'Gate',
                'PO Linked',
                'Extra Expenses',
                'Total',
                'Payment Status',
                'Amount Paid',
                'Amount Due',
                'Mode'
              ].map((col) => DataColumn(label: Text(col, style: headerStyle))).toList(),
              rows: snapshot.data!.map((row) {
                final gate = row['gate_number'];
                return DataRow(
                  cells: [
                    DataCell(Text(row['vehicle_number'] ?? '', style: cellStyle)),
                    DataCell(Text(row['driver_name'] ?? '', style: cellStyle)),
                    DataCell(Text(row['vendor_name'] ?? '', style: cellStyle)),
                    DataCell(Text(gate == null || gate.toString().trim().isEmpty ? '-' : gate.toString(), style: cellStyle)),
                    DataCell(Text(row['po_number'] ?? '-', style: cellStyle)),
                    DataCell(Text(row['extra_expenses']?.toString() ?? '0.0', style: cellStyle)),
                    DataCell(Text(row['total_amount']?.toString() ?? '0.0', style: cellStyle)),
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
                    DataCell(
                      Text(
                        row['amount_paid']?.toString() ?? '0.0',
                        style: const TextStyle(fontSize: 9, color: Colors.green),
                      ),
                    ),
                    DataCell(
                      Text(
                        row['amount_due']?.toString() ?? '0.0',
                        style: const TextStyle(fontSize: 9, color: Colors.red),
                      ),
                    ),
                    DataCell(Text(row['mode_of_payment']?.toString() ?? '-', style: cellStyle)),
                  ],
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

}
