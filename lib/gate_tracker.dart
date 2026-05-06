import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_config.dart';
import 'app_theme.dart';

class GateTrackerPage extends StatefulWidget {
  const GateTrackerPage({super.key});

  @override
  State<GateTrackerPage> createState() => _GateTrackerPageState();
}

class _GateTrackerPageState extends State<GateTrackerPage> {
  DateTime? _selectedDate;
  bool _isLoading = false;
  bool _isFetchingTotals = false;
  bool _isGeneratingGate = false;

  // Daily Totals (KG)
  Map<String, double> _totals = {
    'purchase_total': 0.0,
    'sales_total': 0.0, 
    'bgrade_total': 0.0,
    'rejection_total': 0.0,
    'dump_total': 0.0,
    'mandi_total': 0.0,
  };

  // Gate Form
  final _formKey = GlobalKey<FormState>();
  String? _nextGateNumber;
  final _vehicleController = TextEditingController();
  final _driverController = TextEditingController();
  final _partyController = TextEditingController();
  final _remarksController = TextEditingController();

  // Recent Records
  List<Map<String, dynamic>> _recentGates = [];
  int _gatePage = 1;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadDateTotals();
    _generateGateNumber();
    _loadRecentGates();
  }

  // From check_inventory.dart - adapted for date totals
  Future<Map<String, double>> getDateTotals(String dateStr) async {
    final uri = Uri.parse('$apiBaseUrl/get_date_totals?date=$dateStr');
    final response = await http.get(uri);
    
    if (response.statusCode == 200) {
      return Map<String, double>.from(json.decode(response.body));
    }
    throw Exception('Failed to load date totals');
  }

  Future<void> _loadDateTotals() async {
    if (_selectedDate == null) return;

    setState(() => _isFetchingTotals = true);

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final totals = await getDateTotals(dateStr);
      
      if (mounted) {
        setState(() => _totals = totals);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load totals: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isFetchingTotals = false);
    }
  }

  Future<void> _generateGateNumber() async {
    setState(() => _isGeneratingGate = true);

    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/get_max_gate_number'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() => _nextGateNumber = data['next_gate'].toString());
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate gate number: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingGate = false);
    }
  }

  Future<void> _trackGate() async {
    if (!_formKey.currentState!.validate() || _nextGateNumber == null || _selectedDate == null) return;

    setState(() => _isLoading = true);

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final response = await http.post(
        Uri.parse('$apiBaseUrl/insert_gate_record'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'record_date': dateStr,
          'purchase_total': _totals['purchase_total'],
          'sales_total': _totals['sales_total'],
          'bgrade_total': _totals['bgrade_total'],
          'rejection_total': _totals['rejection_total'],
          'dump_total': _totals['dump_total'],
          'mandi_total': _totals['mandi_total'],
          'vehicle_number': _vehicleController.text.trim(),
          'driver_name': _driverController.text.trim(),
          'party_name': _partyController.text.trim(),
          'remarks': _remarksController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Gate #${data['gate_number']} tracked successfully!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          
          // Clear form & refresh gate number + recent
          _vehicleController.clear();
          _driverController.clear();
          _partyController.clear();
          _remarksController.clear();
          _nextGateNumber = null;
          await Future.wait([_generateGateNumber(), _loadRecentGates()]);
        }
      } else {
        throw Exception('Server error: ${response.body}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to track gate: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRecentGates() async {
    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/get_gate_records?page=1&limit=10'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() => _recentGates = List<Map<String, dynamic>>.from(data['data']));
        }
      }
    } catch (e) {
      debugPrint('Failed to load recent gates: $e');
    }
  }

  double toDouble(dynamic value) => double.tryParse(value.toString()) ?? 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('GATE TRACKER', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.deepPurple,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _selectedDate != null ? () => _loadDateTotals() : null,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 📅 Date Picker
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text('Select Date for Gate Tracking', 
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.calendar_today, color: Colors.deepPurple, size: 28),
                      title: Text(_selectedDate == null 
                        ? 'Tap to select date' 
                        : DateFormat('EEEE, dd MMM yyyy').format(_selectedDate!)),
                      subtitle: _selectedDate != null 
                        ? Text(DateFormat('yyyy-MM-dd').format(_selectedDate!))
                        : null,
                      trailing: const Icon(Icons.arrow_drop_down, color: Colors.deepPurple),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          builder: (context, child) => Theme(
                            data: ThemeData.light().copyWith(
                              colorScheme: ColorScheme.light(primary: Colors.deepPurple),
                            ),
                            child: child!,
                          ),
                        );
                        if (picked != null && mounted) {
                          setState(() => _selectedDate = picked);
                          await Future.wait([_loadDateTotals(), _generateGateNumber()]);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            if (_selectedDate != null) ...[
              // 📊 Daily Totals - 2x3 Grid
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('📊 Daily Totals (KG)', 
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          if (!_isFetchingTotals)
                            Text('${(_totals.values.fold(0.0, (sum, v) => sum + v)).toStringAsFixed(1)} Total',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.deepPurple)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_isFetchingTotals)
                        const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
                      else
                        GridView.count(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          childAspectRatio: 2.8,
                          children: [
                            _buildTotalCard('Purchase\nReceived', _totals['purchase_total']!, Icons.shopping_cart, Colors.green),
                            _buildTotalCard('Sales', _totals['sales_total']!, Icons.trending_down, Colors.red),
                            _buildTotalCard('B-Grade\nSales', _totals['bgrade_total']!, Icons.sell, Colors.orange),
                            _buildTotalCard('Rejection\nReceived', _totals['rejection_total']!, Icons.cancel, Colors.blue),
                            _buildTotalCard('Dump\nSales', _totals['dump_total']!, Icons.delete_sweep, Colors.brown),
                            _buildTotalCard('Mandi\nResale', _totals['mandi_total']!, Icons.store, Colors.teal),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // 🚪 Gate Tracking Form
              Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.door_front_door, color: Colors.deepPurple, size: 32),
                          const SizedBox(width: 16),
                          const Text('Generate & Track Gate Entry', 
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Next Gate Number Row
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              decoration: InputDecoration(
                                labelText: 'Gate Number *',
                                prefixIcon: const Icon(Icons.confirmation_number),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                hintText: _nextGateNumber ?? 'Generate suggested #',
                              ),
                              controller: TextEditingController(text: _nextGateNumber),
                              onTap: () => _generateGateNumber(),
                              readOnly: true,
                              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Gate number required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: _isGeneratingGate ? null : _generateGateNumber,
                              icon: _isGeneratingGate 
                                ? SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)
                                  )
                                : const Icon(Icons.refresh),
                              label: Text(_isGeneratingGate ? 'Loading...' : 'Suggest Next'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Entry Form
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _vehicleController,
                                    decoration: InputDecoration(
                                      labelText: 'Vehicle Number *',
                                      prefixIcon: const Icon(Icons.directions_bus),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                    ),
                                    validator: (v) => (v?.trim().isEmpty ?? true) ? 'Vehicle number required' : null,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: _driverController,
                                    decoration: InputDecoration(
                                      labelText: 'Driver Name',
                                      prefixIcon: const Icon(Icons.person),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _partyController,
                                    decoration: InputDecoration(
                                      labelText: 'Party/Client',
                                      prefixIcon: const Icon(Icons.business),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: _remarksController,
                                    decoration: InputDecoration(
                                      labelText: 'Remarks',
                                      prefixIcon: const Icon(Icons.note),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                    ),
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            SizedBox(
                              height: 56,
                              child: ElevatedButton.icon(
                                onPressed: _isLoading || _nextGateNumber == null ? null : _trackGate,
                                icon: _isLoading 
                                  ? SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)
                                    )
                                  : const Icon(Icons.track_changes, size: 24),
                                label: const Text('Track Gate Entry', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade600,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  elevation: 4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // 📋 Recent Gates Table
              Card(
                elevation: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Recent Gate Records (Last 10)', 
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          TextButton.icon(
                            onPressed: _loadRecentGates,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh'),
                          ),
                        ],
                      ),
                    ),
                    if (_recentGates.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.history, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('No gate records found', style: TextStyle(fontSize: 16, color: Colors.grey)),
                          ],
                        ),
                      )
                    else
                      Container(
                        constraints: const BoxConstraints(maxHeight: 400),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(Colors.deepPurple.shade50),
                            dataRowHeight: 60,
                            headingRowHeight: 56,
                            columns: const [
                              DataColumn(label: Text('Gate #', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                              DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                              DataColumn(label: Text('Vehicle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                              DataColumn(label: Text('Driver', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                              DataColumn(label: Text('Party', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                              DataColumn(label: Text('Total KG', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                              DataColumn(label: Text('Remarks', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                            ],
                            rows: _recentGates.asMap().entries.map((entry) {
                              final index = entry.key;
                              final gate = entry.value;
                              
                              final totalKg = toDouble(gate['purchase_total']) +
                                            toDouble(gate['sales_total']) +
                                            toDouble(gate['bgrade_total']) +
                                            toDouble(gate['rejection_total']) +
                                            toDouble(gate['dump_total']) +
                                            toDouble(gate['mandi_total']);
                              
                              return DataRow(
                                cells: [
                                  DataCell(Text('#${gate['gate_number'] ?? '-'}', 
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple))),
                                  DataCell(Text(gate['record_date'] ?? '-', style: const TextStyle(fontSize: 14))),
                                  DataCell(Text(gate['vehicle_number'] ?? '-', style: const TextStyle(fontSize: 14))),
                                  DataCell(Text(gate['driver_name'] ?? '-', style: const TextStyle(fontSize: 14))),
                                  DataCell(Text(gate['party_name'] ?? '-', style: const TextStyle(fontSize: 14))),
                                  DataCell(Text('${totalKg.toStringAsFixed(1)}', 
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.green.shade700))),
                                  DataCell(Text(gate['remarks'] ?? '-', style: const TextStyle(fontSize: 13), maxLines: 2)),
                                ],
                                onSelectChanged: (index) {
                                  // TODO: Show gate details modal
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Gate #${gate['gate_number']} details (TODO)')),
                                  );
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTotalCard(String title, double value, IconData icon, Color color) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(title, 
              style: const TextStyle(
                fontSize: 12, 
                fontWeight: FontWeight.w500, 
                color: Colors.grey
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text('${value.toStringAsFixed(1)}', 
              style: TextStyle(
                fontSize: 22, 
                fontWeight: FontWeight.bold, 
                color: value > 0 ? Color.alphaBlend(color.withOpacity(0.8), Colors.black) : Colors.grey.shade500,
              ),
            ),
            Text('KG', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _vehicleController.dispose();
    _driverController.dispose();
    _partyController.dispose();
    _remarksController.dispose();
    super.dispose();
  }
}

