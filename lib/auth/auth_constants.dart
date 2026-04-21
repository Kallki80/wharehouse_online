// Auth group constants for easy mapping
class AuthConstants {
  // Group names matching backend
  static const String poSoGroup = 'po_so';
  static const String inventoryGroup = 'inventory'; 
  static const String lmdFmdGroup = 'lmd_fmd';
  static const String adminGroup = 'admin';

  // Page → Group mapping
  static const Map<String, String> pageToGroup = {
    // PO/SO Pages
    'po_so_number': poSoGroup,
    'generate_po_number_page': poSoGroup,
    
    // Inventory Pages  
    'inventory': inventoryGroup,
    'sales': inventoryGroup,
    'purchase': inventoryGroup,
    'packaging_material': inventoryGroup,
    'stock_update': inventoryGroup,
    'b_grade_sales': inventoryGroup,
    'rejection_received': inventoryGroup,
    'vendor_rejection': inventoryGroup,
    'dump_sale': inventoryGroup,
    'mandi_resale': inventoryGroup,
    
    // LMD/FMD
    'lmd_fmd_page': lmdFmdGroup,
    
    // Admin
    'admin_dashboard': adminGroup,
  };
}
