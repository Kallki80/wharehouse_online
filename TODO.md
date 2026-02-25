# Refactoring Flask API to Use SQLAlchemy

## Steps to Complete

- [x] Install Flask-SQLAlchemy dependency
- [x] Configure SQLAlchemy in the Flask app (add db instance, URI)
- [x] Define SQLAlchemy models for all tables:
  - ProductManager
  - GeneratedSO
  - SOItem
  - GeneratedPO
  - LMDData
  - FMDData
  - PaymentHistory
  - Purchase
  - StockUpdate
  - BGradeSale
  - Sale
  - SalesWaitlist
  - RejectionReceived
  - VendorRejection
  - DumpSale
  - MandiResale
  - Item
  - Vendor
  - PurchaseVendor
  - BGradeClient
- [x] Update init_db() to use db.create_all() and insert initial data using models
- [x] Add to_dict() methods to models for JSON serialization
- [x] Replace get_db() with SQLAlchemy session management (db.session)
- [ ] Refactor insert endpoints to use ORM (e.g., insert_generated_so, insert_product_manager, etc.)
- [ ] Refactor query endpoints to use ORM queries (e.g., get_latest_generated_sos_with_items, get_all_generated_pos, etc.)
- [ ] Refactor update endpoints to use ORM (e.g., update_payment_status, update_lmd_data, etc.)
- [ ] Refactor delete endpoints to use ORM (e.g., delete_lmd_data, delete_multiple_entries, etc.)
- [ ] Ensure all JSON responses return dictionaries (use model.to_dict() or similar)
- [ ] Test the refactored API to ensure functionality is preserved
- [ ] Handle any edge cases like complex joins or aggregations
