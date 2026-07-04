from flask import Flask, request, jsonify
from flask_cors import CORS
import sqlite3
import os
import json
from datetime import datetime, timedelta

app = Flask(__name__)
CORS(app)

db_path = 'mydata.db'

def init_db():
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    def _ensure_integer_id(table_name: str, schema_sql: str):
        """Fix `id` type to INTEGER by recreating table and rewriting ids into unique integer sequence."""
        print(f"🛠️ [id-fix] Checking table: {table_name}")
        try:
            cursor.execute(f"PRAGMA table_info({table_name})")

            cols = cursor.fetchall()
            id_cols = [c for c in cols if c[1] == 'id']
            if not id_cols:
                return

            id_decl = (id_cols[0][2] or '').upper()

            # 1) Rename old table -> tmp
            tmp = f"{table_name}__old_varchar_id"
            cursor.execute(f"SELECT COUNT(*) FROM {table_name}")
            before_rows = cursor.fetchone()[0]
            print(f"🛠️ [id-fix] {table_name}: before_rows={before_rows}")

            cursor.execute(f"ALTER TABLE {table_name} RENAME TO {tmp}")
            cursor.execute(schema_sql)


            # 2) Copy all columns except id, then insert with fresh sequential ids.
            cursor.execute(f"PRAGMA table_info({table_name})")
            new_cols = [r[1] for r in cursor.fetchall()]
            cursor.execute(f"PRAGMA table_info({tmp})")
            old_cols = [r[1] for r in cursor.fetchall()]
            if not old_cols:
                return

            common_cols = [c for c in new_cols if c in old_cols]
            if 'id' not in common_cols:
                return

            insert_cols = [c for c in common_cols if c != 'id']
            col_list = ','.join(insert_cols)

            # ROW_NUMBER() gives 1..N unique ids.
            # SQLite supports window functions on modern versions.
            # We preserve order by old rowid.
            if col_list:
                select_cols = ','.join([c for c in insert_cols])
                cursor.execute(
                    f"""
                    INSERT INTO {table_name} (id, {col_list})
                    SELECT
                        ROW_NUMBER() OVER (ORDER BY {tmp}.rowid) AS id,
                        {select_cols}
                    FROM {tmp}
                    """
                )
            else:
                cursor.execute(
                    f"""
                    INSERT INTO {table_name} (id)
                    SELECT ROW_NUMBER() OVER (ORDER BY {tmp}.rowid) AS id
                    FROM {tmp}
                    """
                )

            cursor.execute(f"DROP TABLE {tmp}")
        except sqlite3.OperationalError:
            # If anything goes wrong, skip (safer for production).
            pass


    # SO Dispatch Migration - Safe if columns exist

    _ensure_integer_id(
        'purchase_vendors',
        """CREATE TABLE IF NOT EXISTS purchase_vendors (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)""",
    )
    _ensure_integer_id(
        'b_grade_clients',
        """CREATE TABLE IF NOT EXISTS b_grade_clients (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)""",
    )
    _ensure_integer_id(
        'product_managers',
        """CREATE TABLE IF NOT EXISTS product_managers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)""",
    )
    _ensure_integer_id(
        'items',
        """CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)""",
    )
    _ensure_integer_id(
        'vendors',
        """CREATE TABLE IF NOT EXISTS vendors (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, location TEXT, km REAL)""",
    )
    _ensure_integer_id(
        'packaging_vendors',
        """CREATE TABLE IF NOT EXISTS packaging_vendors (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)""",
    )

    # Create all tables as per _createAllTables

    cursor.execute('''CREATE TABLE IF NOT EXISTS product_managers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)''')

    cursor.execute('''CREATE TABLE IF NOT EXISTS generated_sos (id INTEGER PRIMARY KEY AUTOINCREMENT, client_name TEXT, so_number TEXT, date_of_dispatch TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS so_items (id INTEGER PRIMARY KEY AUTOINCREMENT, so_id INTEGER, item_name TEXT, quantity_kg REAL, quantity_pcs REAL, dispatched_qty_kg REAL DEFAULT 0, dispatched_qty_pcs REAL DEFAULT 0, dispatch_status TEXT DEFAULT 'pending', FOREIGN KEY (so_id) REFERENCES generated_sos (id) ON DELETE CASCADE)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS generated_pos (id INTEGER PRIMARY KEY AUTOINCREMENT, product_manager TEXT, item_name TEXT, po_number TEXT, qty_ordered REAL, rate REAL, unit TEXT, vendor_name TEXT, vendor_id TEXT, advanced_payment TEXT, advanced_payment_date TEXT, expected_date TEXT, quality_specifications TEXT, note TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS lmd_data (id INTEGER PRIMARY KEY AUTOINCREMENT, client_name TEXT, po_number TEXT, vehicle_number TEXT, driver_name TEXT, client_location TEXT, vehicle_type TEXT, booking_person TEXT, km REAL, price_per_km REAL, extra_expenses REAL, reason TEXT, total_amount REAL, payment_status TEXT, mode_of_payment TEXT, amount_paid REAL, amount_due REAL, date TEXT, time TEXT, ctrl_date TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS fmd_data (id INTEGER PRIMARY KEY AUTOINCREMENT, vendor_name TEXT, vendor_location TEXT, vehicle_number TEXT, driver_name TEXT, po_number TEXT, items TEXT, vehicle_type TEXT, booking_person TEXT, gate_number TEXT, km REAL, price_per_km REAL, extra_expenses REAL, reason TEXT, total_amount REAL, payment_status TEXT, mode_of_payment TEXT, amount_paid REAL, amount_due REAL, date TEXT, time TEXT, ctrl_date TEXT)''')
    

    cursor.execute("""CREATE TABLE IF NOT EXISTS admin_report (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, item TEXT, stock_today REAL DEFAULT 0, stock_next_day REAL DEFAULT 0, purchase_received REAL DEFAULT 0, rejection_received REAL DEFAULT 0, vendor_rejection REAL DEFAULT 0, sales REAL DEFAULT 0, dump_sale REAL DEFAULT 0, mandi_resale REAL DEFAULT 0, b_grade_sales REAL DEFAULT 0, total_quantity REAL DEFAULT 0, total_sales REAL DEFAULT 0,check_stock REAL DEFAULT 0)""")
    # Migration: Add ctrl_date column to existing tables if not present
    try:
        cursor.execute("SELECT ctrl_date FROM lmd_data LIMIT 1")
    except sqlite3.OperationalError:
        cursor.execute("ALTER TABLE lmd_data ADD COLUMN ctrl_date TEXT")
    
    try:
        cursor.execute("SELECT ctrl_date FROM fmd_data LIMIT 1")
    except sqlite3.OperationalError:
        cursor.execute("ALTER TABLE fmd_data ADD COLUMN ctrl_date TEXT")

    # Migration: add gate_number column to fmd_data if missing
    try:
        cursor.execute("SELECT gate_number FROM fmd_data LIMIT 1")
    except sqlite3.OperationalError:
        cursor.execute("ALTER TABLE fmd_data ADD COLUMN gate_number TEXT")

    try:
        cursor.execute("SELECT gate_number FROM lmd_data LIMIT 1")
    except sqlite3.OperationalError:
        cursor.execute("ALTER TABLE lmd_data ADD COLUMN gate_number TEXT")

    try:
        cursor.execute("ALTER TABLE so_items ADD COLUMN dispatched_qty_kg REAL DEFAULT 0")
    except sqlite3.OperationalError:
        pass
    try:
        cursor.execute("ALTER TABLE so_items ADD COLUMN dispatched_qty_pcs REAL DEFAULT 0")
    except sqlite3.OperationalError:
        pass
    try:
        cursor.execute("ALTER TABLE so_items ADD COLUMN dispatch_status TEXT DEFAULT 'pending'")
    except sqlite3.OperationalError:
        pass


    try:
        cursor.execute("ALTER TABLE generated_pos ADD COLUMN date TEXT")
    except sqlite3.OperationalError:
        pass

    try:
        cursor.execute("ALTER TABLE generated_pos ADD COLUMN time TEXT")
    except sqlite3.OperationalError:
        pass

    # NEW: migration - ensure generated_pos has payment/vendor columns
    try:
        cursor.execute("SELECT vendor_id FROM generated_pos LIMIT 1")
    except sqlite3.OperationalError:
        cursor.execute("ALTER TABLE generated_pos ADD COLUMN vendor_id TEXT")

    try:
        cursor.execute("SELECT advanced_payment FROM generated_pos LIMIT 1")
    except sqlite3.OperationalError:
        cursor.execute("ALTER TABLE generated_pos ADD COLUMN advanced_payment TEXT")

    try:
        cursor.execute("SELECT advanced_payment_date FROM generated_pos LIMIT 1")
    except sqlite3.OperationalError:
        cursor.execute("ALTER TABLE generated_pos ADD COLUMN advanced_payment_date TEXT")


    
    # cursor.execute("UPDATE so_items SET dispatch_status = 'pending' WHERE dispatch_status IS NULL")
    try:
        cursor.execute("UPDATE so_items SET dispatch_status = 'pending' WHERE dispatch_status IS NULL")
    except sqlite3.OperationalError:
        pass
    
# Add UNIQUE constraint for concurrent PO fix (safe if exists)
    try:
        cursor.execute('''CREATE TABLE IF NOT EXISTS generated_pos (id INTEGER PRIMARY KEY AUTOINCREMENT, product_manager TEXT, item_name TEXT, po_number TEXT UNIQUE, qty_ordered REAL, rate REAL, unit TEXT, vendor_name TEXT, expected_date TEXT, quality_specifications TEXT, note TEXT)''')
    except sqlite3.OperationalError:
        pass

        
    
    # NEW: Section Groups Table for Password Management
    cursor.execute('''CREATE TABLE IF NOT EXISTS section_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_name TEXT UNIQUE NOT NULL, 
        password_hash TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )''')
    
    # NEW: Insert initial 4 groups with '1008' password (hashed simply for demo)
    initial_groups = [
        ('po_so', '1008'), 
        ('inventory', '1008'),
        ('lmd_fmd', '1008'),
        ('admin', '1008')
    ]
    for group_name, pwd in initial_groups:
        # Simple hash (use bcrypt in production)
        pwd_hash = pwd  # TODO: hash(pwd)
        cursor.execute(
            "INSERT OR IGNORE INTO section_groups (group_name, password_hash) VALUES (?, ?)",
            (group_name, pwd_hash)
        )
    
    print("✅ Password groups initialized: po_so, inventory, lmd_fmd, admin")
    
    cursor.execute('''CREATE TABLE IF NOT EXISTS payment_history (id INTEGER PRIMARY KEY AUTOINCREMENT, parent_table_name TEXT NOT NULL, parent_id INTEGER NOT NULL, amount_paid REAL NOT NULL, mode_of_payment TEXT NOT NULL, payment_date TEXT NOT NULL, payment_time TEXT NOT NULL)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item TEXT,
        vendor TEXT,
        po_number TEXT,
        qty_receive REAL,
        unit_receive TEXT,
        pcs_receive REAL,
        qty_accept REAL,
        unit_accept TEXT,
        pcs_accept REAL,
        qty_reject REAL,
        unit_reject TEXT,
        pcs_reject REAL,
        reason_for_rejection TEXT,
        date TEXT,
        time TEXT,
        ctrl_date TEXT,
        item_tag TEXT,
        payment_status TEXT,
        mode_of_payment TEXT,
        amount_paid REAL,
        amount_due REAL,
        rate REAL,
        amount_of_accepted REAL,
        low_grade_qty REAL,
        low_grade_rate REAL,
        total_low_grade_amount REAL,
        total_amount REAL
    )''')



    try:
        cursor.execute("SELECT low_grade_qty FROM purchases LIMIT 1")
    except sqlite3.OperationalError:
        cursor.execute(
            "ALTER TABLE purchases ADD COLUMN low_grade_qty REAL DEFAULT 0"
        )

    try:
        cursor.execute("SELECT low_grade_rate FROM purchases LIMIT 1")
    except sqlite3.OperationalError:
        cursor.execute(
            "ALTER TABLE purchases ADD COLUMN low_grade_rate REAL DEFAULT 0"
        )

    try:
        cursor.execute("SELECT total_low_grade_amount FROM purchases LIMIT 1")
    except sqlite3.OperationalError:
        cursor.execute(
            "ALTER TABLE purchases ADD COLUMN total_low_grade_amount REAL DEFAULT 0"
        )



    try:
        cursor.execute("SELECT amount_of_accepted FROM purchases LIMIT 1")
    except sqlite3.OperationalError:
        try:
            cursor.execute("""
                ALTER TABLE purchases
                RENAME COLUMN total_value TO amount_of_accepted
            """)
        except sqlite3.OperationalError:
            pass





    try:
        cursor.execute("SELECT total_amount FROM purchases LIMIT 1")
    except sqlite3.OperationalError:
        cursor.execute(
            "ALTER TABLE purchases ADD COLUMN total_amount REAL DEFAULT 0"
        )




    cursor.execute('''CREATE TABLE IF NOT EXISTS stock_updates (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT NOT NULL, a_grade_qty REAL, a_grade_unit TEXT, pcs_a_grade REAL, b_grade_qty REAL, b_grade_unit TEXT, pcs_b_grade REAL, c_grade_qty REAL, c_grade_unit TEXT, pcs_c_grade REAL, ungraded_qty REAL, ungraded_unit TEXT, pcs_ungraded REAL, dump_qty REAL, dump_unit TEXT, pcs_dump REAL, total_qty REAL, date TEXT, time TEXT, po_number TEXT, a_grade_tags TEXT, b_grade_tags TEXT, c_grade_tags TEXT, ungraded_tags TEXT, dump_tags TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS b_grade_sales (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, clint TEXT, quantity REAL, rate REAL, unit TEXT, total_value REAL, date TEXT, time TEXT, po_number TEXT, pcs REAL, item_tag TEXT, payment_status TEXT, mode_of_payment TEXT, amount_paid REAL, amount_due REAL)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS sales (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, clint TEXT, quantity REAL, unit TEXT, pcs REAL, date TEXT, time TEXT, po_number TEXT, item_tag TEXT, payment_status TEXT, mode_of_payment TEXT, amount_paid REAL, amount_due REAL, rate REAL, total_value REAL)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS sales_waitlist(id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, clint TEXT, po_number TEXT, quantity REAL, unit TEXT, pcs REAL, item_tag TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS rejection_received (id INTEGER PRIMARY KEY AUTOINCREMENT, client_name TEXT, item TEXT, quantity REAL, unit TEXT, pcs REAL, sample_quantity REAL, reason TEXT, date TEXT, time TEXT, ctrl_date TEXT, po_number TEXT, item_tag TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS vendor_rejections (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, vendor TEXT, po_number TEXT, quantity_sent REAL, unit TEXT, pcs REAL, date TEXT, time TEXT, ctrl_date TEXT)''')

    # Migration: add ctrl_date if table already exists without it
    try:
        cursor.execute("SELECT ctrl_date FROM vendor_rejections LIMIT 1")
    except sqlite3.OperationalError:
        cursor.execute("ALTER TABLE vendor_rejections ADD COLUMN ctrl_date TEXT")
    cursor.execute('''CREATE TABLE IF NOT EXISTS dump_sales (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, quantity REAL, unit TEXT, pcs REAL, date TEXT, time TEXT, po_number TEXT, item_tag TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS mandi_resales (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, quantity REAL, unit TEXT, pcs REAL, date TEXT, time TEXT, item_tag TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS vendors (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, location TEXT, km REAL)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS purchase_vendors (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS b_grade_clients (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)''')   
    cursor.execute('''CREATE TABLE IF NOT EXISTS packaging_materials (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, vendor TEXT, po_number TEXT, qty_receive REAL, unit_receive TEXT, pcs_receive REAL, qty_accept REAL, unit_accept TEXT, pcs_accept REAL, qty_reject REAL, unit_reject TEXT, pcs_reject REAL, reason_for_rejection TEXT, date TEXT, time TEXT, ctrl_date TEXT, item_tag TEXT, payment_status TEXT, mode_of_payment TEXT, amount_paid REAL, amount_due REAL, rate REAL, total_value REAL)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS packaging_vendors (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS gate_tracker (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        gate_number INTEGER UNIQUE NOT NULL,
        record_date TEXT,
        purchase_total REAL DEFAULT 0,
        sales_total REAL DEFAULT 0, 
        bgrade_total REAL DEFAULT 0,
        rejection_total REAL DEFAULT 0,
        dump_total REAL DEFAULT 0,
        mandi_total REAL DEFAULT 0,
        vehicle_number TEXT,
        driver_name TEXT,
        party_name TEXT, 
        remarks TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS gate_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, vehicle_number TEXT, driver_name TEXT, entry_type TEXT, purpose TEXT, party_name TEXT, remarks TEXT, date TEXT, time TEXT)''')

    # Insert initial data
    initial_items = ["Papaya", "Lemon", "Pineapple", "Sweetlime", "Garlic", "Kiwi", "Dragon Fruit", "Pomegranate", "Guava", "Beetroot", "Cucumber", "Ginger", "Capsicum", "Orange", "Apple", "Persimmon", "ghee"]
    for item in initial_items:
        cursor.execute('INSERT OR IGNORE INTO items (name) VALUES (?)', (item,))

    initial_product_managers = ["Kuldeep", "MUKESH", "Sahil", "Shivam", "Armaan"]
    for manager in initial_product_managers:
        cursor.execute('INSERT OR IGNORE INTO product_managers (name) VALUES (?)', (manager,))

    initial_purchase_vendors = ["Siya ram", "Dhaniram", "Amit kumar ahuja", "Mohit", "Chandu", "Rehan papaya DM", "Vinay batra", "Swarn vayu", "Sanskruti agro", "Sudhir chabara", "Triple D", "Fidus Global", "Nutrigo Natura", "Rizwan okhla papaya", "Sambha agro", "Kripya shankar", "Vishal sticker", "Alam papaya", "Rizwan pom AM", "Nasir papaya", "Anil Mahajan", "Goutam traders", "Manjesh SK", "Jashram", "Mahipal jhunjhunu", "Umesh mukhiya okhla", "MD Ashan DM", "Vishal sharma"]
    for vendor in initial_purchase_vendors:
        cursor.execute('INSERT OR IGNORE INTO purchase_vendors (name) VALUES (?)', (vendor,))
        # packaging_vendors remains empty - users will add via app

    initial_clients = ["Zomato- (CPC-LDH1)", "Zomato- (Rajpura)", "Zomato- (CPC-GGN2)", "Zomato- (CPC-DEL3)", "Zomato- (CPC-NOIDA2)", "Zomato- (CPC NOIDA)", "B2B", "KD Enterprises", "Sarasvi Foods Pvt. LTD.", "Safe and Healthy Food", "Red Otter Farms Pvt Ltd", "Sara Vaninetti", "Gurprakash Singh", "Madan's Back2Basics", "Utsav Mandir Foundation", "KSKT Agromart Private Limited", "PJTJ Technologies Private Limited", "PJTJ Rajpura", "Kiranakart Wholesale (DEL FRESH MH-2)", "Kiranakart Wholesale (DEL FRESH MH-5)", "Eliot India Food Services LLP"]
    for client in initial_clients:
        cursor.execute('INSERT OR IGNORE INTO vendors (name) VALUES (?)', (client,))
        cursor.execute('INSERT OR IGNORE INTO b_grade_clients (name) VALUES (?)', (client,))

    # Add new clients with location and km
    new_clients = [
        ("ZOMATO - DELHI", "Block B, Tyagi Vihar, Ghevra, Delhi, 110041", 140),
        ("ZOMATO - NOIDA -1", "24, Ecotech III, Greater Noida, Khera Chonganpur, Uttar Pradesh", 71),
        ("ZOMATO - NOIDA -2", "HG8P+G5J Zomato CPC-NOIDA2, Unnamed Road, Deri Skaner, Greater Noida, Uttar Pradesh 203207", 88),
        ("ZOMATO - GGN", "CV4Q+C7 Zomato Hyperpure Warehouse, Sector 96, Gurugram, Haryana 122505", 165),
        ("Zorba The Buddha", "7, Tropical Dr, Ghitorni, New Delhi, Delhi 110030", 29),
        ("SWIGGY", "Near Sector 42, Sonipat, Haryana 131103", 80),
        ("ZEPTO MH2", "Ghaziabad, Asalatpur Farakh Nagar, Uttar Pradesh 201003", 46),
        ("ZOMATO LUDHIANA", "VWM4+4H9 Zomato CPC, Phase IV, Focal Point, Ludhiana, Punjab 141003", 347),
        ("ZOMATO RAJPURA", "Near Hashampur, Punjab 140417", 256),
    ]
    for client_name, location, km in new_clients:
        cursor.execute('INSERT OR REPLACE INTO vendors (name, location, km) VALUES (?, ?, ?)', (client_name, location, km))
        cursor.execute('INSERT OR IGNORE INTO b_grade_clients (name) VALUES (?)', (client_name,))

    conn.commit()
    conn.close()

# Helper function to get db connection
def get_db():
    return sqlite3.connect(db_path)

def _get_paginated_data(table_name, page=1, per_page=20, start_date=None, end_date=None, search=None):
    """
    Generic pagination helper for dashboard tables.
    """
    offset = (page - 1) * per_page
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    # Build WHERE clause
    where_conditions = []
    where_args = []
    
    # Date filter - try 'date', 'ctrl_date', 'expected_date'
    date_field = None
    date_fields = ['date', 'ctrl_date', 'expected_date', 'date_of_dispatch']
    for field in date_fields:
        cursor.execute(f"PRAGMA table_info({table_name})")
        fields = [row[1] for row in cursor.fetchall()]
        if field in fields:
            date_field = field
            break
    
    if start_date:
        if date_field:
            where_conditions.append(f"{date_field} >= ?")
            where_args.append(start_date)
    
    if end_date:
        if date_field:
            where_conditions.append(f"{date_field} <= ?")
            where_args.append(end_date)
    
    # Search filter
    if search:
        # Common text fields for LIKE
        search_fields = ['item', 'clint', 'client_name', 'vendor', 'name', 'po_number', 'so_number', 'item_name', 'item_tag']
        table_fields = []
        cursor.execute(f"PRAGMA table_info({table_name})")
        for row in cursor.fetchall():
            if row[1] in search_fields and row[2] in [253, 'TEXT']:  # TEXT affinity
                table_fields.append(row[1])
        if table_fields:
            search_conditions = [f"{f} LIKE ?" for f in table_fields]
            # where_conditions.append(" OR ".join(search_conditions))
            where_conditions.append("(" + " OR ".join(search_conditions) + ")")
            where_args.extend([f"%{search}%"] * len(table_fields))
    
    where_clause = "WHERE " + " AND ".join(where_conditions) if where_conditions else ""
    
    # Count total
    count_query = f"SELECT COUNT(*) as total FROM {table_name} {where_clause}"
    cursor.execute(count_query, where_args)
    total = cursor.fetchone()['total']
    
    # Data query
    data_query = f"SELECT * FROM {table_name} {where_clause} ORDER BY id DESC LIMIT ? OFFSET ?"
    data_args = where_args + [per_page, offset]
    cursor.execute(data_query, data_args)
    rows = cursor.fetchall()
    
    conn.close()
    data = [dict(row) for row in rows]
    has_more = len(data) == per_page and offset + per_page < total
    
    return {
        'data': data,
        'total': total,
        'page': page,
        'per_page': per_page,
        'has_more': has_more
    }


@app.route('/insert_generated_so', methods=['POST'])
def insert_generated_so():
    data = request.json
    so_data = data['so_data']
    items_data = data['items_data']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('INSERT INTO generated_sos (client_name, so_number, date_of_dispatch) VALUES (?, ?, ?)', (so_data['client_name'], so_data['so_number'], so_data['date_of_dispatch']))
    so_id = cursor.lastrowid
    for item in items_data:
        cursor.execute('INSERT INTO so_items (so_id, item_name, quantity_kg, quantity_pcs) VALUES (?, ?, ?, ?)', (so_id, item['item_name'], item['quantity_kg'], item['quantity_pcs']))
    conn.commit()
    conn.close()
    return jsonify({'so_id': so_id})

@app.route('/get_latest_generated_sos_with_items', methods=['GET'])
def get_latest_generated_sos_with_items():
    limit = request.args.get('limit', 10, type=int)
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    query = '''SELECT so.id as so_id, so.client_name, so.so_number, so.date_of_dispatch, item.id as item_id, item.item_name, item.quantity_kg, item.quantity_pcs, v.location, v.km FROM generated_sos so JOIN so_items item ON so.id = item.so_id LEFT JOIN vendors v ON so.client_name = v.name WHERE so.id IN (SELECT id FROM generated_sos ORDER BY id DESC LIMIT ?) ORDER BY so.id DESC, item.id ASC'''
    cursor.execute(query, (limit,))
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)



@app.route('/insert_b_grade_sale', methods=['POST'])
def insert_b_grade_sale():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()
    query = '''INSERT INTO b_grade_sales
               (item, clint, quantity, rate, unit, total_value, date, time, po_number, pcs, item_tag, payment_status, mode_of_payment, amount_paid, amount_due)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'''
    params = (
        row.get('item'),
        row.get('clint'),
        row.get('quantity'),
        row.get('rate'),
        row.get('unit'),
        row.get('total_value'),
        row.get('ctrl_date') or row.get('date'),  # ctrl_date
        # row.get('date'),  # date column
        row.get('time'),  # time column
        row.get('po_number'),
        row.get('pcs'),
        row.get('item_tag'),
        row.get('payment_status'),
        row.get('mode_of_payment'),
        row.get('amount_paid'),
        row.get('amount_due'),
    )
    cursor.execute(query, params)
    conn.commit()
    last_id = cursor.lastrowid
    conn.close()
    return jsonify({'id': last_id})

@app.route('/get_latest_b_grade_sales', methods=['GET'])
def get_latest_b_grade_sales():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM b_grade_sales ORDER BY id DESC LIMIT 5')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)


@app.route('/get_all_generated_pos', methods=['GET'])
def get_all_generated_pos():
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    po_number = request.args.get('po_number')
    item_name = request.args.get('item_name')
    vendor_name = request.args.get('vendor_name')
    where_clause = ''
    where_args = []
    if po_number:
        where_clause += 'po_number LIKE ?'
        where_args.append(f'%{po_number}%')
    if item_name:
        if where_clause: where_clause += ' AND '
        where_clause += 'item_name = ?'
        where_args.append(item_name)
    if vendor_name:
        if where_clause: where_clause += ' AND '
        where_clause += 'vendor_name = ?'
        where_args.append(vendor_name)
    if start_date:
        if where_clause: where_clause += ' AND '
        where_clause += 'expected_date >= ?'
        where_args.append(start_date)
    if end_date:
        if where_clause: where_clause += ' AND '
        where_clause += 'expected_date <= ?'
        where_args.append(end_date)
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    query = f'SELECT * FROM generated_pos {f"WHERE {where_clause}" if where_clause else ""} ORDER BY id DESC'
    cursor.execute(query, where_args)
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/get_all_generated_sos_with_items', methods=['GET'])
def get_all_generated_sos_with_items():
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    so_number = request.args.get('so_number')
    item_name = request.args.get('item_name')
    client_name = request.args.get('client_name')
    where_clause = ''
    where_args = []
    if so_number:
        where_clause += 'so.so_number LIKE ?'
        where_args.append(f'%{so_number}%')
    if item_name:
        if where_clause: where_clause += ' AND '
        where_clause += 'item.item_name = ?'
        where_args.append(item_name)
    if client_name:
        if where_clause: where_clause += ' AND '
        where_clause += 'so.client_name = ?'
        where_args.append(client_name)
    if start_date:
        if where_clause: where_clause += ' AND '
        where_clause += 'so.date_of_dispatch >= ?'
        where_args.append(start_date)
    if end_date:
        if where_clause: where_clause += ' AND '
        where_clause += 'so.date_of_dispatch <= ?'
        where_args.append(end_date)
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    query = f'''SELECT so.id as so_id, so.client_name, so.so_number, so.date_of_dispatch, 
                       item.id as item_id, item.item_name, item.quantity_kg, item.quantity_pcs,
                       item.dispatched_qty_kg, item.dispatched_qty_pcs, item.dispatch_status,
                       v.location, v.km 
                FROM generated_sos so 
                JOIN so_items item ON so.id = item.so_id 
                LEFT JOIN vendors v ON so.client_name = v.name 
                {f"WHERE {where_clause}" if where_clause else ""} 
                ORDER BY so.id DESC, item.id ASC'''
    cursor.execute(query, where_args)
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/get_pending_so_items', methods=['GET'])
def get_pending_so_items():
    """New endpoint: Only undisptached SO items"""
    client_name = request.args.get('client_name')
    so_number = request.args.get('so_number')
    where_clause = []
    
    if client_name:
        where_clause.append("so.client_name = ?")
    if so_number:
        where_clause.append("so.so_number = ?")
    
    where_sql = " AND ".join(where_clause) if where_clause else ""
    where_args = [client_name, so_number] if where_clause else []
    
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    query = f'''SELECT so.id as so_id, so.client_name, so.so_number, so.date_of_dispatch,
                       item.id as item_id, item.item_name, 
                       item.quantity_kg, item.quantity_pcs,
                       item.dispatched_qty_kg, item.dispatched_qty_pcs, item.dispatch_status,
                       v.location, v.km,
                       (item.quantity_kg - COALESCE(item.dispatched_qty_kg, 0)) as remaining_kg,
                       (item.quantity_pcs - COALESCE(item.dispatched_qty_pcs, 0)) as remaining_pcs
                FROM generated_sos so 
                JOIN so_items item ON so.id = item.so_id 
                LEFT JOIN vendors v ON so.client_name = v.name
                WHERE item.dispatch_status = 'pending' 
                   OR (item.quantity_kg > COALESCE(item.dispatched_qty_kg, 0))
                   OR (item.quantity_pcs > COALESCE(item.dispatched_qty_pcs, 0))
                {f"AND {where_sql}" if where_sql else ""}
                ORDER BY so.id DESC, item.id ASC'''
    
    cursor.execute(query, where_args)
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/get_available_sos_for_sale', methods=['GET'])
def get_available_sos_for_sale():
    conn = get_db()
    cursor = conn.cursor()
    all_sos = cursor.execute('SELECT * FROM generated_sos').fetchall()
    used_sos = cursor.execute('SELECT po_number FROM sales').fetchall()
    used_so_numbers = set(row[0] for row in used_sos)
    available_sos = [so for so in all_sos if so[2] not in used_so_numbers]
    if not available_sos:
        conn.close()
        return jsonify([])
    so_ids = [so[0] for so in available_sos]
    placeholders = ','.join('?' * len(so_ids))
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    query = f'SELECT so.id as so_id, so.client_name, so.so_number, so.date_of_dispatch, item.id as item_id, item.item_name, item.quantity_kg, item.quantity_pcs FROM generated_sos so JOIN so_items item ON so.id = item.so_id WHERE so.id IN ({placeholders}) ORDER BY so.id DESC, item.id ASC'
    cursor.execute(query, so_ids)
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/insert_product_manager', methods=['POST'])
def insert_product_manager():
    name = request.json['name']
    if not name.strip():
        return jsonify({'error': 'Name cannot be empty'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('INSERT OR IGNORE INTO product_managers (name) VALUES (?)', (name.strip(),))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/get_product_managers', methods=['GET'])
def get_product_managers():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT id, name FROM product_managers ORDER BY name COLLATE NOCASE')
    rows = cursor.fetchall()
    conn.close()
    return jsonify([{'id': r['id'], 'name': r['name']} for r in rows])


@app.route('/add_payment_history_record', methods=['POST'])
def add_payment_history_record():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('INSERT INTO payment_history (parent_table_name, parent_id, amount_paid, mode_of_payment, payment_date, payment_time) VALUES (?, ?, ?, ?, ?, ?)', (row['parent_table_name'], row['parent_id'], row['amount_paid'], row['mode_of_payment'], row['payment_date'], row['payment_time']))
    conn.commit()
    conn.close()
    return jsonify({'id': cursor.lastrowid})

@app.route('/get_payment_history', methods=['GET'])
def get_payment_history():
    table_name = request.args.get('table_name')
    parent_id = request.args.get('parent_id', type=int)
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM payment_history WHERE parent_table_name = ? AND parent_id = ? ORDER BY payment_date DESC, payment_time DESC', (table_name, parent_id))
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/update_payment_status', methods=['PUT'])
def update_payment_status():
    data_in = request.json
    table_name = data_in['table_name']
    id = data_in['id']
    status = data_in['status']
    amount_paid = data_in.get('amount_paid')
    amount_due = data_in.get('amount_due')
    mode_of_payment = data_in.get('mode_of_payment')

    update_fields = {
        'payment_status': status,
        'amount_paid': amount_paid,
        'amount_due': amount_due if status != 'Unpaid' else 0.0,
        'mode_of_payment': mode_of_payment if status != 'Unpaid' else None
    }

    conn = get_db()
    cursor = conn.cursor()
    keys = list(update_fields.keys())
    set_clause = ', '.join([f"{k} = ?" for k in keys])
    values = [update_fields[k] for k in keys]
    values.append(id)

    cursor.execute(f'UPDATE {table_name} SET {set_clause} WHERE id = ?', values)
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/delete_lmd_data', methods=['DELETE'])
def delete_lmd_data():
    id = request.json['id']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM lmd_data WHERE id = ?', (id,))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/delete_fmd_data', methods=['DELETE'])
def delete_fmd_data():
    id = request.json['id']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM fmd_data WHERE id = ?', (id,))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/delete_vendor', methods=['DELETE', 'POST'])
def delete_vendor():
    data = request.json or request.form.to_dict()
    name = data.get('name')
    password = data.get('password')
    
    if not name or not password:
        return jsonify({'error': 'name and password required'}), 400
    
    # Verify LMD group password (for clients in LMD)
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT password_hash FROM section_groups WHERE group_name = ?', ('lmd_fmd',))
    result = cursor.fetchone()
    conn.close()
    
    if not result or result[0] != password:
        return jsonify({'error': 'Invalid LMD password (1008)'}), 403
    
    # Delete vendor/client
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM vendors WHERE name = ?', (name,))
    cursor.execute('DELETE FROM b_grade_clients WHERE name = ?', (name,))
    deleted_vendors = cursor.rowcount
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'deleted': deleted_vendors, 'message': f'Client "{name}" deleted'})



@app.route('/delete_driver', methods=['POST'])
def delete_driver():
    data = request.json
    name = data.get('name')
    password = data.get('password')
    
    if not name or not password:
        return jsonify({'error': 'name and password required'}), 400
    
    # Verify LMD group password
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT password_hash FROM section_groups WHERE group_name = ?', ('lmd_fmd',))
    result = cursor.fetchone()
    conn.close()
    
    if not result or result[0] != password:
        return jsonify({'error': 'Invalid LMD password (1008)'}), 403
    
    # Remove driver references from lmd_data and fmd_data
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE lmd_data SET driver_name = NULL WHERE driver_name = ?", (name,))
    cursor.execute("UPDATE fmd_data SET driver_name = NULL WHERE driver_name = ?", (name,))
    deleted_lmd = cursor.rowcount
    deleted_fmd = cursor.rowcount
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'message': f'Driver references removed: LMD={deleted_lmd}, FMD={deleted_fmd}'})

@app.route('/insert_driver', methods=['POST'])
def insert_driver():
    name = request.json.get('name')
    if not name or not name.strip():
        return jsonify({'error': 'Driver name required'}), 400
    # No dedicated table - just acknowledge (matches frontend expectation)
    return jsonify({'success': True, 'message': f'Driver \"{name.strip()}\" registered for LMD/FMD'})

@app.route('/delete_so_item', methods=['DELETE'])
def delete_so_item():
    id = request.json.get('id')
    if not id:
        return jsonify({'error': 'Item ID is required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM so_items WHERE id = ?', (id,))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/delete_so', methods=['DELETE'])
def delete_so():
    id = request.json.get('so_id')
    if not id:
        return jsonify({'error': 'SO ID is required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    # Delete so_items first (child records)
    cursor.execute('DELETE FROM so_items WHERE so_id = ?', (id,))
    # Delete the so record
    cursor.execute('DELETE FROM generated_sos WHERE id = ?', (id,))
    conn.commit()
    conn.close()
    return jsonify({'success': True})



@app.route('/delete_po', methods=['DELETE'])
def delete_po():
    po_number = request.args.get('po_number')

    if not po_number:
        return jsonify({'error': 'PO Number is required'}), 400

    conn = get_db()
    try:
        cursor = conn.cursor()

        # First delete child records
        # cursor.execute(
        #     'DELETE FROM purchase_order_items WHERE po_number = ?',
        #     (po_number,)
        # )

        # Then delete main record
        cursor.execute(
            'DELETE FROM generated_pos WHERE po_number = ?',
            (po_number,)
        )

        conn.commit()

        return jsonify({
            'success': True,
            'message': 'PO Deleted Successfully'
        }), 200

    except Exception as e:
        conn.rollback()
        print("DELETE ERROR:", e)
        return jsonify({'error': str(e)}), 500

    finally:
        conn.close()

@app.route('/delete_item', methods=['DELETE'])
def delete_item():
    password = request.json.get('password')
    if not password:
        return jsonify({'error': 'Password required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT password_hash FROM section_groups WHERE group_name = ?', ('inventory',))
    result = cursor.fetchone()
    conn.close()
    if not result or result[0] != password:
        return jsonify({'error': 'Invalid inventory password'}), 403
    name = request.json['name']
    if not name:
        return jsonify({'error': 'Item name is required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM items WHERE name = ?', (name,))
    deleted = cursor.rowcount
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'deleted': deleted})


@app.route('/delete_purchase_vendor', methods=['DELETE'])
def delete_purchase_vendor():
    password = request.json.get('password')
    if not password:
        return jsonify({'error': 'Password required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT password_hash FROM section_groups WHERE group_name = ?', ('inventory',))
    result = cursor.fetchone()
    conn.close()
    if not result or result[0] != password:
        return jsonify({'error': 'Invalid inventory password'}), 403
    name = request.json['name']
    if not name:
        return jsonify({'error': 'Vendor name is required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM purchase_vendors WHERE name = ?', (name,))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

# @app.route('/delete_product_manager', methods=['DELETE'])
# def delete_product_manager():
#     data = request.json
#     name = data.get('name')
#     password = data.get('password')
    
#     if not name:
#         return jsonify({'error': 'Manager name required'}), 400
    
#     # Verify inventory group password (since affects PO)
#     conn = get_db()
#     cursor = conn.cursor()
#     cursor.execute('SELECT password_hash FROM section_groups WHERE group_name = ?', ('inventory',))
#     result = cursor.fetchone()
#     conn.close()
#     if not result or result[0] != password:
#         return jsonify({'error': 'Invalid inventory password'}), 403
    
#     conn = get_db()
#     cursor = conn.cursor()
#     cursor.execute('DELETE FROM product_managers WHERE name = ?', (name,))
#     conn.commit()
#     conn.close()
#     return jsonify({'success': True})

@app.route('/update_lmd_data', methods=['PUT'])
def update_lmd_data():
    row = request.json
    id = row['id']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        'UPDATE lmd_data SET client_name=?, po_number=?, vehicle_number=?, driver_name=?, client_location=?, vehicle_type=?, booking_person=?, km=?, price_per_km=?, extra_expenses=?, reason=?, total_amount=?, payment_status=?, mode_of_payment=?, amount_paid=?, amount_due=?, date=?, time=?, gate_number=? WHERE id=?',
        (
            row['client_name'],
            row['po_number'],
            row['vehicle_number'],
            row['driver_name'],
            row['client_location'],
            row['vehicle_type'],
            row['booking_person'],
            row['km'],
            row['price_per_km'],
            row['extra_expenses'],
            row['reason'],
            row['total_amount'],
            row['payment_status'],
            row['mode_of_payment'],
            row['amount_paid'],
            row['amount_due'],
            row['date'],
            row['time'],
            row.get('gate_number'),
            id,
        )
    )
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/update_fmd_data', methods=['PUT'])
def update_fmd_data():
    row = request.json
    id = row['id']
    conn = get_db()
    cursor = conn.cursor()

    gate_number = row.get('gate_number')
    gate_number_int = None
    if gate_number is not None and str(gate_number).strip() != '':
        try:
            gate_number_int = int(gate_number)
        except (TypeError, ValueError):
            gate_number_int = None

    cursor.execute(
        'UPDATE fmd_data SET vendor_name=?, vendor_location=?, vehicle_number=?, driver_name=?, po_number=?, items=?, vehicle_type=?, booking_person=?, km=?, price_per_km=?, extra_expenses=?, reason=?, total_amount=?, payment_status=?, mode_of_payment=?, amount_paid=?, amount_due=?, gate_number=?, date=?, time=? WHERE id=?',
        (
            row['vendor_name'],
            row['vendor_location'],
            row['vehicle_number'],
            row['driver_name'],
            row['po_number'],
            row['items'],
            row['vehicle_type'],
            row['booking_person'],
            row['km'],
            row['price_per_km'],
            row['extra_expenses'],
            row['reason'],
            row['total_amount'],
            row['payment_status'],
            row['mode_of_payment'],
            row['amount_paid'],
            row['amount_due'],
            gate_number_int,
            row['date'],
            row['time'],
            id,
        ),
    )
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/get_filtered_lmd_data', methods=['GET'])
def get_filtered_lmd_data():
    driver_name = request.args.get('driver_name')
    vehicle_number = request.args.get('vehicle_number')
    location = request.args.get('location')
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    payment_status = request.args.get('payment_status')
    where_clause = ''
    where_args = []
    if driver_name:
        where_clause += 'driver_name LIKE ?'
        where_args.append(f'%{driver_name}%')
    if vehicle_number:
        if where_clause: where_clause += ' AND '
        where_clause += 'vehicle_number LIKE ?'
        where_args.append(f'%{vehicle_number}%')
    if location:
        if where_clause: where_clause += ' AND '
        where_clause += 'client_location LIKE ?'
        where_args.append(f'%{location}%')
    if start_date:
        if where_clause: where_clause += ' AND '
        where_clause += 'date >= ?'
        where_args.append(start_date)
    if end_date:
        if where_clause: where_clause += ' AND '
        where_clause += 'date <= ?'
        where_args.append(end_date)
    if payment_status:
        if where_clause: where_clause += ' AND '
        where_clause += 'payment_status = ?'
        where_args.append(payment_status)
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    query = f'SELECT * FROM lmd_data {f"WHERE {where_clause}" if where_clause else ""} ORDER BY id DESC'
    cursor.execute(query, where_args)
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/get_filtered_fmd_data', methods=['GET'])
def get_filtered_fmd_data():
    driver_name = request.args.get('driver_name')
    vehicle_number = request.args.get('vehicle_number')
    location = request.args.get('location')
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    payment_status = request.args.get('payment_status')
    where_clause = ''
    where_args = []
    if driver_name:
        where_clause += 'driver_name LIKE ?'
        where_args.append(f'%{driver_name}%')
    if vehicle_number:
        if where_clause: where_clause += ' AND '
        where_clause += 'vehicle_number LIKE ?'
        where_args.append(f'%{vehicle_number}%')
    if location:
        if where_clause: where_clause += ' AND '
        where_clause += 'vendor_location LIKE ?'
        where_args.append(f'%{location}%')
    if start_date:
        if where_clause: where_clause += ' AND '
        where_clause += 'date >= ?'
        where_args.append(start_date)
    if end_date:
        if where_clause: where_clause += ' AND '
        where_clause += 'date <= ?'
        where_args.append(end_date)
    if payment_status:
        if where_clause: where_clause += ' AND '
        where_clause += 'payment_status = ?'
        where_args.append(payment_status)
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    query = f'SELECT * FROM fmd_data {f"WHERE {where_clause}" if where_clause else ""} ORDER BY id DESC'
    cursor.execute(query, where_args)
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/insert_item', methods=['POST'])
def insert_item():
    name = request.json['name']
    if not name.strip():
        return jsonify({'error': 'Name cannot be empty'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('INSERT OR IGNORE INTO items (name) VALUES (?)', (name.strip(),))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/insert_vendor', methods=['POST'])
def insert_vendor():
    name = request.json['name']
    location = request.json.get('location')
    km = request.json.get('km')
    if not name.strip():
        return jsonify({'error': 'Name cannot be empty'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('INSERT OR REPLACE INTO vendors (name, location, km) VALUES (?, ?, ?)', (name.strip(), location, km))
    cursor.execute('INSERT OR IGNORE INTO b_grade_clients (name) VALUES (?)', (name.strip(),))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/insert_purchase_vendor', methods=['POST'])
def insert_purchase_vendor():
    name = request.json['name']
    if not name.strip():
        return jsonify({'error': 'Name cannot be empty'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('INSERT OR IGNORE INTO purchase_vendors (name) VALUES (?)', (name.strip(),))
    conn.commit()
    conn.close()
    return jsonify({'success': True})


@app.route('/insert_b_grade_client', methods=['POST'])
def insert_b_grade_client():
    name = request.json['name']
    if not name.strip():
        return jsonify({'error': 'Name cannot be empty'}), 400

    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('INSERT OR IGNORE INTO b_grade_clients (name) VALUES (?)', (name.strip(),))
    conn.commit()
    conn.close()
    return jsonify({'success': True})


    
@app.route('/insert_packaging_vendor', methods=['POST'])
def insert_packaging_vendor():
    name = request.json['name']
    if not name.strip():
        return jsonify({'error': 'Name cannot be empty'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('INSERT OR IGNORE INTO packaging_vendors (name) VALUES (?)', (name.strip(),))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/insert_generated_po', methods=['POST'])
def insert_generated_po():
    row = request.json

    conn = get_db()
    cursor = conn.cursor()

    cursor.execute('''
        INSERT INTO generated_pos (
            product_manager,
            item_name,
            po_number,
            qty_ordered,
            rate,
            unit,
            vendor_name,
            vendor_id,
            advanced_payment,
            advanced_payment_date,
            expected_date,
            quality_specifications,
            note,
            date,
            time
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (
        row['product_manager'],
        row['item_name'],
        row['po_number'],
        row['qty_ordered'],
        row['rate'],
        row['unit'],
        row['vendor_name'],
        row.get('vendor_id'),
        row.get('advanced_payment'),
        row.get('advanced_payment_date'),
        row['expected_date'],
        row['quality_specifications'],
        row['note'],
        row['date'],
        row['time']
    ))

    conn.commit()

    inserted_id = cursor.lastrowid

    conn.close()

    return jsonify({'id': inserted_id})




@app.route('/get_latest_generated_pos', methods=['GET'])
def get_latest_generated_pos():
    limit = request.args.get('limit', 10, type=int)
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM generated_pos ORDER BY id DESC LIMIT ?', (limit,))
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/get_last_po_number', methods=['GET'])
def get_last_po_number():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT po_number FROM generated_pos ORDER BY id DESC LIMIT 1')
    result = cursor.fetchone()
    conn.close()
    return jsonify({'po_number': result[0] if result else None})

def _increment_po_number(last_po):
    """Atomic PO number increment: PO-001 -> PO-002"""
    if not last_po:
        return "PO-001"
    match = re.match(r'^(.*?)(\d+)$', last_po)
    if match:
        prefix = match.group(1)
        num = int(match.group(2))
        return f"{prefix}{num+1:03d}"
    return f"{last_po}1"

import re  # Add at top with other imports

@app.route('/generate_next_po', methods=['GET'])
def generate_next_po():
    """Atomic next PO generation - returns next number without reserving"""
    conn = get_db()
    try:
        conn.execute('BEGIN IMMEDIATE')  # Table lock
        cursor = conn.cursor()
        cursor.execute('SELECT po_number FROM generated_pos ORDER BY id DESC LIMIT 1')
        result = cursor.fetchone()
        next_po = _increment_po_number(result[0] if result else None)
        conn.commit()
        return jsonify({'po_number': next_po})
    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        conn.close()

@app.route('/get_all_po_numbers', methods=['GET'])
def get_all_po_numbers():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT DISTINCT po_number FROM generated_pos ORDER BY id DESC')
    results = [row[0] for row in cursor.fetchall() if row[0]]
    conn.close()
    return jsonify(results)

@app.route('/get_last_so_number', methods=['GET'])
def get_last_so_number():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT so_number FROM generated_sos ORDER BY id DESC LIMIT 1')
    result = cursor.fetchone()
    conn.close()
    return jsonify({'so_number': result[0] if result else None})

@app.route('/get_available_pos_for_purchase', methods=['GET'])
def get_available_pos_for_purchase():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    all_pos = cursor.execute('SELECT * FROM generated_pos').fetchall()
    used_pos = cursor.execute('SELECT po_number, item FROM purchases').fetchall()
    used_po_item_set = set(f"{row[0]}|{row[1]}" for row in used_pos)
    available_pos = [dict(po) for po in all_pos if f"{po['po_number']}|{po['item_name']}" not in used_po_item_set]
    conn.close()
    return jsonify(available_pos)

@app.route('/get_available_pos_for_packaging', methods=['GET'])
def get_available_pos_for_packaging():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    all_pos = cursor.execute('SELECT * FROM generated_pos').fetchall()
    used_pos = cursor.execute('SELECT po_number, item FROM packaging_materials').fetchall()
    used_po_item_set = set(f"{row[0]}|{row[1]}" for row in used_pos)
    available_pos = [dict(po) for po in all_pos if f"{po['po_number']}|{po['item_name']}" not in used_po_item_set]
    conn.close()
    return jsonify(available_pos)
    

@app.route('/get_items', methods=['GET'])
def get_items():
    conn = get_db()
    cursor = conn.cursor()
    # AdminDashboard items table expects `id` for delete/update.
    cursor.execute(
        'SELECT id, name FROM items ORDER BY name COLLATE NOCASE'
    )
    rows = cursor.fetchall()
    conn.close()
    # Return list of {id, name} objects.
    return jsonify([{'id': row[0], 'name': row[1]} for row in rows])


@app.route('/get_purchased_items', methods=['GET'])
def get_purchased_items():
    conn = get_db()
    cursor = conn.cursor()
    # cursor.execute('SELECT DISTINCT item FROM purchases ORDER BY item COLLATE NOCASE')
    cursor.execute("""SELECT DISTINCT item FROM purchases WHERE item IS NOT NULL AND TRIM(item) <> '' ORDER BY item COLLATE NOCASE""")
    results = [row[0] for row in cursor.fetchall()]
    conn.close()
    return jsonify(results)


@app.route('/get_vendors', methods=['GET'])
def get_vendors():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT name FROM vendors ORDER BY name COLLATE NOCASE')
    results = [row[0] for row in cursor.fetchall()]
    conn.close()
    return jsonify(results)

@app.route('/get_vendors_with_details', methods=['GET'])
def get_vendors_with_details():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM vendors ORDER BY name COLLATE NOCASE')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/get_purchase_vendors', methods=['GET'])
def get_purchase_vendors():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT id, name FROM purchase_vendors ORDER BY name COLLATE NOCASE')
    rows = cursor.fetchall()
    conn.close()
    return jsonify([{'id': r[0], 'name': r[1]} for r in rows])


@app.route('/get_packaging_vendors', methods=['GET'])
def get_packaging_vendors():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT name FROM packaging_vendors ORDER BY name COLLATE NOCASE')
    results = [row[0] for row in cursor.fetchall()]
    conn.close()
    return jsonify(results)

@app.route('/get_packaging_items', methods=['GET'])
def get_packaging_items():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT DISTINCT item FROM packaging_materials ORDER BY item COLLATE NOCASE')
    results = [row[0] for row in cursor.fetchall()]
    conn.close()
    return jsonify(results)

@app.route('/get_latest_packaging_materials', methods=['GET'])
def get_latest_packaging_materials():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    cursor.execute('''
        UPDATE packaging_materials 
        SET total_value = (rate * qty_accept)
        WHERE total_value IS NULL AND rate IS NOT NULL AND qty_accept IS NOT NULL
    ''')
    
    cursor.execute('''
        UPDATE packaging_materials 
        SET amount_due = (total_value - amount_paid)
        WHERE amount_due IS NULL AND total_value IS NOT NULL AND amount_paid IS NOT NULL
    ''')
    
    conn.commit()
    
    cursor.execute('SELECT * FROM packaging_materials ORDER BY id DESC LIMIT 5')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/get_next_packaging_tag_sequence', methods=['GET'])
def get_next_packaging_tag_sequence():
    vendor_prefix = request.args.get('vendor_prefix')
    day_part = request.args.get('day_part')
    if not vendor_prefix or not day_part:
        return jsonify({'error': 'vendor_prefix and day_part are required'}), 400
    if '-' in vendor_prefix:
        formatted_prefix = vendor_prefix.strip()
    else:
        vp = vendor_prefix.strip()
        if len(vp) == 6:
            formatted_prefix = f'{vp[:3]}-{vp[3:]}'
        else:
            formatted_prefix = vp
    conn = get_db()
    cursor = conn.cursor()
    pattern = f'{formatted_prefix}-{day_part}-%'
    cursor.execute('SELECT item_tag FROM packaging_materials WHERE item_tag LIKE ? ORDER BY id DESC', (pattern,))
    results = cursor.fetchall()
    conn.close()
    if not results:
        return jsonify({'sequence': 1})
    for row in results:
        tag = row[0]
        if not tag: continue
        parts = tag.split('-')
        try:
            last_num = int(parts[-1])
            return jsonify({'sequence': last_num + 1})
        except (ValueError, TypeError):
            continue
    return jsonify({'sequence': 1})

@app.route('/delete_packaging_vendor', methods=['DELETE'])
def delete_packaging_vendor():
    password = request.json.get('password')
    if not password:
        return jsonify({'error': 'Password required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT password_hash FROM section_groups WHERE group_name = ?', ('inventory',))
    result = cursor.fetchone()
    conn.close()
    if not result or result[0] != password:
        return jsonify({'error': 'Invalid inventory password'}), 403
    name = request.json['name']
    if not name:
        return jsonify({'error': 'Vendor name is required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM packaging_vendors WHERE name = ?', (name,))
    conn.commit()
    conn.close()
    return jsonify({'success': True})


@app.route('/get_b_grade_clients', methods=['GET'])
def get_b_grade_clients():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT id, name FROM b_grade_clients ORDER BY name COLLATE NOCASE')
    rows = cursor.fetchall()
    conn.close()
    return jsonify([{'id': r['id'], 'name': r['name']} for r in rows])


@app.route('/delete_multiple_entries', methods=['DELETE'])
def delete_multiple_entries():
    table_name = request.json['table_name']
    ids = request.json['ids']
    if not ids:
        return jsonify({'deleted': 0})
    conn = get_db()
    cursor = conn.cursor()
    placeholders = ','.join('?' * len(ids))
    cursor.execute(f'DELETE FROM {table_name} WHERE id IN ({placeholders})', ids)
    conn.commit()
    conn.close()
    return jsonify({'deleted': cursor.rowcount})

@app.route('/insert_lmd_data', methods=['POST'])
def insert_lmd_data():
    row = request.json

    conn = get_db()
    cursor = conn.cursor()

    cursor.execute("""
        INSERT INTO lmd_data (
            client_name,
            po_number,
            vehicle_number,
            driver_name,
            client_location,
            vehicle_type,
            booking_person,
            km,
            price_per_km,
            extra_expenses,
            reason,
            total_amount,
            payment_status,
            mode_of_payment,
            amount_paid,
            amount_due,
            date,
            time,
            ctrl_date,
            gate_number
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        row.get('client_name'),
        row.get('po_number'),
        row.get('vehicle_number'),
        row.get('driver_name'),
        row.get('client_location'),
        row.get('vehicle_type'),
        row.get('booking_person'),
        row.get('km'),
        row.get('price_per_km'),
        row.get('extra_expenses'),
        row.get('reason'),
        row.get('total_amount'),
        row.get('payment_status'),
        row.get('mode_of_payment'),
        row.get('amount_paid'),
        row.get('amount_due'),
        row.get('date'),
        row.get('time'),
        row.get('ctrl_date'),
        row.get('gate_number')
    ))

    conn.commit()
    last_id = cursor.lastrowid
    conn.close()

    return jsonify({'id': last_id})


@app.route('/insert_fmd_data', methods=['POST'])
def insert_fmd_data():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()

    # gate_number is OPTIONAL (frontend blank => null)
    gate_number = row.get('gate_number')
    gate_number_int = None
    if gate_number is not None and str(gate_number).strip() != '':
        try:
            gate_number_int = int(gate_number)
        except (TypeError, ValueError):
            gate_number_int = None

    cursor.execute(
        'INSERT INTO fmd_data (vendor_name, vendor_location, vehicle_number, driver_name, po_number, items, vehicle_type, booking_person, km, price_per_km, extra_expenses, reason, total_amount, payment_status, mode_of_payment, amount_paid, amount_due, gate_number, date, time, ctrl_date) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        (
            row['vendor_name'],
            row['vendor_location'],
            row['vehicle_number'],
            row['driver_name'],
            row['po_number'],
            row['items'],
            row['vehicle_type'],
            row['booking_person'],
            row['km'],
            row['price_per_km'],
            row['extra_expenses'],
            row['reason'],
            row['total_amount'],
            row['payment_status'],
            row['mode_of_payment'],
            row['amount_paid'],
            row['amount_due'],
            gate_number_int,
            row['date'],
            row['time'],
            row.get('ctrl_date'),
        )
    )


    # DEBUG: ensure placeholders count equals provided params
    # (helps catch "X values for Y columns" quickly)
    conn.commit()
    conn.close()
    return jsonify({'id': cursor.lastrowid})

@app.route('/get_all_lmd_data', methods=['GET'])
def get_all_lmd_data():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('limit', 20, type=int)
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    search = request.args.get('search')
    
    result = _get_paginated_data('lmd_data', page, per_page, start_date, end_date, search)
    return jsonify(result)

@app.route('/get_latest_lmd_data', methods=['GET'])
def get_latest_lmd_data():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM lmd_data ORDER BY id DESC LIMIT 10')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/get_all_fmd_data', methods=['GET'])
def get_all_fmd_data():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Ensure gate_number exists even for old rows that were inserted before migration
    cursor.execute(
        'SELECT * FROM fmd_data ORDER BY id DESC'
    )
    rows = cursor.fetchall()
    conn.close()

    results = [dict(row) for row in rows]

    # Safety: if gate_number column is missing in older db, add it as null in response
    if results and 'gate_number' not in results[0]:
        for r in results:
            r['gate_number'] = None
    return jsonify(results)

@app.route('/get_latest_fmd_data', methods=['GET'])
def get_latest_fmd_data():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM fmd_data ORDER BY id DESC LIMIT 10')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/get_all_purchases', methods=['GET'])
def get_all_purchases():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('limit', 20, type=int)
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    search = request.args.get('search')
    result = _get_paginated_data('purchases', page, per_page, start_date, end_date, search)
    return jsonify(result)

@app.route('/get_all_packaging_materials', methods=['GET'])
def get_all_packaging_materials():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('limit', 20, type=int)
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    search = request.args.get('search')
    result = _get_paginated_data('packaging_materials', page, per_page, start_date, end_date, search)
    return jsonify(result)


@app.route('/get_latest_purchases', methods=['GET'])
def get_latest_purchases():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    cursor.execute('''
        UPDATE purchases
        SET amount_due = (amount_of_accepted - amount_paid)
        WHERE amount_due IS NULL
          AND amount_of_accepted IS NOT NULL
          AND amount_paid IS NOT NULL
    ''')

    conn.commit()

    cursor.execute(
        'SELECT * FROM purchases ORDER BY id DESC LIMIT 5'
    )

    rows = cursor.fetchall()
    conn.close()

    results = [dict(row) for row in rows]

    return jsonify(results)





@app.route('/get_all_stock_updates', methods=['GET'])
def get_all_stock_updates():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('limit', 20, type=int)
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    search = request.args.get('search')
    
    result = _get_paginated_data('stock_updates', page, per_page, start_date, end_date, search)
    return jsonify(result)



@app.route('/get_all_b_grade_sales', methods=['GET'])
def get_all_b_grade_sales():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('limit', 20, type=int)
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    search = request.args.get('search')
    
    result = _get_paginated_data('b_grade_sales', page, per_page, start_date, end_date, search
    )
    
    return jsonify(result)


@app.route('/get_all_sales', methods=['GET'])
def get_all_sales():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('limit', 20, type=int)
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    search = request.args.get('search')
    
    result = _get_paginated_data('sales', page, per_page, start_date, end_date, search)
    return jsonify(result)


@app.route('/get_sales_for_date', methods=['GET'])
def get_sales_for_date():
    date = request.args.get('date')
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('limit', 1000, type=int)  # Increased default
    search = request.args.get('search')
    if not date:
        return jsonify({'error': 'date parameter required (yyyy-MM-dd)'}), 400
    result = _get_paginated_data(
        'sales',
        page=page,
        per_page=per_page,
        start_date=date,
        end_date=date,
        search=search
    )
    return jsonify(result)

@app.route('/get_sales_for_date_all', methods=['GET'])
def get_sales_for_date_all():
    date = request.args.get('date')
    if not date:
        return jsonify({'error': 'date parameter required (yyyy-MM-dd)'}), 400
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM sales WHERE date = ? ORDER BY id DESC', (date,))
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify({'data': results, 'total': len(results), 'has_more': False})


@app.route('/get_waitlisted_sales', methods=['GET'])
def get_waitlisted_sales():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM sales_waitlist ORDER BY id DESC LIMIT 10')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/get_latest_sales', methods=['GET'])
def get_latest_sales():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM sales ORDER BY id DESC LIMIT 10')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

def safe_float(val):
    if val is None:
        return 0.0
    try:
        return float(val)
    except (ValueError, TypeError):
        return 0.0

@app.route('/insert_sale', methods=['POST'])
def insert_sale():
    row = request.json
    so_number = row.get('po_number')  # SO number used as po_number
    item_name = row.get('item')
    sale_qty = safe_float(row.get('quantity', 0))
    
    conn = get_db()
    cursor = conn.cursor()
    
    try:
        # Calculate numeric fields safely
        amount_paid = safe_float(row.get('amount_paid'))
        amount_due = safe_float(row.get('amount_due'))
        rate = safe_float(row.get('rate'))
        total_value = safe_float(row.get('total_value'))
        quantity = safe_float(row.get('quantity'))
        pcs = safe_float(row.get('pcs'))
        
        # 1. Insert sale record
        query = '''INSERT INTO sales
                   (item, clint, po_number, quantity, unit, pcs, date, time, item_tag, payment_status, mode_of_payment, amount_paid, amount_due, rate, total_value)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'''
        params = (
            row.get('item'),
            row.get('clint'),
            row.get('po_number'),
            quantity,
            row.get('unit'),
            pcs,
            row.get('date'),
            row.get('time'),
            row.get('item_tag'),
            row.get('payment_status', 'Unpaid'),
            row.get('mode_of_payment'),
            amount_paid,
            amount_due,
            rate,
            total_value
        )
        cursor.execute(query, params)
        sale_id = cursor.lastrowid
        
        so_updated = False
        # 2. Update SO item dispatched quantities (optional - only if SO data present)
        if so_number and item_name and sale_qty > 0:
            try:
                # Find matching SO item
                cursor.execute('''
                    SELECT item.id FROM so_items item 
                    JOIN generated_sos so ON item.so_id = so.id 
                    WHERE so.so_number = ? AND item.item_name = ? AND item.dispatch_status = 'pending'
                    LIMIT 1
                ''', (so_number, item_name))
                so_item_row = cursor.fetchone()
                
                if so_item_row:
                    so_item_id = so_item_row[0]
                    cursor.execute('''
                        UPDATE so_items 
                        SET dispatched_qty_kg = dispatched_qty_kg + ?,
                            dispatched_qty_pcs = COALESCE(dispatched_qty_pcs, 0) + ?,
                            dispatch_status = CASE 
                                WHEN quantity_kg <= dispatched_qty_kg + ? AND quantity_pcs <= COALESCE(dispatched_qty_pcs, 0) + ?
                                THEN 'completed' ELSE 'pending' END
                        WHERE id = ?
                    ''', (sale_qty, pcs, sale_qty, pcs, so_item_id))
                    so_updated = True
            except Exception as so_error:
                print(f"SO update failed (non-critical): {so_error}")
        
        conn.commit()
        return jsonify({'id': sale_id, 'so_updated': so_updated})
        
    except Exception as e:
        conn.rollback()
        print(f"Insert sale error: {e}")
        return jsonify({'error': str(e)}), 500
    finally:
        conn.close()

@app.route('/update_so_item_dispatch', methods=['POST'])
def update_so_item_dispatch():
    """Manual dispatch update for edge cases"""
    data = request.json
    so_item_id = data['so_item_id']
    qty_kg = data.get('qty_kg', 0)
    qty_pcs = data.get('qty_pcs', 0)
    
    conn = get_db()
    cursor = conn.cursor()
    
    try:
        cursor.execute('''
            UPDATE so_items 
            SET dispatched_qty_kg = dispatched_qty_kg + ?,
                dispatched_qty_pcs = COALESCE(dispatched_qty_pcs, 0) + ?,
                dispatch_status = CASE 
                    WHEN quantity_kg <= dispatched_qty_kg + ? AND quantity_pcs <= COALESCE(dispatched_qty_pcs, 0) + ?
                    THEN 'completed' ELSE 'pending' END
            WHERE id = ? AND dispatch_status = 'pending'
        ''', (qty_kg, qty_pcs, qty_kg, qty_pcs, so_item_id))
        
        updated = cursor.rowcount
        conn.commit()
        return jsonify({'updated': updated > 0})
        
    except Exception as e:
        conn.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        conn.close()

@app.route('/insert_sale_to_waitlist', methods=['POST'])
def insert_sale_to_waitlist():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('INSERT INTO sales_waitlist (item, clint, po_number, quantity, unit, pcs, item_tag) VALUES (?, ?, ?, ?, ?, ?, ?)', (row.get('item'), row.get('clint'), row.get('po_number'), row.get('quantity'), row.get('unit'), row.get('pcs'), row.get('item_tag')))
    conn.commit()
    conn.close()
    return jsonify({'id': cursor.lastrowid})

@app.route('/get_purchased_tags_for_item', methods=['GET'])
def get_purchased_tags_for_item():
    item_name = request.args.get('item_name')
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT DISTINCT item_tag FROM purchases WHERE item = ? AND item_tag IS NOT NULL ORDER BY item_tag', (item_name,))
    results = [row[0] for row in cursor.fetchall()]
    conn.close()
    return jsonify(results)

@app.route('/delete_waitlisted_sale', methods=['DELETE'])
def delete_waitlisted_sale():
    id = request.json['id']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM sales_waitlist WHERE id = ?', (id,))
    conn.commit()
    conn.close()
    return jsonify({'success': True})


@app.route('/get_all_rejection_received', methods=['GET'])
def get_all_rejection_received():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('limit', 20, type=int)
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    search = request.args.get('search')

    result = _get_paginated_data(
        'rejection_received',
        page,
        per_page,
        start_date,
        end_date,
        search
    )

    return jsonify(result)


@app.route('/get_latest_rejection_received', methods=['GET'])
def get_latest_rejection_received():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM rejection_received ORDER BY id DESC LIMIT 10')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/insert_rejection_received', methods=['POST'])
def insert_rejection_received():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('INSERT INTO rejection_received (client_name, item, po_number, item_tag, quantity, unit, pcs, sample_quantity, reason, date, time, ctrl_date) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', (row.get('client_name'), row.get('item'), row.get('po_number'), row.get('item_tag'), row.get('quantity'), row.get('unit'), row.get('pcs'), row.get('sample_quantity'), row.get('reason'), row.get('date'), row.get('time'), row.get('ctrl_date')))
    conn.commit()
    conn.close()
    return jsonify({'id': cursor.lastrowid})


@app.route('/get_all_vendor_rejections', methods=['GET'])
def get_all_vendor_rejections():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('limit', 20, type=int)
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    search = request.args.get('search')

    result = _get_paginated_data(
        'vendor_rejections',
        page,
        per_page,
        start_date,
        end_date,
        search
    )

    return jsonify(result)


@app.route('/get_latest_vendor_rejections', methods=['GET'])
def get_latest_vendor_rejections():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM vendor_rejections ORDER BY id DESC LIMIT 10')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/insert_vendor_rejection', methods=['POST'])
def insert_vendor_rejection():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()

    # ctrl_date is coming from frontend (vendor_rejection.dart)
    cursor.execute(
        'INSERT INTO vendor_rejections (item, vendor, po_number, quantity_sent, unit, pcs, date, time, ctrl_date) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        (
            row.get('item'),
            row.get('vendor'),
            row.get('po_number'),
            row.get('quantity_sent'),
            row.get('unit'),
            row.get('pcs'),
            row.get('date'),
            row.get('time'),
            row.get('ctrl_date'),
        ),
    )

    conn.commit()
    conn.close()
    return jsonify({'id': cursor.lastrowid})


@app.route('/get_all_dump_sales', methods=['GET'])
def get_all_dump_sales():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('limit', 20, type=int)
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    search = request.args.get('search')

    result = _get_paginated_data(
        'dump_sales',
        page,
        per_page,
        start_date,
        end_date,
        search
    )

    return jsonify(result)

@app.route('/get_latest_dump_sales', methods=['GET'])
def get_latest_dump_sales():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM dump_sales ORDER BY id DESC LIMIT 10')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/insert_dump_sale', methods=['POST'])
def insert_dump_sale():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('INSERT INTO dump_sales (item, quantity, unit, pcs, item_tag, date, time) VALUES (?, ?, ?, ?, ?, ?, ?)', (row.get('item'), row.get('quantity'), row.get('unit'), row.get('pcs'), row.get('item_tag'), row.get('date'), row.get('time')))
    conn.commit()
    conn.close()
    return jsonify({'id': cursor.lastrowid})


@app.route('/get_all_mandi_resales', methods=['GET'])
def get_all_mandi_resales():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('limit', 20, type=int)
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    search = request.args.get('search')

    result = _get_paginated_data(
        'mandi_resales',
        page,
        per_page,
        start_date,
        end_date,
        search
    )

    return jsonify(result)


@app.route('/insert_mandi_resale', methods=['POST'])
def insert_mandi_resale():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('INSERT INTO mandi_resales (item, quantity, unit, pcs, item_tag, date, time) VALUES (?, ?, ?, ?, ?, ?, ?)', (row.get('item'), row.get('quantity'), row.get('unit'), row.get('pcs'), row.get('item_tag'), row.get('date'), row.get('time')))
    conn.commit()
    conn.close()
    return jsonify({'id': cursor.lastrowid})

@app.route('/get_latest_mandi_resales', methods=['GET'])
def get_latest_mandi_resales():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM mandi_resales ORDER BY id DESC LIMIT 5')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/get_latest_stock_updates', methods=['GET'])
def get_latest_stock_updates():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM stock_updates ORDER BY id DESC LIMIT 5')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/get_po_number_by_tag', methods=['GET'])
def get_po_number_by_tag():
    item_name = request.args.get('item_name')
    tag = request.args.get('tag')
    if not item_name or not tag:
        return jsonify({'error': 'item_name and tag are required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT po_number FROM purchases WHERE item = ? AND item_tag = ? ORDER BY id DESC LIMIT 1', (item_name, tag))
    result = cursor.fetchone()
    conn.close()
    if result:
        return jsonify({'po_number': result[0]})
    else:
        return jsonify({'po_number': None})

# @app.route('/insert_stock_update', methods=['POST'])
# def insert_stock_update():
#     row = request.json
#     conn = get_db()
#     cursor = conn.cursor()
#     cursor.execute('INSERT INTO stock_updates (item, a_grade_qty, a_grade_unit, pcs_a_grade, b_grade_qty, b_grade_unit, pcs_b_grade, c_grade_qty, c_grade_unit, pcs_c_grade, ungraded_qty, ungraded_unit, pcs_ungraded, dump_qty, dump_unit, pcs_dump, total_qty, date, time, po_number, a_grade_tags, b_grade_tags, c_grade_tags, ungraded_tags, dump_tags) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', (row.get('item'), row.get('a_grade_qty'), row.get('a_grade_unit'), row.get('pcs_a_grade'), row.get('b_grade_qty'), row.get('b_grade_unit'), row.get('pcs_b_grade'), row.get('c_grade_qty'), row.get('c_grade_unit'), row.get('pcs_c_grade'), row.get('ungraded_qty'), row.get('ungraded_unit'), row.get('pcs_ungraded'), row.get('dump_qty'), row.get('dump_unit'), row.get('pcs_dump'), row.get('total_qty'), row.get('date'), row.get('time'), row.get('po_number'), row.get('a_grade_tags'), row.get('b_grade_tags'), row.get('c_grade_tags'), row.get('ungraded_tags'), row.get('dump_tags')))
#     conn.commit()
#     conn.close()
#     return jsonify({'id': cursor.lastrowid})

@app.route('/insert_stock_update', methods=['POST'])
def insert_stock_update():

    row = request.json

    item = row.get("item")

    # Receive JSON strings from frontend
    a_tags_json = row.get("a_grade_tags", "[]")
    b_tags_json = row.get("b_grade_tags", "[]")
    c_tags_json = row.get("c_grade_tags", "[]")
    ungraded_tags_json = row.get("ungraded_tags", "[]")
    dump_tags_json = row.get("dump_tags", "[]")

    # Convert JSON strings to lists for calculation
    a_tags = json.loads(a_tags_json)
    b_tags = json.loads(b_tags_json)
    c_tags = json.loads(c_tags_json)
    ungraded_tags = json.loads(ungraded_tags_json)
    dump_tags = json.loads(dump_tags_json)

    def calculate(tags):
        qty = 0.0
        pcs = 0.0
        po_numbers = set()

        for tag in tags:
            try:
                qty += float(tag.get("qty", 0) or 0)
            except:
                pass

            try:
                pcs += float(tag.get("pcs", 0) or 0)
            except:
                pass

            po = str(tag.get("po", "")).strip()
            if po:
                po_numbers.add(po)

        return qty, pcs, po_numbers

    qtyA, pcsA, poA = calculate(a_tags)
    qtyB, pcsB, poB = calculate(b_tags)
    qtyC, pcsC, poC = calculate(c_tags)
    qtyU, pcsU, poU = calculate(ungraded_tags)
    qtyD, pcsD, poD = calculate(dump_tags)

    total_qty = qtyA + qtyB + qtyC + qtyU + qtyD

    po_number = ", ".join(sorted(poA | poB | poC | poU | poD))

    now = datetime.now()
    date = now.strftime("%Y-%m-%d")
    time = now.strftime("%I:%M %p")

    conn = get_db()
    cursor = conn.cursor()

    cursor.execute("""
        INSERT INTO stock_updates (
            item,
            a_grade_qty,
            a_grade_unit,
            pcs_a_grade,
            b_grade_qty,
            b_grade_unit,
            pcs_b_grade,
            c_grade_qty,
            c_grade_unit,
            pcs_c_grade,
            ungraded_qty,
            ungraded_unit,
            pcs_ungraded,
            dump_qty,
            dump_unit,
            pcs_dump,
            total_qty,
            date,
            time,
            po_number,
            a_grade_tags,
            b_grade_tags,
            c_grade_tags,
            ungraded_tags,
            dump_tags
        )
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    """, (
        item,

        qtyA, "Kg", pcsA,
        qtyB, "Kg", pcsB,
        qtyC, "Kg", pcsC,
        qtyU, "Kg", pcsU,
        qtyD, "Kg", pcsD,

        total_qty,
        date,
        time,
        po_number,

        # Original JSON strings
        a_tags_json,
        b_tags_json,
        c_tags_json,
        ungraded_tags_json,
        dump_tags_json
    ))

    conn.commit()
    stock_id = cursor.lastrowid
    conn.close()

    return jsonify({
        "success": True,
        "id": stock_id
    })




@app.route('/get_single_value', methods=['GET'])
def get_single_value():
    table = request.args.get('table')
    column = request.args.get('column')
    where = request.args.get('where')
    # Parse where_args from where_args[0], where_args[1], etc.
    where_args = []
    i = 0
    while f'where_args[{i}]' in request.args:
        where_args.append(request.args.get(f'where_args[{i}]'))
        i += 1
    conn = get_db()
    cursor = conn.cursor()
    query = f'SELECT SUM({column}) as total FROM {table}'
    if where:
        query += f' WHERE {where}'
    cursor.execute(query, where_args)
    result = cursor.fetchone()
    conn.close()
    return jsonify({'total': result[0] if result and result[0] else 0.0})

@app.route('/get_stock_update_total_for_date', methods=['GET'])
def get_stock_update_total_for_date():
    item = request.args.get('item')
    chosen_date = request.args.get('chosen_date')
    if not item or not chosen_date:
        return jsonify({'error': 'item and chosen_date are required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT SUM(a_grade_qty + b_grade_qty + c_grade_qty + ungraded_qty + dump_qty) as total FROM stock_updates WHERE item = ? AND date = ?', (item, chosen_date))
    result = cursor.fetchone()
    conn.close()
    return jsonify({'total': result[0] if result and result[0] else 0.0})


@app.route('/get_admin_report_rows', methods=['GET'])
def get_admin_report_rows():
    """Single backend route that returns the AdminReport DataTable row for (item, chosen_date).

    Query params:
      - item: item name
      - chosen_date: yyyy-MM-dd
    """
    item = request.args.get('item')
    chosen_date = request.args.get('chosen_date')

    if not item or not chosen_date:
        return jsonify({'error': 'item and chosen_date are required'}), 400

    # previousDate for stock_today (chosen_date - 1 day)
    # SQLite query will just use previousDate string.
    import datetime as _dt
    try:
        chosen_dt = _dt.datetime.strptime(chosen_date, '%Y-%m-%d').date()
        previous_date = (chosen_dt - _dt.timedelta(days=1)).strftime('%Y-%m-%d')
    except Exception:
        return jsonify({'error': 'chosen_date must be yyyy-MM-dd'}), 400

    conn = get_db()
    cursor = conn.cursor()

    def _sum(query, args):
        cursor.execute(query, args)
        row = cursor.fetchone()
        if not row or row[0] is None:
            return 0.0
        try:
            return float(row[0])
        except Exception:
            return 0.0

    purchase_received = _sum(
        'SELECT SUM(qty_receive) FROM purchases WHERE item = ? AND ctrl_date = ?',
        (item, chosen_date),
    )

    rejection_received = _sum(
        'SELECT SUM(quantity) FROM rejection_received WHERE item = ? AND ctrl_date = ?',
        (item, chosen_date),
    )

    vendor_rejection = _sum(
        'SELECT SUM(quantity_sent) FROM vendor_rejections WHERE item = ? AND date = ?',
        (item, chosen_date),
    )

    sales_qty = _sum(
        'SELECT SUM(quantity) FROM sales WHERE item = ? AND date = ?',
        (item, chosen_date),
    )

    dump_sale_qty = _sum(
        'SELECT SUM(quantity) FROM dump_sales WHERE item = ? AND date = ?',
        (item, chosen_date),
    )

    mandi_resale_qty = _sum(
        'SELECT SUM(quantity) FROM mandi_resales WHERE item = ? AND date = ?',
        (item, chosen_date),
    )

    b_grade_sales_qty = _sum(
        'SELECT SUM(quantity) FROM b_grade_sales WHERE item = ? AND date = ?',
        (item, chosen_date),
    )

    stock_next_day = _sum(
        'SELECT SUM(a_grade_qty + b_grade_qty + c_grade_qty + ungraded_qty + dump_qty) FROM stock_updates WHERE item = ? AND date = ?',
        (item, chosen_date),
    )

    stock_today = _sum(
        'SELECT SUM(a_grade_qty + b_grade_qty + c_grade_qty + ungraded_qty + dump_qty) FROM stock_updates WHERE item = ? AND date = ?',
        (item, previous_date),
    )

    total_quantity = stock_today + purchase_received + rejection_received - vendor_rejection
    total_sales = sales_qty + dump_sale_qty + mandi_resale_qty + b_grade_sales_qty
    check_stock = total_quantity - total_sales - stock_next_day

    rows = [
        {
            'date': chosen_date,
            'iteam': item,  # NOTE: frontend uses this key (typo retained)
            'stock_today': stock_today,
            'stock_next_day': stock_next_day,
            'purchase_received': purchase_received,
            'rejection_received': rejection_received,
            'vendor_rejection': vendor_rejection,
            'sales': sales_qty,
            'dump_sale': dump_sale_qty,
            'mandi_resale': mandi_resale_qty,
            'b_grade_sales': b_grade_sales_qty,
            'total_quantity': total_quantity,
            'total_sales': total_sales,
            'check_stock': check_stock,
        }
    ]

    conn.close()
    return jsonify({'data': rows})


@app.route('/insert_purchase', methods=['POST'])
def insert_purchase():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()

    def safe_float(val):
        if val is None:
            return 0.0
        try:
            return float(val)
        except (ValueError, TypeError):
            return 0.0

    # amount_of_accepted = safe_float(row.get('amount_of_accepted'))

    # rate = safe_float(row.get('rate'))
    # qty_accept = safe_float(row.get('qty_accept'))

    # amount_of_accepted = rate * qty_accept

    amount_paid = safe_float(row.get('amount_paid'))

    # low_grade_qty = safe_float(row.get('low_grade_qty'))
    # low_grade_rate = safe_float(row.get('low_grade_rate'))
    # total_low_grade_amount = low_grade_qty * low_grade_rate

    # # Total Amount
    # total_amount = amount_of_accepted + total_low_grade_amount


    rate = safe_float(row.get('rate'))
    qty_accept = safe_float(row.get('qty_accept'))

    amount_of_accepted = rate * qty_accept

    low_grade_qty = safe_float(row.get('low_grade_qty'))
    low_grade_rate = safe_float(row.get('low_grade_rate'))

    total_low_grade_amount = low_grade_qty * low_grade_rate

    total_amount = amount_of_accepted + total_low_grade_amount





    # Get Advanced Payment from generated_pos table
    po_number = row.get('po_number')

    cursor.execute("""
        SELECT advanced_payment
        FROM generated_pos
        WHERE po_number = ?
        LIMIT 1
    """, (po_number,))

    result = cursor.fetchone()

    advanced_payment = 0.0
    if result and result[0]:
        advanced_payment = safe_float(result[0])

    # Amount Due Formula
    amount_due = total_amount - amount_paid - advanced_payment

    print("Received Data:", row)
    print("PO Number:", po_number)
    print("Amount of Accepted:", amount_of_accepted)
    print("Low Grade Amount:", total_low_grade_amount)
    print("Total Amount:", total_amount)
    print("Advanced Payment:", advanced_payment)
    print("Amount Paid:", amount_paid)
    print("Amount Due:", amount_due)

    cursor.execute('''
        INSERT INTO purchases (
            item,
            vendor,
            po_number,
            qty_receive,
            unit_receive,
            pcs_receive,
            qty_accept,
            unit_accept,
            pcs_accept,
            qty_reject,
            unit_reject,
            pcs_reject,
            reason_for_rejection,
            date,
            time,
            ctrl_date,
            item_tag,
            payment_status,
            mode_of_payment,
            amount_paid,
            amount_due,
            rate,
            amount_of_accepted,
            low_grade_qty,
            low_grade_rate,
            total_low_grade_amount,
            total_amount
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
        )
    ''', (
        row.get('item'),
        row.get('vendor'),
        row.get('po_number'),
        row.get('qty_receive'),
        row.get('unit_receive'),
        row.get('pcs_receive'),
        row.get('qty_accept'),
        row.get('unit_accept'),
        row.get('pcs_accept'),
        row.get('qty_reject'),
        row.get('unit_reject'),
        row.get('pcs_reject'),
        row.get('reason_for_rejection'),
        row.get('date'),
        row.get('time'),
        row.get('ctrl_date'),
        row.get('item_tag'),
        row.get('payment_status', 'Unpaid'),
        row.get('mode_of_payment'),
        amount_paid,
        amount_due,
        # row.get('rate', 0.0),
        rate,
        amount_of_accepted,
        low_grade_qty,
        low_grade_rate,
        total_low_grade_amount,
        total_amount,
    ))

    purchase_id = cursor.lastrowid

    conn.commit()
    conn.close()

    return jsonify({
        'id': purchase_id,
        'total_amount': total_amount,
        'advanced_payment': advanced_payment,
        'amount_due': amount_due
    })






    
@app.route('/insert_packaging_material', methods=['POST'])
def insert_packaging_material():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()
    def safe_float(val):
        if val is None:
            return 0.0
        try:
            return float(val)
        except (ValueError, TypeError):
            return 0.0
    
    total_value = safe_float(row.get('total_value'))
    amount_paid = safe_float(row.get('amount_paid'))
    amount_due = total_value - amount_paid
    cursor.execute('INSERT INTO packaging_materials (item, vendor, po_number, qty_receive, unit_receive, pcs_receive, qty_accept, unit_accept, pcs_accept, qty_reject, unit_reject, pcs_reject, reason_for_rejection, date, time, ctrl_date, item_tag, payment_status, mode_of_payment, amount_paid, amount_due, rate, total_value) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', (row.get('item'), row.get('vendor'), row.get('po_number'), row.get('qty_receive'), row.get('unit_receive'), row.get('pcs_receive'), row.get('qty_accept'), row.get('unit_accept'), row.get('pcs_accept'), row.get('qty_reject'), row.get('unit_reject'), row.get('pcs_reject'), row.get('reason_for_rejection'), row.get('date'), row.get('time'), row.get('ctrl_date'), row.get('item_tag'), row.get('payment_status', 'Unpaid'), row.get('mode_of_payment'), amount_paid, amount_due, row.get('rate', 0.0), total_value))
    conn.commit()
    conn.close()
    return jsonify({'id': cursor.lastrowid})


@app.route('/update_purchase', methods=['PUT'])
def update_purchase():
    payload = request.get_json(silent=True) or {}

    # Frontend may send {"data": {...}} or {...}
    data = payload.get('data') if isinstance(payload, dict) and 'data' in payload else payload

    if not isinstance(data, dict):
        return jsonify({'success': False, 'error': 'Invalid payload'}), 400

    record_id = data.get('id')
    if record_id is None:
        return jsonify({'success': False, 'error': 'id is required'}), 400

    def safe_float(val):
        if val is None or val == '':
            return 0.0
        try:
            return float(val)
        except (ValueError, TypeError):
            return 0.0

    # ==========================
    # Calculations
    # ==========================

    rate = safe_float(data.get('rate'))
    qty_accept = safe_float(data.get('qty_accept'))

    amount_of_accepted = rate * qty_accept

    amount_paid = safe_float(data.get('amount_paid'))

    low_grade_qty = safe_float(data.get('low_grade_qty'))
    low_grade_rate = safe_float(data.get('low_grade_rate'))

    total_low_grade_amount = low_grade_qty * low_grade_rate

    total_amount = amount_of_accepted + total_low_grade_amount

    conn = get_db()
    cursor = conn.cursor()

    # ==========================
    # Get Advanced Payment
    # ==========================

    po_number = data.get('po_number')

    cursor.execute("""
        SELECT advanced_payment
        FROM generated_pos
        WHERE po_number = ?
        LIMIT 1
    """, (po_number,))

    result = cursor.fetchone()

    advanced_payment = 0.0
    if result and result[0]:
        advanced_payment = safe_float(result[0])

    # ==========================
    # Due Amount
    # ==========================

    amount_due = total_amount - amount_paid - advanced_payment

    print("Updated Data:", data)
    print("PO Number:", po_number)
    print("Rate:", rate)
    print("Accepted Qty:", qty_accept)
    print("Amount of Accepted:", amount_of_accepted)
    print("Low Grade Amount:", total_low_grade_amount)
    print("Total Amount:", total_amount)
    print("Advanced Payment:", advanced_payment)
    print("Amount Paid:", amount_paid)
    print("Amount Due:", amount_due)

    cursor.execute("""
        UPDATE purchases SET
            item=?,
            vendor=?,
            po_number=?,

            qty_receive=?,
            unit_receive=?,
            pcs_receive=?,

            qty_accept=?,
            unit_accept=?,
            pcs_accept=?,

            qty_reject=?,
            unit_reject=?,
            pcs_reject=?,

            reason_for_rejection=?,

            date=?,
            time=?,
            ctrl_date=?,

            item_tag=?,

            payment_status=?,
            mode_of_payment=?,

            amount_paid=?,
            amount_due=?,

            rate=?,
            amount_of_accepted=?,

            low_grade_qty=?,
            low_grade_rate=?,
            total_low_grade_amount=?,
            total_amount=?

        WHERE id=?
    """, (
        data.get('item'),
        data.get('vendor'),
        po_number,

        data.get('qty_receive'),
        data.get('unit_receive'),
        data.get('pcs_receive'),

        data.get('qty_accept'),
        data.get('unit_accept'),
        data.get('pcs_accept'),

        data.get('qty_reject'),
        data.get('unit_reject'),
        data.get('pcs_reject'),

        data.get('reason_for_rejection'),

        data.get('date'),
        data.get('time'),
        data.get('ctrl_date'),

        data.get('item_tag'),

        data.get('payment_status'),
        data.get('mode_of_payment'),

        amount_paid,
        amount_due,

        rate,
        amount_of_accepted,

        low_grade_qty,
        low_grade_rate,
        total_low_grade_amount,
        total_amount,

        record_id
    ))

    affected = cursor.rowcount

    conn.commit()
    conn.close()

    return jsonify({
        'success': True,
        'affected_rows': affected,
        'amount_of_accepted': amount_of_accepted,
        'total_low_grade_amount': total_low_grade_amount,
        'total_amount': total_amount,
        'advanced_payment': advanced_payment,
        'amount_due': amount_due
    })





@app.route('/update_packaging_material', methods=['PUT'])
def update_packaging_material():
    row = request.json
    id = row['id']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('UPDATE packaging_materials SET item=?, vendor=?, po_number=?, qty_receive=?, unit_receive=?, pcs_receive=?, qty_accept=?, unit_accept=?, pcs_accept=?, qty_reject=?, unit_reject=?, pcs_reject=?, reason_for_rejection=?, date=?, time=?, ctrl_date=?, item_tag=?, payment_status=?, mode_of_payment=?, amount_paid=?, amount_due=?, rate=?, total_value=? WHERE id=?', (row.get('item'), row.get('vendor'), row.get('po_number'), row.get('qty_receive'), row.get('unit_receive'), row.get('pcs_receive'), row.get('qty_accept'), row.get('unit_accept'), row.get('pcs_accept'), row.get('qty_reject'), row.get('unit_reject'), row.get('pcs_reject'), row.get('reason_for_rejection'), row.get('date'), row.get('time'), row.get('ctrl_date'), row.get('item_tag'), row.get('payment_status', 'Unpaid'), row.get('mode_of_payment'), row.get('amount_paid', 0.0), row.get('amount_due', 0.0), row.get('rate', 0.0), row.get('total_value', 0.0), id))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

# ... other update endpoints remain similar but use proper table mappings ...

@app.route('/get_next_item_tag_sequence', methods=['GET'])
def get_next_item_tag_sequence():
    vendor_prefix = request.args.get('vendor_prefix')
    day_part = request.args.get('day_part')

    if not vendor_prefix or not day_part:
        return jsonify({'error': 'vendor_prefix and day_part are required'}), 400

    # Support both old and new tag formats:
    # - Old: VVV-DDMMyy-0001
    # - New: VVV-III-DDMMyy-0001

    if '-' in vendor_prefix:
        formatted_prefix = vendor_prefix.strip()
    else:
        vp = vendor_prefix.strip()
        if len(vp) == 6:  # combined vendor(3)+item(3)
            formatted_prefix = f'{vp[:3]}-{vp[3:]}'
        else:
            formatted_prefix = vp

    conn = get_db()
    cursor = conn.cursor()

    pattern = f'{formatted_prefix}-{day_part}-%'
    cursor.execute(
        'SELECT item_tag FROM purchases WHERE item_tag LIKE ? ORDER BY id DESC',
        (pattern,)
    )

    results = cursor.fetchall()
    conn.close()

    if not results:
        return jsonify({'sequence': 1})

    for row in results:
        tag = row[0]
        if not tag:
            continue

        parts = tag.split('-')

        # Sequence is always last segment
        try:
            last_num = int(parts[-1])
            return jsonify({'sequence': last_num + 1})
        except (ValueError, TypeError):
            continue

    return jsonify({'sequence': 1})

    
@app.route('/update_stock_update', methods=['PUT'])
def update_stock_update():
    row = request.json
    id = row['id']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        UPDATE stock_updates SET 
            item=?, a_grade_qty=?, a_grade_unit=?, pcs_a_grade=?, 
            b_grade_qty=?, b_grade_unit=?, pcs_b_grade=?, 
            c_grade_qty=?, c_grade_unit=?, pcs_c_grade=?, 
            ungraded_qty=?, ungraded_unit=?, pcs_ungraded=?, 
            dump_qty=?, dump_unit=?, pcs_dump=?, 
            total_qty=?, date=?, time=?, po_number=?, 
            a_grade_tags=?, b_grade_tags=?, c_grade_tags=?, ungraded_tags=?, dump_tags=? 
        WHERE id=?
    ''', (
        row.get('item'), row.get('a_grade_qty'), row.get('a_grade_unit'), row.get('pcs_a_grade'),
        row.get('b_grade_qty'), row.get('b_grade_unit'), row.get('pcs_b_grade'),
        row.get('c_grade_qty'), row.get('c_grade_unit'), row.get('pcs_c_grade'),
        row.get('ungraded_qty'), row.get('ungraded_unit'), row.get('pcs_ungraded'),
        row.get('dump_qty'), row.get('dump_unit'), row.get('pcs_dump'),
        row.get('total_qty'), row.get('date'), row.get('time'), row.get('po_number'),
        row.get('a_grade_tags'), row.get('b_grade_tags'), row.get('c_grade_tags'), row.get('ungraded_tags'), row.get('dump_tags'),
        id
    ))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/update_b_grade_sale', methods=['PUT'])
def update_b_grade_sale():
    row = request.json
    id = row['id']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        UPDATE b_grade_sales SET 
            item=?, clint=?, quantity=?, rate=?, unit=?, total_value=?, 
            date=?, time=?, po_number=?, pcs=?, item_tag=?, 
            payment_status=?, mode_of_payment=?, amount_paid=?, amount_due=? 
        WHERE id=?
    ''', (
        row.get('item'), row.get('clint'), row.get('quantity'), row.get('rate'), row.get('unit'), row.get('total_value'),
        row.get('date'), row.get('time'), row.get('po_number'), row.get('pcs'), row.get('item_tag'),
        row.get('payment_status'), row.get('mode_of_payment'), row.get('amount_paid'), row.get('amount_due'),
        id
    ))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/update_sale', methods=['PUT'])
def update_sale():
    data = request.json['data']
    # id = data['id']
    affected = 0
    id = data['id']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        UPDATE sales SET 
            item=?, clint=?, po_number=?, quantity=?, unit=?, pcs=?, 
            date=?, time=?, item_tag=?, payment_status=?, mode_of_payment=?, 
            amount_paid=?, amount_due=?, rate=?, total_value=? 
        WHERE id=?
    ''', (
        data.get('item'), data.get('clint'), data.get('po_number'), data.get('quantity'), data.get('unit'), data.get('pcs'),
        data.get('date'), data.get('time'), data.get('item_tag'), data.get('payment_status'), data.get('mode_of_payment'),
        data.get('amount_paid'), data.get('amount_due'), data.get('rate'), data.get('total_value'),
        id
    ))
    affected = cursor.rowcount
    print(f"Updated {affected} rows in sales id={id}")
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/update_rejection_received', methods=['PUT'])
def update_rejection_received():
    row = request.json
    id = row['id']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        UPDATE rejection_received SET 
            client_name=?, item=?, po_number=?, item_tag=?, quantity=?, unit=?, pcs=?, 
            sample_quantity=?, reason=?, date=?, time=?, ctrl_date=? 
        WHERE id=?
    ''', (
        row.get('client_name'), row.get('item'), row.get('po_number'), row.get('item_tag'), row.get('quantity'), row.get('unit'), row.get('pcs'),
        row.get('sample_quantity'), row.get('reason'), row.get('date'), row.get('time'), row.get('ctrl_date'),
        id
    ))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/update_vendor_rejection', methods=['PUT'])
def update_vendor_rejection():
    row = request.json
    id = row['id']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        UPDATE vendor_rejections SET 
            item=?, vendor=?, po_number=?, quantity_sent=?, unit=?, pcs=?, date=?, time=? 
        WHERE id=?
    ''', (
        row.get('item'), row.get('vendor'), row.get('po_number'), row.get('quantity_sent'), row.get('unit'), row.get('pcs'),
        row.get('date'), row.get('time'),
        id
    ))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/update_dump_sale', methods=['PUT'])
def update_dump_sale():
    row = request.json
    id = row['id']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        UPDATE dump_sales SET 
            item=?, quantity=?, unit=?, pcs=?, item_tag=?, date=?, time=?, po_number=? 
        WHERE id=?
    ''', (
        row.get('item'), row.get('quantity'), row.get('unit'), row.get('pcs'), row.get('item_tag'),
        row.get('date'), row.get('time'), row.get('po_number'),
        id
    ))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/update_mandi_resale', methods=['PUT'])
def update_mandi_resale():
    row = request.json
    id = row['id']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        UPDATE mandi_resales SET 
            item=?, quantity=?, unit=?, pcs=?, item_tag=?, date=?, time=? 
        WHERE id=?
    ''', (
        row.get('item'), row.get('quantity'), row.get('unit'), row.get('pcs'), row.get('item_tag'),
        row.get('date'), row.get('time'),
        id
    ))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/update_so_item', methods=['PUT'])
def update_so_item():
    row = request.json
    id = row.get('id')
    if not id:
        return jsonify({'error': 'id is required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        UPDATE so_items SET 
            item_name=?, quantity_kg=?, quantity_pcs=? 
        WHERE id=?
    ''', (
        row.get('item_name'),
        row.get('quantity_kg'),
        row.get('quantity_pcs'),
        id
    ))
    conn.commit()
    conn.close()
    return jsonify({'success': True})


@app.route('/update_po_item', methods=['PUT'])
def update_po_item():
    row = request.json

    id = row.get('id')
    if not id:
        return jsonify({'error': 'id is required'}), 400

    conn = get_db()
    cursor = conn.cursor()

    cursor.execute('''
        UPDATE generated_pos SET
            product_manager=?,
            po_number=?,
            item_name=?,
            qty_ordered=?,
            unit=?,
            rate=?,
            vendor_id=?,
            vendor_name=?,
            advanced_payment=?,
            advanced_payment_date=?,
            expected_date=?,
            quality_specifications=?,
            note=?
        WHERE id=?
    ''', (
        row.get('product_manager'),
        row.get('po_number'),
        row.get('item_name'),
        row.get('qty_ordered'),
        row.get('unit'),
        row.get('rate'),

        # NEW FIELDS
        row.get('vendor_id'),
        row.get('vendor_name'),
        row.get('advanced_payment'),
        row.get('advanced_payment_date'),

        row.get('expected_date'),
        row.get('quality_specifications'),
        row.get('note'),

        id
    ))

    conn.commit()
    conn.close()

    return jsonify({'success': True})











@app.route('/update_so', methods=['PUT'])
def update_so():
    row = request.json
    # Support both 'id' and 'so_id'
    id = row.get('id') or row.get('so_id')
    if not id:
        return jsonify({'error': 'id or so_id is required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    # Update the generated_so record
    cursor.execute('''
        UPDATE generated_sos SET 
            client_name=?, so_number=?, date_of_dispatch=? 
        WHERE id=?
    ''', (
        row.get('client_name'), 
        row.get('so_number'), 
        row.get('date_of_dispatch'),
        id
    ))
    
    # Update the items if provided
    if 'items' in row and row['items']:
        # Delete existing items for this SO
        cursor.execute('DELETE FROM so_items WHERE so_id = ?', (id,))
        # Insert new items
        for item in row['items']:
            cursor.execute('''
                INSERT INTO so_items (so_id, item_name, quantity_kg, quantity_pcs) 
                VALUES (?, ?, ?, ?)
            ''', (id, item.get('item_name'), item.get('quantity_kg'), item.get('quantity_pcs')))
    
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/add_so_items', methods=['POST'])
def add_so_items():
    data = request.json
    so_id = data['so_id']
    items_data = data['items_data']
    conn = get_db()
    cursor = conn.cursor()
    # Verify SO exists
    cursor.execute('SELECT id FROM generated_sos WHERE id = ?', (so_id,))
    if not cursor.fetchone():
        conn.close()
        return jsonify({'error': 'SO not found'}), 404
    
    for item in items_data:
        cursor.execute('INSERT INTO so_items (so_id, item_name, quantity_kg, quantity_pcs) VALUES (?, ?, ?, ?)', 
                      (so_id, item['item_name'], item['quantity_kg'], item['quantity_pcs']))
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'so_id': so_id})

@app.route('/update_item', methods=['PUT'])
def update_item():
    row = request.json
    id = row.get('id')
    name = row.get('name')
    if not id or not name:
        return jsonify({'error': 'id and name are required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('UPDATE items SET name = ? WHERE id = ?', (name, id))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/update_vendor', methods=['PUT'])
def update_vendor():
    row = request.json
    id = row.get('id')
    if not id:
        return jsonify({'error': 'id is required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('UPDATE vendors SET name = ?, location = ?, km = ? WHERE id = ?', 
        (row.get('name'), row.get('location'), row.get('km'), id))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/update_purchase_vendor', methods=['PUT'])
def update_purchase_vendor():
    row = request.json
    id = row.get('id')
    name = row.get('name')
    if not id or not name:
        return jsonify({'error': 'id and name are required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('UPDATE purchase_vendors SET name = ? WHERE id = ?', (name, id))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/update_b_grade_client', methods=['PUT'])
def update_b_grade_client():
    row = request.json
    id = row.get('id')
    name = row.get('name')
    if not id or not name:
        return jsonify({'error': 'id and name are required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('UPDATE b_grade_clients SET name = ? WHERE id = ?', (name, id))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/update_product_manager', methods=['PUT'])
def update_product_manager():
    row = request.json
    id = row.get('id')
    name = row.get('name')
    if not id or not name:
        return jsonify({'error': 'id and name are required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('UPDATE product_managers SET name = ? WHERE id = ?', (name, id))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

init_db()

# NEW: Password Verification Endpoint
@app.route('/verify_group_password', methods=['POST'])
def verify_group_password():
    data = request.json
    group_name = data.get('group_name')
    password = data.get('password')
    
    if not group_name or not password:
        return jsonify({'valid': False, 'error': 'group_name and password required'}), 400
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT password_hash FROM section_groups WHERE group_name = ?', (group_name,))
    result = cursor.fetchone()
    conn.close()
    
    if result and result[0] == password:  # Simple match (hash in prod)
        return jsonify({'valid': True})
    return jsonify({'valid': False})

# NEW: Update Group Password (Admin Only)
@app.route('/update_group_password', methods=['PUT'])
def update_group_password():
    data = request.json
    group_name = data.get('group_name')
    old_password = data.get('old_password') 
    new_password = data.get('new_password')
    
    if not all([group_name, old_password, new_password]):
        return jsonify({'success': False, 'error': 'All fields required'}), 400
    
    # Verify old password first
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT password_hash FROM section_groups WHERE group_name = ?', (group_name,))
    result = cursor.fetchone()
    
    if not result or result[0] != old_password:
        conn.close()
        return jsonify({'success': False, 'error': 'Old password incorrect'}), 403
    # Update with new password
    cursor.execute(
        'UPDATE section_groups SET password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE group_name = ?',
        (new_password, group_name)  # Hash in production
    )
    conn.commit()
    conn.close()
    return jsonify({'success': True})

# NEW: Get All Groups (Admin Dashboard)
@app.route('/get_all_groups', methods=['GET'])
def get_all_groups():
    # TODO: Proper admin auth later
    admin_key = request.args.get('admin_key', '')
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT password_hash FROM section_groups WHERE group_name = ?', ('admin',))
    result = cursor.fetchone()
    conn.close()
    if not result or result[0] != admin_key:
        return jsonify({'error': 'Invalid admin password'}), 403
    
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT group_name, created_at, updated_at FROM section_groups ORDER BY group_name')
    rows = cursor.fetchall()
    conn.close()
    results = [{'group_name': row['group_name'], 'created_at': row['created_at'], 'updated_at': row['updated_at']} for row in rows]
    return jsonify(results)

# Apply similar pattern to other DELETE endpoints...
@app.route('/delete_product_manager', methods=['DELETE'])
def delete_product_manager():
    data = request.json
    name = data.get('name')
    password = data.get('password')
    
    if not name:
        return jsonify({'error': 'Manager name required'}), 400
    
    # Verify PO_SO group password  
    verify_data = {'group_name': 'po_so', 'password': password}
    if not verify_group_password().get_json()['valid']:
        return jsonify({'error': 'Invalid password for PO/SO operations'}), 403
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM product_managers WHERE name = ?', (name,))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/delete_vehicle', methods=['POST'])
def delete_vehicle():
    data = request.json or request.form.to_dict()
    name = data.get('name') or data.get('number')  # Frontend sends 'name' for all
    password = data.get('password')
    
    if not name or not password:
        return jsonify({'error': 'name/number and password required'}), 400
    
    # Verify LMD group password
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT password_hash FROM section_groups WHERE group_name = ?', ('lmd_fmd',))
    result = cursor.fetchone()
    conn.close()
    
    if not result or result[0] != password:
        return jsonify({'error': 'Invalid LMD password (1008)'}), 403
    
    # Remove vehicle references from lmd_data and fmd_data
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE lmd_data SET vehicle_number = NULL WHERE vehicle_number = ?", (name,))
    cursor.execute("UPDATE fmd_data SET vehicle_number = NULL WHERE vehicle_number = ?", (name,))
    deleted_lmd = cursor.rowcount
    deleted_fmd = cursor.rowcount
    conn.commit()
    conn.close()
    return jsonify({'success': True, 'message': f'Vehicle "{name}" references removed: LMD={deleted_lmd}, FMD={deleted_fmd}'})


@app.route('/insert_vehicle', methods=['POST'])
def insert_vehicle():
    number = request.json.get('number')
    if not number or not number.strip():
        return jsonify({'error': 'Vehicle number required'}), 400
    # No dedicated table - just acknowledge (matches frontend expectation)
    return jsonify({'success': True, 'message': f'Vehicle \"{number.strip()}\" registered for LMD/FMD'})

@app.route('/get_drivers', methods=['GET'])
def get_drivers():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT DISTINCT driver_name FROM lmd_data WHERE driver_name IS NOT NULL AND TRIM(driver_name) != ''
        UNION 
        SELECT DISTINCT driver_name FROM fmd_data WHERE driver_name IS NOT NULL AND TRIM(driver_name) != ''
        ORDER BY driver_name COLLATE NOCASE
    """)
    results = [row[0] for row in cursor.fetchall()]
    conn.close()
    return jsonify(results)

@app.route('/get_vehicles', methods=['GET'])
def get_vehicles():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT DISTINCT vehicle_number FROM lmd_data WHERE vehicle_number IS NOT NULL AND TRIM(vehicle_number) != ''
        UNION 
        SELECT DISTINCT vehicle_number FROM fmd_data WHERE vehicle_number IS NOT NULL AND TRIM(vehicle_number) != ''
        ORDER BY vehicle_number COLLATE NOCASE
    """)
    results = [row[0] for row in cursor.fetchall()]
    conn.close()
    return jsonify(results)

@app.route('/get_last_rate_for_item', methods=['GET'])
def get_last_rate_for_item():
    item_name = request.args.get('item_name')
    table = request.args.get('table', 'sales')  # sales, b_grade_sales, purchases
    if not item_name:
        return jsonify({'error': 'item_name is required'}), 400
    
    conn = get_db()
    cursor = conn.cursor()
    
    # Query based on table
    if table == 'purchases':
        cursor.execute('SELECT rate FROM purchases WHERE item = ? ORDER BY id DESC LIMIT 1', (item_name,))
    elif table == 'b_grade_sales':
        cursor.execute('SELECT rate FROM b_grade_sales WHERE item = ? ORDER BY id DESC LIMIT 1', (item_name,))
    else:  # sales
        cursor.execute('SELECT rate FROM sales WHERE item = ? ORDER BY id DESC LIMIT 1', (item_name,))
    
    result = cursor.fetchone()
    conn.close()
    
    if result and result[0]:
        return jsonify({'rate': result[0]})
    return jsonify({'rate': None})

@app.route('/get_related_data_for_item', methods=['GET'])
def get_related_data_for_item():
    """Get all related data for an item: tags, PO numbers, last rate, etc."""
    item_name = request.args.get('item_name')
    if not item_name:
        return jsonify({'error': 'item_name is required'}), 400
    
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    # Get all tags for this item from purchases
    cursor.execute('SELECT DISTINCT item_tag, po_number FROM purchases WHERE item = ? AND item_tag IS NOT NULL ORDER BY id DESC', (item_name,))
    tags_data = cursor.fetchall()
    
    # Get last rate from sales
    cursor.execute('SELECT rate FROM sales WHERE item = ? ORDER BY id DESC LIMIT 1', (item_name,))
    last_rate = cursor.fetchone()
    
    # Get last rate from purchases
    cursor.execute('SELECT rate FROM purchases WHERE item = ? ORDER BY id DESC LIMIT 1', (item_name,))
    last_purchase_rate = cursor.fetchone()
    
    conn.close()
    
    # Build tags list
    tags = []
    po_numbers = set()
    for row in tags_data:
        if row['item_tag']:
            tags.append(row['item_tag'])
        if row['po_number']:
            po_numbers.add(row['po_number'])
    
    return jsonify({
        'tags': tags,
        'po_numbers': list(po_numbers),
        'last_sales_rate': last_rate[0] if last_rate else None,
        'last_purchase_rate': last_purchase_rate[0] if last_purchase_rate else None,
    })

@app.route('/get_section_groups', methods=['GET'])
def get_section_groups():
    """Get all section groups for passwords tab"""
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT group_name, created_at, updated_at, password_hash FROM section_groups ORDER BY group_name')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

# --- Gate Tracker Endpoints ---

@app.route('/insert_gate_entry', methods=['POST'])
def insert_gate_entry():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        'INSERT INTO gate_entries (vehicle_number, driver_name, entry_type, purpose, party_name, remarks, date, time) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        (row.get('vehicle_number'), row.get('driver_name'), row.get('entry_type'), row.get('purpose'), row.get('party_name'), row.get('remarks'), row.get('date'), row.get('time'))
    )
    conn.commit()
    last_id = cursor.lastrowid
    conn.close()
    return jsonify({'id': last_id})

@app.route('/get_all_gate_entries', methods=['GET'])
def get_all_gate_entries():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('limit', 20, type=int)
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    search = request.args.get('search')
    result = _get_paginated_data('gate_entries', page, per_page, start_date, end_date, search)
    return jsonify(result)

@app.route('/get_latest_gate_entries', methods=['GET'])
def get_latest_gate_entries():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM gate_entries ORDER BY id DESC LIMIT 10')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/update_gate_entry', methods=['PUT'])
def update_gate_entry():
    row = request.json
    id = row.get('id')
    if not id:
        return jsonify({'error': 'id is required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        'UPDATE gate_entries SET vehicle_number=?, driver_name=?, entry_type=?, purpose=?, party_name=?, remarks=?, date=?, time=? WHERE id=?',
        (row.get('vehicle_number'), row.get('driver_name'), row.get('entry_type'), row.get('purpose'), row.get('party_name'), row.get('remarks'), row.get('date'), row.get('time'), id)
    )
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/delete_gate_entry', methods=['DELETE'])
def delete_gate_entry():
    id = request.json.get('id')
    if not id:
        return jsonify({'error': 'id is required'}), 400
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM gate_entries WHERE id = ?', (id,))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/get_vehicle_data', methods=['GET'])
def get_vehicle_data():
    """Get IN/OUT vehicle-related data for gate tracker by date"""
    date = request.args.get('date')
    data_type = request.args.get('type', 'both').lower()  # 'in', 'out', 'both'
    
    if not date:
        return jsonify({'error': 'date parameter required (YYYY-MM-DD)'}), 400
    
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    all_data = []
    
    # IN Data: Goods coming in
    if data_type in ['in', 'both']:
        # Purchases
        cursor.execute("""
            SELECT 'purchases' as table_name, item, vendor as party, qty_accept as qty, 
                   po_number, ctrl_date as record_date, id 
            FROM purchases WHERE (date = ? OR ctrl_date = ?) AND qty_accept > 0
        """, (date, date))
        all_data.extend([dict(row) for row in cursor.fetchall()])
        
        # FMD (vendor inbound)
        cursor.execute("""
            SELECT 'fmd_data' as table_name, items as item, vendor_name as party, 
                   NULL as qty, po_number, ctrl_date as record_date, id 
            FROM fmd_data WHERE (date = ? OR ctrl_date = ?)
        """, (date, date))
        all_data.extend([dict(row) for row in cursor.fetchall()])
        
        # Rejection received  
        cursor.execute("""
            SELECT 'rejection_received' as table_name, item, client_name as party, 
                   quantity as qty, po_number, ctrl_date as record_date, id 
            FROM rejection_received WHERE (date = ? OR ctrl_date = ?)
        """, (date, date))
        all_data.extend([dict(row) for row in cursor.fetchall()])
    
    # OUT Data: Goods going out  
    if data_type in ['out', 'both']:
        # Sales
        cursor.execute("""
            SELECT 'sales' as table_name, item, clint as party, quantity as qty, 
                   po_number, date as record_date, id 
            FROM sales WHERE date = ?
        """, (date,))
        all_data.extend([dict(row) for row in cursor.fetchall()])
        
        # LMD (client outbound)
        cursor.execute("""
            SELECT 'lmd_data' as table_name, NULL as item, client_name as party, 
                   NULL as qty, po_number, ctrl_date as record_date, id 
            FROM lmd_data WHERE (date = ? OR ctrl_date = ?)
        """, (date, date))
        all_data.extend([dict(row) for row in cursor.fetchall()])
        
        # Dump sales, B-grade, Mandi resales
        cursor.execute("""
            SELECT 'dump_sales' as table_name, item, NULL as party, quantity as qty, 
                   po_number, date as record_date, id 
            FROM dump_sales WHERE date = ?
            UNION ALL
            SELECT 'b_grade_sales' as table_name, item, clint as party, quantity as qty, 
                   po_number, date as record_date, id 
            FROM b_grade_sales WHERE date = ?
            UNION ALL  
            SELECT 'mandi_resales' as table_name, item, NULL as party, quantity as qty, 
                   NULL as po_number, date as record_date, id 
            FROM mandi_resales WHERE date = ?
        """, (date, date, date))
        all_data.extend([dict(row) for row in cursor.fetchall()])
    
    # Sort by ID DESC (newest first)
    all_data.sort(key=lambda x: x['id'], reverse=True)
    
    conn.close()
    return jsonify({
        'data': all_data[:50],  # Limit results
        'date': date,
        'type': data_type,
        'total': len(all_data)
    })


# 🚀 NEW GATE TRACKER ENDPOINTS
@app.route('/get_date_totals', methods=['GET'])
def get_date_totals():
    """Get 6 category totals for a specific date"""
    date = request.args.get('date')
    if not date:
        return jsonify({'error': 'date parameter required (YYYY-MM-DD)'}), 400
    
    conn = get_db()
    cursor = conn.cursor()
    
    totals = {
        'purchase_total': 0.0,
        'sales_total': 0.0,
        'bgrade_total': 0.0,
        'rejection_total': 0.0,
        'dump_total': 0.0, 
        'mandi_total': 0.0
    }
    
    # Purchase: SUM(qty_receive) WHERE ctrl_date = date
    cursor.execute("SELECT SUM(qty_receive) as total FROM purchases WHERE ctrl_date = ?", (date,))
    totals['purchase_total'] = cursor.fetchone()[0] or 0.0
    
    # Sales
    cursor.execute("SELECT SUM(quantity) as total FROM sales WHERE date = ?", (date,))
    totals['sales_total'] = cursor.fetchone()[0] or 0.0
    
    # B-Grade Sales  
    cursor.execute("SELECT SUM(quantity) as total FROM b_grade_sales WHERE date = ?", (date,))
    totals['bgrade_total'] = cursor.fetchone()[0] or 0.0
    
    # Rejection Received
    cursor.execute("SELECT SUM(quantity) as total FROM rejection_received WHERE ctrl_date = ?", (date,))
    totals['rejection_total'] = cursor.fetchone()[0] or 0.0
    
    # Dump Sales
    cursor.execute("SELECT SUM(quantity) as total FROM dump_sales WHERE date = ?", (date,))
    totals['dump_total'] = cursor.fetchone()[0] or 0.0
    
    # Mandi Resales
    cursor.execute("SELECT SUM(quantity) as total FROM mandi_resales WHERE date = ?", (date,))
    totals['mandi_total'] = cursor.fetchone()[0] or 0.0
    
    conn.close()
    return jsonify(totals)


@app.route('/get_max_gate_number', methods=['GET'])
def get_max_gate_number():
    """Get next available gate number"""
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT COALESCE(MAX(CAST(gate_number AS INTEGER)), 0) + 1 as next_gate FROM gate_tracker")
    result = cursor.fetchone()[0]
    conn.close()
    return jsonify({'next_gate': int(result)})


@app.route('/insert_gate_record', methods=['POST'])
def insert_gate_record():
    """Insert gate record with totals snapshot.

    If frontend sends `gate_number`, use it.
    Otherwise fallback to auto next (MAX+1).
    """
    data = request.json
    conn = get_db()
    cursor = conn.cursor()

    # If user manually provided gate_number, use it.
    requested_gate = data.get('gate_number')
    try:
        requested_gate_int = int(requested_gate) if requested_gate is not None else None
    except (TypeError, ValueError):
        requested_gate_int = None

    if requested_gate_int is not None:
        gate_to_use = requested_gate_int
    else:
        # Get next gate number atomically
        cursor.execute(
            "SELECT COALESCE(MAX(CAST(gate_number AS INTEGER)), 0) + 1 as next_gate FROM gate_tracker"
        )
        gate_to_use = cursor.fetchone()[0]

    cursor.execute('''
        INSERT INTO gate_tracker (
            gate_number, record_date, purchase_total, sales_total, bgrade_total, 
            rejection_total, dump_total, mandi_total, vehicle_number, driver_name, 
            party_name, remarks
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (
        gate_to_use,
        data.get('record_date'),
        data.get('purchase_total', 0),
        data.get('sales_total', 0),
        data.get('bgrade_total', 0),
        data.get('rejection_total', 0),
        data.get('dump_total', 0),
        data.get('mandi_total', 0),
        data.get('vehicle_number'),
        data.get('driver_name'),
        data.get('party_name'),
        data.get('remarks')
    ))

    gate_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return jsonify({'gate_id': gate_id, 'gate_number': gate_to_use})


@app.route('/get_gate_records', methods=['GET'])
def get_gate_records():
    """Get recent gate records"""
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('limit', 20, type=int)
    result = _get_paginated_data('gate_tracker', page, per_page)
    return jsonify(result)


@app.route('/insert_admin_report', methods=['POST'])
def insert_admin_report():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        '''
        SELECT id
        FROM admin_report
        WHERE date = ? AND item = ?
        ''',
        (
            row.get('date'),
            row.get('item')
        )
    )

    existing = cursor.fetchone()

    if existing:
        conn.close()

        return jsonify({
            'success': False,
            'message': f"Report already exists for item '{row.get('item')}' on date '{row.get('date')}'"
        }), 409
    cursor.execute("""INSERT INTO admin_report (date, item, stock_today, stock_next_day, purchase_received, rejection_received, vendor_rejection, sales, dump_sale, mandi_resale, b_grade_sales, total_quantity, total_sales, check_stock)VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""", (row.get('date'), row.get('item'), row.get('stock_today'), row.get('stock_next_day'), row.get('purchase_received'), row.get('rejection_received'), row.get('vendor_rejection'), row.get('sales'), row.get('dump_sale'), row.get('mandi_resale'), row.get('b_grade_sales'), row.get('total_quantity'), row.get('total_sales'), row.get('check_stock'),))
    conn.commit()
    inserted_id = cursor.lastrowid
    conn.close()
    return jsonify({'success': True, 'id': inserted_id,})



@app.route('/get_admin_report', methods=['GET'])
def get_admin_report():

    conn = get_db()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT *
        FROM admin_report
        ORDER BY id DESC
    """)

    columns = [c[0] for c in cursor.description]

    rows = [
        dict(zip(columns, row))
        for row in cursor.fetchall()
    ]

    conn.close()

    return jsonify({'data': rows})

@app.route('/get_stock_items', methods=['GET'])
def get_stock_items():
    conn = None

    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        today = datetime.now().strftime('%Y-%m-%d')

        cursor.execute("""
            SELECT MAX(date) AS latest_date
            FROM stock_updates
            WHERE date < ?
        """, (today,))

        result = cursor.fetchone()

        if not result or not result["latest_date"]:
            return jsonify({
                "success": True,
                "count": 0,
                "items": []
            })

        latest_date = result["latest_date"]

        # print("Latest Date:", latest_date)

        cursor.execute("""
            SELECT DISTINCT TRIM(item) AS item
            FROM stock_updates
            WHERE date = ?
              AND item IS NOT NULL
              AND TRIM(item) <> ''
            ORDER BY item ASC
        """, (latest_date,))

        rows = cursor.fetchall()
        items = [row["item"] for row in rows]
        # print(items)

        return jsonify({
            "success": True,
            "date": latest_date,
            "count": len(items),
            "items": items
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500

    finally:
        if conn:
            conn.close()



@app.route('/get_recent_purchase_tags', methods=['GET'])
def get_recent_purchase_tags():
    conn = sqlite3.connect('mydata.db')
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("""
        SELECT item, item_tag, po_number
        FROM purchases
        WHERE ctrl_date >= date('now', '-15 day')
    """)

    rows = [dict(r) for r in cur.fetchall()]
    conn.close()

    return jsonify(rows)




@app.route('/get_so_by_client_and_date', methods=['GET'])
def get_so_by_client_and_date():
    client_name = request.args.get('client_name', '').strip().lower()
    ctrl_date = request.args.get('ctrl_date', '').strip()

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("""
        SELECT so_number, client_name, date_of_dispatch
        FROM generated_sos
        WHERE date_of_dispatch = ?
    """, (ctrl_date,))

    rows = cur.fetchall()
    conn.close()

    for row in rows:
        db_clients = (row['client_name'] or '').lower()

        # split multiple clients
        clients = [c.strip() for c in db_clients.split(',')]

        for c in clients:
            if c == client_name:
                return {
                    "success": True,
                    "so_number": row['so_number']
                }

    return {
        "success": False,
        "so_number": ""
    }



if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000, debug=True)

