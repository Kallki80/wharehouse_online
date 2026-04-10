# TODO: Fix Sales Date Selection in Rejection Received Page

## Steps:
- [ ] Step 1: Read lib/rejection_received.dart to confirm current structure (already done).
- [ ] Step 2: Add DateTime? selectedSaleDate state variable.
- [ ] Step 3: Create _buildSaleDateButton() widget like _buildCtrlDateButton().
- [ ] Step 4: Replace sales date DropdownButtonFormField with _buildSaleDateButton() in _buildTopSelectionSection().
- [ ] Step 5: Update filtering logic (_onSaleDateChanged, _onClientChanged, etc.) to use selectedSaleDate instead of _selectedDate string.
- [ ] Step 6: Remove unused _selectedDate, _availableDates vars and related code.
- [ ] Step 7: Update item population in _addNewItem() and _onItemChanged to use selectedSaleDate.
- [ ] Step 8: Test: Hot reload, select sale date, verify client/item dropdowns filter correctly.
- [ ] Step 9: attempt_completion.

**Current Progress:** Steps 1-6 complete (date picker implemented, filtering updated). Step 7: Final clean-up & test.


