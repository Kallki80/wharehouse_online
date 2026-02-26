import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:wharehouse/make_payment_page.dart'; // For PaymentTableType enum

// const String apiBaseUrl = 'http://13.53.71.103:5000/';
// const String apiBaseUrl = 'http://10.0.2.2:5000';
const String apiBaseUrl = 'http://127.0.0.1:5000';

class PaymentDetailUpdatePage extends StatefulWidget {
  final Map<String, dynamic> itemData;
  final PaymentTableType tableType;

  const PaymentDetailUpdatePage({
    super.key,
    required this.itemData,
    required this.tableType,
  });

  @override
  State<PaymentDetailUpdatePage> createState() => _PaymentDetailUpdatePageState();
}

class _PaymentDetailUpdatePageState extends State<PaymentDetailUpdatePage> {
  late Map<String, dynamic> _currentItemData;
  late String _currentStatus;
  String? _modeOfPayment;
  bool _dataChanged = false;
  late Future<List<Map<String, dynamic>>> _paymentHistoryFuture;

  @override
  void initState() {
    super.initState();
    _currentItemData = Map<String, dynamic>.from(widget.itemData);
    _currentStatus = _currentItemData['payment_status'] ?? 'Unpaid';
    _modeOfPayment = _currentItemData['mode_of_payment'];
    _loadPaymentHistory();
  }

  void _loadPaymentHistory() {
    final tableName = widget.tableType == PaymentTableType.lmd ? 'lmd_data' : 'fmd_data';
    final parentId = _currentItemData['id'] as int;
    setState(() {
      _paymentHistoryFuture = http.get(Uri.parse('$apiBaseUrl/get_payment_history?table_name=$tableName&parent_id=$parentId')).then((response) {
        if (response.statusCode == 200) {
          return List<Map<String, dynamic>>.from(json.decode(response.body));
        } else {
          throw Exception('Failed to load payment history');
        }
      });
    });
  }

  Future<void> _updatePaymentStatus(
    String newStatus, {
    double? amountPaid,
    double? amountDue,
    String? modeOfPayment,
    double? transactionAmount,
  }) async {
    final tableName = widget.tableType == PaymentTableType.lmd ? 'lmd_data' : 'fmd_data';
    final id = _currentItemData['id'] as int;

    final updateData = {
      'table_name': tableName,
      'id': id,
      'status': newStatus,
      'amount_paid': amountPaid,
      'amount_due': amountDue,
      'mode_of_payment': modeOfPayment,
    };

    final updateResponse = await http.put(Uri.parse('$apiBaseUrl/update_payment_status'), body: json.encode(updateData), headers: {'Content-Type': 'application/json'});

    if (!mounted) return;

    if (updateResponse.statusCode == 200) {
      if (transactionAmount != null && transactionAmount > 0) {
        final historyData = {
          'parent_table_name': tableName,
          'parent_id': id,
          'amount_paid': transactionAmount,
          'mode_of_payment': modeOfPayment,
          'payment_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'payment_time': DateFormat('HH:mm:ss').format(DateTime.now()),
        };
        await http.post(Uri.parse('$apiBaseUrl/add_payment_history'), body: json.encode(historyData), headers: {'Content-Type': 'application/json'});
      }

      if (!mounted) return;

      setState(() {
        _currentItemData['payment_status'] = newStatus;
        _currentItemData['amount_paid'] = amountPaid;
        _currentItemData['amount_due'] = amountDue;
        _currentItemData['mode_of_payment'] = modeOfPayment;
        _currentStatus = newStatus;
        _modeOfPayment = modeOfPayment;
        _dataChanged = true;
      });

      _loadPaymentHistory();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment status updated successfully!'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update payment status.'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showPartialPaymentDialog(double totalAmount, double alreadyPaid) async {
    final amountController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? selectedMode;
    final double currentAmountDue = totalAmount - alreadyPaid;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Partial Payment'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Amount Due: ₹${currentAmountDue.toStringAsFixed(2)}'),
              const SizedBox(height: 16),
              TextFormField(
                controller: amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'New Amount to Pay'),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter an amount';
                  final amount = double.tryParse(value);
                  if (amount == null) return 'Invalid number';
                  if (amount <= 0) return 'Amount must be positive';
                  if (amount > currentAmountDue) {
                    return 'Amount cannot be more than the amount due.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Mode of Payment'),
                items: ['Online', 'Cash', 'Imprest'].map((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
                }).toList(),
                onChanged: (String? newValue) => selectedMode = newValue,
                validator: (value) => value == null ? 'Please select a mode' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop({
                  'amount': double.parse(amountController.text),
                  'mode': selectedMode,
                });
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (result != null) {
      final double newPaymentAmount = result['amount'];
      final String mode = result['mode'];
      
      final double newTotalPaid = alreadyPaid + newPaymentAmount;
      final double newAmountDue = totalAmount - newTotalPaid;

      if (newAmountDue <= 0.01) {
        await _updatePaymentStatus(
          'Paid',
          amountPaid: totalAmount,
          amountDue: 0,
          modeOfPayment: mode,
          transactionAmount: newPaymentAmount,
        );
      } else {
        await _updatePaymentStatus(
          'Partial Paid',
          amountPaid: newTotalPaid,
          amountDue: newAmountDue,
          modeOfPayment: mode,
          transactionAmount: newPaymentAmount,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = (widget.tableType == PaymentTableType.lmd ? _currentItemData['client_name'] : _currentItemData['vendor_name']) ?? 'No Name';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        Navigator.pop(context, _dataChanged);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _dataChanged),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildPaymentSummaryCard(theme),
            const SizedBox(height: 16),
            _buildPaymentHistoryCard(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSummaryCard(ThemeData theme) {
    final totalAmount = _currentItemData['total_amount'] as double? ?? 0.0;
    final amountPaid = _currentItemData['amount_paid'] as double?;
    final amountDue = _currentItemData['amount_due'] as double?;

    Widget paymentDetails;
    if (_currentStatus == 'Partial Paid' && amountPaid != null && amountDue != null) {
      paymentDetails = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow(theme, 'Total Amount', '₹${totalAmount.toStringAsFixed(2)}'),
          _buildDetailRow(theme, 'Amount Paid', '₹${amountPaid.toStringAsFixed(2)}', valueColor: Colors.green),
          _buildDetailRow(theme, 'Amount Due', '₹${amountDue.toStringAsFixed(2)}', valueColor: Colors.red),
        ],
      );
    } else {
      paymentDetails = _buildDetailRow(theme, 'Total Amount', '₹${totalAmount.toStringAsFixed(2)}');
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(']', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            paymentDetails,
            if (_modeOfPayment != null)
              _buildDetailRow(theme, 'Last Payment Mode', _modeOfPayment!),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Update Status', style: theme.textTheme.titleLarge),
                DropdownButton<String>(
                  value: _currentStatus,
                  items: <String>['Paid', 'Unpaid', 'Partial Paid'].map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue == null) return;

                    if (newValue == 'Partial Paid') {
                      final currentPaidAmount = _currentItemData['amount_paid'] as double? ?? 0.0;
                      _showPartialPaymentDialog(totalAmount, currentPaidAmount);
                      return;
                    }

                    if (newValue != _currentStatus) {
                      if (newValue == 'Paid') {
                        _showModeOfPaymentDialog(totalAmount, newValue);
                      } else { // Unpaid
                        _updatePaymentStatus(newValue, amountPaid: 0, amountDue: totalAmount, transactionAmount: 0);
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentHistoryCard(ThemeData theme) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payment History', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _paymentHistoryFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No payment history found.'));
                }
                final history = snapshot.data!;
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final record = history[index];
                    return ListTile(
                      title: Text('₹${record['amount_paid']} - ${record['mode_of_payment']}'),
                      subtitle: Text('${record['payment_date']} at ${record['payment_time']}'),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showModeOfPaymentDialog(double totalAmount, String newStatus) async {
    String? selectedMode;
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Select Mode of Payment'),
              content: Form(
                  key: formKey,
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Mode of Payment'),
                    items: ['Online', 'Cash', 'Imprest'].map((String value) {
                      return DropdownMenuItem<String>(value: value, child: Text(value));
                    }).toList(),
                    onChanged: (String? newValue) => selectedMode = newValue,
                    validator: (value) => value == null ? 'Please select a mode' : null,
                  )),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                TextButton(
                    onPressed: () {
                      if (formKey.currentState!.validate()) {
                        Navigator.of(context).pop(selectedMode);
                      }
                    },
                    child: const Text('Submit')),
              ],
            ));

    if (result != null) {
      final currentPaidAmount = _currentItemData['amount_paid'] as double? ?? 0.0;
      final transactionAmount = totalAmount - currentPaidAmount;
      await _updatePaymentStatus(
        newStatus,
        amountPaid: totalAmount,
        amountDue: 0,
        modeOfPayment: result,
        transactionAmount: transactionAmount,
      );
    }
  }


  Widget _buildDetailRow(ThemeData theme, String title, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
