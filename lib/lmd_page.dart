import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'payment_page.dart';

// const String apiBaseUrl = 'http://13.53.71.103:5000/';
const String apiBaseUrl = 'http://10.0.2.2:5000';

class LmdPage extends StatefulWidget {
  final Map<String, dynamic>? dataToEdit;

  const LmdPage({super.key, this.dataToEdit});

  @override
  State<LmdPage> createState() => _LmdPageState();
}

class _LocationEntry {
  String? selectedClient;
  bool isOtherClient = false;
  final clientNameController = TextEditingController(); 
  final soNumberController = TextEditingController();

  void dispose() {
    clientNameController.dispose();
    soNumberController.dispose();
  }

  void clear() {
    selectedClient = null;
    isOtherClient = false;
    clientNameController.clear();
    soNumberController.clear();
  }
}

class _LmdPageState extends State<LmdPage> {
  final _formKey = GlobalKey<FormState>();
  Future<List<Map<String, dynamic>>>? _lmdDataFuture;

  final _vehicleNumberController = TextEditingController();
  final _driverNameController = TextEditingController();
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();

  DateTime? ctrlDate;

  final List<_LocationEntry> _locations = [];
  List<String> _clientList = [];
  List<String> _availableSOs = [];
  List<Map<String, dynamic>> _allSOData = [];
  bool _isLoading = true;

  Map<String, dynamic>? _paymentDetails;
  bool get _isEditMode => widget.dataToEdit != null;

  @override
  void initState() {
    super.initState();
    _locations.add(_LocationEntry());

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
      final clientsResponse = await http.get(Uri.parse('$apiBaseUrl/get_vendors'));
      final sosResponse = await http.get(Uri.parse('$apiBaseUrl/get_all_generated_sos_with_items'));
      if (clientsResponse.statusCode == 200 && sosResponse.statusCode == 200) {
        final List<dynamic> clientsJson = json.decode(clientsResponse.body);
        final List<dynamic> sosJson = json.decode(sosResponse.body);
        
        final clients = clientsJson.map((e) => e.toString()).toList();
        final sos = List<Map<String, dynamic>>.from(sosJson);
        
        setState(() {
          _clientList = ["Other", ...clients.where((c) => c != "Other")].toSet().toList();
          _allSOData = sos;
          _availableSOs = sos.map((e) => e['so_number']?.toString() ?? "").where((s) => s.isNotEmpty).toSet().toList();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _autoFillSO(int index) {
    final location = _locations[index];
    final client = location.selectedClient;
    final date = _dateController.text;

    if (client != null && client != "Other" && date.isNotEmpty) {
      try {
        final match = _allSOData.firstWhere((so) {
          final soClient = (so['client_name'] ?? so['vendor_name'] ?? '').toString();
          final soDate = (so['date'] ?? '').toString();
          return soClient.toLowerCase() == client.toLowerCase() && soDate.contains(date);
        });
        setState(() {
          location.soNumberController.text = match['so_number'] ?? '';
        });
      } catch (e) {
        // No match found
      }
    }
  }

  void _populateFields(Map<String, dynamic> data) {
    String clientName = data['client_name'] ?? '';
    if (_clientList.contains(clientName)) {
      _locations.first.selectedClient = clientName;
    } else {
      _locations.first.selectedClient = "Other";
      _locations.first.isOtherClient = true;
      _locations.first.clientNameController.text = clientName;
    }

    _locations.first.soNumberController.text = data['po_number'] ?? '';

    _vehicleNumberController.text = data['vehicle_number'] ?? '';
    _driverNameController.text = data['driver_name'] ?? '';
    _dateController.text = data['date'] ?? '';
    _timeController.text = data['time'] ?? '';
    _paymentDetails = data;
  }

  void _refreshData() {
    setState(() {
      _lmdDataFuture = http.get(Uri.parse('$apiBaseUrl/get_latest_lmd_data')).then((response) {
        if (response.statusCode == 200) {
          return List<Map<String, dynamic>>.from(json.decode(response.body));
        } else {
          throw Exception('Failed to load LMD data');
        }
      });
    });
  }

  @override
  void dispose() {
    _vehicleNumberController.dispose();
    _driverNameController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    for (var location in _locations) {
      location.dispose();
    }
    super.dispose();
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

    List<String> finalClientNames = [];
    for (var loc in _locations) {
      String name = loc.isOtherClient ? loc.clientNameController.text.trim() : loc.selectedClient ?? '';
      if (loc.isOtherClient && name.isNotEmpty) {
        await http.post(Uri.parse('$apiBaseUrl/insert_vendor'), body: json.encode({'name': name}), headers: {'Content-Type': 'application/json'});
      }
      finalClientNames.add(name);
    }

    final clientNamesStr = finalClientNames.where((s) => s.isNotEmpty).join(', ');
    final soNumbers = _locations.map((e) => e.soNumberController.text.trim()).where((s) => s.isNotEmpty).join(', ');

    final data = {
      'vehicle_number': _vehicleNumberController.text,
      'driver_name': _driverNameController.text,
      'date': _dateController.text,
      'time': _timeController.text,
      'client_name': clientNamesStr,
      'po_number': soNumbers,
      'client_location': '', 
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
      final response = await http.put(Uri.parse('$apiBaseUrl/update_lmd_data'), body: json.encode(data), headers: {'Content-Type': 'application/json'});
      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('LMD Data Updated Successfully!'), backgroundColor: Colors.blue));
        Navigator.of(context).pop();
      }
    } else {
      final response = await http.post(Uri.parse('$apiBaseUrl/insert_lmd_data'), body: json.encode(data), headers: {'Content-Type': 'application/json'});
      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('LMD Data Saved Successfully!'), backgroundColor: Colors.green));
        _resetForm();
        _loadInitialData();
        _refreshData();
      }
    }
  }

  void _resetForm() {
    _formKey.currentState!.reset();
    _vehicleNumberController.clear();
    _driverNameController.clear();
    for (var location in _locations) {
      location.clear();
    }
    setState(() {
      _locations.removeRange(1, _locations.length);
      _locations.first.clear();
      _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _timeController.text = DateFormat('HH:mm:ss').format(DateTime.now());
      _paymentDetails = null;
      ctrlDate = null;
    });
  }

  void _addLocation() {
    setState(() {
      _locations.add(_LocationEntry());
    });
  }

  void _removeLocation(int index) {
    if (_locations.length > 1) {
      setState(() {
        _locations[index].dispose();
        _locations.removeAt(index);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit LMD Entry' : 'LMD - Book Logistics (SO Link)'),
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
                      for (int i = 0; i < _locations.length; i++) {
                        _autoFillSO(i);
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
            itemCount: _locations.length,
            itemBuilder: (context, index) => _buildLocationEntry(index, theme),
          ),
          const SizedBox(height: 16),
          if (!_isEditMode)
            TextButton.icon(icon: const Icon(Icons.add_location_alt_outlined), label: const Text('Add Another Client'), onPressed: _addLocation),
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

  Widget _buildLocationEntry(int index, ThemeData theme) {
    final location = _locations[index];
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
                Text('Client ${index + 1}', style: theme.textTheme.titleMedium),
                if (index > 0 && !_isEditMode) IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => _removeLocation(index)),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: location.selectedClient,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Select Client', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
              items: _clientList.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (val) => setState(() { 
                location.selectedClient = val; 
                location.isOtherClient = val == "Other"; 
                _autoFillSO(index);
              }),
              validator: (val) => val == null ? 'Required' : null,
            ),
            if (location.isOtherClient)
              Padding(padding: const EdgeInsets.only(top: 16.0), child: _buildTextFormField(location.clientNameController, 'New Client Name', Icons.edit_note, theme, isRequired: true)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _availableSOs.contains(location.soNumberController.text) ? location.soNumberController.text : "",
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Linked SO Number', border: OutlineInputBorder(), prefixIcon: Icon(Icons.receipt_long)),
              items: [const DropdownMenuItem(value: "", child: Text("None")), ..._availableSOs.map((p) => DropdownMenuItem(value: p, child: Text(p)))],
              onChanged: (val) => setState(() => location.soNumberController.text = val ?? ""),
            ),
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
        future: _lmdDataFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text('No entries found.')));
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: ['Vehicle', 'Driver', 'Clients', 'SO Linked', 'Due'].map((col) => DataColumn(label: Text(col, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
              rows: snapshot.data!.map((row) => DataRow(cells: [
                DataCell(Text(row['vehicle_number'] ?? '')),
                DataCell(Text(row['driver_name'] ?? '')),
                DataCell(Text(row['client_name'] ?? '')),
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
