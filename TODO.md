# Extra Expenses Feature Implementation

## Task: Add Extra Expenses section in PO page (after rate section)

### Steps:
1. [x] Analyze the generate_po_number_page.dart file
2. [ ] Add extra expenses controller at state level
3. [ ] Add extra expenses text field in the form (after rate section)
4. [ ] Add grand total calculation display
5. [ ] Update PDF to show extra expenses and grand total
6. [ ] Update database submission to include extra expenses

### Implementation Details:
- Single extra expenses field at PO level (not per item)
- Optional field - if empty, defaults to 0
- Shows grand total = (sum of items) + extra expenses
- Display in PDF preview
- Save to database with PO data

