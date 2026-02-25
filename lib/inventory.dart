import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'purchase.dart';
import 'stock_update.dart';
import 'b-grade_sales.dart';
import 'sales.dart';
import 'rejection_received.dart';
import 'vendor_rejection.dart';
import 'dump_sale.dart';
import 'mandi_resale.dart';
import 'check_inventory.dart';

const String apiBaseUrl = 'http://13.53.71.103:5000/';
// const String apiBaseUrl = 'http://10.0.2.2:5000';

enum TableType { purchase, stockUpdate, bGradeSales, sales, rejectionReceived, vendorRejection, dumpSale, mandiResale }

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  TableType _selectedTable = TableType.purchase;

  String _getUpdateEndpoint(TableType type) {
    switch (type) {
      case TableType.purchase: return '/update_purchase';
      case TableType.stockUpdate: return '/update_stock_update';
      case TableType.bGradeSales: return '/update_b_grade_sale';
      case TableType.sales: return '/update_sale';
      case TableType.rejectionReceived: return '/update_rejection_received';
      case TableType.vendorRejection: return '/update_vendor_rejection';
      case TableType.dumpSale: return '/update_dump_sale';
      case TableType.mandiResale: return '/update_mandi_resale';
    }
  }

  List<Map<String, dynamic>> _allData = [];
  List<Map<String, dynamic>> _filteredData = [];

  DateTime? _startDate, _endDate;
  String? _selectedItem, _selectedClientVendor, _poNumber, _pcs, _itemTag;

  DateTime? _tempStartDate, _tempEndDate;
  String? _tempSelectedItem, _tempSelectedClientVendor;
  final TextEditingController _poNumberController = TextEditingController();
  final TextEditingController _pcsController = TextEditingController();
  final TextEditingController _itemTagController = TextEditingController();

  List<String> _itemsForFilter = [];
  List<String> _clientsVendorsForFilter = [];
  bool _isExporting = false;
  bool _isLoadingData = true; 
  static const String _authPassword = "1008";

  Future<List<Map<String, dynamic>>> _fetchData(String endpoint) async {
    final response = await http.get(Uri.parse('$apiBaseUrl$endpoint'));
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    } else {
      throw Exception('Failed to load data from $endpoint');
    }
  }

  Future<List<String>> _fetchStringList(String endpoint) async {
    final response = await http.get(Uri.parse('$apiBaseUrl$endpoint'));
    if (response.statusCode == 200) {
      return List<String>.from(json.decode(response.body));
    } else {
      throw Exception('Failed to load data from $endpoint');
    }
  }

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    await _loadData();
    await _populateFilterOptions();
  }

  @override
  void dispose() {
    _poNumberController.dispose();
    _pcsController.dispose();
    _itemTagController.dispose();
    super.dispose();
  }

  String _getGetAllEndpoint(TableType type) {
    switch (type) {
      case TableType.purchase: return '/get_all_purchases';
      case TableType.stockUpdate: return '/get_all_stock_updates';
      case TableType.bGradeSales: return '/get_all_b_grade_sales';
      case TableType.sales: return '/get_all_sales';
      case TableType.rejectionReceived: return '/get_all_rejection_received';
      case TableType.vendorRejection: return '/get_all_vendor_rejections';
      case TableType.dumpSale: return '/get_all_dump_sales';
      case TableType.mandiResale: return '/get_all_mandi_resales';
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() { _isLoadingData = true; });

    try {
      List<Map<String, dynamic>> data = await _fetchData(_getGetAllEndpoint(_selectedTable));
      if (!mounted) return;
      setState(() {
        _allData = data;
        _applyFilters();
        _isLoadingData = false;
      });
    } catch (e) {
      debugPrint("Error loading data: $e");
      if (mounted) setState(() { _isLoadingData = false; });
    }
  }

  Future<void> _populateFilterOptions() async {
    try {
      final results = await Future.wait([
        _fetchStringList('/get_items'),
        _fetchStringList('/get_vendors'),
        _fetchStringList('/get_purchase_vendors'),
        _fetchStringList('/get_b_grade_clients')
      ]);
      if (!mounted) return;
      setState(() {
        _itemsForFilter = results[0]..sort();
        _clientsVendorsForFilter = {...results[1], ...results[2], ...results[3]}.toList()..sort();
      });
    } catch (e) {
      debugPrint("Error populating filters: $e");
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> data = List.from(_allData);
    if (_startDate != null && _endDate != null) {
      data = data.where((row) {
        try {
          final dateStr = row['date'] ?? row['ctrl_date'];
          final rowDate = DateTime.parse(dateStr);
          return rowDate.isAfter(_startDate!.subtract(const Duration(days: 1))) && rowDate.isBefore(_endDate!.add(const Duration(days: 1)));
        } catch (e) { return false; }
      }).toList();
    }
    if (_selectedItem != null) data = data.where((row) => row['item'] == _selectedItem).toList();
    if (_selectedClientVendor != null) data = data.where((row) => (row['vendor'] == _selectedClientVendor) || (row['clint'] == _selectedClientVendor) || (row['client_name'] == _selectedClientVendor)).toList();
    if (_poNumber != null && _poNumber!.isNotEmpty) data = data.where((row) => row['po_number']?.toString().contains(_poNumber!) ?? false).toList();
    if (_pcs != null && _pcs!.isNotEmpty) data = data.where((row) => row['pcs']?.toString() == _pcs).toList();
    if (_itemTag != null && _itemTag!.isNotEmpty) data = data.where((row) => row['item_tag']?.toString().contains(_itemTag!) ?? false).toList();
    setState(() { _filteredData = data; });
  }

  void _clearAllFilters() {
    setState(() { 
      _startDate = _endDate = _selectedItem = _selectedClientVendor = _poNumber = _pcs = _itemTag = null; 
      _poNumberController.clear(); _pcsController.clear(); _itemTagController.clear();
      _tempStartDate = _tempEndDate = _tempSelectedItem = _tempSelectedClientVendor = null;
      _applyFilters(); 
    });
  }

  void _resetTempFilters() {
    _tempStartDate = _startDate; _tempEndDate = _endDate;
    _tempSelectedItem = _selectedItem; _tempSelectedClientVendor = _selectedClientVendor;
    _poNumberController.text = _poNumber ?? ''; _pcsController.text = _pcs ?? '';
    _itemTagController.text = _itemTag ?? '';
  }

  Future<bool> _checkAuth() async {
    String entered = "";
    return await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Authentication Required"),
        content: TextField(obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "Enter Password"), onChanged: (v) => entered = v),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, entered == _authPassword), child: const Text("VERIFY")),
        ],
      ),
    ) ?? false;
  }

  void _handleDelete(int id) async {
    if (await _checkAuth()) {
      final response = await http.delete(
        Uri.parse('$apiBaseUrl/delete_multiple_entries'),
        body: json.encode({'table_name': _getTableNameFromEnum(), 'ids': [id]}),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        _loadData();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Entry Deleted")));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to delete entry"), backgroundColor: Colors.red));
      }
    }
  }

  void _handleEdit(Map<String, dynamic> row) async {
    if (await _checkAuth()) {
      final controllers = <String, TextEditingController>{};
      row.forEach((key, value) {
        if (key != 'id') {
          controllers[key] = TextEditingController(text: value?.toString() ?? '');
        }
      });

      void calculateRelatedValues(StateSetter setDialogState) {
        if (_selectedTable == TableType.purchase || _selectedTable == TableType.sales || _selectedTable == TableType.bGradeSales) {
          double qty = double.tryParse(controllers['quantity']?.text ?? controllers['qty_receive']?.text ?? '0') ?? 0;
          double rate = double.tryParse(controllers['rate']?.text ?? '0') ?? 0;
          
          if (controllers.containsKey('total_value')) {
            double total = qty * rate;
            controllers['total_value']!.text = total.toStringAsFixed(2);
            
            double paid = double.tryParse(controllers['amount_paid']?.text ?? '0') ?? 0;
            double due = total - paid;
            controllers['amount_due']?.text = due.toStringAsFixed(2);
            
            String status = 'Unpaid';
            if (total > 0) {
              if (paid >= total) {
                status = 'Paid';
              } else if (paid > 0) status = 'Partial Paid';
            }
            controllers['payment_status']?.text = status;
          }
        } else if (_selectedTable == TableType.stockUpdate) {
          double a = double.tryParse(controllers['a_grade_qty']?.text ?? '0') ?? 0;
          double b = double.tryParse(controllers['b_grade_qty']?.text ?? '0') ?? 0;
          double c = double.tryParse(controllers['c_grade_qty']?.text ?? '0') ?? 0;
          double u = double.tryParse(controllers['ungraded_qty']?.text ?? '0') ?? 0;
          double d = double.tryParse(controllers['dump_qty']?.text ?? '0') ?? 0;
          controllers['total_qty']?.text = (a + b + c + u + d).toStringAsFixed(2);
        }
        setDialogState(() {});
      }

      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text("Edit ${_selectedTable.name.toUpperCase()}"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: controllers.entries.map<Widget>((e) {
                  final String key = e.key;
                  final TextEditingController ctrl = e.value;
                  bool isAuto = (key == 'amount_due' || key == 'payment_status' || key == 'total_qty' || key == 'total_value');

                  if (key == 'item' || key == 'item_name') {
                    return _buildEditDropdown(key, ctrl, _itemsForFilter, setDialogState, calculateRelatedValues);
                  }
                  if (key == 'vendor' || key == 'clint' || key == 'client_name' || key == 'product_manager' || key == 'vendor_name') {
                    return _buildEditDropdown(key, ctrl, _clientsVendorsForFilter, setDialogState, calculateRelatedValues);
                  }
                  if (key == 'payment_status') {
                    return _buildEditDropdown(key, ctrl, ["Unpaid", "Paid", "Partial Paid"], setDialogState, calculateRelatedValues);
                  }
                  if (key == 'date' || key == 'ctrl_date') {
                    return _buildEditDateField(key, ctrl, context, setDialogState);
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: TextField(
                      controller: ctrl,
                      decoration: InputDecoration(
                        labelText: key.replaceAll('_', ' ').toUpperCase(),
                        border: const OutlineInputBorder(),
                        filled: isAuto,
                        fillColor: isAuto ? Colors.grey.shade100 : null,
                        suffixIcon: isAuto ? const Icon(Icons.auto_fix_high, size: 16, color: Colors.blueGrey) : null,
                      ),
                      readOnly: isAuto,
                      keyboardType: (row[key] is num) ? TextInputType.number : TextInputType.text,
                      onChanged: (_) => calculateRelatedValues(setDialogState),
                    ),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final updated = <String, dynamic>{'id': row['id']};
                    controllers.forEach((key, ctrl) {
                      if (row[key] is double) {
                        updated[key] = double.tryParse(ctrl.text) ?? 0.0;
                      } else if (row[key] is int) {
                        updated[key] = int.tryParse(ctrl.text) ?? 0;
                      } else {
                        updated[key] = ctrl.text;
                      }
                    });
                    
                    final response = await http.put(
                      Uri.parse('$apiBaseUrl${_getUpdateEndpoint(_selectedTable)}'),
                      body: json.encode(updated),
                      headers: {'Content-Type': 'application/json'},
                    ).timeout(const Duration(seconds: 10));

                    if (response.statusCode == 200) {
                      if (mounted) {
                        Navigator.pop(ctx);
                        _loadData();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Updated Successfully"), backgroundColor: Colors.green));
                      }
                    } else {
                      throw Exception('Server Error: ${response.statusCode}');
                    }
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                  }
                },
                child: const Text("SAVE"),
              ),
            ],
          ),
        ),
      );
    }
  }

  // Widget _buildEditDropdown(String key, TextEditingController ctrl, List<String> options, StateSetter setDialogState, Function calculate) {
  //   String? currentVal = options.contains(ctrl.text) ? ctrl.text : null;
  //   return Padding(
  //     padding: const EdgeInsets.symmetric(vertical: 4.0),
  //     child: DropdownButtonFormField<String>(
  //       value: currentVal,
  //       decoration: InputDecoration(labelText: key.replaceAll('_', ' ').toUpperCase(), border: const OutlineInputBorder()),
  //       items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt, overflow: TextOverflow.ellipsis))).toList(),
  //       onChanged: (val) {
  //         if (val != null) {
  //           ctrl.text = val;
  //           calculate(setDialogState);
  //         }
  //       },
  //     ),
  //   );
  // }

  Widget _buildEditDateField(String key, TextEditingController ctrl, BuildContext context, StateSetter setDialogState) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: TextFormField(
        controller: ctrl,
        readOnly: true,
        decoration: InputDecoration(
          labelText: key.replaceAll('_', ' ').toUpperCase(),
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today),
        ),
        onTap: () async {
          DateTime initialDate = DateTime.tryParse(ctrl.text) ?? DateTime.now();
          DateTime? picked = await showDatePicker(context: context, initialDate: initialDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
          if (picked != null) {
            ctrl.text = DateFormat('yyyy-MM-dd').format(picked);
            setDialogState(() {});
          }
        },
      ),
    );
  }

  Future<void> _generatePdf(List<Map<String, dynamic>> items) async {
    final pdf = pw.Document();
    final first = items.first;
    final dateStr = _formatDate(first['date'] ?? first['ctrl_date']);
    final timeStr = first['time']?.toString() ?? 'N/A';
    
    pdf.addPage(pw.Page(
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
                    pw.Text("${_selectedTable.name.toUpperCase()} SLIP", style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("Date: $dateStr", style: const pw.TextStyle(fontSize: 10)),
                    pw.Text("Time: $timeStr", style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Divider(thickness: 1, color: PdfColors.grey300),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (first['po_number'] != null) pw.Text("PO/SO Number: ${first['po_number']}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    if (first['vendor'] != null || first['clint'] != null || first['client_name'] != null)
                      pw.Text("Party Name: ${first['vendor'] ?? first['clint'] ?? first['client_name']}", style: const pw.TextStyle(fontSize: 11)),
                  ]
                ),
                if (first['item_tag'] != null) pw.Text("Tag: ${first['item_tag']}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              ]
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.teal),
              cellHeight: 25,
              cellStyle: const pw.TextStyle(fontSize: 9),
              headers: _getPdfTableHeaders(),
              data: items.map((i) => _getPdfRowData(i)).toList(),
            ),
            pw.Spacer(),
            pw.Divider(thickness: 1, color: PdfColors.grey300),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(children: [
                  pw.SizedBox(width: 120, child: pw.Divider(thickness: 1, color: PdfColors.grey400)),
                  pw.Text("Authorized Signature", style: const pw.TextStyle(fontSize: 10)),
                ]),
                pw.Column(children: [
                  pw.SizedBox(width: 120, child: pw.Divider(thickness: 1, color: PdfColors.grey400)),
                  pw.Text("Receiver Signature", style: const pw.TextStyle(fontSize: 10)),
                ]),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Center(child: pw.Text("This is a computer generated slip.", style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic))),
          ],
        );
      },
    ));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Slip_${first['id']}');
  }

  List<String> _getPdfTableHeaders() {
    switch (_selectedTable) {
      case TableType.purchase: return ['Tag', 'Item', 'Received', 'Accepted', 'Rejected', 'Rate', 'Total'];
      case TableType.stockUpdate: return ['Item', 'A-Grade', 'B-Grade', 'C-Grade', 'Ungraded', 'Dump'];
      case TableType.bGradeSales: return ['Item', 'Qty', 'Rate', 'Total', 'Paid', 'Due'];
      case TableType.sales: return ['Tag', 'Item', 'Qty', 'Rate', 'Total', 'Paid', 'Due'];
      case TableType.rejectionReceived: return ['Tag', 'Item', 'Qty', 'Pcs', 'Reason'];
      case TableType.vendorRejection: return ['Item', 'Qty', 'Pcs', 'Reason'];
      case TableType.dumpSale: return ['Tag', 'Item', 'Qty', 'Pcs'];
      case TableType.mandiResale: return ['Tag', 'Item', 'Qty', 'Pcs'];
      default: return ['Item', 'Quantity', 'Details'];
    }
  }

  List<String> _getPdfRowData(Map<String, dynamic> row) {
    switch (_selectedTable) {
      case TableType.purchase: return [row['item_tag'] ?? '', row['item'] ?? '', "${row['qty_receive']} ${row['unit_receive']}", "${row['qty_accept'] ?? '0'} ${row['unit_accept'] ?? ''}", "${row['qty_reject'] ?? '0'} ${row['unit_reject'] ?? ''}", row['rate']?.toString() ?? '0', row['total_value']?.toString() ?? '0'];
      case TableType.stockUpdate: return [row['item'] ?? '', "${row['a_grade_qty']} ${row['a_grade_unit']}", "${row['b_grade_qty']} ${row['b_grade_unit']}", "${row['c_grade_qty']} ${row['c_grade_unit']}", "${row['ungraded_qty'] ?? '0'} ${row['ungraded_unit'] ?? ''}", "${row['dump_qty'] ?? '0'} ${row['dump_unit'] ?? ''}"];
      case TableType.bGradeSales: return [row['item'] ?? '', "${row['quantity']} ${row['unit']}", row['rate']?.toString() ?? '0', row['total_value']?.toString() ?? '0', row['amount_paid']?.toString() ?? '0', row['amount_due']?.toString() ?? '0'];
      case TableType.sales: return [row['item_tag'] ?? '', row['item'] ?? '', "${row['quantity']} ${row['unit']}", row['rate']?.toString() ?? '0', row['total_value']?.toString() ?? '0', row['amount_paid']?.toString() ?? '0', row['amount_due']?.toString() ?? '0'];
      case TableType.rejectionReceived: return [row['item_tag'] ?? '', row['item'] ?? '', "${row['quantity']} ${row['unit']}", row['pcs']?.toString() ?? '', row['reason'] ?? ''];
      case TableType.vendorRejection: return [row['item'] ?? '', "${row['quantity_sent']} ${row['unit']}", row['pcs']?.toString() ?? '', row['reason'] ?? ''];
      case TableType.dumpSale: return [row['item_tag'] ?? '', row['item'] ?? '', "${row['quantity']} ${row['unit']}", row['pcs']?.toString() ?? ''];
      case TableType.mandiResale: return [row['item_tag'] ?? '', row['item'] ?? '', "${row['quantity']} ${row['unit']}", row['pcs']?.toString() ?? ''];
      default: return [row['item'] ?? '', row['quantity']?.toString() ?? '', ''];
    }
  }

  Future<ServiceAccountCredentials> _loadCredentials() async {
    final jsonString = await rootBundle.loadString('assets/service_account_key.json');
    return ServiceAccountCredentials.fromJson(json.decode(jsonString));
  }

  Future<void> uploadFileToDrive(File file, String folderId) async {
    try {
      final credentials = await _loadCredentials();
      final client = await clientViaServiceAccount(credentials, [drive.DriveApi.driveScope]);
      final driveApi = drive.DriveApi(client);
      var fileMetadata = drive.File()..name = file.path.split('/').last..parents = [folderId];
      await driveApi.files.create(fileMetadata, uploadMedia: drive.Media(file.openRead(), file.lengthSync()));
    } catch (e) { throw Exception("Failed to upload to Google Drive: $e"); }
  }

  Future<File?> _generateExcelFile() async {
    if (_filteredData.isEmpty) return null;
    final excelFile = excel.Excel.createExcel();
    final excel.Sheet sheet = excelFile[excelFile.getDefaultSheet()!];
    final headers = _getColumnsForTable().map((col) => (col.label as Text).data!).where((h) => h != 'Actions').toList();
    sheet.appendRow(headers.map((h) => excel.TextCellValue(h)).toList());
    for (var rowData in _filteredData) {
      final rowAsStrings = _getRowDataAsString(rowData);
      sheet.appendRow(rowAsStrings.map((cell) => excel.TextCellValue(cell)).toList());
    }
    final Directory? directory = await getExternalStorageDirectory();
    if (directory == null) return null;
    final String fileName = '${_selectedTable.name}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
    final file = File('${directory.path}/$fileName')..writeAsBytesSync(excelFile.save()!);
    return file;
  }

  Future<void> _handleDriveUpload() async {
    setState(() => _isExporting = true);
    try {
      final file = await _generateExcelFile();
      if (file == null) throw "Excel generation failed";
      await uploadFileToDrive(file, "1GpkW87U4N2DpD_QxCM4re1jn90VJB52V");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploaded to Google Drive!'), backgroundColor: Colors.green));
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red)); }
    finally { if (mounted) setState(() => _isExporting = false); }
  }

  List<String> _getRowDataAsString(Map<String, dynamic> row) {
    String date = _formatDate(row['date'] ?? row['ctrl_date']);
    if (_selectedTable == TableType.purchase) return [row['item_tag'] ?? '', row['item'] ?? '', row['vendor'] ?? '', row['po_number'] ?? '', "${row['qty_receive']} ${row['unit_receive']}", row['total_value']?.toString() ?? '0', row['amount_paid']?.toString() ?? '0', row['amount_due']?.toString() ?? '0', row['payment_status'] ?? '', date];
    if (_selectedTable == TableType.stockUpdate) return [row['item'] ?? '', row['po_number'] ?? '', "${row['a_grade_qty']} ${row['a_grade_unit']}", "${row['b_grade_qty']} ${row['b_grade_unit']}", "${row['c_grade_qty']} ${row['c_grade_unit']}", "${row['ungraded_qty'] ?? '0'} ${row['ungraded_unit'] ?? ''}", "${row['dump_qty'] ?? '0'} ${row['dump_unit'] ?? ''}", row['total_qty']?.toString() ?? '', date];
    if (_selectedTable == TableType.rejectionReceived) return [row['item_tag'] ?? '', row['item'] ?? '', row['client_name'] ?? '', row['po_number'] ?? '', "${row['quantity']} ${row['unit']}", row['pcs']?.toString() ?? '', row['reason'] ?? '', date];
    if (_selectedTable == TableType.vendorRejection) return [row['item'] ?? '', row['vendor'] ?? '', row['po_number'] ?? '', "${row['quantity_sent']} ${row['unit']}", row['pcs']?.toString() ?? '', date];
    if (_selectedTable == TableType.bGradeSales) return [row['item'] ?? '', row['clint'] ?? '', row['po_number'] ?? '', "${row['quantity']} ${row['unit']}", row['total_value']?.toString() ?? '0', row['amount_paid']?.toString() ?? '0', row['amount_due']?.toString() ?? '0', date];
    if (_selectedTable == TableType.sales) return [row['item_tag'] ?? '', row['item'] ?? '', row['clint'] ?? '', row['po_number'] ?? '', "${row['quantity']} ${row['unit']}", row['total_value']?.toString() ?? '0', row['amount_paid']?.toString() ?? '0', row['amount_due']?.toString() ?? '0', date];
    if (_selectedTable == TableType.dumpSale || _selectedTable == TableType.mandiResale) return [row['item_tag'] ?? '', row['item'] ?? '', row['po_number']?.toString() ?? '', "${row['quantity']} ${row['unit']}", row['pcs']?.toString() ?? '', date];
    return [row['item'] ?? '', row['vendor'] ?? row['clint'] ?? row['client_name'] ?? '', row['po_number']?.toString() ?? '', row['quantity']?.toString() ?? row['qty_receive']?.toString() ?? '', date];
  }

  String _getTableNameFromEnum() {
    switch (_selectedTable) {
      case TableType.purchase: return 'purchases'; case TableType.stockUpdate: return 'stock_updates';
      case TableType.bGradeSales: return 'b_grade_sales'; case TableType.sales: return 'sales';
      case TableType.rejectionReceived: return 'rejection_received'; case TableType.vendorRejection: return 'vendor_rejections';
      case TableType.dumpSale: return 'dump_sales'; case TableType.mandiResale: return 'mandi_resales';
    }
  }

  List<DataColumn> _getColumnsForTable() {
    List<String> cols = [];
    switch (_selectedTable) {
      case TableType.purchase: cols = ['Tag', 'Item', 'Vendor', 'PO Num', 'Qty (Kg)', 'Qty (Pcs)', 'Total', 'Paid', 'Due', 'Status', 'Date', 'Actions']; break;
      case TableType.stockUpdate: cols = ['Item', 'PO Num', 'A-Grade (Kg/Pcs)', 'B-Grade (Kg/Pcs)', 'C-Grade (Kg/Pcs)', 'Ungraded (Kg/Pcs)', 'Dump (Kg/Pcs)', 'Total Kg', 'Date', 'Actions']; break;
      case TableType.sales: cols = ['Tag', 'Item', 'Client', 'PO Num', 'Qty (Kg)', 'Qty (Pcs)', 'Total', 'Paid', 'Due', 'Status', 'Date', 'Actions']; break;
      case TableType.rejectionReceived: cols = ['Tag', 'Item', 'Client', 'PO Num', 'Qty (Kg)', 'Qty (Pcs)', 'Reason', 'Date', 'Actions']; break;
      case TableType.vendorRejection: cols = ['Item', 'Vendor', 'PO Num', 'Qty (Kg)', 'Qty (Pcs)', 'Date', 'Actions']; break;
      case TableType.dumpSale: cols = ['Tag', 'Item', 'PO Num', 'Qty (Kg)', 'Qty (Pcs)', 'Date', 'Actions']; break;
      case TableType.mandiResale: cols = ['Tag', 'Item', 'PO Num', 'Qty (Kg)', 'Qty (Pcs)', 'Date', 'Actions']; break;
      case TableType.bGradeSales: cols = ['Item', 'Client', 'PO Num', 'Qty (Kg)', 'Qty (Pcs)', 'Total', 'Paid', 'Due', 'Status', 'Date', 'Actions']; break;
      default: cols = ['Item', 'Client/Vendor', 'PO Num', 'Qty', 'Date', 'Actions'];
    }
    return cols.map((c) => DataColumn(label: Text(c, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 11)))).toList();
  }

  List<DataRow> _getRowsForTable() {
    if (_selectedTable == TableType.purchase || _selectedTable == TableType.sales || _selectedTable == TableType.rejectionReceived || _selectedTable == TableType.bGradeSales || _selectedTable == TableType.dumpSale || _selectedTable == TableType.mandiResale) {
      Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var row in _filteredData) {
        String key = "${row['po_number']}_${row['clint'] ?? row['vendor'] ?? row['client_name']}_${row['date']}_${row['time']}";
        grouped.putIfAbsent(key, () => []).add(row);
      }
      return grouped.entries.map((e) => _buildGroupedRow(e.key, e.value)).toList();
    }
    return _filteredData.map((row) => DataRow(cells: _buildCells(row))).toList();
  }

  DataRow _buildGroupedRow(String key, List<Map<String, dynamic>> items) {
    final first = items.first;
    const style = TextStyle(fontSize: 11);
    
    double subTotal = items.fold(0, (sum, i) => sum + (i['total_value'] as num? ?? 0).toDouble());
    double subPaid = items.fold(0, (sum, i) => sum + (i['amount_paid'] as num? ?? 0).toDouble());
    double subDue = items.fold(0, (sum, i) => sum + (i['amount_due'] as num? ?? 0).toDouble());

    return DataRow(cells: [
      if (_selectedTable == TableType.purchase || _selectedTable == TableType.rejectionReceived || _selectedTable == TableType.sales || _selectedTable == TableType.dumpSale || _selectedTable == TableType.mandiResale) 
        DataCell(Text(first['item_tag'] ?? '', style: style)),
      DataCell(_buildStackedText(items, (i) => i['item'] ?? '')),
      if (_selectedTable != TableType.dumpSale && _selectedTable != TableType.mandiResale)
        DataCell(Text(first['vendor'] ?? first['clint'] ?? first['client_name'] ?? '', style: style)),
      DataCell(Text(first['po_number']?.toString() ?? '', style: style)),
      
      if (_selectedTable == TableType.purchase) ...[
        DataCell(_buildStackedText(items, (i) => "${i['qty_receive']} ${i['unit_receive']}")),
        DataCell(_buildStackedText(items, (i) => i['pcs_receive']?.toString() ?? '0')),
        DataCell(Text(subTotal.toStringAsFixed(2), style: style)),
        DataCell(Text(subPaid.toStringAsFixed(2), style: const TextStyle(fontSize: 11, color: Colors.green))),
        DataCell(Text(subDue.toStringAsFixed(2), style: const TextStyle(fontSize: 11, color: Colors.red))),
        DataCell(_buildStatusCell(first['payment_status'])),
      ] else if (_selectedTable == TableType.rejectionReceived) ...[
        DataCell(_buildStackedText(items, (i) => "${i['quantity']} ${i['unit']}")),
        DataCell(_buildStackedText(items, (i) => i['pcs']?.toString() ?? '')),
        DataCell(_buildStackedText(items, (i) => i['reason'] ?? '')),
      ] else if (_selectedTable == TableType.sales || _selectedTable == TableType.bGradeSales) ...[
        DataCell(_buildStackedText(items, (i) => "${i['quantity']} ${i['unit']}")),
        DataCell(_buildStackedText(items, (i) => i['pcs']?.toString() ?? '0')),
        DataCell(Text(subTotal.toStringAsFixed(2), style: style)),
        DataCell(Text(subPaid.toStringAsFixed(2), style: const TextStyle(fontSize: 11, color: Colors.green))),
        DataCell(Text(subDue.toStringAsFixed(2), style: const TextStyle(fontSize: 11, color: Colors.red))),
        DataCell(_buildStatusCell(first['payment_status'])),
      ] else if (_selectedTable == TableType.dumpSale || _selectedTable == TableType.mandiResale) ...[
        DataCell(_buildStackedText(items, (i) => "${i['quantity']} ${i['unit']}")),
        DataCell(_buildStackedText(items, (i) => i['pcs']?.toString() ?? '')),
      ] else ...[
        DataCell(_buildStackedText(items, (i) => i['quantity']?.toString() ?? '')),
        DataCell(_buildStackedText(items, (i) => i['pcs']?.toString() ?? '')),
      ],
      DataCell(Text(_formatDate(first['date'] ?? first['ctrl_date']), style: style)),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.blueGrey, size: 18), onPressed: () => _generatePdf(items)),
        IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 18), onPressed: () => _handleEdit(first)),
        IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => _handleDelete(first['id'])),
      ])),
    ]);
  }

  Widget _buildStatusCell(String? status) {
    Color color = Colors.red;
    if (status == 'Paid') {
      color = Colors.green;
    } else if (status == 'Partial Paid') color = Colors.orange;
    return Text(status ?? 'Unpaid', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color));
  }

  Widget _buildStackedText(List<Map<String, dynamic>> items, String Function(Map<String, dynamic>) mapper) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: items.map((i) => Text(mapper(i), style: const TextStyle(fontSize: 11))).toList());
  }

  List<DataCell> _buildCells(Map<String, dynamic> row) {
    const style = TextStyle(fontSize: 11);
    if (_selectedTable == TableType.stockUpdate) {
      return [
        DataCell(Text(row['item'] ?? '', style: style)),
        DataCell(Text(row['po_number'] ?? '', style: style)),
        DataCell(Text("${row['a_grade_qty']} Kg / ${row['pcs_a_grade'] ?? 0} Pcs", style: style)),
        DataCell(Text("${row['b_grade_qty']} Kg / ${row['pcs_b_grade'] ?? 0} Pcs", style: style)),
        DataCell(Text("${row['c_grade_qty']} Kg / ${row['pcs_c_grade'] ?? 0} Pcs", style: style)),
        DataCell(Text("${row['ungraded_qty'] ?? 0} Kg / ${row['pcs_ungraded'] ?? 0} Pcs", style: style)),
        DataCell(Text("${row['dump_qty'] ?? 0} Kg / ${row['pcs_dump'] ?? 0} Pcs", style: style)),
        DataCell(Text(row['total_qty']?.toString() ?? '', style: style)),
        DataCell(Text(_formatDate(row['date']), style: style)),
        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.blueGrey, size: 18), onPressed: () => _generatePdf([row])),
          IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 18), onPressed: () => _handleEdit(row)),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => _handleDelete(row['id']))
        ]))
      ];
    }
    if (_selectedTable == TableType.vendorRejection) {
      return [DataCell(Text(row['item'] ?? '', style: style)), DataCell(Text(row['vendor'] ?? '', style: style)), DataCell(Text(row['po_number'] ?? '', style: style)), DataCell(Text("${row['quantity_sent']} ${row['unit']}", style: style)), DataCell(Text(row['pcs']?.toString() ?? '', style: style)), DataCell(Text(_formatDate(row['date']), style: style)), DataCell(Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.blueGrey, size: 18), onPressed: () => _generatePdf([row])), IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 18), onPressed: () => _handleEdit(row)), IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => _handleDelete(row['id']))]))];
    }
    if (_selectedTable == TableType.dumpSale || _selectedTable == TableType.mandiResale) {
      return [DataCell(Text(row['item_tag'] ?? '', style: style)), DataCell(Text(row['item'] ?? '', style: style)), DataCell(Text(row['po_number']?.toString() ?? '', style: style)), DataCell(Text("${row['quantity']} ${row['unit']}", style: style)), DataCell(Text(row['pcs']?.toString() ?? '', style: style)), DataCell(Text(_formatDate(row['date']), style: style)), DataCell(Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.blueGrey, size: 18), onPressed: () => _generatePdf([row])), IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 18), onPressed: () => _handleEdit(row)), IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => _handleDelete(row['id']))]))];
    }
    return [DataCell(Text(row['item'] ?? '', style: style)), DataCell(Text(row['vendor'] ?? row['clint'] ?? row['client_name'] ?? '', style: style)), DataCell(Text(row['po_number']?.toString() ?? '', style: style)), DataCell(Text(row['quantity']?.toString() ?? row['qty_receive']?.toString() ?? '')), DataCell(Text(_formatDate(row['date']), style: style)), DataCell(Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.blueGrey, size: 18), onPressed: () => _generatePdf([row])), IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 18), onPressed: () => _handleEdit(row)), IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => _handleDelete(row['id']))]))];
  }

  String _formatDate(String? s) { if (s == null || s.isEmpty) return ''; try { return DateFormat('dd-MM-yy').format(DateTime.parse(s)); } catch (e) { return s; } }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(title: const Text("DASHBOARD", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), backgroundColor: Colors.indigo, iconTheme: const IconThemeData(color: Colors.white), actions: [IconButton(icon: const Icon(Icons.filter_list), onPressed: () { _resetTempFilters(); _scaffoldKey.currentState?.openEndDrawer(); }), IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData)]),
      drawer: _buildSideDrawer(),
      endDrawer: _buildFilterPanel(),
      body: Column(children: [
        _buildTopTabs(),
        Expanded(
          child: _isLoadingData 
            ? const Center(child: CircularProgressIndicator())
            : _filteredData.isEmpty 
              ? const Center(child: Text("No data found")) 
              : RefreshIndicator(onRefresh: _loadData, child: SingleChildScrollView(scrollDirection: Axis.vertical, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: _getColumnsForTable(), rows: _getRowsForTable(), headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50))))),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, -2))]),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: _isExporting ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cloud_upload, color: Colors.white, size: 18),
                  label: const Text("DRIVE UPLOAD", style: TextStyle(fontSize: 12)),
                  onPressed: _isExporting || _filteredData.isEmpty ? null : _handleDriveUpload,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildSideDrawer() {
    return Drawer(child: ListView(padding: EdgeInsets.zero, children: [
      UserAccountsDrawerHeader(accountName: const Text("Inventory Pro", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), accountEmail: const Text("Dashboard & Navigation"), currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.inventory, size: 36, color: Colors.indigo)), decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.indigo.shade700, Colors.indigo.shade400], begin: Alignment.topLeft, end: Alignment.bottomRight))),
      _buildDrawerListTile(icon: Icons.shopping_cart, title: "Purchase Entry", color: Colors.blue, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const Page1())).then((_) => _loadData())),
      _buildDrawerListTile(icon: Icons.update, title: "Stock Update", color: Colors.orange, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const Page2())).then((_) => _loadData())),
      _buildDrawerListTile(icon: Icons.trending_down, title: "B-Grade Sales", color: Colors.teal, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const Page3())).then((_) => _loadData())),
      _buildDrawerListTile(icon: Icons.point_of_sale, title: "Sales", color: Colors.green, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const Page4())).then((_) => _loadData())),
      _buildDrawerListTile(icon: Icons.cancel, title: "Rejection Received", color: Colors.red, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RejectionReceived())).then((_) => _loadData())),
      const Divider(),
      _buildDrawerListTile(icon: Icons.undo, title: "Vendor Rejection", color: Colors.purple, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const VendorRejectionPage())).then((_) => _loadData())),
      _buildDrawerListTile(icon: Icons.delete_sweep, title: "Dump Sale", color: Colors.brown, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DumpSale())).then((_) => _loadData())),
      _buildDrawerListTile(icon: Icons.store_mall_directory, title: "Mandi Resale", color: Colors.pink, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MandiResale())).then((_) => _loadData())),
      _buildDrawerListTile(icon: Icons.analytics_outlined, title: "Reports", color: Colors.indigo, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CheckInventory())).then((_) => _loadData())),
    ]));
  }

  Widget _buildDrawerListTile({required IconData icon, required String title, required VoidCallback onTap, required Color color}) { return ListTile(leading: Icon(icon, color: color), title: Text(title), onTap: () { Navigator.pop(context); onTap(); }); }

  Widget _buildTopTabs() { return Container(height: 50, padding: const EdgeInsets.symmetric(vertical: 8), child: ListView(scrollDirection: Axis.horizontal, children: TableType.values.map((type) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(type.name.toUpperCase()), selected: _selectedTable == type, onSelected: (val) { if (val) { setState(() { _selectedTable = type; _loadData(); }); } }))).toList())); }

  Widget _buildFilterPanel() {
    return Drawer(
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 16, bottom: 16, left: 16, right: 16),
            color: Colors.indigo,
            width: double.infinity,
            child: const Text("Filters", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: [
                _buildFilterSection(icon: Icons.date_range, title: "Date Range", child: Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () async { final p = await showDatePicker(context: context, initialDate: _tempStartDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100)); if (p != null) setState(() => _tempStartDate = p); }, child: Text(_tempStartDate == null ? "Start" : DateFormat('dd/MM/yy').format(_tempStartDate!), style: const TextStyle(fontSize: 11)))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton(onPressed: () async { final p = await showDatePicker(context: context, initialDate: _tempEndDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100)); if (p != null) setState(() => _tempEndDate = p); }, child: Text(_tempEndDate == null ? "End" : DateFormat('dd/MM/yy').format(_tempEndDate!), style: const TextStyle(fontSize: 11)))),
                ])),
                _buildFilterSection(icon: Icons.inventory_2_outlined, title: "Item", child: DropdownButtonFormField<String>(isExpanded: true, value: _tempSelectedItem, hint: const Text("All Items"), items: [const DropdownMenuItem(value: null, child: Text("All Items")), ..._itemsForFilter.map((item) => DropdownMenuItem(value: item, child: Text(item)))], onChanged: (val) => setState(() => _tempSelectedItem = val))),
                _buildFilterSection(icon: Icons.person_outline, title: "Client / Vendor", child: DropdownButtonFormField<String>(isExpanded: true, value: _tempSelectedClientVendor, hint: const Text("All Clients/Vendors"), items: [const DropdownMenuItem(value: null, child: Text("All Clients/Vendors")), ..._clientsVendorsForFilter.map((name) => DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis)))], onChanged: (val) => setState(() => _tempSelectedClientVendor = val))),
                _buildFilterSection(icon: Icons.receipt_long_outlined, title: "PO Number", child: TextField(controller: _poNumberController, decoration: const InputDecoration(hintText: "Enter PO Number", contentPadding: EdgeInsets.symmetric(vertical: 8)))),
                _buildFilterSection(icon: Icons.numbers, title: "PCS", child: TextField(controller: _pcsController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "Enter PCS", contentPadding: EdgeInsets.symmetric(vertical: 8)))),
                _buildFilterSection(icon: Icons.tag, title: "Item Tag", child: TextField(controller: _itemTagController, decoration: const InputDecoration(hintText: "Enter Item Tag", contentPadding: EdgeInsets.symmetric(vertical: 8)))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, -2))]),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () { 
                    setState(() { 
                      _startDate = _tempStartDate; 
                      _endDate = _tempEndDate; 
                      _selectedItem = _tempSelectedItem;
                      _selectedClientVendor = _tempSelectedClientVendor;
                      _poNumber = _poNumberController.text;
                      _pcs = _pcsController.text;
                      _itemTag = _itemTagController.text;
                    }); 
                    _applyFilters(); 
                    Navigator.pop(context); 
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 40), backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  child: const Text("Apply Filters"),
                ),
                TextButton(
                  onPressed: () { _clearAllFilters(); Navigator.pop(context); },
                  child: const Text("Clear All", style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection({required IconData icon, required String title, required Widget child}) { return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, size: 18, color: Colors.grey), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))]), const SizedBox(height: 8), child])); }

  Widget _buildEditDropdown(String key, TextEditingController ctrl, List<String> options, StateSetter setDialogState, Function calculate) {
    String? currentVal = options.contains(ctrl.text) ? ctrl.text : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: DropdownButtonFormField<String>(
        value: currentVal,
        decoration: InputDecoration(labelText: key.replaceAll('_', ' ').toUpperCase(), border: const OutlineInputBorder()),
        items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (val) {
          if (val != null) {
            ctrl.text = val;
            calculate(setDialogState);
          }
        },
      ),
    );
  }
  //
  // Widget _buildEditDateField(String key, TextEditingController ctrl, BuildContext context, StateSetter setDialogState) {
  //   return Padding(
  //     padding: const EdgeInsets.symmetric(vertical: 4.0),
  //     child: TextFormField(
  //       controller: ctrl,
  //       readOnly: true,
  //       decoration: InputDecoration(
  //         labelText: key.replaceAll('_', ' ').toUpperCase(),
  //         border: const OutlineInputBorder(),
  //         suffixIcon: const Icon(Icons.calendar_today),
  //       ),
  //       onTap: () async {
  //         DateTime initialDate = DateTime.tryParse(ctrl.text) ?? DateTime.now();
  //         DateTime? picked = await showDatePicker(context: context, initialDate: initialDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
  //         if (picked != null) {
  //           ctrl.text = DateFormat('yyyy-MM-dd').format(picked);
  //           setDialogState(() {});
  //         }
  //       },
  //     ),
  //   );
  // }
}
