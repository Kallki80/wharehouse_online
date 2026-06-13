# TODO - Admin Dashboard Add Buttons

- [x] Identify existing add button logic (FAB only for `items`).
- [ ] Extend `floatingActionButton` in `lib/admin_dashboard.dart`:
  - [ ] Keep existing `items` FAB using `AdminAddItemDialog`.
  - [ ] Add FAB using `AdminSimpleAddDialog` for:
    - [ ] clientList
    - [ ] purchaseVendors
    - [ ] bGradeClients
    - [ ] productManagers
  - [ ] Use correct insert endpoint via `_getInsertEndpoint`.
  - [ ] After successful add, refresh data via `_loadData()`.
- [ ] Run app and manually verify Add flow for all 4 tables.

