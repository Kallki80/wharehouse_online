# Task TODO

- [ ] Fix Flask API `/insert_b_grade_sale` to write `ctrl_date` into `b_grade_sales` (currently inserts `date` into `ctrl_date`/omits it).
- [ ] Fix Flask API `/update_b_grade_sale` to update `ctrl_date` as well.
- [ ] Add DB migration logic to ensure `b_grade_sales.ctrl_date` exists and backfill for legacy rows if possible.
- [ ] Verify Dart client payload matches backend columns (`ctrl_date` should be sent).
- [ ] Run a quick smoke test: insert + fetch b_grade_sales to confirm `ctrl_date` is stored.

