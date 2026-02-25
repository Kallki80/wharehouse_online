# TODO - Make CTRL Date Mandatory

## Task
Add CTRL Date validation to lmd_page.dart and fmd_page.dart (similar to purchase.dart)

## Changes Required

### 1. lib/lmd_page.dart
- [x] Add validation check in `_submitForm()` to ensure ctrlDate is not null
- [x] Show error message if CTRL Date is not selected

### 2. lib/fmd_page.dart
- [x] Add validation check in `_submitForm()` to ensure ctrlDate is not null
- [x] Show error message if CTRL Date is not selected
