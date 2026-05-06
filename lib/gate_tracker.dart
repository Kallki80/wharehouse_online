
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
      _generateGateNumber(),
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
        setState(() {
          _nextGateNumber = data['next_gate']?.toString();
          _gateNumberController.text = _nextGateNumber ?? '';
        });
      }
    } catch (e) {
      _error('Gate number error: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingGate = false);
    }
  }

  Future<void> _trackGate() async {
    if (!_formKey.currentState!.validate() ||
        _nextGateNumber == null ||
        _selectedDate == null) return;

    setState(() => _isLoading = true);

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);

      final res = await http.post(
        Uri.parse('$apiBaseUrl/insert_gate_record'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'gate_number': _nextGateNumber,
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
        }),
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('✅ Gate #${data['gate_number']} tracked successfully'),
            backgroundColor: Colors.green,
          ),
        );

        _clearForm();

        await Future.wait([
          _generateGateNumber(),
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
                              horizontal: 8,
                              vertical: 6,
                            ),
                            label: Text(
                              '$title: ${_formatMoney(e.value)}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
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
                          TextFormField(
                            controller: _gateNumberController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Gate Number',
                              prefixIcon: Icon(Icons.confirmation_num),
                            ),
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

            // Recent list
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
                      Column(
                        children: _recentGates.map((g) {
                          final total = toDouble(g['purchase_total']) +
                              toDouble(g['sales_total']) +
                              toDouble(g['bgrade_total']) +
                              toDouble(g['rejection_total']) +
                              toDouble(g['dump_total']) +
                              toDouble(g['mandi_total']);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor:
                                    Theme.of(context).colorScheme.primaryContainer,
                                child: Text(
                                  '${(g['gate_number'] ?? '-').toString().replaceAll(' ', '')}'.isEmpty
                                      ? '-'
                                      : (g['gate_number'] ?? '-')
                                          .toString()
                                          .replaceAll(' ', '')
                                          .substring(0, 1)
                                          .toUpperCase(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                                ),
                              ),
                              title: Text(
                                'Gate #${g['gate_number'] ?? '-'}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              subtitle: Text(
                                g['vehicle_number'] ?? '-',
                              ),
                              trailing: Text(
                                _formatMoney(total),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                          );
                        }).toList(),
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