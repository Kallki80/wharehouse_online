
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_config.dart';

class GateTrackerPage extends StatefulWidget {
  const GateTrackerPage({super.key});

  @override
  State<GateTrackerPage> createState() => _GateTrackerPageState();
}

class _GateTrackerPageState extends State<GateTrackerPage> {
  DateTime? _selectedDate = DateTime.now();

  bool _isLoading = false;
  bool _isFetchingTotals = false;
  bool _isGeneratingGate = false;

  final _formKey = GlobalKey<FormState>();

  String? _nextGateNumber;

  final _gateNumberController = TextEditingController();
  final _vehicleController = TextEditingController();
  final _driverController = TextEditingController();
  final _partyController = TextEditingController();
  final _remarksController = TextEditingController();

  List<Map<String, dynamic>> _recentGates = [];

  Map<String, double> _totals = {
    'purchase_total': 0.0,
    'sales_total': 0.0,
    'bgrade_total': 0.0,
    'rejection_total': 0.0,
    'dump_total': 0.0,
    'mandi_total': 0.0,
  };

  String _formatMoney(double v) => v.toStringAsFixed(1);

  String _titleForKey(String key) {
    switch (key) {
      case 'purchase_total':
        return 'Purchase';
      case 'sales_total':
        return 'Sales';
      case 'bgrade_total':
        return 'B-Grade';
      case 'rejection_total':
        return 'Rejection';
      case 'dump_total':
        return 'Dump';
      case 'mandi_total':
        return 'Mandi';
      default:
        return key;
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.wait([
      _loadDateTotals(),
      _loadRecentGates(),
    ]);
  }

  Future<Map<String, double>> getDateTotals(String dateStr) async {
    final uri = Uri.parse('$apiBaseUrl/get_date_totals?date=$dateStr');
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      Map<String, double> safeTotals = {
        'purchase_total': 0.0,
        'sales_total': 0.0,
        'bgrade_total': 0.0,
        'rejection_total': 0.0,
        'dump_total': 0.0,
        'mandi_total': 0.0,
      };

      if (data is Map) {
        data.forEach((key, value) {
          safeTotals[key] = double.tryParse(value?.toString() ?? '0') ?? 0.0;
        });
      }

      return safeTotals;
    }

    throw Exception('Failed to load date totals');
  }

  Future<void> _loadDateTotals() async {
    if (_selectedDate == null) return;

    setState(() => _isFetchingTotals = true);

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final totals = await getDateTotals(dateStr);

      if (!mounted) return;
      setState(() => _totals = totals);
    } catch (e) {
      _error('Totals error: $e');
    } finally {
      if (mounted) setState(() => _isFetchingTotals = false);
    }
  }

  Future<void> _generateGateNumber() async {
    setState(() => _isGeneratingGate = true);

    try {
      final res =
          await http.get(Uri.parse('$apiBaseUrl/get_max_gate_number'));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);

        if (!mounted) return;

        // User ne jo gate_number database me upload kiya hai,
        // button click par latest max ke hisaab se next number generate hona chahiye.
        final nextGate = data['next_gate']?.toString() ?? '';

        setState(() {
          _nextGateNumber = nextGate;
          _gateNumberController.text = _nextGateNumber ?? '';
        });

        await _loadRecentGates();
      }
    } catch (e) {
      _error('Gate number error: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingGate = false);
    }
  }



  Future<void> _trackGate() async {
    if (!_formKey.currentState!.validate() || _selectedDate == null) {
      return;
    }

    final gateNumberToUse = _gateNumberController.text.trim();
    if (gateNumberToUse.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);

      final payload = {
        'gate_number': gateNumberToUse,
        'record_date': dateStr,
        'purchase_total': _totals['purchase_total'] ?? 0,
        'sales_total': _totals['sales_total'] ?? 0,
        'bgrade_total': _totals['bgrade_total'] ?? 0,
        'rejection_total': _totals['rejection_total'] ?? 0,
        'dump_total': _totals['dump_total'] ?? 0,
        'mandi_total': _totals['mandi_total'] ?? 0,
        'vehicle_number': _vehicleController.text.trim(),
        'driver_name': _driverController.text.trim(),
        'party_name': _partyController.text.trim(),
        'remarks': _remarksController.text.trim(),
      };

      final res = await http.post(
        Uri.parse('$apiBaseUrl/insert_gate_record'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);

        if (!mounted) return;

        // Backend currently ignore karta hai gate_number from request and always next_gate use karta hai.
        // Isliye user entered gateNumberToUse ka mismatch ho sakta hai.
        // UI ko truthful dikhane ke liye backend ka gate_number hi show kar rahe hain.
        final backendGate = data['gate_number']?.toString();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Gate #${backendGate ?? gateNumberToUse} tracked successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Clear only other fields; gate number user ka manually input overwrite na ho.
        // But since backend gate_number always auto-increments, clearing avoids confusion.
        _clearForm();
        _gateNumberController.clear();
        _nextGateNumber = null;

        await Future.wait([
          _loadRecentGates(),
        ]);
      } else {
        throw Exception(res.body);
      }
    } catch (e) {
      _error('Track failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRecentGates() async {
    try {
      final res = await http
          .get(Uri.parse('$apiBaseUrl/get_gate_records?page=1&limit=10'));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);

        final list = data['data'] ?? data['records'] ?? data;

        if (!mounted) return;

        setState(() {
          _recentGates =
              List<Map<String, dynamic>>.from(list ?? []);
        });
      }
    } catch (e) {
      _error('Recent gates failed');
    }
  }

  // ================= HELPERS =================

  void _clearForm() {
    _vehicleController.clear();
    _driverController.clear();
    _partyController.clear();
    _remarksController.clear();
  }

  void _error(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  double toDouble(dynamic v) =>
      double.tryParse(v.toString()) ?? 0.0;

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Gate Tracker'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _init,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top section
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // DATE
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today),
                      title: Text(
                        _selectedDate == null
                            ? 'Select date'
                            : DateFormat('dd MMM yyyy').format(_selectedDate!),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );

                        if (picked != null) {
                          setState(() => _selectedDate = picked);
                          await _init();
                        }
                      },
                    ),

                    const SizedBox(height: 10),

                    // TOTALS
                    Row(
                      children: [
                        const Icon(Icons.analytics_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Totals',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const Spacer(),
                        if (_isFetchingTotals)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (!_isFetchingTotals)
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _totals.entries.map((e) {
                          final title = _titleForKey(e.key);
                          return Chip(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            label: Text(
                              '$title: ${_formatMoney(e.value)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Form
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.add_circle_outline, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'New Gate Entry',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _gateNumberController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Gate Number',
                                    prefixIcon: Icon(Icons.confirmation_num),
                                  ),
                                  validator: (v) {
                                    final value = v?.trim() ?? '';
                                    if (value.isEmpty) return 'Required';
                                    final n = int.tryParse(value);
                                    if (n == null || n <= 0) return 'Invalid';
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              IconButton(
                                tooltip: 'Generate latest gate number',
                                onPressed: _isLoading ? null : _generateGateNumber,
                                icon: const Icon(Icons.refresh),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _vehicleController,
                            decoration: const InputDecoration(
                              labelText: 'Vehicle *',
                              prefixIcon: Icon(Icons.directions_car),
                            ),
                            validator: (v) =>
                                v!.trim().isEmpty ? 'Required' : null,
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _driverController,
                            decoration: const InputDecoration(
                              labelText: 'Driver',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _partyController,
                            decoration: const InputDecoration(
                              labelText: 'Party',
                              prefixIcon: Icon(Icons.groups_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _remarksController,
                            decoration: const InputDecoration(
                              labelText: 'Remarks',
                              prefixIcon: Icon(Icons.note_outlined),
                            ),
                          ),
                          const SizedBox(height: 16),

                          FilledButton.icon(
                            onPressed: _isLoading ? null : _trackGate,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send),
                            label: Text(_isLoading ? 'Submitting' : 'Submit'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Table of recent gates
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.history_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Recent Gates',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Load recent',
                          onPressed: _isLoading ? null : _loadRecentGates,
                          icon: const Icon(Icons.refresh),
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_recentGates.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          children: const [
                            Icon(Icons.inbox_outlined, size: 28),
                            SizedBox(height: 10),
                            Text(
                              'No gate records found',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      )
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 16,
                          headingRowHeight: 40,
                          dataRowHeight: 56,
                          columns: const [
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('Gate #')),
                            DataColumn(label: Text('Vehicle')),
                            DataColumn(label: Text('Driver')),
                            DataColumn(label: Text('Party')),
                            DataColumn(label: Text('Remark')),
                          ],
                          rows: _recentGates.map((g) {
                            final dateStr = (g['record_date'] ?? g['date'] ?? '-').toString();
                            final gateNo = (g['gate_number'] ?? '-').toString();
                            final vehicle = (g['vehicle_number'] ?? '-').toString();
                            final driver = (g['driver_name'] ?? '-').toString();
                            final party = (g['party_name'] ?? '-').toString();
                            final remark = (g['remarks'] ?? '-').toString();

                            return DataRow(cells: [
                              DataCell(Text(dateStr)),
                              DataCell(Text(gateNo.toString())),
                              DataCell(Text(vehicle)),
                              DataCell(Text(driver)),
                              DataCell(Text(party)),
                              DataCell(Text(remark)),
                            ]);
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _gateNumberController.dispose();
    _vehicleController.dispose();
    _driverController.dispose();
    _partyController.dispose();
    _remarksController.dispose();
    super.dispose();
  }
}