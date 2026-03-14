# Vendor Management in Generate PO Page

## Approved Plan Steps
- [ ] 1. Add _manageVendorCtrl = TextEditingController() near _manageItemCtrl
- [ ] 2. Add _manageVendorCtrl.dispose() in dispose()
- [ ] 3. In _buildItemCard Row (after items IconButton): Add vendor IconButton (Icons.store_mall_directory_outlined, Colors.teal.shade600, tooltip 'Manage Vendors (${_vendors.length - 1})', onPressed: _manageVendorsDialog)
- [ ] 4. Create _manageVendorsDialog(): Exact copy _manageItemsDialog - swap texts/APIs/icons/colors (teal theme), use _vendors/_manageVendorCtrl/insertPurchaseVendor/deletePurchaseVendor
- [ ] 5. Test add/delete -> dropdown refresh
- [ ] 6. Complete

