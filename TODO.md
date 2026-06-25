# TODO

- [ ] Update backend Flask API: `purchases.total_value` response key should become `amount_of_accepted` (in `/get_latest_purchases` and anywhere else purchases total_value is returned/used).
- [ ] Update Flutter UI (`lib/purchase.dart`): DataTable heading text change from `Total` to `Amount of Accepted`.
- [ ] Update Flutter rows mapping: read `row['amount_of_accepted']` instead of `row['total_value']`.
- [ ] Run/build sanity checks: restart Flutter and Flask; verify purchases table renders and due/paid calculations still work.

