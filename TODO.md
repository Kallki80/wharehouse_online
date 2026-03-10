# TODO - Purchase Page Fix

## Task: Fix Total Amount and Due Amount fields in Purchase page

### Issues:
1. Total Amount and Due Amount showing "0000,000" 
2. These should NOT be stored in database - only shown in table after calculation
3. Auto-fill issue

### Plan:
- [x] 1. Remove amount_due from frontend calculation (calculated in backend)
- [x] 2. Save amount_paid to database for Partial Paid tracking
- [x] 3. Update table to calculate amount_due dynamically in display
- [x] 4. Backend calculates amount_due = total_value - amount_paid

### Changes Made:

#### lib/purchase.dart:
1. Added amount_paid to dataToSave map in _handleSubmit() to store in DB
2. Updated _buildPurchasesTable to calculate Paid/Due based on payment_status:
   - If status = "Paid": Paid = total_value, Due = 0
   - If status = "Unpaid": Paid = 0, Due = total_value
   - If status = "Partial Paid": Paid = amount_paid from DB, Due = total_value - amount_paid

#### flask_api.py:
1. Updated insert_purchase to calculate amount_due = total_value - amount_paid automatically

### File edited:
- lib/purchase.dart
- flask_api.py

