import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await initDB();
    return _db!;
  }

  Future<Database> initDB() async {
    String path = join(await getDatabasesPath(), "mydata.db");
    return await openDatabase(path, version: 65, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createAllTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 52) {
      await _dropAllTables(db);
      await _createAllTables(db);
    } else {
       if (oldVersion == 52 && newVersion >= 53) {
        var tableInfo = await db.rawQuery('PRAGMA table_info(stock_updates)');
        var columnNames = tableInfo.map((row) => row['name'] as String).toList();
        if (!columnNames.contains('c_grade_qty')) await db.execute('ALTER TABLE stock_updates ADD COLUMN c_grade_qty REAL');
        if (!columnNames.contains('c_grade_unit')) await db.execute('ALTER TABLE stock_updates ADD COLUMN c_grade_unit TEXT');
        if (!columnNames.contains('pcs_c_grade')) await db.execute('ALTER TABLE stock_updates ADD COLUMN pcs_c_grade REAL');
      }
      if (oldVersion < 54 && newVersion >= 54) {
         var tableInfo = await db.rawQuery('PRAGMA table_info(generated_pos)');
         var columnNames = tableInfo.map((row) => row['name'] as String).toList();
         if (!columnNames.contains('rate')) await db.execute('ALTER TABLE generated_pos ADD COLUMN rate REAL');
         if (!columnNames.contains('unit')) await db.execute('ALTER TABLE generated_pos ADD COLUMN unit TEXT');
      }
      if (oldVersion < 55 && newVersion >= 55) {
         var tableInfo = await db.rawQuery('PRAGMA table_info(purchases)');
         var columnNames = tableInfo.map((row) => row['name'] as String).toList();
         if (!columnNames.contains('item_tag')) await db.execute('ALTER TABLE purchases ADD COLUMN item_tag TEXT');
      }
      if (oldVersion < 56 && newVersion >= 56) {
         var salesInfo = await db.rawQuery('PRAGMA table_info(sales)');
         if (!salesInfo.map((row) => row['name'] as String).contains('item_tag')) {
           await db.execute('ALTER TABLE sales ADD COLUMN item_tag TEXT');
         }
         var waitlistInfo = await db.rawQuery('PRAGMA table_info(sales_waitlist)');
         if (!waitlistInfo.map((row) => row['name'] as String).contains('item_tag')) {
           await db.execute('ALTER TABLE sales_waitlist ADD COLUMN item_tag TEXT');
         }
      }
      if (oldVersion < 57 && newVersion >= 57) {
         var rejectionInfo = await db.rawQuery('PRAGMA table_info(rejection_received)');
         if (!rejectionInfo.map((row) => row['name'] as String).contains('item_tag')) {
           await db.execute('ALTER TABLE rejection_received ADD COLUMN item_tag TEXT');
         }
      }
      if (oldVersion < 58 && newVersion >= 58) {
         var bGradeInfo = await db.rawQuery('PRAGMA table_info(b_grade_sales)');
         if (!bGradeInfo.map((row) => row['name'] as String).contains('item_tag')) {
           await db.execute('ALTER TABLE b_grade_sales ADD COLUMN item_tag TEXT');
         }
      }
      if (oldVersion < 59 && newVersion >= 59) {
         var bGradeInfo = await db.rawQuery('PRAGMA table_info(b_grade_sales)');
         var columns = bGradeInfo.map((row) => row['name'] as String).toList();
         if (!columns.contains('payment_status')) await db.execute('ALTER TABLE b_grade_sales ADD COLUMN payment_status TEXT');
         if (!columns.contains('mode_of_payment')) await db.execute('ALTER TABLE b_grade_sales ADD COLUMN mode_of_payment TEXT');
         if (!columns.contains('amount_paid')) await db.execute('ALTER TABLE b_grade_sales ADD COLUMN amount_paid REAL');
         if (!columns.contains('amount_due')) await db.execute('ALTER TABLE b_grade_sales ADD COLUMN amount_due REAL');
      }
      if (oldVersion < 60 && newVersion >= 60) {
         var purchaseInfo = await db.rawQuery('PRAGMA table_info(purchases)');
         var pCols = purchaseInfo.map((row) => row['name'] as String).toList();
         if (!pCols.contains('payment_status')) await db.execute('ALTER TABLE purchases ADD COLUMN payment_status TEXT');
         if (!pCols.contains('mode_of_payment')) await db.execute('ALTER TABLE purchases ADD COLUMN mode_of_payment TEXT');
         if (!pCols.contains('amount_paid')) await db.execute('ALTER TABLE purchases ADD COLUMN amount_paid REAL');
         if (!pCols.contains('amount_due')) await db.execute('ALTER TABLE purchases ADD COLUMN amount_due REAL');
         if (!pCols.contains('rate')) await db.execute('ALTER TABLE purchases ADD COLUMN rate REAL');
         if (!pCols.contains('total_value')) await db.execute('ALTER TABLE purchases ADD COLUMN total_value REAL');

         var salesInfo = await db.rawQuery('PRAGMA table_info(sales)');
         var sCols = salesInfo.map((row) => row['name'] as String).toList();
         if (!sCols.contains('payment_status')) await db.execute('ALTER TABLE sales ADD COLUMN payment_status TEXT');
         if (!sCols.contains('mode_of_payment')) await db.execute('ALTER TABLE sales ADD COLUMN mode_of_payment TEXT');
         if (!sCols.contains('amount_paid')) await db.execute('ALTER TABLE sales ADD COLUMN amount_paid REAL');
         if (!sCols.contains('amount_due')) await db.execute('ALTER TABLE sales ADD COLUMN amount_due REAL');
         if (!sCols.contains('rate')) await db.execute('ALTER TABLE sales ADD COLUMN rate REAL');
         if (!sCols.contains('total_value')) await db.execute('ALTER TABLE sales ADD COLUMN total_value REAL');
      }
      if (oldVersion < 61 && newVersion >= 61) {
         var dumpInfo = await db.rawQuery('PRAGMA table_info(dump_sales)');
         if (!dumpInfo.map((row) => row['name'] as String).contains('item_tag')) {
           await db.execute('ALTER TABLE dump_sales ADD COLUMN item_tag TEXT');
         }
      }
      if (oldVersion < 62 && newVersion >= 62) {
         var mandiInfo = await db.rawQuery('PRAGMA table_info(mandi_resales)');
         if (!mandiInfo.map((row) => row['name'] as String).contains('item_tag')) {
           await db.execute('ALTER TABLE mandi_resales ADD COLUMN item_tag TEXT');
         }
      }
      if (oldVersion < 63 && newVersion >= 63) {
         var stockInfo = await db.rawQuery('PRAGMA table_info(stock_updates)');
         var cols = stockInfo.map((row) => row['name'] as String).toList();
         if (!cols.contains('a_grade_tags')) await db.execute('ALTER TABLE stock_updates ADD COLUMN a_grade_tags TEXT');
         if (!cols.contains('b_grade_tags')) await db.execute('ALTER TABLE stock_updates ADD COLUMN b_grade_tags TEXT');
         if (!cols.contains('c_grade_tags')) await db.execute('ALTER TABLE stock_updates ADD COLUMN c_grade_tags TEXT');
         if (!cols.contains('ungraded_tags')) await db.execute('ALTER TABLE stock_updates ADD COLUMN ungraded_tags TEXT');
         if (!cols.contains('dump_tags')) await db.execute('ALTER TABLE stock_updates ADD COLUMN dump_tags TEXT');
      }
      if (oldVersion < 64 && newVersion >= 64) {
         var vendorInfo = await db.rawQuery('PRAGMA table_info(vendors)');
         var vCols = vendorInfo.map((row) => row['name'] as String).toList();
         if (!vCols.contains('location')) await db.execute('ALTER TABLE vendors ADD COLUMN location TEXT');
         if (!vCols.contains('km')) await db.execute('ALTER TABLE vendors ADD COLUMN km REAL');
      }
      if (oldVersion < 65 && newVersion >= 65) {
         var poInfo = await db.rawQuery('PRAGMA table_info(generated_pos)');
         if (!poInfo.map((row) => row['name'] as String).contains('note')) {
           await db.execute('ALTER TABLE generated_pos ADD COLUMN note TEXT');
         }
      }
    }
  }

  Future<void> _dropAllTables(Database db) async {
    await db.execute('DROP TABLE IF EXISTS product_managers');
    await db.execute('DROP TABLE IF EXISTS so_items');
    await db.execute('DROP TABLE IF EXISTS generated_sos');
    await db.execute('DROP TABLE IF EXISTS generated_pos');
    await db.execute('DROP TABLE IF EXISTS payment_history');
    await db.execute('DROP TABLE IF EXISTS sales_waitlist');
    await db.execute('DROP TABLE IF EXISTS lmd_data');
    await db.execute('DROP TABLE IF EXISTS fmd_data');
    await db.execute('DROP TABLE IF EXISTS items');
    await db.execute('DROP TABLE IF EXISTS vendors');
    await db.execute('DROP TABLE IF EXISTS purchase_vendors');
    await db.execute('DROP TABLE IF EXISTS b_grade_clients');
    await db.execute('DROP TABLE IF EXISTS purchases');
    await db.execute('DROP TABLE IF EXISTS stock_updates');
    await db.execute('DROP TABLE IF EXISTS b_grade_sales');
    await db.execute('DROP TABLE IF EXISTS sales');
    await db.execute('DROP TABLE IF EXISTS rejection_received');
    await db.execute('DROP TABLE IF EXISTS vendor_rejections');
    await db.execute('DROP TABLE IF EXISTS dump_sales');
    await db.execute('DROP TABLE IF EXISTS mandi_resales');
  }

  Future<void> _createAllTables(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS product_managers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');
    await db.execute('CREATE TABLE IF NOT EXISTS generated_sos (id INTEGER PRIMARY KEY AUTOINCREMENT, client_name TEXT, so_number TEXT, date_of_dispatch TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS so_items (id INTEGER PRIMARY KEY AUTOINCREMENT, so_id INTEGER, item_name TEXT, quantity_kg REAL, quantity_pcs REAL, FOREIGN KEY (so_id) REFERENCES generated_sos (id) ON DELETE CASCADE)');
    await db.execute('CREATE TABLE IF NOT EXISTS generated_pos (id INTEGER PRIMARY KEY AUTOINCREMENT, product_manager TEXT, item_name TEXT, po_number TEXT, qty_ordered REAL, rate REAL, unit TEXT, vendor_name TEXT, expected_date TEXT, quality_specifications TEXT, note TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS lmd_data (id INTEGER PRIMARY KEY AUTOINCREMENT, client_name TEXT, po_number TEXT, vehicle_number TEXT, driver_name TEXT, client_location TEXT, vehicle_type TEXT, booking_person TEXT, km REAL, price_per_km REAL, extra_expenses REAL, reason TEXT, total_amount REAL, payment_status TEXT, mode_of_payment TEXT, amount_paid REAL, amount_due REAL, date TEXT, time TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS fmd_data (id INTEGER PRIMARY KEY AUTOINCREMENT, vendor_name TEXT, vendor_location TEXT, vehicle_number TEXT, driver_name TEXT, po_number TEXT, items TEXT, vehicle_type TEXT, booking_person TEXT, km REAL, price_per_km REAL, extra_expenses REAL, reason TEXT, total_amount REAL, payment_status TEXT, mode_of_payment TEXT, amount_paid REAL, amount_due REAL, date TEXT, time TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS payment_history (id INTEGER PRIMARY KEY AUTOINCREMENT, parent_table_name TEXT NOT NULL, parent_id INTEGER NOT NULL, amount_paid REAL NOT NULL, mode_of_payment TEXT NOT NULL, payment_date TEXT NOT NULL, payment_time TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS purchases (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, vendor TEXT, po_number TEXT, qty_receive REAL, unit_receive TEXT, pcs_receive REAL, qty_accept REAL, unit_accept TEXT, pcs_accept REAL, qty_reject REAL, unit_reject TEXT, pcs_reject REAL, reason_for_rejection TEXT, date TEXT, time TEXT, ctrl_date TEXT, item_tag TEXT, payment_status TEXT, mode_of_payment TEXT, amount_paid REAL, amount_due REAL, rate REAL, total_value REAL)');
    await db.execute('CREATE TABLE IF NOT EXISTS stock_updates (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT NOT NULL, a_grade_qty REAL, a_grade_unit TEXT, pcs_a_grade REAL, b_grade_qty REAL, b_grade_unit TEXT, pcs_b_grade REAL, c_grade_qty REAL, c_grade_unit TEXT, pcs_c_grade REAL, ungraded_qty REAL, ungraded_unit TEXT, pcs_ungraded REAL, dump_qty REAL, dump_unit TEXT, pcs_dump REAL, total_qty REAL, date TEXT, time TEXT, po_number TEXT, a_grade_tags TEXT, b_grade_tags TEXT, c_grade_tags TEXT, ungraded_tags TEXT, dump_tags TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS b_grade_sales (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, clint TEXT, quantity REAL, rate REAL, unit TEXT, total_value REAL, date TEXT, time TEXT, po_number TEXT, pcs REAL, item_tag TEXT, payment_status TEXT, mode_of_payment TEXT, amount_paid REAL, amount_due REAL)');
    await db.execute('CREATE TABLE IF NOT EXISTS sales (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, clint TEXT, quantity REAL, unit TEXT, pcs REAL, date TEXT, time TEXT, po_number TEXT, item_tag TEXT, payment_status TEXT, mode_of_payment TEXT, amount_paid REAL, amount_due REAL, rate REAL, total_value REAL)');
    await db.execute('CREATE TABLE IF NOT EXISTS sales_waitlist(id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, clint TEXT, po_number TEXT, quantity REAL, unit TEXT, pcs REAL, item_tag TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS rejection_received (id INTEGER PRIMARY KEY AUTOINCREMENT, client_name TEXT, item TEXT, quantity REAL, unit TEXT, pcs REAL, sample_quantity REAL, reason TEXT, date TEXT, time TEXT, ctrl_date TEXT, po_number TEXT, item_tag TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS vendor_rejections (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, vendor TEXT, po_number TEXT, quantity_sent REAL, unit TEXT, pcs REAL, date TEXT, time TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS dump_sales (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, quantity REAL, unit TEXT, pcs REAL, date TEXT, time TEXT, po_number TEXT, item_tag TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS mandi_resales (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, quantity REAL, unit TEXT, pcs REAL, date TEXT, time TEXT, po_number TEXT, item_tag TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');
    await db.execute('CREATE TABLE IF NOT EXISTS vendors (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, location TEXT, km REAL)');
    await db.execute('CREATE TABLE IF NOT EXISTS purchase_vendors (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');
    await db.execute('CREATE TABLE IF NOT EXISTS b_grade_clients (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');

    final List<String> initialItems = ["Papaya", "Lemon", "Pineapple", "Sweetlime", "Garlic", "Kiwi", "Dragon Fruit", "Pomegranate", "Guava", "Beetroot", "Cucumber", "Ginger", "Capsicum", "Orange", "Apple", "Persimmon", "ghee"];
    for (String item in initialItems) {
      await db.insert('items', {'name': item}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final List<String> initialProductManagers = [ "Kuldeep", "MUKESH", "Sahil", "Shivam", "Armaan" ];
    for (String manager in initialProductManagers) {
      await db.insert('product_managers', {'name': manager}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final List<String> initialPurchaseVendors = ["Siya ram", "Dhaniram", "Amit kumar ahuja", "Mohit", "Chandu", "Rehan papaya DM", "Vinay batra", "Swarn vayu", "Sanskruti agro", "Sudhir chabara", "Triple D", "Fidus Global", "Nutrigo Natura", "Rizwan okhla papaya", "Sambha agro", "Kripya shankar", "Vishal sticker", "Alam papaya", "Rizwan pom AM", "Nasir papaya", "Anil Mahajan", "Goutam traders", "Manjesh SK", "Jashram", "Mahipal jhunjhunu", "Umesh mukhiya okhla", "MD Ashan DM", "Vishal sharma"];
    for (String vendor in initialPurchaseVendors) {
      await db.insert('purchase_vendors', {'name': vendor}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final List<String> initialClients = ["Zomato- (CPC-LDH1)", "Zomato- (Rajpura)", "Zomato- (CPC-GGN2)", "Zomato- (CPC-DEL3)", "Zomato- (CPC-NOIDA2)", "Zomato- (CPC NOIDA)", "B2B", "KD Enterprises", "Sarasvi Foods Pvt. LTD.", "Safe and Healthy Food", "Red Otter Farms Pvt Ltd", "Sara Vaninetti", "Gurprakash Singh", "Madan's Back2Basics", "Utsav Mandir Foundation", "KSKT Agromart Private Limited", "PJTJ Technologies Private Limited", "PJTJ Rajpura", "Kiranakart Wholesale (DEL FRESH MH-2)", "Kiranakart Wholesale (DEL FRESH MH-5)", "Eliot India Food Services LLP"];
    for (String client in initialClients) {
      await db.insert('vendors', {'name': client}, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert('b_grade_clients', {'name': client}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<int> insertGeneratedSO(Map<String, dynamic> soData, List<Map<String, dynamic>> itemsData) async {
    final dbClient = await db;
    return await dbClient.transaction((txn) async {
      int soId = await txn.insert('generated_sos', soData);
      for (var item in itemsData) {
        item['so_id'] = soId;
        await txn.insert('so_items', item);
      }
      return soId;
    });
  }

  Future<List<Map<String, dynamic>>> getLatestGeneratedSOsWithItems({int limit = 10}) async {
    final dbClient = await db;
    const String query = 'SELECT so.id as so_id, so.client_name, so.so_number, so.date_of_dispatch, item.id as item_id, item.item_name, item.quantity_kg, item.quantity_pcs, v.location, v.km FROM generated_sos so JOIN so_items item ON so.id = item.so_id LEFT JOIN vendors v ON so.client_name = v.name WHERE so.id IN (SELECT id FROM generated_sos ORDER BY id DESC LIMIT ?) ORDER BY so.id DESC, item.id ASC';
    return await dbClient.rawQuery(query, [limit]);
  }

  Future<List<Map<String, dynamic>>> getAllGeneratedPOs({String? startDate, String? endDate, String? poNumber, String? itemName, String? vendorName}) async {
    final dbClient = await db;
    String whereClause = '';
    List<dynamic> whereArgs = [];
    if (poNumber != null && poNumber.isNotEmpty) { whereClause += 'po_number LIKE ?'; whereArgs.add('%$poNumber%'); }
    if (itemName != null && itemName.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'item_name = ?'; whereArgs.add(itemName); }
    if (vendorName != null && vendorName.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'vendor_name = ?'; whereArgs.add(vendorName); }
    if (startDate != null && startDate.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'expected_date >= ?'; whereArgs.add(startDate); }
    if (endDate != null && endDate.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'expected_date <= ?'; whereArgs.add(endDate); }
    return await dbClient.query('generated_pos', where: whereClause.isEmpty ? null : whereClause, whereArgs: whereArgs.isEmpty ? null : whereArgs, orderBy: 'id DESC');
  }

  Future<List<Map<String, dynamic>>> getAllGeneratedSOsWithItems({String? startDate, String? endDate, String? soNumber, String? itemName, String? clientName}) async {
    final dbClient = await db;
    String whereClause = '';
    List<dynamic> whereArgs = [];
    if (soNumber != null && soNumber.isNotEmpty) { whereClause += 'so.so_number LIKE ?'; whereArgs.add('%$soNumber%'); }
    if (itemName != null && itemName.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'item.item_name = ?'; whereArgs.add(itemName); }
    if (clientName != null && clientName.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'so.client_name = ?'; whereArgs.add(clientName); }
    if (startDate != null && startDate.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'so.date_of_dispatch >= ?'; whereArgs.add(startDate); }
    if (endDate != null && endDate.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'so.date_of_dispatch <= ?'; whereArgs.add(endDate); }
    final String query = 'SELECT so.id as so_id, so.client_name, so.so_number, so.date_of_dispatch, item.id as item_id, item.item_name, item.quantity_kg, item.quantity_pcs, v.location, v.km FROM generated_sos so JOIN so_items item ON so.id = item.so_id LEFT JOIN vendors v ON so.client_name = v.name ${whereClause.isNotEmpty ? 'WHERE $whereClause' : ''} ORDER BY so.id DESC, item.id ASC';
    return await dbClient.rawQuery(query, whereArgs);
  }

  Future<List<Map<String, dynamic>>> getAvailableSOsForSale() async {
    final dbClient = await db;
    List<Map<String, dynamic>> allSOs = List.from(await dbClient.query('generated_sos'));
    List<Map<String, dynamic>> usedSOs = await dbClient.query('sales', columns: ['po_number']);
    Set<String> usedSoNumbers = usedSOs.map((so) => so['po_number'] as String).toSet();
    allSOs.removeWhere((so) => usedSoNumbers.contains(so['so_number']));
    if (allSOs.isEmpty) return [];
    List<int> soIds = allSOs.map((so) => so['id'] as int).toList();
    String placeholders = List.generate(soIds.length, (_) => '?').join(', ');
    final String query = 'SELECT so.id as so_id, so.client_name, so.so_number, so.date_of_dispatch, item.id as item_id, item.item_name, item.quantity_kg, item.quantity_pcs FROM generated_sos so JOIN so_items item ON so.id = item.so_id WHERE so.id IN ($placeholders) ORDER BY so.id DESC, item.id ASC';
    return await dbClient.rawQuery(query, soIds);
  }

  Future<void> insertProductManager(String name) async {
    final dbClient = await db; if (name.trim().isEmpty) return;
    await dbClient.insert('product_managers', {'name': name.trim()}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<String>> getProductManagers() async {
    final dbClient = await db;
    final List<Map<String, dynamic>> maps = await dbClient.query('product_managers', orderBy: 'name COLLATE NOCASE');
    return List.generate(maps.length, (i) => maps[i]['name'] as String);
  }

  Future<int> addPaymentHistoryRecord(Map<String, dynamic> row) async { final dbClient = await db; return await dbClient.insert('payment_history', row); }
  Future<List<Map<String, dynamic>>> getPaymentHistory(String tableName, int parentId) async { final dbClient = await db; return await dbClient.query('payment_history', where: 'parent_table_name = ? AND parent_id = ?', whereArgs: [tableName, parentId], orderBy: 'payment_date DESC, payment_time DESC'); }
  Future<int> updatePaymentStatus(String tableName, int id, String status, {double? amountPaid, double? amountDue, String? modeOfPayment}) async {
    final dbClient = await db;
    Map<String, dynamic> data = {'payment_status': status, 'amount_paid': amountPaid, 'amount_due': status == 'Unpaid' ? null : amountDue};
    if (status == 'Unpaid') { data['mode_of_payment'] = null; } else { data['mode_of_payment'] = modeOfPayment; }
    return await dbClient.update(tableName, data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteLmdData(int id) async { final dbClient = await db; return await dbClient.delete('lmd_data', where: 'id = ?', whereArgs: [id]); }
  Future<int> deleteFmdData(int id) async { final dbClient = await db; return await dbClient.delete('fmd_data', where: 'id = ?', whereArgs: [id]); }
  Future<int> updateLmdData(Map<String, dynamic> row) async { final dbClient = await db; int id = row['id']; return await dbClient.update('lmd_data', row, where: 'id = ?', whereArgs: [id]); }
  Future<int> updateFmdData(Map<String, dynamic> row) async { final dbClient = await db; int id = row['id']; return await dbClient.update('fmd_data', row, where: 'id = ?', whereArgs: [id]); }

  Future<List<Map<String, dynamic>>> getFilteredLmdData({String? driverName, String? vehicleNumber, String? location, String? startDate, String? endDate, String? paymentStatus}) async {
    final dbClient = await db;
    String whereClause = ''; List<dynamic> whereArgs = [];
    if (driverName != null && driverName.isNotEmpty) { whereClause += 'driver_name LIKE ?'; whereArgs.add('%$driverName%'); }
    if (vehicleNumber != null && vehicleNumber.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'vehicle_number LIKE ?'; whereArgs.add('%$vehicleNumber%'); }
    if (location != null && location.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'client_location LIKE ?'; whereArgs.add('%$location%'); }
    if (startDate != null && startDate.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'date >= ?'; whereArgs.add(startDate); }
    if (endDate != null && endDate.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'date <= ?'; whereArgs.add(endDate); }
    if (paymentStatus != null && paymentStatus.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'payment_status = ?'; whereArgs.add(paymentStatus); }
    return await dbClient.query('lmd_data', where: whereClause.isEmpty ? null : whereClause, whereArgs: whereArgs.isEmpty ? null : whereArgs, orderBy: 'id DESC');
  }

  Future<List<Map<String, dynamic>>> getFilteredFmdData({String? driverName, String? vehicleNumber, String? location, String? startDate, String? endDate, String? paymentStatus}) async {
    final dbClient = await db;
    String whereClause = ''; List<dynamic> whereArgs = [];
    if (driverName != null && driverName.isNotEmpty) { whereClause += 'driver_name LIKE ?'; whereArgs.add('%$driverName%'); }
    if (vehicleNumber != null && vehicleNumber.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'vehicle_number LIKE ?'; whereArgs.add('%$vehicleNumber%'); }
    if (location != null && location.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'vendor_location LIKE ?'; whereArgs.add('%$location%'); }
    if (startDate != null && startDate.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'date >= ?'; whereArgs.add(startDate); }
    if (endDate != null && endDate.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'date <= ?'; whereArgs.add(endDate); }
    if (paymentStatus != null && paymentStatus.isNotEmpty) { if (whereClause.isNotEmpty) whereClause += ' AND '; whereClause += 'payment_status = ?'; whereArgs.add(paymentStatus); }
    return await dbClient.query('fmd_data', where: whereClause.isEmpty ? null : whereClause, whereArgs: whereArgs.isEmpty ? null : whereArgs, orderBy: 'id DESC');
  }

  Future<void> insertItem(String name) async { final dbClient = await db; if (name.trim().isEmpty) return; await dbClient.insert('items', {'name': name.trim()}, conflictAlgorithm: ConflictAlgorithm.ignore); }
  Future<void> insertVendor(String name, {String? location, double? km}) async { 
    final dbClient = await db; if (name.trim().isEmpty) return; 
    await dbClient.insert('vendors', {'name': name.trim(), 'location': location, 'km': km}, conflictAlgorithm: ConflictAlgorithm.replace); 
    await dbClient.insert('b_grade_clients', {'name': name.trim()}, conflictAlgorithm: ConflictAlgorithm.ignore); 
  }
  Future<void> insertPurchaseVendor(String name) async { final dbClient = await db; if (name.trim().isEmpty) return; await dbClient.insert('purchase_vendors', {'name': name.trim()}, conflictAlgorithm: ConflictAlgorithm.ignore); }
  Future<int> insertGeneratedPO(Map<String, dynamic> row) async { final dbClient = await db; return await dbClient.insert('generated_pos', row); }
  Future<List<Map<String, dynamic>>> getLatestGeneratedPOs({int limit = 10}) async { final dbClient = await db; return await dbClient.query('generated_pos', orderBy: 'id DESC', limit: limit); }
  Future<String?> getLastPoNumber() async { final dbClient = await db; final List<Map<String, dynamic>> maps = await dbClient.query('generated_pos', columns: ['po_number'], orderBy: 'id DESC', limit: 1); if (maps.isNotEmpty) return maps.first['po_number'] as String?; return null; }
  Future<String?> getLastSoNumber() async { final dbClient = await db; final List<Map<String, dynamic>> maps = await dbClient.query('generated_sos', columns: ['so_number'], orderBy: 'id DESC', limit: 1); if (maps.isNotEmpty) return maps.first['so_number'] as String?; return null; }

  Future<List<Map<String, dynamic>>> getAvailablePOsForPurchase() async {
    final dbClient = await db;
    List<Map<String, dynamic>> allPOs = List.from(await dbClient.query('generated_pos'));
    List<Map<String, dynamic>> usedPOs = await dbClient.query('purchases', columns: ['po_number', 'item']);
    Set<String> usedPoItemSet = usedPOs.map((p) => "${p['po_number']}|${p['item']}").toSet();
    allPOs.removeWhere((po) => usedPoItemSet.contains("${po['po_number']}|${po['item_name']}"));
    return allPOs;
  }

  Future<List<String>> getItems() async { final dbClient = await db; final List<Map<String, dynamic>> maps = await dbClient.query('items', orderBy: 'name COLLATE NOCASE'); return List.generate(maps.length, (i) => maps[i]['name'] as String); }
  Future<List<String>> getPurchasedItems() async {
    final dbClient = await db;
    final List<Map<String, dynamic>> maps = await dbClient.rawQuery('SELECT DISTINCT item FROM purchases ORDER BY item COLLATE NOCASE');
    return List.generate(maps.length, (i) => maps[i]['item'] as String);
  }
  Future<List<String>> getVendors() async { final dbClient = await db; final List<Map<String, dynamic>> maps = await dbClient.query('vendors', orderBy: 'name COLLATE NOCASE'); return List.generate(maps.length, (i) => maps[i]['name'] as String); }
  Future<List<Map<String, dynamic>>> getVendorsWithDetails() async {
    final dbClient = await db;
    return await dbClient.query('vendors', orderBy: 'name COLLATE NOCASE');
  }
  Future<List<String>> getPurchaseVendors() async { final dbClient = await db; final List<Map<String, dynamic>> maps = await dbClient.query('purchase_vendors', orderBy: 'name COLLATE NOCASE'); return List.generate(maps.length, (i) => maps[i]['name'] as String); }
  Future<List<String>> getBGradeClients() async { final dbClient = await db; final List<Map<String, dynamic>> maps = await dbClient.query('b_grade_clients', orderBy: 'name COLLATE NOCASE'); return List.generate(maps.length, (i) => maps[i]['name'] as String); }
  Future<int> deleteMultipleEntries(String tableName, List<int> ids) async { final dbClient = await db; if (ids.isEmpty) return 0; final placeholders = List.generate(ids.length, (_) => '?').join(', '); return await dbClient.delete(tableName, where: 'id IN ($placeholders)', whereArgs: ids); }
  Future<int> insertLmdData(Map<String, dynamic> row) async { final dbClient = await db; return await dbClient.insert('lmd_data', row); }
  Future<int> insertFmdData(Map<String, dynamic> row) async { final dbClient = await db; return await dbClient.insert('fmd_data', row); }
  Future<List<Map<String, dynamic>>> getLatestLmdData() async { final dbClient = await db; return await dbClient.query('lmd_data', orderBy: 'id DESC', limit: 5); }
  Future<List<Map<String, dynamic>>> getLatestFmdData() async { final dbClient = await db; return await dbClient.query('fmd_data', orderBy: 'id DESC', limit: 5); }
  Future<List<Map<String, dynamic>>> getAllLmdData() async { final dbClient = await db; return await dbClient.query('lmd_data', orderBy: 'id DESC'); }
  Future<List<Map<String, dynamic>>> getAllFmdData() async { final dbClient = await db; return await dbClient.query('fmd_data', orderBy: 'id DESC'); }
  Future<List<Map<String, dynamic>>> getLatestPurchases() async { return await (await db).query("purchases", orderBy: "id DESC", limit: 5); }
  Future<List<Map<String, dynamic>>> getLatestStockUpdates() async { return await (await db).query("stock_updates", orderBy: "id DESC", limit: 5); }
  Future<List<Map<String, dynamic>>> getLatestBGradeSales() async { return await (await db).query("b_grade_sales", orderBy: "id DESC", limit: 5); }
  Future<List<Map<String, dynamic>>> getLatestSales() async { return await (await db).query("sales", orderBy: "id DESC", limit: 5); }
  Future<List<Map<String, dynamic>>> getLatestRejectionReceived() async { return await (await db).query('rejection_received', orderBy: 'id DESC', limit: 5); }
  Future<List<Map<String, dynamic>>> getLatestVendorRejections() async { return await (await db).query("vendor_rejections", orderBy: "id DESC", limit: 5); }
  Future<List<Map<String, dynamic>>> getLatestDumpSales() async { return await (await db).query("dump_sales", orderBy: "id DESC", limit: 5); }
  Future<List<Map<String, dynamic>>> getLatestMandiResales() async { return await (await db).query("mandi_resales", orderBy: "id DESC", limit: 5); }
  Future<int> insertPurchase(Map<String, dynamic> row) async { return await (await db).insert("purchases", row); }
  Future<int> insertStockUpdate(Map<String, dynamic> row) async { return await (await db).insert("stock_updates", row); }
  Future<int> insertBGradeSale(Map<String, dynamic> row) async { return await (await db).insert("b_grade_sales", row); }
  Future<int> insertSale(Map<String, dynamic> row) async { return await (await db).insert("sales", row); }
  Future<void> insertRejectionReceived(Map<String, dynamic> data) async { await (await db).insert('rejection_received', data, conflictAlgorithm: ConflictAlgorithm.replace); }
  Future<int> insertVendorRejection(Map<String, dynamic> row) async { return await (await db).insert('vendor_rejections', row); }
  Future<int> insertDumpSale(Map<String, dynamic> row) async { return await (await db).insert("dump_sales", row); }
  Future<int> insertMandiResale(Map<String, dynamic> row) async { return await (await db).insert("mandi_resales", row); }
  Future<List<Map<String, dynamic>>> getAllPurchases() async { return await (await db).query("purchases", orderBy: "id DESC"); }
  Future<List<Map<String, dynamic>>> getAllStockUpdates() async { return await (await db).query("stock_updates", orderBy: "id DESC"); }
  Future<List<Map<String, dynamic>>> getAllBGradeSales() async { return await (await db).query('b_grade_sales', orderBy: 'id DESC'); }
  Future<List<Map<String, dynamic>>> getAllSales() async { return await (await db).query('sales', orderBy: 'id DESC'); }
  Future<List<Map<String, dynamic>>> getAllRejectionReceived() async { return await (await db).query('rejection_received', orderBy: 'id DESC'); }
  Future<List<Map<String, dynamic>>> getAllVendorRejections() async { return await (await db).query("vendor_rejections", orderBy: "id DESC"); }
  Future<List<Map<String, dynamic>>> getAllDumpSales() async { return await (await db).query("dump_sales", orderBy: "id DESC"); }
  Future<List<Map<String, dynamic>>> getAllMandiResales() async { return await (await db).query("mandi_resales", orderBy: "id DESC"); }
  Future<List<String>> getAllUniqueItems() async { return await getItems(); }
  Future<double> getSingleValue({ required String table, required String column, String? where, List<dynamic>? whereArgs, }) async { final dbClient = await db; var result = await dbClient.query( table, columns: ['SUM($column) as total'], where: where, whereArgs: whereArgs, ); if (result.isNotEmpty && result.first['total'] != null) { return (result.first['total'] as num).toDouble(); } return 0.0; }
  Future<double> getStockUpdateTotalForDate({required String item, required String chosenDate}) async { final dbClient = await db; var result = await dbClient.query( 'stock_updates', columns: ['SUM(total_qty) as total'], where: 'item = ? AND date = ?', whereArgs: [item, chosenDate], ); return (result.first['total'] as num?)?.toDouble() ?? 0.0; }
  Future<void> insertSaleToWaitlist(Map<String, dynamic> data) async { final dbClient = await db; await dbClient.insert('sales_waitlist', data, conflictAlgorithm: ConflictAlgorithm.replace); }
  Future<List<Map<String, dynamic>>> getWaitlistedSales() async { final dbClient = await db; return await dbClient.query('sales_waitlist', orderBy: 'id DESC'); }
  Future<void> deleteWaitlistedSale(int id) async { final dbClient = await db; await dbClient.delete('sales_waitlist', where: 'id = ?', whereArgs: [id]); }
  Future<int> deletePOsByNumber(String poNumber) async { final dbClient = await db; return await dbClient.delete('generated_pos', where: 'po_number = ?', whereArgs: [poNumber]); }
  Future<int> deleteSOById(int soId) async { final dbClient = await db; return await dbClient.delete('generated_sos', where: 'id = ?', whereArgs: [soId]); }
  Future<int> deletePOItem(int id) async { final dbClient = await db; return await dbClient.delete('generated_pos', where: 'id = ?', whereArgs: [id]); }
  Future<int> deleteSOItem(int id) async { final dbClient = await db; return await dbClient.delete('so_items', where: 'id = ?', whereArgs: [id]); }
  Future<int> updatePOItem(int id, Map<String, dynamic> row) async { final dbClient = await db; return await dbClient.update('generated_pos', row, where: 'id = ?', whereArgs: [id]); }
  Future<int> updateSO(int id, Map<String, dynamic> row) async { final dbClient = await db; return await dbClient.update('generated_sos', row, where: 'id = ?', whereArgs: [id]); }
  Future<int> updateSOItem(int id, Map<String, dynamic> row) async { final dbClient = await db; return await dbClient.update('so_items', row, where: 'id = ?', whereArgs: [id]); }

  Future<int> getNextItemTagSequence(String vendorPrefix, String dayPart) async {
    final dbClient = await db;
    final String pattern = '$vendorPrefix-$dayPart-%';
    final result = await dbClient.rawQuery( 'SELECT item_tag FROM purchases WHERE item_tag LIKE ? ORDER BY id DESC', [pattern] );
    if (result.isEmpty) return 1;
    for (var row in result) {
      String lastTag = row['item_tag'] as String;
      List<String> parts = lastTag.split('-');
      if (parts.length == 3) {
        int? lastNum = int.tryParse(parts.last);
        if (lastNum != null) return lastNum + 1;
      }
    }
    return 1;
  }

  Future<List<String>> getPurchasedTagsForItem(String itemName) async {
    final dbClient = await db;
    final List<Map<String, dynamic>> result = await dbClient.query(
      'purchases',
      distinct: true,
      columns: ['item_tag'],
      where: 'item = ? AND item_tag IS NOT NULL AND item_tag != ""',
      whereArgs: [itemName],
      orderBy: 'item_tag ASC'
    );
    return result.map((row) => row['item_tag'] as String).toList();
  }

  Future<int> deleteItemTagFromSystem(String tag) async {
    final dbClient = await db;
    return await dbClient.update('purchases', {'item_tag': null}, where: 'item_tag = ?', whereArgs: [tag]);
  }

  Future<String?> getPoNumberByTag(String item, String tag) async {
    final dbClient = await db;
    final List<Map<String, dynamic>> result = await dbClient.query( 'purchases', columns: ['po_number'], where: 'item = ? AND item_tag = ?', whereArgs: [item, tag], limit: 1 );
    if (result.isNotEmpty) return result.first['po_number'] as String?;
    return null;
  }
}
