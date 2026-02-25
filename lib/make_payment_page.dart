import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:wharehouse/payment_update_page.dart';

const String apiBaseUrl = 'https://api.shabari.ai';

enum PaymentTableType { lmd, fmd }

class MakePaymentPage extends StatefulWidget {
  const MakePaymentPage({super.key});

  @override
  _MakePaymentPageState createState() => _MakePaymentPageState();
}

class _MakePaymentPageState extends State<MakePaymentPage> {
  PaymentTableType _selectedTable = PaymentTableType.lmd;
  late Future<List<Map<String, dynamic>>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      if (_selectedTable == PaymentTableType.lmd) {
        _dataFuture = http.get(Uri.parse('$apiBaseUrl/get_all_lmd_data')).then((response) {
          if (response.statusCode == 200) {
            return List<Map<String, dynamic>>.from(json.decode(response.body));
          } else {
            throw Exception('Failed to load LMD data');
          }
        });
      } else {
        _dataFuture = http.get(Uri.parse('$apiBaseUrl/get_all_fmd_data')).then((response) {
          if (response.statusCode == 200) {
            return List<Map<String, dynamic>>.from(json.decode(response.body));
          } else {
            throw Exception('Failed to load FMD data');
          }
        });
      }
    });
  }

  Future<void> _navigateToDetail(Map<String, dynamic> item) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentDetailUpdatePage(
          itemData: item,
          tableType: _selectedTable,
        ),
      ),
    );

    // If data was changed on the detail page, refresh the list
    if (result == true) {
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Overview'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SegmentedButton<PaymentTableType>(
              style: SegmentedButton.styleFrom(
                backgroundColor: theme.colorScheme.secondary.withAlpha(50),
                foregroundColor: theme.colorScheme.primary,
                selectedForegroundColor: theme.colorScheme.onPrimary,
                selectedBackgroundColor: theme.colorScheme.primary,
              ),
              segments: const [
                ButtonSegment(value: PaymentTableType.lmd, label: Text('LMD'), icon: Icon(Icons.local_shipping)),
                ButtonSegment(value: PaymentTableType.fmd, label: Text('FMD'), icon: Icon(Icons.store)),
              ],
              selected: {_selectedTable},
              onSelectionChanged: (Set<PaymentTableType> newSelection) {
                setState(() {
                  _selectedTable = newSelection.first;
                  _loadData();
                });
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _dataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No entries found.'));
                }
                final data = snapshot.data!;
                return ListView.builder(
                  itemCount: data.length,
                  itemBuilder: (context, index) {
                    final item = data[index];
                    final title = (_selectedTable == PaymentTableType.lmd ? item['client_name'] : item['vendor_name']) ?? 'No Name';
                    final totalAmount = item['total_amount'] as double? ?? 0.0;
                    final amountPaid = item['amount_paid'] as double?;
                    final amountDue = item['amount_due'] as double?;
                    final currentStatus = item['payment_status'] ?? 'Unpaid';

                    Widget subtitle;
                    if (currentStatus == 'Partial Paid' && amountPaid != null && amountDue != null) {
                      subtitle = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total: ₹${totalAmount.toStringAsFixed(2)}'),
                          Text('Paid: ₹${amountPaid.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                          Text('Due: ₹${amountDue.toStringAsFixed(2)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        ],
                      );
                    } else {
                      subtitle = Text('Date: ${item['date']} - Amount: ₹${totalAmount.toStringAsFixed(2)}');
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      elevation: 3,
                      child: ListTile(
                        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: subtitle,
                        trailing: Chip(
                          label: Text(
                            currentStatus,
                             style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          backgroundColor: currentStatus == 'Paid' ? Colors.green : (currentStatus == 'Partial Paid' ? Colors.orange : Colors.red),
                        ),
                        onTap: () => _navigateToDetail(item),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
