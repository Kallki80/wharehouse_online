import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const String apiBaseUrl = 'http://13.53.71.103:5000/';
// const String apiBaseUrl = 'http://10.0.2.2:5000';

// API Helper Functions
Future<List<Map<String, dynamic>>> getVendorsWithDetails() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_vendors_with_details'));
  if (response.statusCode == 200) {
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load vendors with details');
  }
}

Future<List<Map<String, dynamic>>> getLatestGeneratedSOsWithItems({int limit = 100}) async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_latest_generated_sos_with_items?limit=$limit'));
  if (response.statusCode == 200) {
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load latest generated SOs with items');
  }
}

Future<List<String>> getPurchasedItems() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_items'));
  if (response.statusCode == 200) {
    return List<String>.from(json.decode(response.body));
  } else {
    throw Exception('Failed to load purchased items');
  }
}

Future<String?> getLastSoNumber() async {
  final response = await http.get(Uri.parse('$apiBaseUrl/get_last_so_number'));
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['so_number'];
  } else {
    throw Exception('Failed to load last SO number');
  }
}

Future<void> insertItem(String name) async {
  final response = await http.post(
    Uri.parse('$apiBaseUrl/insert_item'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({'name': name}),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to insert item');
  }
}

Future<void> insertGeneratedSO(Map<String, dynamic> soData, List<Map<String, dynamic>> itemsData) async {
  final data = {'so_data': soData, 'items_data': itemsData};
  final response = await http.post(
    Uri.parse('$apiBaseUrl/insert_generated_so'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(data),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to insert generated SO');
  }
}

Future<void> insertVendor(String name, String location, double km) async {
  final response = await http.post(
    Uri.parse('$apiBaseUrl/insert_vendor'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({'name': name, 'location': location, 'km': km}),
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to insert vendor');
  }
}

Future<bool> deleteClient(String name) async {
  final response = await http.delete(
    Uri.parse('$apiBaseUrl/delete_client'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({'name': name}),
  );
  return response.statusCode == 200;
}

class SoItem {
  String? selectedItem;
  final TextEditingController quantityKgController = TextEditingController();
  final TextEditingController quantityPcsController = TextEditingController();
  bool isOtherItem = false;
  final TextEditingController otherItemController = TextEditingController();

  void dispose() {
    quantityKgController.dispose();
    quantityPcsController.dispose();
    otherItemController.dispose();
  }
}

class GenerateSoNumberPage extends StatefulWidget {
  const GenerateSoNumberPage({super.key});

  @override
  State<GenerateSoNumberPage> createState() => _GenerateSoNumberPageState();
}

class _GenerateSoNumberPageState extends State<GenerateSoNumberPage> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedClient;
  final TextEditingController _otherClientController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _kmController = TextEditingController();
  bool _isOtherClient = false;

  final TextEditingController _soNumberController = TextEditingController();
  DateTime? _dispatchDate;
  List<SoItem> _soItems = [];
  
  List<Map<String, dynamic>> _registeredClientsData = [];
  List<Map<String, dynamic>> _soDataList = [];
  List<String> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _addItemEntry();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final allVendors = await getVendorsWithDetails();
    final allSOs = await getLatestGeneratedSOsWithItems(limit: 100);
    final itemsList = await getPurchasedItems();

    if (mounted) {
      setState(() {
        _registeredClientsData = allVendors.where((v) => v['location'] != null && v['location'].toString().isNotEmpty).toList();
        _soDataList = allSOs;
        _items = ['Other', ...itemsList];
        _isLoading = false;
      });
    }
  }

  void _addItemEntry() {
    setState(() {
      _soItems.add(SoItem());
    });
  }

  void _removeItem(int index) {
    if (_soItems.length > 1) {
      _soItems[index].dispose();
      setState(() {
        _soItems.removeAt(index);
      });
    }
  }

  String _generateNextSoNumber(String? lastSo) {
    if (lastSo == null || lastSo.isEmpty) return "so-001";
    final match = RegExp(r'(\d+)$').firstMatch(lastSo);
    if (match != null) {
      String numberPart = match.group(1)!;
      int nextNumber = int.parse(numberPart) + 1;
      return "so-${nextNumber.toString().padLeft(3, '0')}";
    }
    return "so-001";
  }

  void _showSoNumberOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('SO Number Options', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline, color: Colors.teal),
                title: const Text('Create SO Number (Auto-increment)'),
                onTap: () async {
                  Navigator.pop(context);
                  String? lastSo = await getLastSoNumber();
                  String nextSo = _generateNextSoNumber(lastSo);
                  setState(() {
                    _soNumberController.text = nextSo;
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Colors.orange),
                title: const Text('Enter SO Number (Manual)'),
                onTap: () {
                  Navigator.pop(context);
                  _showManualSoEntry();
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _showManualSoEntry() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController(text: _soNumberController.text);
        return AlertDialog(
          title: const Text('Enter SO Number'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              labelText: 'SO Number',
              hintText: 'e.g. so-123',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              controller.text = value;
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _soNumberController.text = controller.text;
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _soNumberController.dispose();
    _otherClientController.dispose();
    _locationController.dispose();
    _kmController.dispose();
    for (var item in _soItems) {
      item.dispose();
    }
    super.dispose();
  }

 Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      String finalClientName = _isOtherClient ? _otherClientController.text : (_selectedClient ?? '');
      
      if (finalClientName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select or enter a client name')));
        return;
      }

      if (_soNumberController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select or enter a SO number')));
        return;
      }

      if (_dispatchDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select dispatch date'), backgroundColor: Colors.orange));
        return;
      }

      await insertVendor(finalClientName, _locationController.text, double.tryParse(_kmController.text) ?? 0.0);

      final soData = {
        'client_name': finalClientName,
        'so_number': _soNumberController.text,
        'date_of_dispatch': DateFormat('yyyy-MM-dd').format(_dispatchDate!),
      };

      final List<Map<String, dynamic>> itemsData = [];
      for (var item in _soItems) {
        if (item.selectedItem == null) continue;
        String finalItem = item.selectedItem!;
        if (item.isOtherItem) {
          finalItem = item.otherItemController.text;
          await insertItem(finalItem);
        }
        itemsData.add({
          'item_name': finalItem,
          'quantity_kg': double.tryParse(item.quantityKgController.text) ?? 0.0,
          'quantity_pcs': double.tryParse(item.quantityPcsController.text) ?? 0.0,
        });
      }
      if (itemsData.isNotEmpty) {
        await insertGeneratedSO(soData, itemsData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data Saved Successfully!'), backgroundColor: Colors.green),
        );
        _formKey.currentState!.reset();
        setState(() {
          _selectedClient = null;
          _isOtherClient = false;
          _dispatchDate = null;
          _soNumberController.clear();
          _otherClientController.clear();
          _locationController.clear();
          _kmController.clear();
          for (var item in _soItems) {
            item.dispose();
          }
          _soItems = [];
        });
        _addItemEntry();
        _loadInitialData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Clients & SO'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text("Client Selection", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                            ),
                            if (_registeredClientsData.isNotEmpty)
                              TextButton.icon(
                                onPressed: _showClientListWithDelete,
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                label: const Text('Manage Clients', style: TextStyle(color: Colors.red, fontSize: 12)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildDropdownFormField(
                            value: _isOtherClient ? 'Other' : _selectedClient,
                            label: 'Select Registered Client',
                            icon: Icons.person_outline,
                            items: ['Other', ..._registeredClientsData.map((c) => c['name'] as String)],
                            onChanged: (val) {
                              setState(() {
                                _isOtherClient = val == 'Other';
                                if (_isOtherClient) {
                                  _selectedClient = null;
                                  _locationController.clear();
                                  _kmController.clear();
                                  _otherClientController.clear();
                                } else {
                                  _selectedClient = val;
                                  final client = _registeredClientsData.firstWhere((c) => c['name'] == val);
                                  _locationController.text = client['location'] ?? '';
                                  _kmController.text = client['km']?.toString() ?? '';
                                }
                              });
                            },
                            validator: (val) => val == null ? 'Required' : null,
                        ),
                        if (_isOtherClient) ...[
                          const SizedBox(height: 18),
                          _buildTextFormField(controller: _otherClientController, label: 'Client Name', icon: Icons.edit, validator: (v) => v!.isEmpty ? "Required" : null),
                        ],
                        if (_selectedClient != null || _isOtherClient) ...[
                          const SizedBox(height: 12),
                          _buildTextFormField(controller: _locationController, label: 'Location', icon: Icons.location_on_outlined, validator: (v) => v!.isEmpty ? "Required" : null),
                          const SizedBox(height: 12),
                          _buildTextFormField(controller: _kmController, label: 'Kilometers', icon: Icons.map_outlined, keyboardType: TextInputType.number, validator: (v) => v!.isEmpty ? "Required" : null),
                        ],
                        const Divider(height: 40, thickness: 1),
                        const Text("SO Details", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        const SizedBox(height: 12),
                         _buildTextFormField(
                            controller: _soNumberController,
                            label: 'SO Number',
                            icon: Icons.receipt_long_outlined,
                            readOnly: true,
                            onTap: _showSoNumberOptions,
                            validator: (value) => (value == null || value.isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 12.0),
                        _buildDatePicker(),
                        const SizedBox(height: 12.0),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _soItems.length,
                          itemBuilder: (context, index) => _buildItemEntry(index),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.add_circle_outline, color: Colors.teal),
                          label: const Text("Add More Items"),
                          onPressed: _addItemEntry,
                        ),
                        const SizedBox(height: 32.0),
                        ElevatedButton(
                          onPressed: _submitForm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                             textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          child: const Text('SUBMIT DATA'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text("All Activity Records", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal)),
                  const SizedBox(height: 8),
                  _buildUnifiedTable(),
                ],
              ),
            ),
    );
  }

  Widget _buildItemEntry(int index) {
    final soItem = _soItems[index];
    return Container(
       margin: const EdgeInsets.symmetric(vertical: 8.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12.0)),
      child: Column(
        children: [
           Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Item #${index + 1}", style: const TextStyle(fontWeight: FontWeight.bold)),
              if (_soItems.length > 1)
                IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => _removeItem(index)),
            ],
          ),
          _buildDropdownFormField(
            value: soItem.selectedItem,
            label: 'Item Name',
            icon: Icons.inventory_2_outlined,
            items: _items,
            onChanged: (val) => setState(() { soItem.selectedItem = val; soItem.isOtherItem = val == 'Other'; }),
            validator: (val) => null,
          ),
          if (soItem.isOtherItem) ...[
            const SizedBox(height: 12),
            _buildTextFormField(controller: soItem.otherItemController, label: 'New Item Name', icon: Icons.edit_note),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _buildTextFormField(controller: soItem.quantityKgController, label: 'Qty (Kg)', icon: Icons.scale, keyboardType: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(child: _buildTextFormField(controller: soItem.quantityPcsController, label: 'Qty (Pcs)', icon: Icons.numbers, keyboardType: TextInputType.number)),
          ])
        ],
      ),
    );
  }

   Widget _buildTextFormField({required TextEditingController controller, required String label, required IconData icon, String? Function(String?)? validator, TextInputType? keyboardType, VoidCallback? onTap, bool readOnly = false}) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, color: Colors.teal.shade700), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.grey.shade50),
      keyboardType: keyboardType,
      validator: validator,
    );
  }

  Widget _buildDropdownFormField<T>({required T? value, required String label, required IconData icon, required List<T> items, required void Function(T?)? onChanged, required String? Function(T?)? validator}) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, color: Colors.teal.shade700), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.grey.shade50),
      items: items.map((T item) => DropdownMenuItem<T>(value: item, child: Text(item.toString(), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
    );
  }

  Widget _buildDatePicker() {
    return InkWell(
      onTap: () async {
        final DateTime? picked = await showDatePicker(context: context, initialDate: _dispatchDate ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2101));
        if (picked != null) setState(() => _dispatchDate = picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: 'Dispatch Date', prefixIcon: Icon(Icons.calendar_today, color: Colors.teal.shade700), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.grey.shade50),
        child: Text(_dispatchDate == null ? 'Select Date' : DateFormat('dd-MM-yyyy').format(_dispatchDate!)),
      ),
    );
  }

  Future<void> _deleteClient(String clientName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Client'),
        content: Text('Are you sure you want to delete "$clientName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await deleteClient(clientName);
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$clientName deleted successfully!'), backgroundColor: Colors.green),
          );
          _loadInitialData();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete client'), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showClientListWithDelete() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Manage Clients', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _registeredClientsData.length,
                    itemBuilder: (context, index) {
                      final client = _registeredClientsData[index];
                      final clientName = client['name'] ?? '';
                      final location = client['location'] ?? '';
                      return ListTile(
                        leading: const Icon(Icons.person, color: Colors.teal),
                        title: Text(clientName),
                        subtitle: Text(location),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteClient(clientName);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildUnifiedTable() {
    List<DataRow> rows = [];
    
    Map<int, List<Map<String, dynamic>>> groupedSOs = {};
    List<int> soOrder = [];
    for (var so in _soDataList) {
      int id = so['so_id'] ?? 0;
      if (!groupedSOs.containsKey(id)) {
        groupedSOs[id] = [];
        soOrder.add(id);
      }
      groupedSOs[id]!.add(so);
    }

    Set<String> clientsWithRecentSOs = _soDataList.map((so) => so['client_name'] as String).toSet();

    for (int soId in soOrder) {
      final items = groupedSOs[soId]!;
      final first = items.first;
      final clientName = first['client_name'] ?? '';
      
      final clientDetails = _registeredClientsData.firstWhere((c) => c['name'] == clientName, orElse: () => {});
      final loc = clientDetails['location'] ?? '-';
      final km = clientDetails['km']?.toString() ?? '-';

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        rows.add(DataRow(cells: [
          DataCell(Text(i == 0 ? clientName : '', style: const TextStyle(fontWeight: FontWeight.bold))),
          DataCell(Text(i == 0 ? loc : '')),
          DataCell(Text(i == 0 ? km : '')),
          DataCell(Text(i == 0 ? (item['so_number']?.toString() ?? '') : '')),
          DataCell(Text(i == 0 && item['date_of_dispatch'] != null ? DateFormat('dd-MM-yy').format(DateTime.parse(item['date_of_dispatch'])) : '')),
          DataCell(Text(item['item_name']?.toString() ?? '')),
          DataCell(Text("${item['quantity_kg'] ?? 0} Kg")),
          DataCell(Text("${item['quantity_pcs'] ?? 0} Pcs")),
          DataCell(i == 0 ? IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _deleteClient(clientName),
          ) : const SizedBox()),
        ]));
      }
    }

    final clientsNoSOs = _registeredClientsData.where((c) => c['name'] != null && !clientsWithRecentSOs.contains(c['name'])).toList();
    for (var client in clientsNoSOs) {
      rows.add(DataRow(cells: [
        DataCell(Text(client['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(client['location'] ?? '')),
        DataCell(Text(client['km']?.toString() ?? '')),
        const DataCell(Text('-')), const DataCell(Text('-')), const DataCell(Text('-')), const DataCell(Text('-')), const DataCell(Text('-')),
        DataCell(IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () => _deleteClient(client['name'] ?? ''),
        )),
      ]));
    }

    if (rows.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(20), child: Text("No records found.", textAlign: TextAlign.center)));

    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.teal.shade100),
          columns: const [
            DataColumn(label: Text('Client')),
            DataColumn(label: Text('Location')),
            DataColumn(label: Text('KM')),
            DataColumn(label: Text('SO Num')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Item')),
            DataColumn(label: Text('Qty Kg')),
            DataColumn(label: Text('Qty Pcs')),
            DataColumn(label: Text('Action')),
          ],
          rows: rows,
        ),
      ),
    );
  }
}
