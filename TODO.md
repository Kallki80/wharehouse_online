# TODO - Admin delete fix (string ids)

- [x] Update `lib/admin_dashboard.dart` to handle delete for tables where `id` is a string (not parseable to int)
- [x] Update both single delete and bulk delete (date range) to safely collect ids as strings/ints
- [x] Keep special case for `purchaseVendors` deletion by `name` + password
- [ ] Run Flutter build/run and manually verify deletion works for:
  - [ ] items
  - [ ] b_grade_clients
  - [ ] product_managers
- [ ] Verify bulk "DELETE" works for the same tables

