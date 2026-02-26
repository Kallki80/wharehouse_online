import 'package:flutter/material.dart';

class PaymentPage extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  const PaymentPage({super.key, this.initialData});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedVehicleType;
  bool _showVehicleFields = false;
  bool _showTotalAmountField = false;

  final _kmController = TextEditingController();
  final _pricePerKmController = TextEditingController();
  final _extraExpensesController = TextEditingController();
  final _reasonController = TextEditingController();
  final _totalAmountController = TextEditingController();
  final _bookingPersonController = TextEditingController();
  final _amountPaidController = TextEditingController();
  final _amountDueController = TextEditingController();

  String _paymentStatus = 'Unpaid'; // Default status
  String? _modeOfPayment;
  double _totalValue = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _populateFields(widget.initialData!);
    }
    _addListeners();
  }

  void _addListeners() {
    _kmController.addListener(_calculateTotal);
    _pricePerKmController.addListener(_calculateTotal);
    _extraExpensesController.addListener(_calculateTotal);
    _totalAmountController.addListener(_calculateTotal);
    _amountPaidController.addListener(_calculateAmountDue);
  }

  void _populateFields(Map<String, dynamic> data) {
    _selectedVehicleType = data['vehicle_type'];
    _bookingPersonController.text = data['booking_person']?.toString() ?? '';
    _paymentStatus = data['payment_status'] ?? 'Unpaid';
    _modeOfPayment = data['mode_of_payment'];

    final vehicleType = data['vehicle_type'];
    _showVehicleFields = (vehicleType == 'BIG' || vehicleType == 'Small' || vehicleType == 'Bike');
    _showTotalAmountField = (vehicleType == 'Auto' || vehicleType == 'Porter');

    if (_showVehicleFields) {
      _kmController.text = data['km']?.toString() ?? '';
      _pricePerKmController.text = data['price_per_km']?.toString() ?? '';
      _extraExpensesController.text = data['extra_expenses']?.toString() ?? '';
      _reasonController.text = data['reason']?.toString() ?? '';
    }

    if (_showTotalAmountField) {
      _totalAmountController.text = data['total_amount']?.toString() ?? '';
    }

    if (_paymentStatus == 'Partial Paid') {
      _amountPaidController.text = data['amount_paid']?.toString() ?? '';
    }
    
    _totalValue = (data['total_amount'] as num?)?.toDouble() ?? 0.0;
    _calculateAmountDue();
  }

  @override
  void dispose() {
    _kmController.removeListener(_calculateTotal);
    _pricePerKmController.removeListener(_calculateTotal);
    _extraExpensesController.removeListener(_calculateTotal);
    _totalAmountController.removeListener(_calculateTotal);
    _amountPaidController.removeListener(_calculateAmountDue);

    _kmController.dispose();
    _pricePerKmController.dispose();
    _extraExpensesController.dispose();
    _reasonController.dispose();
    _totalAmountController.dispose();
    _bookingPersonController.dispose();
    _amountPaidController.dispose();
    _amountDueController.dispose();
    super.dispose();
  }

  void _calculateTotal() {
    double km = double.tryParse(_kmController.text) ?? 0.0;
    double pricePerKm = double.tryParse(_pricePerKmController.text) ?? 0.0;
    double extraExpenses = double.tryParse(_extraExpensesController.text) ?? 0.0;
    double totalAmountFromField = double.tryParse(_totalAmountController.text) ?? 0.0;

    double newTotal = 0.0;
    if (_showVehicleFields) {
      newTotal = (km * pricePerKm) + extraExpenses;
    } else if (_showTotalAmountField) {
      newTotal = totalAmountFromField;
    }

    if (newTotal != _totalValue) {
      setState(() {
        _totalValue = newTotal;
        _calculateAmountDue();
      });
    }
  }

  void _calculateAmountDue() {
    if (_paymentStatus == 'Partial Paid') {
      double amountPaid = double.tryParse(_amountPaidController.text) ?? 0.0;
      double amountDue = _totalValue - amountPaid;
      _amountDueController.text = amountDue.toStringAsFixed(2);
    } else {
      _amountDueController.clear();
    }
  }

  void _onVehicleTypeChanged(String? newValue) {
    setState(() {
      _selectedVehicleType = newValue;
      if (newValue == 'BIG' || newValue == 'Small' || newValue == 'Bike') {
        _showVehicleFields = true;
        _showTotalAmountField = false;
      } else if (newValue == 'Auto' || newValue == 'Porter') {
        _showVehicleFields = false;
        _showTotalAmountField = true;
      } else {
        _showVehicleFields = false;
        _showTotalAmountField = false;
      }
      _kmController.clear();
      _pricePerKmController.clear();
      _extraExpensesController.clear();
      _reasonController.clear();
      _totalAmountController.clear();
      _amountPaidController.clear();
      _amountDueController.clear();
      _calculateTotal();
    });
  }

  void _submitPaymentDetails() {
    if (_formKey.currentState!.validate()) {
      final data = {
        'vehicle_type': _selectedVehicleType,
        'booking_person': _bookingPersonController.text,
        'km': _showVehicleFields ? double.tryParse(_kmController.text) : null,
        'price_per_km': _showVehicleFields ? double.tryParse(_pricePerKmController.text) : null,
        'extra_expenses': _showVehicleFields ? double.tryParse(_extraExpensesController.text) : null,
        'reason': _showVehicleFields ? _reasonController.text : null,
        'total_amount': _totalValue,
        'payment_status': _paymentStatus,
        'mode_of_payment': _modeOfPayment,
        'amount_paid': _paymentStatus == 'Partial Paid'
            ? double.tryParse(_amountPaidController.text)
            : (_paymentStatus == 'Paid' ? _totalValue : null),
        'amount_due': _paymentStatus == 'Partial Paid'
            ? double.tryParse(_amountDueController.text)
            : (_paymentStatus == 'Paid' ? 0.0 : null),
      };

      Navigator.pop(context, data);
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Details'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDropdown(theme),
              const SizedBox(height: 20),
              TextFormField(
                controller: _bookingPersonController,
                decoration: InputDecoration(
                  labelText: 'Booking Person Name',
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_pin, color: theme.colorScheme.primary),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter the booking person\'s name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              if (_showVehicleFields) _buildVehicleFields(theme),
              if (_showTotalAmountField) _buildTotalAmountField(theme),
              const SizedBox(height: 20),
              _buildStatusSelector(theme),
              if (_paymentStatus == 'Paid' || _paymentStatus == 'Partial Paid') ...[
                const SizedBox(height: 20),
                _buildModeOfPaymentSelector(theme),
              ],
              if (_paymentStatus == 'Partial Paid') ...[
                const SizedBox(height: 20),
                _buildPartialPaymentFields(theme),
              ],
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'Total: ₹${_totalValue.toStringAsFixed(2)}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _submitPaymentDetails,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown(ThemeData theme) {
    return DropdownButtonFormField<String>(
      initialValue: _selectedVehicleType,
      decoration: InputDecoration(
        labelText: 'Vehicle Type',
        border: const OutlineInputBorder(),
        prefixIcon: Icon(Icons.delivery_dining, color: theme.colorScheme.primary),
      ),
      hint: const Text('Select vehicle type'),
      items: ['BIG', 'Small', 'Bike', 'Auto', 'Porter'].map((String value) {
        return DropdownMenuItem<String>(
          value: value,
          child: Text(value),
        );
      }).toList(),
      onChanged: _onVehicleTypeChanged,
      validator: (value) => value == null ? 'Please select a vehicle type' : null,
    );
  }

  Widget _buildStatusSelector(ThemeData theme) {
    return DropdownButtonFormField<String>(
      initialValue: _paymentStatus,
      decoration: InputDecoration(
        labelText: 'Payment Status',
        border: const OutlineInputBorder(),
        prefixIcon: Icon(
          _paymentStatus == 'Paid' ? Icons.check_circle : (_paymentStatus == 'Partial Paid' ? Icons.hourglass_bottom : Icons.cancel),
          color: _paymentStatus == 'Paid' ? Colors.green : (_paymentStatus == 'Partial Paid' ? Colors.orange : Colors.red),
        ),
      ),
      items: ['Paid', 'Unpaid', 'Partial Paid'].map((String value) {
        return DropdownMenuItem<String>(
          value: value,
          child: Text(value),
        );
      }).toList(),
      onChanged: (String? newValue) {
        if (newValue != null) {
          setState(() {
            _paymentStatus = newValue;
            if (_paymentStatus == 'Unpaid') {
              _modeOfPayment = null;
            }
            _calculateAmountDue();
          });
        }
      },
    );
  }

  Widget _buildModeOfPaymentSelector(ThemeData theme) {
    return DropdownButtonFormField<String>(
      initialValue: _modeOfPayment,
      decoration: InputDecoration(
        labelText: 'Mode of Payment',
        border: const OutlineInputBorder(),
        prefixIcon: Icon(Icons.payment, color: theme.colorScheme.primary),
      ),
      hint: const Text('Select mode of payment'),
      items: ['Online', 'Cash', 'Imprest'].map((String value) {
        return DropdownMenuItem<String>(
          value: value,
          child: Text(value),
        );
      }).toList(),
      onChanged: (String? newValue) {
        setState(() {
          _modeOfPayment = newValue;
        });
      },
      validator: (value) {
        if ((_paymentStatus == 'Paid' || _paymentStatus == 'Partial Paid') && value == null) {
          return 'Please select a mode of payment';
        }
        return null;
      },
    );
  }
  
  Widget _buildPartialPaymentFields(ThemeData theme) {
    return Column(
      children: [
        TextFormField(
          controller: _amountPaidController,
          decoration: InputDecoration(
            labelText: 'Amount Paid',
            border: const OutlineInputBorder(),
            prefixIcon: Icon(Icons.attach_money, color: theme.colorScheme.primary),
          ),
          keyboardType: TextInputType.number,
          validator: (value) {
            if (_paymentStatus == 'Partial Paid' && (value == null || value.isEmpty)) {
              return 'Please enter the amount paid';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _amountDueController,
          decoration: const InputDecoration(
            labelText: 'Amount Due',
            border: OutlineInputBorder(),
            filled: true,
          ),
          readOnly: true,
        ),
      ],
    );
  }

  Widget _buildVehicleFields(ThemeData theme) {
    return Column(
      children: [
        TextFormField(
          controller: _kmController,
          decoration: InputDecoration(
            labelText: 'Kilometers',
            border: const OutlineInputBorder(),
            prefixIcon: Icon(Icons.map, color: theme.colorScheme.primary),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _pricePerKmController,
          decoration: InputDecoration(
            labelText: 'Price per KM',
            border: const OutlineInputBorder(),
            prefixIcon: Icon(Icons.monetization_on, color: theme.colorScheme.primary),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _extraExpensesController,
          decoration: InputDecoration(
            labelText: 'Extra Expenses',
            border: const OutlineInputBorder(),
            prefixIcon: Icon(Icons.add_shopping_cart, color: theme.colorScheme.primary),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _reasonController,
          decoration: const InputDecoration(
            labelText: 'Reason for Extra Expenses',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildTotalAmountField(ThemeData theme) {
    return TextFormField(
      controller: _totalAmountController,
      decoration: InputDecoration(
        labelText: 'Total Amount',
        border: const OutlineInputBorder(),
        prefixIcon: Icon(Icons.attach_money, color: theme.colorScheme.primary),
      ),
      keyboardType: TextInputType.number,
    );
  }
}
