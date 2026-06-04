import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as excel;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'generate_po_number_page.dart';
import 'generate_so_number_page.dart';
import 'api_config.dart';

// POItemEntry class for edit new items (copied from generate_po_number_page.dart)
class POItemEntry {
  String? selectedItem;
  String? selectedVendor;
  String? selectedUnit = 'kg';
  DateTime? expectedDate;
  bool isOtherItem = false;
  bool isOtherVendor = false;
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController rateController = TextEditingController();
  final TextEditingController otherItemController = TextEditingController();
  final TextEditingController otherVendorController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  final TextEditingController itemSearchController = TextEditingController();
  final TextEditingController vendorSearchController = TextEditingController();
  List<TextEditingController> qualityPointsControllers = [TextEditingController()];

  void dispose() {
    qtyController.dispose();
    rateController.dispose();
    otherItemController.dispose();
    otherVendorController.dispose();
    noteController.dispose();
    itemSearchController.dispose();
    vendorSearchController.dispose();
    for (var controller in qualityPointsControllers) {
      controller.dispose();
    }
  }

  void addQualityPoint() {
    qualityPointsControllers.add(TextEditingController());
  }

  void removeQualityPoint(int index) {
    if (qualityPointsControllers.length > 1) {
      qualityPointsControllers[index].dispose();
      qualityPointsControllers.removeAt(index);
    } else {
      qualityPointsControllers[0].clear();
    }
  }
}


class PoNumberPage extends StatefulWidget {
  const PoNumberPage({super.key});

  @override
  State<PoNumberPage> createState() => _PoNumberPageState();
}

class SOItemEntry {
  String? selectedItem;
  String? selectedClient;
  DateTime? expectedDate;
  bool isOtherItem = false;
  bool isOtherClient = false;
  final TextEditingController qtyKgController = TextEditingController();
  final TextEditingController qtyPcsController = TextEditingController();
  final TextEditingController otherItemController = TextEditingController();
  final TextEditingController otherClientController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  final TextEditingController itemSearchController = TextEditingController();
  final TextEditingController clientSearchController = TextEditingController();
  List<TextEditingController> qualityPointsControllers = [TextEditingController()];

  void dispose() {
    qtyKgController.dispose();
    qtyPcsController.dispose();
    otherItemController.dispose();
    otherClientController.dispose();
    noteController.dispose();
    itemSearchController.dispose();
    clientSearchController.dispose();
    for (var controller in qualityPointsControllers) {
      controller.dispose();
    }
  }

  void addQualityPoint() {
    qualityPointsControllers.add(TextEditingController());
  }

  void removeQualityPoint(int index) {
    if (qualityPointsControllers.length > 1) {
      qualityPointsControllers[index].dispose();
      qualityPointsControllers.removeAt(index);
    } else {
      qualityPointsControllers[0].clear();
    }
  }
}

class _PoNumberPageState extends State<PoNumberPage> with SingleTickerProviderStateMixin {
  // Add these methods for new items in edit dialog (will be used in StatefulBuilder)
// Helper methods for PO/SO edit dialogs
  void _addNewPoItemEntry(List<POItemEntry> newItemEntries, StateSetter setDialogState) {
    newItemEntries.add(POItemEntry());
    setDialogState(() {});
  }

  void _removeNewPoItemEntry(int index, List<POItemEntry> newItemEntries, StateSetter setDialogState) {
    newItemEntries[index].dispose();
    newItemEntries.removeAt(index);
    setDialogState(() {});
  }

  void _addNewSoItemEntry(List<SOItemEntry> newItemEntries, StateSetter setDialogState) {
    newItemEntries.add(SOItemEntry());
    setDialogState(() {});
  }

  void _removeNewSoItemEntry(int index, List<SOItemEntry> newItemEntries, StateSetter setDialogState) {
    newItemEntries[index].dispose();
    newItemEntries.removeAt(index);
    setDialogState(() {});
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  List<Map<String, dynamic>> _filteredPOs = [];
  List<Map<String, dynamic>> _filteredSOs = [];
  
  late TabController _tabController;

  // Filters
  DateTime? _startDate;
  DateTime? _endDate;
  String? _poNumber;
  String? _soNumber;
  String? _selectedItem;
  String? _selectedClientVendor;

  // Temporary filters
  DateTime? _tempStartDate;
  DateTime? _tempEndDate;
  String? _tempSelectedItem;
  String? _tempSelectedClientVendor;
  final TextEditingController _poNumberController = TextEditingController();
  final TextEditingController _soNumberController = TextEditingController();
  bool _isExporting = false;

  List<String> _itemsForFilter = [];
  List<String> _clientsVendorsForFilter = [];


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
         _clearAllFilters();
      }
    });
    _populateFilterOptions();
    _refreshData();
  }

  Future<void> _populateFilterOptions() async {
      final itemsResponse = await http.get(Uri.parse('$apiBaseUrl/get_items'));
    final vendorsResponse = await http.get(Uri.parse('$apiBaseUrl/get_purchase_vendors'));
    final clientsResponse = await http.get(Uri.parse('$apiBaseUrl/get_b_grade_clients'));

    if (itemsResponse.statusCode == 200 && vendorsResponse.statusCode == 200 && clientsResponse.statusCode == 200) {
      final dynamic itemsDecoded = json.decode(itemsResponse.body);
      final dynamic vendorsDecoded = json.decode(vendorsResponse.body);
      final dynamic clientsDecoded = json.decode(clientsResponse.body);

      // API kabhi list<string> deta hai aur kabhi list<map>. Dono handle karein.
      List<String> asStringList(dynamic decoded) {
        if (decoded is List) {
          return decoded.map((e) {
            if (e == null) return '';
            if (e is String) return e;
            if (e is Map) {
              // common keys: name/item/vendor/client
              return (e['name'] ?? e['item'] ?? e['vendor'] ?? e['client'] ?? e['client_name'] ?? e.values.firstOrNull)?.toString() ?? '';
            }
            return e.toString();
          }).where((s) => s.isNotEmpty).toList();
        }
        return const [];
      }

      final items = asStringList(itemsDecoded);
      final vendors = asStringList(vendorsDecoded);
      final clients = asStringList(clientsDecoded);

      final allClientsVendors = {...vendors, ...clients};
      if (mounted) {
        setState(() {
          _itemsForFilter = items.toSet().toList()..sort();
          _clientsVendorsForFilter = allClientsVendors.toSet().toList()..sort();
        });
      }
    }
  }


  void _refreshData() {
    _applyFilters();
  }

  void _applyFilters() async {
    final queryParams = {
      if (_startDate != null) 'start_date': DateFormat('yyyy-MM-dd').format(_startDate!),
      if (_endDate != null) 'end_date': DateFormat('yyyy-MM-dd').format(_endDate!),
      if (_poNumber != null) 'po_number': _poNumber!,
      if (_soNumber != null) 'so_number': _soNumber!,
      if (_selectedItem != null) 'item_name': _selectedItem!,
      if (_selectedClientVendor != null) 'client_vendor_name': _selectedClientVendor!,
    };

    final poUri = Uri.parse('$apiBaseUrl/get_all_generated_pos').replace(queryParameters: queryParams);
    final soUri = Uri.parse('$apiBaseUrl/get_all_generated_sos_with_items').replace(queryParameters: queryParams);

    final poResponse = await http.get(poUri);
    final soResponse = await http.get(soUri);

    if (poResponse.statusCode == 200 && soResponse.statusCode == 200) {
      setState(() {
        _filteredPOs = List<Map<String, dynamic>>.from(json.decode(poResponse.body));
        _filteredSOs = List<Map<String, dynamic>>.from(json.decode(soResponse.body));
      });
    } else {
      // Handle error
      setState(() {
        _filteredPOs = [];
        _filteredSOs = [];
      });
    }
  }


  void _clearAllFilters() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _poNumber = null;
      _soNumber = null;
      _selectedItem = null;
      _selectedClientVendor = null;
      _poNumberController.clear();
      _soNumberController.clear();
      _resetTempFilters();
      _applyFilters();
    });
  }

  void _resetTempFilters() {
    _tempStartDate = _startDate;
    _tempEndDate = _endDate;
    _tempSelectedItem = _selectedItem;
    _tempSelectedClientVendor = _selectedClientVendor;
    _poNumberController.text = _poNumber ?? '';
    _soNumberController.text = _soNumber ?? '';
  }


  @override
  void dispose() {
    _tabController.dispose();
    _poNumberController.dispose();
    _soNumberController.dispose();
    super.dispose();
  }

  Future<bool> _showPasswordDialog() async {
    String enteredPassword = "";
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Colors.teal),
            SizedBox(width: 10),
            Text("Auth Required", style: TextStyle(fontSize: 16)),
          ],
        ),
        content: TextField(
          obscureText: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: "Enter Password",
            hintStyle: const TextStyle(fontSize: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.password, size: 20),
          ),
          onChanged: (val) => enteredPassword = val,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL", style: TextStyle(fontSize: 13))),
          ElevatedButton(
            onPressed: () {
              if (enteredPassword == "1008") {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Incorrect Password")));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            child: const Text("VERIFY", style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    ) ?? false;
  }










  // void _handleDeletePO(String poNum) async {
  //   if (await _showPasswordDialog()) {
  //     final response = await http.delete(Uri.parse('$apiBaseUrl/delete_po'), body: json.encode({'po_number': poNum}), headers: {'Content-Type': 'application/json'});
  //     if (response.statusCode == 200) {
  //       _refreshData();
  //       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PO Deleted")));
  //     } else {
  //       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to delete PO"), backgroundColor: Colors.red));
  //     }
  //   }
  // }




  void _handleDeletePO(String poNum) async {
    if (await _showPasswordDialog()) {
      try {
        final response = await http.delete(
          Uri.parse('$apiBaseUrl/delete_po?po_number=$poNum'),
        );

        if (response.statusCode == 200) {
          _refreshData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("PO Deleted")),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Failed to delete PO: ${response.body}"),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error: $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }




  void _handleDeleteSO(int soId) async {
    if (await _showPasswordDialog()) {
      final response = await http.delete(Uri.parse('$apiBaseUrl/delete_so'), body: json.encode({'so_id': soId}), headers: {'Content-Type': 'application/json'});
      if (response.statusCode == 200) {
        _refreshData();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("SO Deleted")));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to delete SO"), backgroundColor: Colors.red));
      }
    }
  }

void _handleEditPO(String poNum, List<Map<String, dynamic>> items) async {
    if (await _showPasswordDialog()) {
       final managerCtrl = TextEditingController(text: items.first['product_manager']);
       final poNumCtrl = TextEditingController(text: poNum);

       List<Map<String, dynamic>> localItems = items.map((e) => Map<String, dynamic>.from(e)).toList();

List<POItemEntry> newItemEntries = []; // Initialize empty
  List<String> editItems = ['Other'];
  List<String> editVendors = ['Other'];
  
Future<void> loadEditData() async {
    try {
      final itemsResponse = await http.get(Uri.parse('$apiBaseUrl/get_items'));
      final vendorsResponse = await http.get(Uri.parse('$apiBaseUrl/get_purchase_vendors'));
      if (itemsResponse.statusCode == 200) {
        editItems = ['Other', ...List<String>.from(json.decode(itemsResponse.body))];
      }
      if (vendorsResponse.statusCode == 200) {
        editVendors = ['Other', ...List<String>.from(json.decode(vendorsResponse.body))];
      }
    } catch (e) {
      editItems = ['Other'];
      editVendors = ['Other'];
      debugPrint('Failed to load edit data: $e');
    }
  }

           showDialog(
         context: context,
         builder: (context) {
           return StatefulBuilder(
             builder: (context, setDialogState) {
               return AlertDialog(
                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                 titlePadding: EdgeInsets.zero,
                 title: Container(
                   padding: const EdgeInsets.all(16),
                   decoration: const BoxDecoration(
                     color: Colors.teal,
                     borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                   ),
                   child: const Text("Edit Purchase Order", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                 ),
                 content: SizedBox(
                   width: MediaQuery.of(context).size.width * 0.9,
                   child: ListView(
                     shrinkWrap: true,
                     children: [
                       const SizedBox(height: 10),
                       _buildEditTextField(managerCtrl, "Product Manager", Icons.person),
                       const SizedBox(height: 12),
                       _buildEditTextField(poNumCtrl, "PO Number", Icons.receipt_long),
                       const Padding(
                         padding: EdgeInsets.symmetric(vertical: 16.0),
                         child: Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("ITEMS", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12))), Expanded(child: Divider())]),
                       ),
                       ...localItems.asMap().entries.map((entry) {
                         int idx = entry.key;
                         var item = entry.value;
                         return Card(
                           margin: const EdgeInsets.only(bottom: 12),
                           elevation: 0,
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
                           child: Padding(
                             padding: const EdgeInsets.all(12),
                             child: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 Text("Existing Item #${idx + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 13)),
                                 const SizedBox(height: 8),
                                 _buildSmallEditField(TextEditingController(text: item['item_name']), "Item Name", (v) => item['item_name'] = v),
                                 Row(
                                   children: [
                                     Expanded(child: _buildSmallEditField(TextEditingController(text: item['qty_ordered'].toString()), "Qty", (v) => item['qty_ordered'] = double.tryParse(v) ?? item['qty_ordered'], isNum: true)),
                                     const SizedBox(width: 8),
                                     Expanded(child: _buildSmallEditField(TextEditingController(text: item['unit']), "Unit", (v) => item['unit'] = v)),
                                   ],
                                 ),
                                 _buildSmallEditField(TextEditingController(text: item['rate'].toString()), "Rate (₹)", (v) => item['rate'] = double.tryParse(v) ?? item['rate'], isNum: true),
                                 _buildSmallEditField(TextEditingController(text: item['vendor_name']), "Vendor", (v) => item['vendor_name'] = v),
                                 _buildSmallEditField(TextEditingController(text: item['quality_specifications'] ?? ''), "Quality Specs", (v) => item['quality_specifications'] = v),
                                 _buildSmallEditField(TextEditingController(text: item['note'] ?? ''), "Note", (v) => item['note'] = v),
                                 InkWell(
                                   onTap: () async {
                                     final picked = await showDatePicker(
                                       context: context,
                                       initialDate: DateTime.tryParse(item['expected_date']) ?? DateTime.now(),
                                       firstDate: DateTime(2000),
                                       lastDate: DateTime(2100),
                                     );
                                     if (picked != null) {
                                       setDialogState(() {
                                         item['expected_date'] = DateFormat('yyyy-MM-dd').format(picked);
                                       });
                                     }
                                   },
                                   child: Container(
                                     width: double.infinity,
                                     padding: const EdgeInsets.all(12),
                                     margin: const EdgeInsets.only(top: 8),
                                     decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                                     child: Row(
                                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                       children: [
                                         Text("Expected Date: ${item['expected_date']}", style: const TextStyle(fontSize: 12)),
                                         const Icon(Icons.calendar_today, size: 14, color: Colors.teal),
                                       ],
                                     ),
                                   ),
                                 ),
                               ],
                             ),
                           ),
                         );
                       }),

                       // NEW ITEMS SECTION
                       const Padding(
                         padding: EdgeInsets.symmetric(vertical: 16.0),
                         child: Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("ADD NEW ITEMS", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 12))), Expanded(child: Divider())]),
                       ),
                       ElevatedButton.icon(
                         icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 18),
                         label: const Text("➕ Add New Item", style: TextStyle(fontSize: 13)),
                        onPressed: () {
                            if (newItemEntries.length < 10) {
                              loadEditData();
                              setDialogState(() {
                                newItemEntries.add(POItemEntry());
                              });
                            }
                          },
                         style: ElevatedButton.styleFrom(
                           backgroundColor: Colors.orange.shade600,
                           foregroundColor: Colors.white,
                           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                         ),
                       ),
  ...newItemEntries.asMap().entries.map((entry) {
    int idx = entry.key;
    POItemEntry newEntry = entry.value;
    return Card(
      key: ValueKey('new_item_$idx'),
      margin: EdgeInsets.only(bottom: 12, top: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.orange.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("New Item #${idx + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13)),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                  onPressed: () => _removeNewPoItemEntry(idx, newItemEntries, setDialogState),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Full search dropdown for Items (copied from generate_po)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: newEntry.itemSearchController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Item Name (Search/Filter)',
                    labelStyle: TextStyle(fontSize: 13),
                    prefixIcon: Icon(Icons.inventory_2_outlined, color: Colors.orange, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    suffixIcon: newEntry.itemSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, size: 18),
                            onPressed: () {
                              setDialogState(() {
                                newEntry.itemSearchController.clear();
                                newEntry.selectedItem = null;
                                newEntry.isOtherItem = false;
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (text) {
                    setDialogState(() {
                      // Filter items
                      List<String> filtered = editItems.where((item) =>
                        item.toLowerCase().contains(text.toLowerCase())
                      ).toList();
                      if (text.isEmpty || filtered.contains(text)) {
                        newEntry.selectedItem = text.isNotEmpty ? text : null;
                        newEntry.isOtherItem = false;
                      } else {
                        newEntry.selectedItem = 'Other';
                        newEntry.isOtherItem = true;
                        newEntry.otherItemController.text = text;
                      }
                    });
                  },
                ),
                // Dropdown results
                if (newEntry.itemSearchController.text.isNotEmpty && editItems.any((item) => item.toLowerCase().contains(newEntry.itemSearchController.text.toLowerCase())))
                  Container(
                    constraints: BoxConstraints(maxHeight: 150),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: editItems.length,
                      itemBuilder: (context, i) {
                        final item = editItems[i];
                        if (!item.toLowerCase().contains(newEntry.itemSearchController.text.toLowerCase())) return SizedBox.shrink();
                        return ListTile(
                          leading: Icon(Icons.inventory_2_outlined, color: Colors.orange, size: 18),
                          title: Text(item, style: const TextStyle(fontSize: 13)),
                          dense: true,
                          onTap: () {
                            setDialogState(() {
                              newEntry.itemSearchController.text = item;
                              newEntry.selectedItem = item;
                              newEntry.isOtherItem = false;
                            });
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
            if (newEntry.isOtherItem)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _buildEditTextField(newEntry.otherItemController, 'Enter New Item Name', Icons.edit_note_outlined),
              ),
// TEMP: Quantity + Unit
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: newEntry.qtyController,
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      prefixIcon: Icon(Icons.format_list_numbered, color: Colors.orange),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: newEntry.selectedUnit,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                    ),
                    items: ['kg', 'g', 'pcs'].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                    onChanged: (val) => setDialogState(() => newEntry.selectedUnit = val!),
                  ),
                ),
              ],
            ),
            // Rate
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: TextFormField(
                controller: newEntry.rateController,
                decoration: const InputDecoration(
                  labelText: 'Rate (₹)',
                  prefixIcon: Icon(Icons.currency_rupee, color: Colors.orange),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
// TEMP: Simple vendor dropdown - full search later
            DropdownButtonFormField<String>(
              initialValue: newEntry.selectedVendor,
              decoration: const InputDecoration(
                labelText: 'Vendor Name',
                prefixIcon: Icon(Icons.store_mall_directory_outlined, color: Colors.orange),
                border: OutlineInputBorder(),
              ),
              items: editVendors.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (newValue) {
                setDialogState(() {
                  newEntry.selectedVendor = newValue;
                  newEntry.isOtherVendor = newValue == 'Other';
                });
              },
            ),
            if (newEntry.isOtherVendor)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _buildEditTextField(newEntry.otherVendorController, 'Enter New Vendor Name', Icons.edit_note_outlined),
              ),
            // TEMP: Simple quality specs field
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: TextFormField(
                controller: newEntry.noteController,
                decoration: const InputDecoration(
                  labelText: 'Quality Specs (1. spec1, 2. spec2...)',
                  prefixIcon: Icon(Icons.high_quality_outlined, color: Colors.orange),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: TextFormField(
                controller: TextEditingController(),
                decoration: const InputDecoration(
                  labelText: 'Note (Optional)',
                  prefixIcon: Icon(Icons.note_add_outlined, color: Colors.orange),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            // TEMP: Date picker
            Builder(
              builder: (context) => InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: newEntry.expectedDate ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setDialogState(() {
                      newEntry.expectedDate = picked;
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Expected Date',
                    prefixIcon: Icon(Icons.calendar_today, color: Colors.orange),
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    newEntry.expectedDate == null ? 'Select Date' : DateFormat('dd-MM-yyyy').format(newEntry.expectedDate!),
                  ),
                ),
              ),
            ),
            // Item Total Display
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Item Total:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
  Text("₹ ${((double.tryParse(newEntry.qtyController.text) ?? 0) * (double.tryParse(newEntry.rateController.text) ?? 0)).toStringAsFixed(2)}", 
                       style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }),
                     ],
                   ),
                 ),
                 actions: [
                   TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(fontSize: 13))),
                   ElevatedButton(
                     onPressed: () async {
                       // Update existing items
                       for (var item in localItems) {
                         final response = await http.put(Uri.parse('$apiBaseUrl/update_po_item'), body: json.encode({
                           'id': item['id'],
                           'product_manager': managerCtrl.text,
                           'po_number': poNumCtrl.text,
                           'item_name': item['item_name'],
                           'qty_ordered': item['qty_ordered'],
                           'unit': item['unit'],
                           'rate': item['rate'],
                           'vendor_name': item['vendor_name'],
                           'expected_date': item['expected_date'],
                           'quality_specifications': item['quality_specifications'],
                           'note': item['note'],
                         }), headers: {'Content-Type': 'application/json'});
                         if (response.statusCode != 200) {
                           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to update PO item"), backgroundColor: Colors.red));
                           return;
                         }
                       }

                       // Insert new items
                       // Insert new items (quality specs fixed)
                       for (var newEntry in newItemEntries) {
                         String specs = newEntry.qualityPointsControllers
                             .map((c) => c.text.trim())
                             .where((t) => t.isNotEmpty)
                             .toList()
                             .asMap()
                             .entries
                             .map((e) => "${e.key + 1}. ${e.value}")
                             .join('\\n');

                         final newData = {
                           'product_manager': managerCtrl.text,
                           'po_number': poNumCtrl.text,
                           'item_name': newEntry.isOtherItem ? newEntry.otherItemController.text : (newEntry.selectedItem ?? ''),
                           'qty_ordered': double.tryParse(newEntry.qtyController.text) ?? 0.0,
                           'unit': newEntry.selectedUnit ?? 'kg',
                           'rate': double.tryParse(newEntry.rateController.text) ?? 0.0,
                           'vendor_name': newEntry.isOtherVendor ? newEntry.otherVendorController.text : (newEntry.selectedVendor ?? ''),
                           'expected_date': newEntry.expectedDate != null ? DateFormat('yyyy-MM-dd').format(newEntry.expectedDate!) : DateFormat('yyyy-MM-dd').format(DateTime.now()),
                           'quality_specifications': specs,
                           'note': newEntry.noteController.text.trim(),
                         };
                         final insertResponse = await http.post(
                           Uri.parse('$apiBaseUrl/insert_generated_po'),
                           headers: {'Content-Type': 'application/json'},
                           body: json.encode(newData),
                         );
                         if (insertResponse.statusCode != 200) {
                           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to add new PO item: ${insertResponse.body}"), backgroundColor: Colors.red));
                           return;
                         }
                       }

                       // Clean up
                       for (var newEntry in newItemEntries) {
                         newEntry.dispose();
                       }

                       Navigator.pop(context);
                       _refreshData();
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PO Updated with New Items!"), backgroundColor: Colors.green));
                     },
                     style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                     child: const Text("SAVE ALL", style: TextStyle(fontSize: 13)),
                   ),
                 ],
               );
             }
           );
         }
       );
    }
  }

void _handleEditSO(int soId, List<Map<String, dynamic>> items) async {
    if (await _showPasswordDialog()) {
       final clientCtrl = TextEditingController(text: items.first['client_name']);
       final soNumCtrl = TextEditingController(text: items.first['so_number']);
       String dispatchDate = items.first['date_of_dispatch'];

       List<Map<String, dynamic>> localItems = items.map((e) => Map<String, dynamic>.from(e)).toList();

List<SOItemEntry> newItemEntries = []; // Initialize empty
  List<String> editItems = ['Other'];
  List<String> editClients = ['Other'];
  
Future<void> loadEditData() async {
    try {
      final itemsResponse = await http.get(Uri.parse('$apiBaseUrl/get_items'));
      final clientsResponse = await http.get(Uri.parse('$apiBaseUrl/get_b_grade_clients'));
      if (itemsResponse.statusCode == 200) {
        editItems = ['Other', ...List<String>.from(json.decode(itemsResponse.body))];
      }
      if (clientsResponse.statusCode == 200) {
        editClients = ['Other', ...List<String>.from(json.decode(clientsResponse.body))];
      }
    } catch (e) {
      editItems = ['Other'];
      editClients = ['Other'];
      debugPrint('Failed to load SO edit data: $e');
    }
  }

       showDialog(
         context: context,
         builder: (context) {
           return StatefulBuilder(
             builder: (context, setDialogState) {
               return AlertDialog(
                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                 titlePadding: EdgeInsets.zero,
                 title: Container(
                   padding: const EdgeInsets.all(16),
                   decoration: const BoxDecoration(
                     color: Colors.teal,
                     borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                   ),
                   child: const Text("Edit Sales Order", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                 ),
                 content: SizedBox(
                   width: MediaQuery.of(context).size.width * 0.9,
                   child: ListView(
                     shrinkWrap: true,
                     children: [
                       const SizedBox(height: 10),
                       _buildEditTextField(clientCtrl, "Client Name", Icons.business),
                       const SizedBox(height: 12),
                       _buildEditTextField(soNumCtrl, "SO Number", Icons.receipt_long),
                       InkWell(
                         onTap: () async {
                           final picked = await showDatePicker(
                             context: context,
                             initialDate: DateTime.tryParse(dispatchDate) ?? DateTime.now(),
                             firstDate: DateTime(2000),
                             lastDate: DateTime(2100),
                           );
                           if (picked != null) {
                             setDialogState(() {
                               dispatchDate = DateFormat('yyyy-MM-dd').format(picked);
                             });
                           }
                         },
                         child: Container(
                           width: double.infinity,
                           padding: const EdgeInsets.all(12),
                           margin: const EdgeInsets.only(top: 12),
                           decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                           child: Row(
                             mainAxisAlignment: MainAxisAlignment.spaceBetween,
                             children: [
                               Text("Dispatch Date: $dispatchDate", style: const TextStyle(fontSize: 13)),
                               const Icon(Icons.calendar_today, size: 16, color: Colors.teal),
                             ],
                           ),
                         ),
                       ),
                       const Padding(
                         padding: EdgeInsets.symmetric(vertical: 16.0),
                         child: Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("ITEMS", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12))), Expanded(child: Divider())]),
                       ),
                       ...localItems.asMap().entries.map((entry) {
                         int idx = entry.key;
                         var item = entry.value;
                         return Card(
                           margin: const EdgeInsets.only(bottom: 12),
                           elevation: 0,
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
                           child: Padding(
                             padding: const EdgeInsets.all(12),
                             child: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 Text("Existing Item #${idx + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 13)),
                                 const SizedBox(height: 8),
                                 _buildSmallEditField(TextEditingController(text: item['item_name']), "Item Name", (v) => item['item_name'] = v),
                                 Row(
                                   children: [
                                     Expanded(child: _buildSmallEditField(TextEditingController(text: item['quantity_kg'].toString()), "Kg", (v) => item['quantity_kg'] = double.tryParse(v) ?? item['quantity_kg'], isNum: true)),
                                     const SizedBox(width: 8),
                                     Expanded(child: _buildSmallEditField(TextEditingController(text: item['quantity_pcs'].toString()), "Pcs", (v) => item['quantity_pcs'] = double.tryParse(v) ?? item['quantity_pcs'], isNum: true)),
                                   ],
                                 ),
                               ],
                             ),
                           ),
                         );
                       }),

                       // NEW ITEMS SECTION - MATCHING PO
                       const Padding(
                         padding: EdgeInsets.symmetric(vertical: 16.0),
                         child: Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("ADD NEW ITEMS", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 12))), Expanded(child: Divider())]),
                       ),
                       ElevatedButton.icon(
                         icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 18),
                         label: const Text("➕ Add New Item", style: TextStyle(fontSize: 13)),
                         onPressed: () {
                           if (newItemEntries.length < 10) {
                             loadEditData();
                             setDialogState(() {
                               newItemEntries.add(SOItemEntry());
                             });
                           }
                         },
                         style: ElevatedButton.styleFrom(
                           backgroundColor: Colors.orange.shade600,
                           foregroundColor: Colors.white,
                           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                         ),
                       ),
                       ...newItemEntries.asMap().entries.map((entry) {
                         int idx = entry.key;
                         SOItemEntry newEntry = entry.value;
                         return Card(
                           key: ValueKey('new_so_item_$idx'),
                           margin: EdgeInsets.only(bottom: 12, top: 8),
                           elevation: 2,
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.orange.shade200)),
                           child: Padding(
                             padding: const EdgeInsets.all(12),
                             child: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 Row(
                                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                   children: [
                                     Text("New Item #${idx + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13)),
                                     IconButton(
                                       icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                                       onPressed: () => _removeNewSoItemEntry(idx, newItemEntries, setDialogState),
                                     ),
                                   ],
                                 ),
                                 const SizedBox(height: 8),
                                 // Item search dropdown
                                 Column(
                                   crossAxisAlignment: CrossAxisAlignment.start,
                                   children: [
                                     TextFormField(
                                       controller: newEntry.itemSearchController,
                                       style: const TextStyle(fontSize: 13),
                                       decoration: InputDecoration(
                                         labelText: 'Item Name (Search/Filter)',
                                         labelStyle: TextStyle(fontSize: 13),
                                         prefixIcon: Icon(Icons.inventory_2_outlined, color: Colors.orange, size: 20),
                                         border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                         contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                         filled: true,
                                         fillColor: Colors.grey.shade50,
                                         suffixIcon: newEntry.itemSearchController.text.isNotEmpty
                                             ? IconButton(
                                                 icon: Icon(Icons.clear, size: 18),
                                                 onPressed: () {
                                                   setDialogState(() {
                                                     newEntry.itemSearchController.clear();
                                                     newEntry.selectedItem = null;
                                                     newEntry.isOtherItem = false;
                                                   });
                                                 },
                                               )
                                             : null,
                                       ),
                                       onChanged: (text) {
                                         setDialogState(() {
                                           List<String> filtered = editItems.where((item) =>
                                             item.toLowerCase().contains(text.toLowerCase())
                                           ).toList();
                                           if (text.isEmpty || filtered.contains(text)) {
                                             newEntry.selectedItem = text.isNotEmpty ? text : null;
                                             newEntry.isOtherItem = false;
                                           } else {
                                             newEntry.selectedItem = 'Other';
                                             newEntry.isOtherItem = true;
                                             newEntry.otherItemController.text = text;
                                           }
                                         });
                                       },
                                     ),
                                     if (newEntry.itemSearchController.text.isNotEmpty && editItems.any((item) => item.toLowerCase().contains(newEntry.itemSearchController.text.toLowerCase())))
                                       Container(
                                         constraints: BoxConstraints(maxHeight: 150),
                                         decoration: BoxDecoration(
                                           color: Colors.white,
                                           border: Border.all(color: Colors.grey.shade300),
                                           borderRadius: BorderRadius.circular(12),
                                           boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                                         ),
                                         child: ListView.builder(
                                           shrinkWrap: true,
                                           itemCount: editItems.length,
                                           itemBuilder: (context, i) {
                                             final item = editItems[i];
                                             if (!item.toLowerCase().contains(newEntry.itemSearchController.text.toLowerCase())) return SizedBox.shrink();
                                             return ListTile(
                                               leading: Icon(Icons.inventory_2_outlined, color: Colors.orange, size: 18),
                                               title: Text(item, style: const TextStyle(fontSize: 13)),
                                               dense: true,
                                               onTap: () {
                                                 setDialogState(() {
                                                   newEntry.itemSearchController.text = item;
                                                   newEntry.selectedItem = item;
                                                   newEntry.isOtherItem = false;
                                                 });
                                               },
                                             );
                                           },
                                         ),
                                       ),
                                   ],
                                 ),
                                 if (newEntry.isOtherItem)
                                   Padding(
                                     padding: const EdgeInsets.only(top: 12),
                                     child: _buildEditTextField(newEntry.otherItemController, 'Enter New Item Name', Icons.edit_note_outlined),
                                   ),
                                 // Kg/Pcs Qty row
                                 Row(
                                   children: [
                                     Expanded(
                                       child: TextFormField(
                                         controller: newEntry.qtyKgController,
                                         decoration: const InputDecoration(
                                           labelText: 'Qty (Kg)',
                                           prefixIcon: Icon(Icons.scale, color: Colors.orange),
                                           border: OutlineInputBorder(),
                                         ),
                                         keyboardType: TextInputType.number,
                                       ),
                                     ),
                                     const SizedBox(width: 8),
                                     Expanded(
                                       child: TextFormField(
                                         controller: newEntry.qtyPcsController,
                                         decoration: const InputDecoration(
                                           labelText: 'Qty (Pcs)',
                                           prefixIcon: Icon(Icons.numbers, color: Colors.orange),
                                           border: OutlineInputBorder(),
                                         ),
                                         keyboardType: TextInputType.number,
                                       ),
                                     ),
                                   ],
                                 ),
                                 // Quality specs
                                 Padding(
                                   padding: const EdgeInsets.symmetric(vertical: 4),
                                   child: TextFormField(
                                     controller: newEntry.noteController,
                                     decoration: const InputDecoration(
                                       labelText: 'Quality Specs (1. spec1, 2. spec2...)',
                                       prefixIcon: Icon(Icons.high_quality_outlined, color: Colors.orange),
                                       border: OutlineInputBorder(),
                                     ),
                                   ),
                                 ),
                                 // Note
                                 Padding(
                                   padding: const EdgeInsets.symmetric(vertical: 4),
                                   child: TextFormField(
                                     controller: TextEditingController(),
                                     decoration: const InputDecoration(
                                       labelText: 'Note (Optional)',
                                       prefixIcon: Icon(Icons.note_add_outlined, color: Colors.orange),
                                       border: OutlineInputBorder(),
                                     ),
                                   ),
                                 ),
                                 // Date picker
                                 InkWell(
                                   onTap: () async {
                                     final picked = await showDatePicker(
                                       context: context,
                                       initialDate: newEntry.expectedDate ?? DateTime.now(),
                                       firstDate: DateTime(2000),
                                       lastDate: DateTime(2100),
                                     );
                                     if (picked != null) {
                                       setDialogState(() {
                                         newEntry.expectedDate = picked;
                                       });
                                     }
                                   },
                                   child: InputDecorator(
                                     decoration: const InputDecoration(
                                       labelText: 'Expected Date',
                                       prefixIcon: Icon(Icons.calendar_today, color: Colors.orange),
                                       border: OutlineInputBorder(),
                                     ),
                                     child: Text(
                                       newEntry.expectedDate == null ? 'Select Date' : DateFormat('dd-MM-yyyy').format(newEntry.expectedDate!),
                                     ),
                                   ),
                                 ),
                                 // Item Total Display (Kg * some rate or just qty display)
                                 Container(
                                   padding: const EdgeInsets.all(8),
                                   margin: const EdgeInsets.only(top: 8),
                                   decoration: BoxDecoration(
                                     color: Colors.orange.shade50,
                                     borderRadius: BorderRadius.circular(8),
                                   ),
                                   child: Row(
                                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                     children: [
                                       const Text("Item Qty:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                       Text("${newEntry.qtyKgController.text} Kg + ${newEntry.qtyPcsController.text} Pcs", 
                                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                                     ],
                                   ),
                                 ),
                               ],
                             ),
                           ),
                         );
                       }),
                     ],
                   ),
                 ),
                 actions: [
                   TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(fontSize: 13))),
                   ElevatedButton(
                     onPressed: () async {
                       // Update SO header
                       final soResponse = await http.put(Uri.parse('$apiBaseUrl/update_so'), body: json.encode({
                         'so_id': soId,
                         'client_name': clientCtrl.text,
                         'so_number': soNumCtrl.text,
                         'date_of_dispatch': dispatchDate,
                       }), headers: {'Content-Type': 'application/json'});
                       if (soResponse.statusCode != 200) {
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to update SO"), backgroundColor: Colors.red));
                         return;
                       }
                       // Update existing items
                       for (var item in localItems) {
                         final itemResponse = await http.put(Uri.parse('$apiBaseUrl/update_so_item'), body: json.encode({
                           'id': item['item_id'],
                           'item_name': item['item_name'],
                           'quantity_kg': item['quantity_kg'],
                           'quantity_pcs': item['quantity_pcs'],
                         }), headers: {'Content-Type': 'application/json'});
                         if (itemResponse.statusCode != 200) {
                           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to update SO item"), backgroundColor: Colors.red));
                           return;
                         }
                       }
                       // Insert new items
                       for (var newEntry in newItemEntries) {
                         String specs = newEntry.qualityPointsControllers
                             .map((c) => c.text.trim())
                             .where((t) => t.isNotEmpty)
                             .toList()
                             .asMap()
                             .entries
                             .map((e) => "${e.key + 1}. ${e.value}")
                             .join('\n');

                         // Use new endpoint to add to EXISTING soId
                         final itemData = {
                           'item_name': newEntry.isOtherItem ? newEntry.otherItemController.text : (newEntry.selectedItem ?? ''),
                           'quantity_kg': double.tryParse(newEntry.qtyKgController.text) ?? 0.0,
                           'quantity_pcs': double.tryParse(newEntry.qtyPcsController.text) ?? 0.0,
                         };
                         final insertResponse = await http.post(
                           Uri.parse('$apiBaseUrl/add_so_items'),
                           headers: {'Content-Type': 'application/json'},
                           body: json.encode({
                             'so_id': soId,
                             'items_data': [itemData]
                           }),
                         );
                         if (insertResponse.statusCode != 200) {
                           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to add new SO item: ${insertResponse.body}"), backgroundColor: Colors.red));
                           return;
                         }
                       }

                       // Clean up
                       for (var newEntry in newItemEntries) {
                         newEntry.dispose();
                       }

                       Navigator.pop(context);
                       _refreshData();
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("SO Updated with New Items!"), backgroundColor: Colors.green));
                     },
                     style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                     child: const Text("SAVE ALL", style: TextStyle(fontSize: 13)),
                   ),
                 ],
               );
             }
           );
         }
       );
    }
  }

  // Existing _buildEditTextField used for both PO/SO edit (no duplicate)


  // Existing _buildSmallEditField used for both PO/SO edit (no duplicate)


  // Future<void> _generateAndPreviewPO(String poNumber, String manager, List<Map<String, dynamic>> items) async {
  //   final pdf = pw.Document();
  //   final dateStr = DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now());

  //   pdf.addPage(
  //     pw.Page(
  //       pageFormat: PdfPageFormat.a4,
  //       margin: const pw.EdgeInsets.all(32),
  //       build: (pw.Context context) {
  //         return pw.Column(
  //           crossAxisAlignment: pw.CrossAxisAlignment.start,
  //           children: [
  //             pw.Row(
  //               mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  //               children: [
  //                 pw.Column(
  //                   crossAxisAlignment: pw.CrossAxisAlignment.start,
  //                   children: [
  //                     pw.Text("SHABARI.AI WAREHOUSE", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.teal)),
  //                     pw.Text("Purchase Order Slip", style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
  //                   ],
  //                 ),
  //                 pw.Container(
  //                   padding: const pw.EdgeInsets.all(8),
  //                   decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.teal, width: 2)),
  //                   child: pw.Text("PO: $poNumber", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
  //                 ),
  //               ],
  //             ),
  //             pw.SizedBox(height: 30),
  //             pw.Row(
  //               mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  //               children: [
  //                 pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
  //                   pw.Text("Product Manager:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
  //                   pw.Text(manager, style: const pw.TextStyle(fontSize: 12)),
  //                 ]),
  //                 pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
  //                   pw.Text("Date & Time:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
  //                   pw.Text(dateStr, style: const pw.TextStyle(fontSize: 12)),
  //                 ]),
  //               ],
  //             ),
  //             pw.SizedBox(height: 25),
  //             pw.TableHelper.fromTextArray(
  //               border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
  //               headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
  //               headerDecoration: const pw.BoxDecoration(color: PdfColors.teal),
  //               cellHeight: 30,
  //               cellStyle: const pw.TextStyle(fontSize: 10),
  //               headers: ['Item Name', 'Quantity', 'Rate', 'Vendor', 'Exp. Date', 'Specs & Note'],
  //               data: items.map((item) {
  //                  String specs = item['quality_specifications']?.toString() ?? '';
  //                  String note = item['note']?.toString() ?? '';
  //                  String display = specs;
  //                  if (note.isNotEmpty) {
  //                    display += "${display.isEmpty ? "" : "\n\n"}Note: $note";
  //                  }
  //                  return [
  //                     item['item_name'],
  //                     "${item['qty_ordered']} ${item['unit']}",
  //                     "Rs. ${item['rate']}",
  //                     item['vendor_name'],
  //                     item['expected_date'] != null ? DateFormat('dd-MM-yy').format(DateTime.parse(item['expected_date'])) : "N/A",
  //                     display.isEmpty ? "-" : display,
  //                   ];
  //               }).toList(),
  //             ),
  //             pw.Spacer(),
  //             pw.Row(
  //               mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  //               children: [
  //                 pw.Column(children: [pw.SizedBox(width: 120, child: pw.Divider(thickness: 1)), pw.Text("Authorized Sign", style: const pw.TextStyle(fontSize: 10))]),
  //                 pw.Column(children: [pw.SizedBox(width: 120, child: pw.Divider(thickness: 1)), pw.Text("Receiver Sign", style: const pw.TextStyle(fontSize: 10))]),
  //               ],
  //             ),
  //             pw.SizedBox(height: 10),
  //             pw.Center(child: pw.Text("Thank you for your business!", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))),
  //           ],
  //         );
  //       },
  //     ),
  //   );
  //   await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'PO_Slip_$poNumber');
  // }









  Future<void> _generateAndPreviewPO(String poNumber, String manager, List<Map<String, dynamic>> items) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header Section (Same as before)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("SHABARI.AI WAREHOUSE", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.teal)),
                      pw.Text("Purchase Order Slip", style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.teal, width: 2)),
                    child: pw.Text("PO: $poNumber", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  ),
                ],
              ),
              pw.SizedBox(height: 30),
              
              // Manager & Date Section
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text("Product Manager:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text(manager, style: const pw.TextStyle(fontSize: 12)),
                  ]),
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                    pw.Text("Date & Time:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text(dateStr, style: const pw.TextStyle(fontSize: 12)),
                  ]),
                ],
              ),
              pw.SizedBox(height: 25),

              // --- FIXED WIDTH TABLE START ---
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2),   // Item Name
                  1: pw.FlexColumnWidth(1.2), // Quantity
                  2: pw.FlexColumnWidth(1.2), // Rate
                  3: pw.FlexColumnWidth(1.5), // Vendor
                  4: pw.FlexColumnWidth(1.2), // Exp. Date
                  5: pw.FlexColumnWidth(3),   // Specs & Note (ज्यादा हिस्सा इसे दिया है)
                },
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.teal),
                    children: [
                      'Item Name', 'Quantity', 'Rate', 'Vendor', 'Exp. Date', 'Specs & Note'
                    ].map((h) => pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10)),
                    )).toList(),
                  ),
                  // Table Data Rows
                  ...items.map((item) {
                    String specs = item['quality_specifications']?.toString() ?? '';
                    String note = item['note']?.toString() ?? '';
                    String display = specs;
                    if (note.isNotEmpty) {
                      display += "${display.isEmpty ? "" : "\n\n"}Note: $note";
                    }

                    return pw.TableRow(
                      children: [
                        _buildTableCell(item['item_name']),
                        _buildTableCell("${item['qty_ordered']} ${item['unit']}"),
                        _buildTableCell("Rs. ${item['rate']}"),
                        _buildTableCell(item['vendor_name']),
                        _buildTableCell(item['expected_date'] != null ? DateFormat('dd-MM-yy').format(DateTime.parse(item['expected_date'])) : "N/A"),
                        // Specs & Note Cell
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(display.isEmpty ? "-" : display, style: const pw.TextStyle(fontSize: 9)),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              // --- FIXED WIDTH TABLE END ---

              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(children: [pw.SizedBox(width: 120, child: pw.Divider(thickness: 1)), pw.Text("Authorized Sign", style: const pw.TextStyle(fontSize: 10))]),
                  pw.Column(children: [pw.SizedBox(width: 120, child: pw.Divider(thickness: 1)), pw.Text("Receiver Sign", style: const pw.TextStyle(fontSize: 10))]),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text("Thank you for your business!", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'PO_Slip_$poNumber');
  }

  // Helper widget to make code cleaner
  pw.Widget _buildTableCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 10)),
    );
  }

  // Edit dialog helper methods - copied/adapted from generate_po_number_page.dart
  Widget _buildEditTextField(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.teal, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildSmallEditField(TextEditingController ctrl, String label, Function(String) onChanged, {bool isNum = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: TextField(
        controller: ctrl,
        onChanged: onChanged,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
      ),
    );
  }

  Widget _buildEditItemCard(StateSetter setDialogState, int index, Map<String, dynamic> item, List<String> itemsList, List<String> vendorsList, List<String> unitsList) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Existing Item #${index + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13)),
            const SizedBox(height: 8),
            _buildSmallEditField(TextEditingController(text: item['item_name']), "Item Name", (v) => item['item_name'] = v),
            Row(
              children: [
                Expanded(child: _buildSmallEditField(TextEditingController(text: item['qty_ordered'].toString()), "Qty", (v) => item['qty_ordered'] = double.tryParse(v) ?? item['qty_ordered'], isNum: true)),
                const SizedBox(width: 8),
                Expanded(child: _buildSmallEditField(TextEditingController(text: item['unit'] ?? ''), "Unit", (v) => item['unit'] = v)),
              ],
            ),
            _buildSmallEditField(TextEditingController(text: item['rate'].toString()), "Rate (₹)", (v) => item['rate'] = double.tryParse(v) ?? item['rate'], isNum: true),
            _buildSmallEditField(TextEditingController(text: item['vendor_name'] ?? ''), "Vendor", (v) => item['vendor_name'] = v),
            _buildSmallEditField(TextEditingController(text: item['quality_specifications'] ?? ''), "Quality Specs", (v) => item['quality_specifications'] = v),
            _buildSmallEditField(TextEditingController(text: item['note'] ?? ''), "Note", (v) => item['note'] = v),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(item['expected_date']) ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setDialogState(() {
                    item['expected_date'] = DateFormat('yyyy-MM-dd').format(picked);
                  });
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Expected Date: ${item['expected_date'] ?? 'Not set'}", style: const TextStyle(fontSize: 12)),
                    const Icon(Icons.calendar_today, size: 14, color: Colors.teal),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }















  Future<void> _generateAndPreviewSO(String soNumber, String client, List<Map<String, dynamic>> items) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("SHABARI.AI WAREHOUSE", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.teal)),
                      pw.Text("Sales Order Slip", style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.teal, width: 2)),
                    child: pw.Text("SO: $soNumber", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  ),
                ],
              ),
              pw.SizedBox(height: 30),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text("Client Name:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text(client, style: const pw.TextStyle(fontSize: 12)),
                  ]),
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                    pw.Text("Date & Time:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text(dateStr, style: const pw.TextStyle(fontSize: 12)),
                  ]),
                ],
              ),
              pw.SizedBox(height: 25),
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.teal),
                cellHeight: 30,
                cellStyle: const pw.TextStyle(fontSize: 10),
                headers: ['Item Name', 'Qty (Kg)', 'Qty (Pcs)'],
                data: items.map((item) => [
                  item['item_name'],
                  item['quantity_kg'].toString(),
                  item['quantity_pcs'].toString(),
                ]).toList(),
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(children: [pw.SizedBox(width: 120, child: pw.Divider(thickness: 1)), pw.Text("Authorized Sign", style: const pw.TextStyle(fontSize: 10))]),
                  pw.Column(children: [pw.SizedBox(width: 120, child: pw.Divider(thickness: 1)), pw.Text("Receiver Sign", style: const pw.TextStyle(fontSize: 10))]),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text("Thank you for your business!", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'SO_Slip_$soNumber');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Orders',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.2, fontSize: 18),
        ),
        backgroundColor: Colors.teal,
        elevation: 4,
        actions: [
           IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.white, size: 20),
            onPressed: () {
              _resetTempFilters();
              _scaffoldKey.currentState?.openEndDrawer();
            },
            tooltip: 'Filter',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
            onPressed: _refreshData,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Purchase Orders'),
            Tab(text: 'Sales Orders'),
          ],
        ),
      ),
      drawer: _buildDrawer(),
      endDrawer: _buildFilterPanel(),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPOTable(),
                _buildSOTable(),
              ],
            ),
          ),
           Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, -2))]),
            child: ElevatedButton.icon(
              icon: _isExporting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 20),
              label: Text(_isExporting ? "EXPORTING..." : "EXPORT TO EXCEL & DRIVE", style: const TextStyle(fontSize: 13)),
              onPressed: _isExporting ? null : _handleExport,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade400,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Drawer _buildDrawer() {
    return Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            UserAccountsDrawerHeader(
              accountName: const Text(
                "PO & SO Options",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
              accountEmail: const Text("Manage Purchase & Sales Orders", style: TextStyle(color: Colors.white70, fontSize: 12)),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.receipt_long,
                  size: 32,
                  color: Colors.teal.shade800,
                ),
              ),
              decoration: const BoxDecoration(
                color: Colors.teal,
              ),
            ),
            ListTile(
              leading: Icon(Icons.add_shopping_cart, color: Colors.teal.shade600, size: 20),
              title: const Text(
                'Generate PO Number',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const GeneratePoPage()),
                ).then((_) => _refreshData());
              },
            ),
             ListTile(
              leading: Icon(Icons.add_chart, color: Colors.teal.shade600, size: 20),
              title: const Text(
                'Generate SO Number',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const GenerateSoNumberPage()),
                ).then((_) => _refreshData());
              },
            ),
          ],
        ),
      );
  }

  Widget _buildFilterPanel() {
  return Drawer(
      child: Column(
        children: [
          AppBar(
            title: const Text("Filters", style: TextStyle(color: Colors.white, fontSize: 18)),
            automaticallyImplyLeading: false,
            backgroundColor: Colors.teal.shade700,
            elevation: 1,
            actions: [
              IconButton(
                icon: const Icon(Icons.clear_all, color: Colors.white, size: 20),
                tooltip: "Clear All Filters",
                onPressed: () {
                  _clearAllFilters();
                  Navigator.pop(context);
                },
              )
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildFilterSection(
                  icon: Icons.date_range_outlined,
                  title: "Date Range",
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(context: context, initialDate: _tempStartDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2025));
                            if (picked != null) setState(() => _tempStartDate = picked);
                          },
                          child: Text(_tempStartDate == null ? "Start" : DateFormat('dd/MM/yy').format(_tempStartDate!), style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(context: context, initialDate: _tempEndDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2025));
                            if (picked != null) setState(() => _tempEndDate = picked);
                          },
                          child: Text(_tempEndDate == null ? "End" : DateFormat('dd/MM/yy').format(_tempEndDate!), style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
                 _buildFilterSection(
                  icon: Icons.inventory_2_outlined,
                  title: "Item",
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _tempSelectedItem,
                    hint: const Text("All Items", style: TextStyle(fontSize: 13)),
                    decoration: const InputDecoration(border: InputBorder.none),
                    style: const TextStyle(fontSize: 13, color: Colors.black),
                    items: [const DropdownMenuItem(value: null, child: Text("All Items", style: TextStyle(fontSize: 13))), ..._itemsForFilter.map((item) => DropdownMenuItem(value: item, child: Text(item, style: const TextStyle(fontSize: 13))))],
                    onChanged: (val) => setState(() => _tempSelectedItem = val),
                  ),
                ),
                _buildFilterSection(
                  icon: Icons.person_outline,
                  title: "Client / Vendor",
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _tempSelectedClientVendor,
                    hint: const Text("All Clients/Vendors", style: TextStyle(fontSize: 13)),
                     decoration: const InputDecoration(border: InputBorder.none),
                    style: const TextStyle(fontSize: 13, color: Colors.black),
                    items: [const DropdownMenuItem(value: null, child: Text("All Clients/Vendors", style: TextStyle(fontSize: 13))), ..._clientsVendorsForFilter.map((name) => DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))))],
                    onChanged: (val) => setState(() => _tempSelectedClientVendor = val),
                  ),
                ),
                if (_tabController.index == 0)
                  _buildFilterSection(
                    icon: Icons.receipt_long_outlined,
                    title: "PO Number",
                    child: TextFormField(
                      controller: _poNumberController,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(hintText: "Enter PO Number...", hintStyle: TextStyle(fontSize: 13), border: InputBorder.none),
                    ),
                  ),
                if (_tabController.index == 1)
                  _buildFilterSection(
                  icon: Icons.receipt_long_outlined,
                  title: "SO Number",
                  child: TextFormField(
                    controller: _soNumberController,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(hintText: "Enter SO Number...", hintStyle: TextStyle(fontSize: 13), border: InputBorder.none),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
                icon: const Icon(Icons.check, color: Colors.white, size: 20),
                label: const Text("Apply Filters", style: TextStyle(fontSize: 14)),
                onPressed: () {
                  setState(() {
                    _startDate = _tempStartDate;
                    _endDate = _tempEndDate;
                    _selectedItem = _tempSelectedItem;
                    _selectedClientVendor = _tempSelectedClientVendor;
                    if (_tabController.index == 0) {
                       _poNumber = _poNumberController.text.trim();
                       _soNumber = null;
                    } else {
                       _soNumber = _soNumberController.text.trim();
                       _poNumber = null;
                    }
                  });
                  _applyFilters();
                  Navigator.pop(context);
                },
                 style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          )
        ],
      ),
    );
  }

   Widget _buildFilterSection({required IconData icon, required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.grey.shade600, size: 18),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey.shade800)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
             padding: const EdgeInsets.symmetric(horizontal: 12.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.grey.shade300)
            ),
            child: child
          )
        ],
      ),
    );
  }


  Widget _buildPOTable() {
    Map<String, List<Map<String, dynamic>>> grouped = {};
    List<String> poOrder = [];
    for (var po in _filteredPOs) {
      String poNum = po['po_number']?.toString() ?? 'N/A';
      if (!grouped.containsKey(poNum)) {
        grouped[poNum] = [];
        poOrder.add(poNum);
      }
      grouped[poNum]!.add(po);
    }

    const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 10);
    const cellStyle = TextStyle(fontSize: 9);

     return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Card(
          clipBehavior: Clip.antiAlias,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: _filteredPOs.isEmpty
          ? const Center(child: Text("No PO records found.", style: TextStyle(fontSize: 12)))
          : SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.teal.shade100),
                    dataRowMinHeight: 48,
                    dataRowMaxHeight: 150,
                    columns: const [
                      DataColumn(label: Text('Manager', style: headerStyle)),
                      DataColumn(label: Text('PO Number', style: headerStyle)),
                      DataColumn(label: Text('Item', style: headerStyle)),
                      DataColumn(label: Text('Qty', style: headerStyle)),
                      DataColumn(label: Text('Unit', style: headerStyle)),
                      DataColumn(label: Text('Rate', style: headerStyle)),
                      DataColumn(label: Text('Vendor', style: headerStyle)),
                      DataColumn(label: Text('Specs & Note', style: headerStyle)),
                      DataColumn(label: Text('Expected Date', style: headerStyle)),
                      DataColumn(label: Text('Actions', style: headerStyle)),
                    ],
                    rows: poOrder.map((poNum) {
                      final group = grouped[poNum]!;
                      final first = group.first;
                      // print("Row poNum => '$poNum'");
                      return DataRow(cells: [
                        DataCell(Text(first['product_manager']?.toString() ?? '', style: cellStyle)),
                        DataCell(Text(poNum, style: cellStyle)),
                        DataCell(_buildStackedCell(group, (item) => item['item_name']?.toString() ?? '')),
                        DataCell(_buildStackedCell(group, (item) => item['qty_ordered']?.toString() ?? '')),
                        DataCell(_buildStackedCell(group, (item) => item['unit']?.toString() ?? '')),
                        DataCell(_buildStackedCell(group, (item) => "₹${item['rate']}")),
                        DataCell(_buildStackedCell(group, (item) => item['vendor_name']?.toString() ?? '')),
                        DataCell(_buildStackedCell(group, (item) {
                           String specs = item['quality_specifications']?.toString() ?? '';
                           String note = item['note']?.toString() ?? '';
                           String display = specs;
                           if (note.isNotEmpty) {
                             display += "${display.isEmpty ? "" : "\n\n"}Note: $note";
                           }
                           return display.isEmpty ? "-" : display;
                        })),
                        DataCell(_buildStackedCell(group, (item) => item['expected_date'] != null ? DateFormat('dd-MM-yy').format(DateTime.parse(item['expected_date'])) : '')),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.blueGrey, size: 18), onPressed: () => _generateAndPreviewPO(poNum, first['product_manager'], group)),
                            IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 18), onPressed: () => _handleEditPO(poNum, group)),
                            IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => _handleDeletePO(poNum)),
                          ],
                        )),
                      ]);
                    }).toList(),
                  ),
                ),
              ),

        ),
      );
  }

  Widget _buildSOTable() {
    Map<int, List<Map<String, dynamic>>> grouped = {};
    List<int> soOrder = [];
    for (var so in _filteredSOs) {
      int soId = so['so_id'];
      if (!grouped.containsKey(soId)) {
        grouped[soId] = [];
        soOrder.add(soId);
      }
      grouped[soId]!.add(so);
    }

    const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 10);
    const cellStyle = TextStyle(fontSize: 9);

     return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Card(
          clipBehavior: Clip.antiAlias,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: _filteredSOs.isEmpty
          ? const Center(child: Text("No SO records found.", style: TextStyle(fontSize: 12)))
          : SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.teal.shade100),
                    dataRowMinHeight: 48,
                    dataRowMaxHeight: 150,
                    columns: const [
                      DataColumn(label: Text('Client', style: headerStyle)),
                      DataColumn(label: Text('Location', style: headerStyle)),
                      DataColumn(label: Text('KM', style: headerStyle)),
                      DataColumn(label: Text('SO Number', style: headerStyle)),
                      DataColumn(label: Text("Dispatch Date", style: headerStyle)),
                      DataColumn(label: Text('Item', style: headerStyle)),
                      DataColumn(label: Text('Qty (Kg)', style: headerStyle)),
                      DataColumn(label: Text('Qty (Pcs)', style: headerStyle)),
                      DataColumn(label: Text('Actions', style: headerStyle)),
                    ],
                     rows: soOrder.map((soId) {
                        final group = grouped[soId]!;
                        final first = group.first;
                        return DataRow(cells: [
                          DataCell(Text(first['client_name']?.toString() ?? '', style: cellStyle)),
                          DataCell(Text(first['location']?.toString() ?? '-', style: cellStyle)),
                          DataCell(Text(first['km']?.toString() ?? '-', style: cellStyle)),
                          DataCell(Text(first['so_number']?.toString() ?? '', style: cellStyle)),
                          DataCell(Text(first['date_of_dispatch'] != null ? DateFormat('dd-MM-yy').format(DateTime.parse(first['date_of_dispatch'])) : '', style: cellStyle)),
                          DataCell(_buildStackedCell(group, (item) => item['item_name']?.toString() ?? '')),
                          DataCell(_buildStackedCell(group, (item) => item['quantity_kg']?.toString() ?? '')),
                          DataCell(_buildStackedCell(group, (item) => item['quantity_pcs']?.toString() ?? '')),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.blueGrey, size: 18), onPressed: () => _generateAndPreviewSO(first['so_number'], first['client_name'], group)),
                              IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 18), onPressed: () => _handleEditSO(soId, group)),
                              IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => _handleDeleteSO(soId)),
                            ],
                          )),
                        ]);
                     }).toList(),
                  ),
                ),
              ),
        ),
      );
  }

  Widget _buildStackedCell(List<Map<String, dynamic>> group, String Function(Map<String, dynamic>) labelMapper) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: group.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Text(labelMapper(item), style: const TextStyle(fontSize: 9)),
          )).toList(),
        ),
      ),
    );
  }

  Future<void> _handleExport() async {
    final dataToExport = _tabController.index == 0 ? _filteredPOs : _filteredSOs;
    if (dataToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to export.', style: TextStyle(fontSize: 12)), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _isExporting = true);
    try {
      final excelFile = excel.Excel.createExcel();
      final excel.Sheet sheet = excelFile[excelFile.getDefaultSheet()!];

      final List<String> headers = _tabController.index == 0
          ? ['Manager', 'Item', 'PO Number', 'Qty', 'Vendor', 'Specs', 'Note', 'Expected Date']
          : ['Client', 'Location', 'KM', 'SO Number', 'Dispatch Date', 'Item', 'Qty (Kg)', 'Qty (Pcs)'];

      sheet.appendRow(headers.map((h) => excel.TextCellValue(h)).toList());

      if (_tabController.index == 0) {
        for (var rowData in dataToExport) {
           sheet.appendRow([
              excel.TextCellValue(rowData['product_manager']?.toString() ?? ''),
              excel.TextCellValue(rowData['item_name']?.toString() ?? ''),
              excel.TextCellValue(rowData['po_number']?.toString() ?? ''),
              excel.TextCellValue(rowData['qty_ordered']?.toString() ?? ''),
              excel.TextCellValue(rowData['vendor_name']?.toString() ?? ''),
              excel.TextCellValue(rowData['quality_specifications']?.toString() ?? ''),
              excel.TextCellValue(rowData['note']?.toString() ?? ''),
              excel.TextCellValue(rowData['expected_date'] != null ? DateFormat('dd-MM-yy').format(DateTime.parse(rowData['expected_date'])) : ''),
           ]);
        }
      } else {
         Map<int, List<Map<String, dynamic>>> groupedSOs = {};
          for (var so in dataToExport) {
            groupedSOs.putIfAbsent(so['so_id'], () => []).add(so);
          }
          groupedSOs.forEach((soId, items) {
            for (int i = 0; i < items.length; i++) {
              final item = items[i];
              sheet.appendRow([
                excel.TextCellValue(i == 0 ? item['client_name']?.toString() ?? '' : ''),
                excel.TextCellValue(i == 0 ? item['location']?.toString() ?? '' : ''),
                excel.TextCellValue(i == 0 ? item['km']?.toString() ?? '' : ''),
                excel.TextCellValue(i == 0 ? item['so_number']?.toString() ?? '' : ''),
                excel.TextCellValue(i == 0 ? (item['date_of_dispatch'] != null ? DateFormat('dd-MM-yy').format(DateTime.parse(item['date_of_dispatch'])) : '') : ''),
                excel.TextCellValue(item['item_name']?.toString() ?? ''),
                excel.TextCellValue(item['quantity_kg']?.toString() ?? ''),
                excel.TextCellValue(item['quantity_pcs']?.toString() ?? ''),
              ]);
            }
          });
      }

      final Directory? directory = await getExternalStorageDirectory();
      if (directory == null) throw Exception("Could not get storage directory.");
      final String fileName = '${_tabController.index == 0 ? 'PurchaseOrders' : 'SalesOrders'}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final String filePath = '${directory.path}/$fileName';
      final fileBytes = excelFile.save();
      if (fileBytes == null) throw Exception("Failed to create Excel file bytes.");
      final file = File(filePath)..writeAsBytesSync(fileBytes);
      const String driveFolderId = "1GpkW87U4N2DpD_QxCM4re1jn90VJB52V";
      await uploadFileToDrive(file, driveFolderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exported & Uploaded to Drive!', style: TextStyle(fontSize: 12)), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: ${e.toString()}', style: const TextStyle(fontSize: 12)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<ServiceAccountCredentials> _loadCredentials() async {
    final jsonString = await rootBundle.loadString('assets/service_account_key.json');
    final jsonContent = json.decode(jsonString);
    return ServiceAccountCredentials.fromJson(jsonContent);
  }

  Future<void> uploadFileToDrive(File file, String folderId) async {
    try {
      final credentials = await _loadCredentials();
      final client = await clientViaServiceAccount(credentials, [drive.DriveApi.driveScope]);
      final driveApi = drive.DriveApi(client);
      var fileMetadata = drive.File()
        ..name = file.path.split('/').last
        ..parents = [folderId];
      await driveApi.files.create(
        fileMetadata,
        uploadMedia: drive.Media(file.openRead(), file.lengthSync()),
      );
    } catch (e) {
      throw Exception("Failed to upload to Google Drive: $e");
    }
  }
}
