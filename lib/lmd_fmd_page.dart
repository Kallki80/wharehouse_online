import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart' as excel;
import 'package:intl/intl.dart';
import 'lmd_page.dart';
import 'fmd_page.dart';
import 'make_payment_page.dart';

import 'api_config.dart';

enum TableType { lmd, fmd }

class LmdFmdPage extends StatefulWidget {
  const LmdFmdPage({super.key});

  @override
  State<LmdFmdPage> createState() => _LmdFmdPageState();
}

class _LmdFmdPageState extends State<LmdFmdPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late Future<List<Map<String, dynamic>>> _dataFuture;
  List<Map<String, dynamic>> _currentData = [];

  TableType _selectedTable = TableType.lmd;
  bool _isExporting = false;

  // Filter state
  String? _driverName, _vehicleNumber, _location, _paymentStatus;
  DateTime? _startDate, _endDate;
  final _driverNameController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _locationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<List<Map<String, dynamic>>> _fetchFilteredData(String endpoint, Map<String, String> queryParams) async {
    final uri = Uri.parse('$apiBaseUrl$endpoint').replace(queryParameters: queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    } else {
      throw Exception('Failed to load data from $endpoint');
    }
  }

  void _loadData() {
    setState(() {
      final queryParams = <String, String>{};
      if (_driverName != null && _driverName!.isNotEmpty) queryParams['driver_name'] = _driverName!;
      if (_vehicleNumber != null && _vehicleNumber!.isNotEmpty) queryParams['vehicle_number'] = _vehicleNumber!;
      if (_location != null && _location!.isNotEmpty) queryParams['location'] = _location!;
      if (_startDate != null) queryParams['start_date'] = DateFormat('yyyy-MM-dd').format(_startDate!);
      if (_endDate != null) queryParams['end_date'] = DateFormat('yyyy-MM-dd').format(_endDate!);
      if (_paymentStatus != null) queryParams['payment_status'] = _paymentStatus!;

      if (_selectedTable == TableType.lmd) {
        _dataFuture = _fetchFilteredData('/get_filtered_lmd_data', queryParams);
      } else {
        _dataFuture = _fetchFilteredData('/get_filtered_fmd_data', queryParams);
      }
    });
  }

  @override
  void dispose() {
    _driverNameController.dispose();
    _vehicleNumberController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _openFilterPanel() {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  void _applyFilters() {
    setState(() {
      _driverName = _driverNameController.text;
      _vehicleNumber = _vehicleNumberController.text;
      _location = _locationController.text;
    });
    _loadData();
    Navigator.pop(context); // Close the drawer
  }

  void _clearFilters() {
    setState(() {
      _driverName = null;
      _vehicleNumber = null;
      _location = null;
      _startDate = null;
      _endDate = null;
      _paymentStatus = null;

      _driverNameController.clear();
      _vehicleNumberController.clear();
      _locationController.clear();
    });
    _loadData();
  }

  Future<ServiceAccountCredentials> _loadCredentials() async {
    final directory = await getApplicationDocumentsDirectory();
    final jsonFile = File('${directory.path}/service_account_key.json');
    if (!jsonFile.existsSync()) {
      final jsonString = await rootBundle.loadString('assets/service_account_key.json');
      await jsonFile.writeAsString(jsonString);
    }
    final jsonContent = json.decode(await jsonFile.readAsString());
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

  Future<void> _handleExport() async {
    if (_isExporting) return; // Prevent multiple exports if already running

    if (_currentData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to export.', style: TextStyle(fontSize: 12)), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _isExporting = true);
    try {
      final excelFile = excel.Excel.createExcel();
      final excel.Sheet sheet = excelFile[excelFile.getDefaultSheet()!];

      if (_currentData.isNotEmpty) {
        final headers = _currentData.first.keys.toList();
        sheet.appendRow(headers.map((h) => excel.TextCellValue(h.replaceAll('_', ' ').toUpperCase())).toList());
      }

      for (var rowData in _currentData) {
        final rowAsStrings = rowData.values.map((cell) => cell.toString()).toList();
        sheet.appendRow(rowAsStrings.map((cell) => excel.TextCellValue(cell)).toList());
      }

      final Directory? directory = await getExternalStorageDirectory();
      if (directory == null) throw Exception("Could not get storage directory.");

      final String tableName = _selectedTable == TableType.lmd ? 'LMD' : 'FMD';
      final String fileName = '${tableName}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
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

  Future<bool> _showPasswordDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const _PasswordDialog(),
    );
    return result ?? false;
  }

  Future<void> _handleDelete(int id) async {
    final isPasswordCorrect = await _showPasswordDialog();
    if (!mounted) return;

    if (!isPasswordCorrect) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect Password!', style: TextStyle(fontSize: 12)), backgroundColor: Colors.red),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion', style: TextStyle(fontSize: 16)),
        content: const Text('Are you sure you want to delete this entry? This action cannot be undone.', style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('CANCEL', style: TextStyle(fontSize: 13))),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DELETE', style: TextStyle(color: Colors.red, fontSize: 13)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final endpoint = _selectedTable == TableType.lmd ? '/delete_lmd_data' : '/delete_fmd_data';
      final response = await http.delete(
        Uri.parse('$apiBaseUrl$endpoint'),
        body: json.encode({'id': id}),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        _loadData(); // Refresh the data
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entry successfully deleted.', style: TextStyle(fontSize: 12)), backgroundColor: Colors.green),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete entry.', style: TextStyle(fontSize: 12)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleEdit(Map<String, dynamic> data) async {
    final isPasswordCorrect = await _showPasswordDialog();
     if (!mounted) return;
    if (!isPasswordCorrect) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect Password!', style: TextStyle(fontSize: 12)), backgroundColor: Colors.red),
      );
      return;
    }

    if (_selectedTable == TableType.lmd) {
      await Navigator.push(context, MaterialPageRoute(builder: (context) => LmdPage(dataToEdit: data)));
    } else {
      await Navigator.push(context, MaterialPageRoute(builder: (context) => FmdPage(dataToEdit: data)));
    }
    _loadData(); // Refresh data after returning from edit page
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('LMD & FMD Records', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter Data',
            onPressed: _openFilterPanel,
          ),
        ],
      ),
      drawer: _buildDrawer(theme),
      endDrawer: _buildFilterDrawer(theme),
      body: Column(
        children: [
          _buildTableSelector(theme),
          Expanded(
            child: _buildDataTable(theme),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              icon: _isExporting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(Icons.cloud_upload_outlined, color: theme.colorScheme.onPrimary, size: 20),
              label: Text(_isExporting ? "EXPORTING..." : "EXPORT TO EXCEL & DRIVE", style: const TextStyle(fontSize: 13)),
              onPressed: _currentData.isEmpty ? null : _handleExport,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                disabledBackgroundColor: Colors.grey.shade400,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(ThemeData theme) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: theme.colorScheme.primary),
            child: Text('Entry Forms', style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 20)),
          ),
          ListTile(
            leading: Icon(Icons.local_shipping, color: theme.colorScheme.primary, size: 20),
            title: const Text('Book LMD', style: TextStyle(fontSize: 14)),
            onTap: () => _navigateToPage(const LmdPage()),
          ),
          ListTile(
            leading: Icon(Icons.store, color: theme.colorScheme.primary, size: 20),
            title: const Text('Book FMD', style: TextStyle(fontSize: 14)),
            onTap: () => _navigateToPage(const FmdPage()),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.payment, color: theme.colorScheme.primary, size: 20),
            title: const Text('Make Payment', style: TextStyle(fontSize: 14)),
            onTap: () => _navigateToPage(const MakePaymentPage()),
          ),
        ],
      ),
    );
  }

  void _navigateToPage(Widget page) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (context) => page)).then((_) => _loadData());
  }

  Widget _buildFilterDrawer(ThemeData theme) {
    return Drawer(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Text('Filter Options', style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary, fontSize: 18)),
            const SizedBox(height: 20),
            TextField(controller: _driverNameController, style: const TextStyle(fontSize: 13), decoration: const InputDecoration(labelText: 'Driver Name', labelStyle: TextStyle(fontSize: 13), border: OutlineInputBorder(), prefixIcon: Icon(Icons.person, size: 20))),
            const SizedBox(height: 10),
            TextField(controller: _vehicleNumberController, style: const TextStyle(fontSize: 13), decoration: const InputDecoration(labelText: 'Vehicle Number', labelStyle: TextStyle(fontSize: 13), border: OutlineInputBorder(), prefixIcon: Icon(Icons.directions_car, size: 20))),
            const SizedBox(height: 10),
            TextField(controller: _locationController, style: const TextStyle(fontSize: 13), decoration: const InputDecoration(labelText: 'Location', labelStyle: TextStyle(fontSize: 13), border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_on, size: 20))),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    onPressed: () async {
                      final date = await showDatePicker(context: context, initialDate: _startDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                      if (date != null) setState(() => _startDate = date);
                    },
                    label: Text(_startDate == null ? 'Start Date' : DateFormat('dd/MM/yy').format(_startDate!), style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    onPressed: () async {
                      final date = await showDatePicker(context: context, initialDate: _endDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                      if (date != null) setState(() => _endDate = date);
                    },
                    label: Text(_endDate == null ? 'End Date' : DateFormat('dd/MM/yy').format(_endDate!), style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
             const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _paymentStatus,
              decoration: const InputDecoration(
                labelText: 'Payment Status',
                labelStyle: TextStyle(fontSize: 13),
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.payment, size: 20),
              ),
              style: const TextStyle(fontSize: 13, color: Colors.black),
              items: ['All', 'Paid', 'Unpaid'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value, style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _paymentStatus = (newValue == 'All') ? null : newValue;
                });
              },
            ),
            const SizedBox(height: 40),
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(onPressed: _applyFilters, style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: theme.colorScheme.onPrimary, padding: const EdgeInsets.symmetric(vertical: 16)), child: const Text('Apply Filters', style: TextStyle(fontSize: 14))),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(onPressed: _clearFilters, style: TextButton.styleFrom(foregroundColor: theme.colorScheme.secondary), child: const Text('Clear Filters', style: TextStyle(fontSize: 13))),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTableSelector(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SegmentedButton<TableType>(
        style: SegmentedButton.styleFrom(
          backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.196),
          foregroundColor: theme.colorScheme.primary,
          selectedForegroundColor: theme.colorScheme.onPrimary,
          selectedBackgroundColor: theme.colorScheme.primary,
        ),
        segments: const [
          ButtonSegment(value: TableType.lmd, label: Text('LMD', style: TextStyle(fontSize: 13)), icon: Icon(Icons.local_shipping, size: 18)),
          ButtonSegment(value: TableType.fmd, label: Text('FMD', style: TextStyle(fontSize: 13)), icon: Icon(Icons.store, size: 18)),
        ],
        selected: {_selectedTable},
        onSelectionChanged: (Set<TableType> newSelection) {
          setState(() {
            _selectedTable = newSelection.first;
            _loadData();
          });
        },
      ),
    );
  }

  Widget _buildDataTable(ThemeData theme) {
  return FutureBuilder<List<Map<String, dynamic>>>(
    future: _dataFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
      }
      if (snapshot.hasError) {
        return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(fontSize: 12)));
      }
      if (!snapshot.hasData || snapshot.data!.isEmpty) {
        _currentData = [];
        return const Center(child: Text('No records found.', style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic)));
      }

      _currentData = snapshot.data!;
      final columns = _currentData.first.keys.map((key) {
        return DataColumn(
          label: Text(
            key.replaceAll('_', ' ').toUpperCase(),
            style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList()
      ..add(DataColumn(
          label: Text(
            'ACTIONS',
            style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 10),
          ),
        ));

      final rows = _currentData.asMap().entries.map((entry) {
        int idx = entry.key;
        Map<String, dynamic> row = entry.value;

        final cells = row.values.map((cell) => DataCell(Text(cell.toString(), style: const TextStyle(fontSize: 9)))).toList();
        cells.add(
          DataCell(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.edit, color: theme.colorScheme.secondary, size: 18),
                  tooltip: 'Edit',
                  onPressed: () => _handleEdit(row),
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: theme.colorScheme.error, size: 18),
                  tooltip: 'Delete',
                  onPressed: () => _handleDelete(row['id'] as int),
                ),
              ],
            ),
          ),
        );

        return DataRow(
          color: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              if (idx.isEven) return theme.colorScheme.primary.withValues(alpha: 0.05);
              return null; // Use default value for other states and odd rows.
            },
          ),
          cells: cells,
        );
      }).toList();

      return SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: columns,
            rows: rows,
            headingRowColor: WidgetStateProperty.resolveWith<Color?>((states) => theme.colorScheme.primary.withValues(alpha: 0.1)),
            dataRowMinHeight: 45,
            dataRowMaxHeight: 65,
            columnSpacing: 20,
            border: TableBorder.all(
              width: 1.0,
              color: Colors.black.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      );
    },
  );
}

}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  __PasswordDialogState createState() => __PasswordDialogState();
}

class __PasswordDialogState extends State<_PasswordDialog> {
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter Password', style: TextStyle(fontSize: 16)),
      content: TextField(
        controller: _passwordController,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Password', labelStyle: TextStyle(fontSize: 14)),
        style: const TextStyle(fontSize: 14),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel', style: TextStyle(fontSize: 13))),
        TextButton(
          onPressed: () {
            if (_passwordController.text == '1008') {
              Navigator.of(context).pop(true);
            } else {
              Navigator.of(context).pop(false);
            }
          },
          child: const Text('Submit', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}
