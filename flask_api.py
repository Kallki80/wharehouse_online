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

# Tables the admin dashboard is allowed to browse / export. Also used as a
# whitelist so dynamic SQL below never interpolates an untrusted table name.
ADMIN_TABLE_WHITELIST = {
    'purchases', 'packaging_materials', 'sales', 'stock_updates',
    'lmd_data', 'fmd_data', 'generated_pos', 'generated_sos',
    'rejection_received', 'vendor_rejections', 'dump_sales',
    'mandi_resales', 'b_grade_sales', 'items', 'vendors',
    'purchase_vendors', 'b_grade_clients', 'product_managers',
    'admin_report', 'gate_entries',
}

# Order matters: the first column found on the table is used for date filters.
DATE_FIELD_CANDIDATES = [
    'date', 'ctrl_date', 'expected_date', 'date_of_dispatch',
    'record_date', 'payment_date',
]


def _table_columns(cursor, table_name):
    """Return the column names of `table_name` using a single PRAGMA call."""
    cursor.execute(f"PRAGMA table_info({table_name})")
    return [row[1] for row in cursor.fetchall()]


def _find_date_field(columns):
    """Pick the column used for date-range filtering (None when table has none)."""
    for field in DATE_FIELD_CANDIDATES:
        if field in columns:
            return field
    return None


def _build_search_clause(cursor, table_name, search, search_fields=None):
    """Build a `(sql, args)` pair that searches `search` across text columns.

    When `search_fields` is given only those columns are searched (they must
    exist on the table). Otherwise every text column of the table is searched,
    mirroring the client side "contains" search the admin dashboard used to do.
    """
    if not search or not str(search).strip():
        return '', []

    columns = _table_columns(cursor, table_name)
    if search_fields:
        fields = [f for f in search_fields if f in columns]
    else:
        fields = []
        cursor.execute(f"PRAGMA table_info({table_name})")
        for row in cursor.fetchall():
            col_type = (row[2] or '').upper()
            if 'TEXT' in col_type or 'CHAR' in col_type or 'CLOB' in col_type:
                fields.append(row[1])

    if not fields:
        return '', []

    conditions = [f"LOWER(CAST({field} AS TEXT)) LIKE ?" for field in fields]
    args = [f"%{str(search).strip().lower()}%"] * len(fields)
    return '(' + ' OR '.join(conditions) + ')', args


def _get_paginated_data(table_name, page=1, per_page=20, start_date=None, end_date=None,
                        search=None, search_fields=None, extra_conditions=None,
                        extra_args=None):
    """Generic pagination helper for dashboard tables.

    Returns a `{data, total, page, per_page, has_more, date_field}` envelope.
    """
    page = max(1, int(page or 1))
    per_page = max(1, min(int(per_page or 20), 100000))

    if table_name not in ADMIN_TABLE_WHITELIST:
        return {
            'data': [], 'total': 0, 'page': page, 'per_page': per_page,
            'has_more': False, 'date_field': None, 'error': 'unknown table',
        }

    offset = (page - 1) * per_page
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    columns = _table_columns(cursor, table_name)
    date_field = _find_date_field(columns)

    where_conditions = []
    where_args = []

    # Custom (exact match / LIKE) conditions passed by callers.
    if extra_conditions:
        where_conditions.extend(extra_conditions)
        where_args.extend(extra_args or [])

    if start_date and date_field:
        where_conditions.append(f"{date_field} >= ?")
        where_args.append(start_date)

    if end_date and date_field:
        where_conditions.append(f"{date_field} <= ?")
        where_args.append(end_date)

    search_clause, search_args = _build_search_clause(
        cursor, table_name, search, search_fields
    )
    if search_clause:
        where_conditions.append(search_clause)
        where_args.extend(search_args)

    where_clause = "WHERE " + " AND ".join(where_conditions) if where_conditions else ""
    order_clause = 'id DESC' if 'id' in columns else 'rowid DESC'

    # Count total
    count_query = f"SELECT COUNT(*) as total FROM {table_name} {where_clause}"
    cursor.execute(count_query, where_args)
    total = cursor.fetchone()['total']

    # Data query
    data_query = (f"SELECT * FROM {table_name} {where_clause} "
                  f"ORDER BY {order_clause} LIMIT ? OFFSET ?")
    cursor.execute(data_query, where_args + [per_page, offset])
    rows = cursor.fetchall()

    conn.close()
    data = [dict(row) for row in rows]
    has_more = (offset + len(data)) < total

    return {
        'data': data,
        'total': total,
        'page': page,
        'per_page': per_page,
        'has_more': has_more,
        'date_field': date_field,
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
    page = request.args.get('page', type=int)

    if page is not None:
        # Admin dashboard: paginated envelope (date + text search supported).
        extra_conditions = []
        extra_args = []
        if po_number:
            extra_conditions.append('po_number LIKE ?')
            extra_args.append(f'%{po_number}%')
        if item_name:
            extra_conditions.append('item_name = ?')
            extra_args.append(item_name)
        if vendor_name:
            extra_conditions.append('vendor_name = ?')
            extra_args.append(vendor_name)
        result = _get_paginated_data(
            'generated_pos',
            page,
            request.args.get('limit', 50, type=int),
            start_date=start_date,
            end_date=end_date,
            search=request.args.get('search'),
            search_fields=['po_number', 'item_name', 'vendor_name', 'product_manager'],
            extra_conditions=extra_conditions,
            extra_args=extra_args,
        )
        return jsonify(result)

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
    page = request.args.get('page', type=int)

    if page is not None:
        # Admin dashboard: paginated envelope. Rows are SO *items*, so the page
        # size counts item rows and the page window is selected by item id.
        per_page = max(1, min(request.args.get('limit', 50, type=int), 100000))
        page = max(1, page)
        offset = (page - 1) * per_page

        conditions = []
        args = []
        if so_number:
            conditions.append('so2.so_number LIKE ?')
            args.append(f'%{so_number}%')
        if item_name:
            conditions.append('item2.item_name = ?')
            args.append(item_name)
        if client_name:
            conditions.append('so2.client_name = ?')
            args.append(client_name)
        if start_date:
            conditions.append('so2.date_of_dispatch >= ?')
            args.append(start_date)
        if end_date:
            conditions.append('so2.date_of_dispatch <= ?')
            args.append(end_date)
        search = request.args.get('search')
        if search and search.strip():
            like = f"%{search.strip().lower()}%"
            conditions.append(
                '(LOWER(CAST(so2.so_number AS TEXT)) LIKE ? '
                'OR LOWER(CAST(so2.client_name AS TEXT)) LIKE ? '
                'OR LOWER(CAST(item2.item_name AS TEXT)) LIKE ?)'
            )
            args.extend([like, like, like])
        where_sql = 'WHERE ' + ' AND '.join(conditions) if conditions else ''

        conn = get_db()
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute(
            f'''SELECT COUNT(*) AS total
                FROM generated_sos so2
                JOIN so_items item2 ON so2.id = item2.so_id
                LEFT JOIN vendors v2 ON so2.client_name = v2.name
                {where_sql}''',
            args,
        )
        total = cursor.fetchone()['total']

        query = f'''SELECT so.id as so_id, so.client_name, so.so_number, so.date_of_dispatch,
                           item.id as item_id, item.item_name, item.quantity_kg, item.quantity_pcs,
                           item.dispatched_qty_kg, item.dispatched_qty_pcs, item.dispatch_status,
                           v.location, v.km
                    FROM generated_sos so
                    JOIN so_items item ON so.id = item.so_id
                    LEFT JOIN vendors v ON so.client_name = v.name
                    WHERE item.id IN (
                        SELECT item2.id FROM generated_sos so2
                        JOIN so_items item2 ON so2.id = item2.so_id
                        LEFT JOIN vendors v2 ON so2.client_name = v2.name
                        {where_sql}
                        ORDER BY so2.id DESC, item2.id ASC
                        LIMIT ? OFFSET ?
                    )
                    ORDER BY so.id DESC, item.id ASC'''
        cursor.execute(query, args + [per_page, offset])
        rows = cursor.fetchall()
        conn.close()
        data = [dict(row) for row in rows]
        return jsonify({
            'data': data,
            'total': total,
            'page': page,
            'per_page': per_page,
            'has_more': (offset + len(data)) < total,
            'date_field': 'date_of_dispatch',
        })

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
    page = request.args.get('page', type=int)
    if page is None:
        # Legacy behaviour: plain full list for the other screens.
        conn = get_db()
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute('SELECT id, name FROM product_managers ORDER BY name COLLATE NOCASE')
        rows = cursor.fetchall()
        conn.close()
        return jsonify([{'id': r['id'], 'name': r['name']} for r in rows])

    result = _get_paginated_data(
        'product_managers',
        page,
        request.args.get('limit', 50, type=int),
        search=request.args.get('search'),
        search_fields=['name'],
    )
    return jsonify(result)


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
    new_item = cursor.rowcount > 0
    conn.commit()
    conn.close()
    _record_new_item_unit(name.strip(), request.json, new_item)
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

# @app.route('/insert_generated_po', methods=['POST'])
# def insert_generated_po():
#     row = request.json

#     conn = get_db()
#     cursor = conn.cursor()

#     cursor.execute('''
#         INSERT INTO generated_pos (
#             product_manager,
#             item_name,
#             po_number,
#             qty_ordered,
#             rate,
#             unit,
#             vendor_name,
#             vendor_id,
#             advanced_payment,
#             advanced_payment_date,
#             expected_date,
#             quality_specifications,
#             note,
#             date,
#             time
#         )
#         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
#     ''', (
#         row['product_manager'],
#         row['item_name'],
#         row['po_number'],
#         row['qty_ordered'],
#         row['rate'],
#         row['unit'],
#         row['vendor_name'],
#         row.get('vendor_id'),
#         row.get('advanced_payment'),
#         row.get('advanced_payment_date'),
#         row['expected_date'],
#         row['quality_specifications'],
#         row['note'],
#         row['date'],
#         row['time']
#     ))

#     conn.commit()

#     inserted_id = cursor.lastrowid

#     conn.close()

#     return jsonify({'id': inserted_id})




@app.route('/insert_generated_po', methods=['POST'])
def insert_generated_po():
    row = request.json

    # Agar date/time nahi mila to current date/time use karo
    now = datetime.now()

    date = row.get('date') or now.strftime('%Y-%m-%d')
    time = row.get('time') or now.strftime('%H:%M:%S')

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
        date,
        time
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
    page = request.args.get('page', type=int)
    search = request.args.get('search')
    # `distinct=1` collapses duplicate names (keeps the smallest id) so the
    # admin dashboard can still page through a de-duplicated list.
    distinct = str(request.args.get('distinct', '')).lower() in ('1', 'true', 'yes')

    if page is None:
        # Legacy behaviour: the other screens expect the full plain list.
        conn = get_db()
        cursor = conn.cursor()
        # AdminDashboard items table expects `id` for delete/update.
        if distinct:
            cursor.execute(
                'SELECT MIN(id) AS id, name FROM items GROUP BY name '
                'ORDER BY name COLLATE NOCASE'
            )
        else:
            cursor.execute(
                'SELECT id, name FROM items ORDER BY name COLLATE NOCASE'
            )
        rows = cursor.fetchall()
        conn.close()
        # Return list of {id, name} objects.
        return jsonify([{'id': row[0], 'name': row[1]} for row in rows])

    per_page = max(1, min(request.args.get('limit', 50, type=int), 100000))
    page = max(1, page)
    offset = (page - 1) * per_page

    where_sql = ''
    args = []
    if search and search.strip():
        where_sql = 'WHERE name LIKE ?'
        args.append(f'%{search.strip()}%')

    conn = get_db()
    cursor = conn.cursor()
    if distinct:
        cursor.execute(
            f'SELECT COUNT(*) FROM (SELECT name FROM items {where_sql} GROUP BY name)',
            args,
        )
        total = cursor.fetchone()[0]
        cursor.execute(
            f'SELECT MIN(id) AS id, name FROM items {where_sql} GROUP BY name '
            'ORDER BY name COLLATE NOCASE LIMIT ? OFFSET ?',
            args + [per_page, offset],
        )
    else:
        cursor.execute(f'SELECT COUNT(*) FROM items {where_sql}', args)
        total = cursor.fetchone()[0]
        cursor.execute(
            f'SELECT id, name FROM items {where_sql} '
            'ORDER BY name COLLATE NOCASE LIMIT ? OFFSET ?',
            args + [per_page, offset],
        )
    rows = cursor.fetchall()
    conn.close()
    data = [{'id': row[0], 'name': row[1]} for row in rows]
    return jsonify({
        'data': data,
        'total': total,
        'page': page,
        'per_page': per_page,
        'has_more': (offset + len(data)) < total,
        'date_field': None,
    })


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
    page = request.args.get('page', type=int)
    if page is None:
        # Legacy behaviour: plain full list for the other screens.
        conn = get_db()
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute('SELECT * FROM vendors ORDER BY name COLLATE NOCASE')
        rows = cursor.fetchall()
        conn.close()
        results = [dict(row) for row in rows]
        return jsonify(results)

    result = _get_paginated_data(
        'vendors',
        page,
        request.args.get('limit', 50, type=int),
        search=request.args.get('search'),
        search_fields=['name', 'location'],
    )
    return jsonify(result)

@app.route('/get_purchase_vendors', methods=['GET'])
def get_purchase_vendors():
    page = request.args.get('page', type=int)
    if page is None:
        # Legacy behaviour: plain full list for the other screens.
        conn = get_db()
        cursor = conn.cursor()
        cursor.execute('SELECT id, name FROM purchase_vendors ORDER BY name COLLATE NOCASE')
        rows = cursor.fetchall()
        conn.close()
        return jsonify([{'id': r[0], 'name': r[1]} for r in rows])

    result = _get_paginated_data(
        'purchase_vendors',
        page,
        request.args.get('limit', 50, type=int),
        search=request.args.get('search'),
        search_fields=['name'],
    )
    return jsonify(result)


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
    page = request.args.get('page', type=int)
    if page is None:
        # Legacy behaviour: plain full list for the other screens.
        conn = get_db()
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute('SELECT id, name FROM b_grade_clients ORDER BY name COLLATE NOCASE')
        rows = cursor.fetchall()
        conn.close()
        return jsonify([{'id': r['id'], 'name': r['name']} for r in rows])

    result = _get_paginated_data(
        'b_grade_clients',
        page,
        request.args.get('limit', 50, type=int),
        search=request.args.get('search'),
        search_fields=['name'],
    )
    return jsonify(result)


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


@app.route('/count_by_date_range', methods=['GET'])
def count_by_date_range():
    """Preview how many rows a date-range delete would remove (admin dashboard)."""
    table_name = request.args.get('table_name')
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')

    if table_name not in ADMIN_TABLE_WHITELIST:
        return jsonify({'error': 'unknown table_name'}), 400
    if not start_date or not end_date:
        return jsonify({'error': 'start_date and end_date are required (yyyy-MM-dd)'}), 400

    conn = get_db()
    cursor = conn.cursor()
    date_field = _find_date_field(_table_columns(cursor, table_name))
    if not date_field:
        conn.close()
        return jsonify({'count': 0, 'date_field': None, 'note': 'table has no date column'})

    cursor.execute(
        f'SELECT COUNT(*) FROM {table_name} WHERE {date_field} >= ? AND {date_field} <= ?',
        (start_date, end_date),
    )
    count = cursor.fetchone()[0]
    conn.close()
    return jsonify({'count': count, 'date_field': date_field})


@app.route('/delete_by_date_range', methods=['POST', 'DELETE'])
def delete_by_date_range():
    """Delete every row of a dashboard table inside [start_date, end_date]."""
    payload = request.json or {}
    table_name = payload.get('table_name')
    start_date = payload.get('start_date')
    end_date = payload.get('end_date')

    if table_name not in ADMIN_TABLE_WHITELIST:
        return jsonify({'error': 'unknown table_name'}), 400
    if not start_date or not end_date:
        return jsonify({'error': 'start_date and end_date are required (yyyy-MM-dd)'}), 400

    conn = get_db()
    cursor = conn.cursor()
    date_field = _find_date_field(_table_columns(cursor, table_name))
    if not date_field:
        conn.close()
        return jsonify({'deleted': 0, 'date_field': None, 'note': 'table has no date column'})

    cursor.execute(
        f'DELETE FROM {table_name} WHERE {date_field} >= ? AND {date_field} <= ?',
        (start_date, end_date),
    )
    deleted = cursor.rowcount
    conn.commit()
    conn.close()
    return jsonify({'deleted': deleted, 'date_field': date_field})

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

# @app.route('/get_all_lmd_data', methods=['GET'])
# def get_all_lmd_data():
#     page = request.args.get('page', 1, type=int)
#     per_page = request.args.get('limit', 20, type=int)
#     start_date = request.args.get('start_date')
#     end_date = request.args.get('end_date')
#     search = request.args.get('search')
    
#     result = _get_paginated_data('lmd_data', page, per_page, start_date, end_date, search)
#     return jsonify(result)

@app.route('/get_all_lmd_data', methods=['GET'])
def get_all_lmd_data():
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    search = request.args.get('search')
    page = request.args.get('page', type=int)

    if page is not None:
        # Admin dashboard: paginated envelope with date + text search.
        result = _get_paginated_data(
            'lmd_data',
            page,
            request.args.get('limit', 50, type=int),
            start_date=start_date,
            end_date=end_date,
            search=search,
            search_fields=[
                'client_name', 'po_number', 'vehicle_number', 'driver_name',
                'client_location', 'booking_person', 'gate_number',
                'payment_status', 'mode_of_payment',
            ],
        )
        return jsonify(result)

    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    query = "SELECT * FROM lmd_data WHERE 1=1"
    params = []

    if start_date:
        query += " AND date >= ?"
        params.append(start_date)

    if end_date:
        query += " AND date <= ?"
        params.append(end_date)

    if search:
        query += " AND (client_name LIKE ? OR po_number LIKE ?)"
        params.extend([f"%{search}%", f"%{search}%"])

    query += " ORDER BY id DESC"

    cursor.execute(query, params)
    data = [dict(row) for row in cursor.fetchall()]
    conn.close()

    return jsonify(data)

    
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
    page = request.args.get('page', type=int)

    if page is not None:
        # Admin dashboard: paginated envelope with date + text search.
        result = _get_paginated_data(
            'fmd_data',
            page,
            request.args.get('limit', 50, type=int),
            start_date=request.args.get('start_date'),
            end_date=request.args.get('end_date'),
            search=request.args.get('search'),
            search_fields=[
                'vendor_name', 'vendor_location', 'vehicle_number', 'driver_name',
                'po_number', 'items', 'booking_person', 'gate_number',
                'payment_status', 'mode_of_payment',
            ],
        )
        return jsonify(result)

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
        _set_sale_class(cursor, sale_id, row)
        
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


# @app.route('/get_admin_report_rows', methods=['GET'])
# def get_admin_report_rows():
#     """Single backend route that returns the AdminReport DataTable row for (item, chosen_date).

#     Query params:
#       - item: item name
#       - chosen_date: yyyy-MM-dd
#     """
#     item = request.args.get('item')
#     chosen_date = request.args.get('chosen_date')

#     if not item or not chosen_date:
#         return jsonify({'error': 'item and chosen_date are required'}), 400

#     # previousDate for stock_today (chosen_date - 1 day)
#     # SQLite query will just use previousDate string.
#     import datetime as _dt
#     try:
#         chosen_dt = _dt.datetime.strptime(chosen_date, '%Y-%m-%d').date()
#         previous_date = (chosen_dt - _dt.timedelta(days=1)).strftime('%Y-%m-%d')
#     except Exception:
#         return jsonify({'error': 'chosen_date must be yyyy-MM-dd'}), 400

#     conn = get_db()
#     cursor = conn.cursor()

#     def _sum(query, args):
#         cursor.execute(query, args)
#         row = cursor.fetchone()
#         if not row or row[0] is None:
#             return 0.0
#         try:
#             return float(row[0])
#         except Exception:
#             return 0.0

#     purchase_received = _sum(
#         'SELECT SUM(qty_receive) FROM purchases WHERE item = ? AND ctrl_date = ?',
#         (item, chosen_date),
#     )

#     rejection_received = _sum(
#         'SELECT SUM(quantity) FROM rejection_received WHERE item = ? AND ctrl_date = ?',
#         (item, chosen_date),
#     )

#     vendor_rejection = _sum(
#         'SELECT SUM(quantity_sent) FROM vendor_rejections WHERE item = ? AND date = ?',
#         (item, chosen_date),
#     )

#     sales_qty = _sum(
#         'SELECT SUM(quantity) FROM sales WHERE item = ? AND date = ?',
#         (item, chosen_date),
#     )

#     dump_sale_qty = _sum(
#         'SELECT SUM(quantity) FROM dump_sales WHERE item = ? AND date = ?',
#         (item, chosen_date),
#     )

#     mandi_resale_qty = _sum(
#         'SELECT SUM(quantity) FROM mandi_resales WHERE item = ? AND date = ?',
#         (item, chosen_date),
#     )

#     b_grade_sales_qty = _sum(
#         'SELECT SUM(quantity) FROM b_grade_sales WHERE item = ? AND date = ?',
#         (item, chosen_date),
#     )

#     stock_next_day = _sum(
#         'SELECT SUM(a_grade_qty + b_grade_qty + c_grade_qty + ungraded_qty + dump_qty) FROM stock_updates WHERE item = ? AND date = ?',
#         (item, chosen_date),
#     )

#     stock_today = _sum(
#         'SELECT SUM(a_grade_qty + b_grade_qty + c_grade_qty + ungraded_qty + dump_qty) FROM stock_updates WHERE item = ? AND date = ?',
#         (item, previous_date),
#     )

#     total_quantity = stock_today + purchase_received + rejection_received - vendor_rejection
#     total_sales = sales_qty + dump_sale_qty + mandi_resale_qty + b_grade_sales_qty
#     check_stock = total_quantity - total_sales - stock_next_day

#     rows = [
#         {
#             'date': chosen_date,
#             'iteam': item,  # NOTE: frontend uses this key (typo retained)
#             'stock_today': stock_today,
#             'stock_next_day': stock_next_day,
#             'purchase_received': purchase_received,
#             'rejection_received': rejection_received,
#             'vendor_rejection': vendor_rejection,
#             'sales': sales_qty,
#             'dump_sale': dump_sale_qty,
#             'mandi_resale': mandi_resale_qty,
#             'b_grade_sales': b_grade_sales_qty,
#             'total_quantity': total_quantity,
#             'total_sales': total_sales,
#             'check_stock': check_stock,
#         }
#     ]

#     conn.close()
#     return jsonify({'data': rows})



# =====================================================================
# ADMIN REPORT ENGINE
# ---------------------------------------------------------------------
# Everything the Admin Report needs lives in this block:
#   * unit conversion (g -> kg, pcs handling)               [fix 1]
#   * item spelling matching + "convert spelling" endpoints [fix 2]
#   * clear date names: report_date / next_date             [fix 3]
#   * automatic generation + auto-update of saved reports   [fix 4]
#   * papaya / pineapple reported and saved in pcs          [fix 5]
# =====================================================================
import re as _re
import threading as _threading
import difflib as _difflib

_REPORT_LOCK = _threading.RLock()

# ---------- units -----------------------------------------------------
_GRAM_UNITS = {'g', 'gm', 'gms', 'gr', 'grm', 'grms', 'gram', 'grams', 'gramme', 'grammes'}
_KG_UNITS = {'', 'kg', 'kgs', 'kilo', 'kilos', 'kilogram', 'kilograms'}
_PCS_UNITS = {'pc', 'pcs', 'piece', 'pieces', 'nos', 'no', 'number', 'numbers'}


def _norm_unit(unit):
    return _re.sub(r'\s+', '', str(unit or '')).lower().rstrip('.')


def _num(value):
    try:
        f = float(value)
        return f if f == f else 0.0  # NaN guard
    except (TypeError, ValueError):
        return 0.0


def _is_pcs_unit(unit):
    return _norm_unit(unit) in _PCS_UNITS


def _qty_to_kg(qty, unit):
    """Quantity converted to kg.
    g/gm/grams -> /1000, kg or blank -> as is, pcs -> 0 (a piece count has no
    weight). Any other unknown unit is treated as kg (same as before)."""
    u = _norm_unit(unit)
    q = _num(qty)
    if u in _GRAM_UNITS:
        return q / 1000.0
    if u in _PCS_UNITS:
        return 0.0
    return q


def _entry_pcs(qty, unit, pcs, kg_fallback):
    """Piece count of one entry.
    1. quantity entered with unit 'pcs'  -> that quantity
    2. otherwise the pcs column, if filled
    3. otherwise (only for pcs items: papaya/pineapple) the kg value."""
    if _is_pcs_unit(unit):
        return _num(qty)
    p = _num(pcs)
    if p > 0:
        return p
    if kg_fallback:
        return _qty_to_kg(qty, unit)
    return 0.0


# ---------- items -----------------------------------------------------
PCS_ITEM_KEYWORDS = ('papaya', 'pineapple')


def _norm_item(name):
    """'  Sweet  Potato ' -> 'sweet potato' (case and extra spaces ignored)."""
    return _re.sub(r'\s+', ' ', str(name or '').strip()).lower()


_PCS_CACHE = {'at': 0.0, 'map': {}}


def _pcs_setting_map():
    """{item_key: True/False} from Item Settings ("stock counted in pieces"), cached 30 s."""
    import time as _time
    if _time.time() - _PCS_CACHE['at'] > 30:
        m = {}
        try:
            conn = sqlite3.connect(db_path, timeout=10)
            try:
                for k, v in conn.execute('SELECT item_key, stock_in_pcs FROM item_settings WHERE stock_in_pcs IS NOT NULL'):
                    m[k] = bool(v)
            finally:
                conn.close()
        except sqlite3.Error:
            pass
        _PCS_CACHE['map'], _PCS_CACHE['at'] = m, _time.time()
    return _PCS_CACHE['map']


def _is_pcs_item(name):
    """Stock of this item is counted in pieces. Set per item in Item Settings
    (asked when an item is added); items not set yet use the old rule:
    papaya / pineapple in pieces, everything else in kg."""
    n = _norm_item(name)
    m = _pcs_setting_map()
    if n in m:
        return m[n]
    return any(k in n for k in PCS_ITEM_KEYWORDS)


# Tables the report reads from. date_col = the date the report filters on.
_REPORT_SOURCES = {
    'purchases':          {'date_col': 'ctrl_date', 'qty': 'qty_receive',   'unit': 'unit_receive', 'pcs': 'pcs_receive'},
    'rejection_received': {'date_col': 'ctrl_date', 'qty': 'quantity',      'unit': 'unit',         'pcs': 'pcs'},
    'vendor_rejections':  {'date_col': 'date',      'qty': 'quantity_sent', 'unit': 'unit',         'pcs': 'pcs'},
    'sales':              {'date_col': 'date',      'qty': 'quantity',      'unit': 'unit',         'pcs': 'pcs'},
    'dump_sales':         {'date_col': 'date',      'qty': 'quantity',      'unit': 'unit',         'pcs': 'pcs'},
    'mandi_resales':      {'date_col': 'date',      'qty': 'quantity',      'unit': 'unit',         'pcs': 'pcs'},
    'b_grade_sales':      {'date_col': 'date',      'qty': 'quantity',      'unit': 'unit',         'pcs': 'pcs'},
}
_STOCK_GRADES = [
    ('a_grade_qty', 'a_grade_unit', 'pcs_a_grade'),
    ('b_grade_qty', 'b_grade_unit', 'pcs_b_grade'),
    ('c_grade_qty', 'c_grade_unit', 'pcs_c_grade'),
    ('ungraded_qty', 'ungraded_unit', 'pcs_ungraded'),
    ('dump_qty', 'dump_unit', 'pcs_dump'),
]
_ITEM_TABLES = list(_REPORT_SOURCES.keys()) + ['stock_updates']

_REPORT_FIELDS = [
    'stock_today', 'stock_next_day', 'purchase_received', 'rejection_received',
    'vendor_rejection', 'sales', 'dump_sale', 'mandi_resale', 'b_grade_sales',
    'total_quantity', 'total_sales', 'check_stock',
]


def _report_conn(timeout=30):
    conn = sqlite3.connect(db_path, timeout=timeout)
    conn.create_function('norm_item', 1, _norm_item)
    return conn


def _load_item_catalog(cursor):
    """canon: {normalized name -> name in Admin item list (first/lowest id wins)}
    aliases: {normalized wrong spelling -> item name it belongs to}"""
    canon = {}
    cursor.execute('SELECT name FROM items WHERE name IS NOT NULL ORDER BY id')
    for (name,) in cursor.fetchall():
        k = _norm_item(name)
        if k and k not in canon:
            canon[k] = name
    aliases = {}
    try:
        cursor.execute('SELECT alias_key, item_name FROM item_aliases')
        aliases = {a: t for a, t in cursor.fetchall()}
    except sqlite3.OperationalError:
        pass
    return canon, aliases


def _resolve_item(name, canon, aliases):
    """Name as written in an entry -> item name from the Admin item list (or None)."""
    k = _norm_item(name)
    if not k:
        return None
    if k in canon:
        return canon[k]
    if k in aliases:
        return canon.get(_norm_item(aliases[k]))
    return None


def _keys_for_item(item_name, aliases):
    ck = _norm_item(item_name)
    keys = {ck}
    keys.update(a for a, t in aliases.items() if _norm_item(t) == ck)
    return keys


def _to_iso_date(value):
    """Accepts 'YYYY-MM-DD' (optionally with time), 'Tue, 29 Sep 2026 00:00:00 GMT',
    'DD-MM-YYYY' or 'DD/MM/YYYY'. Returns 'YYYY-MM-DD' or None."""
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return None
    for fmt, part in (('%Y-%m-%d', s[:10]), ('%a, %d %b %Y %H:%M:%S GMT', s),
                      ('%d-%m-%Y', s[:10]), ('%d/%m/%Y', s[:10])):
        try:
            return datetime.strptime(part, fmt).strftime('%Y-%m-%d')
        except ValueError:
            continue
    return None


def _shift_date(iso_date, days):
    return (datetime.strptime(iso_date, '%Y-%m-%d') + timedelta(days=days)).strftime('%Y-%m-%d')


# ---------- report calculation ---------------------------------------
def _compute_admin_report(conn, item, report_date, keep_kg=False):
    """Report for one item on one day.
    report_date = the day picked on the Admin Report screen (YYYY-MM-DD).
    next_date   = report_date + 1 day; its stock update is the CLOSING stock.
    Flows (purchase, sales, rejections...) are taken on report_date."""
    cur = conn.cursor()
    canon, aliases = _load_item_catalog(cur)
    item_name = _resolve_item(item, canon, aliases) or item
    keys = sorted(_keys_for_item(item_name, aliases))
    placeholders = ','.join('?' * len(keys))
    next_date = _shift_date(report_date, 1)
    is_pcs_item = _is_pcs_item(item_name)

    def flow(table):
        cfg = _REPORT_SOURCES[table]
        cur.execute(
            f"SELECT {cfg['qty']}, {cfg['unit']}, {cfg['pcs']} FROM {table} "
            f"WHERE norm_item(item) IN ({placeholders}) AND {cfg['date_col']} = ?",
            (*keys, report_date),
        )
        kg = pcs = 0.0
        for qty, unit, pcs_val in cur.fetchall():
            kg += _qty_to_kg(qty, unit)
            pcs += _entry_pcs(qty, unit, pcs_val, is_pcs_item)
        return kg, pcs

    def stock(day):
        cols = ', '.join(f'{q}, {u}, {p}' for q, u, p in _STOCK_GRADES)
        cur.execute(
            f"SELECT {cols} FROM stock_updates "
            f"WHERE norm_item(item) IN ({placeholders}) AND date = ?",
            (*keys, day),
        )
        rows = cur.fetchall()
        kg = pcs = 0.0
        for row in rows:
            for i in range(0, len(_STOCK_GRADES) * 3, 3):
                qty, unit, pcs_val = row[i:i + 3]
                kg += _qty_to_kg(qty, unit)
                pcs += _entry_pcs(qty, unit, pcs_val, is_pcs_item)
        return kg, pcs, len(rows) > 0

    stock_today, stock_today_pcs, _ = stock(report_date)
    stock_next_day, stock_next_day_pcs, has_closing_stock = stock(next_date)
    purchase_received, purchase_received_pcs = flow('purchases')
    rejection_received, rejection_received_pcs = flow('rejection_received')
    vendor_rejection, vendor_rejection_pcs = flow('vendor_rejections')
    sales_qty, sales_pcs = flow('sales')
    dump_sale_qty, dump_sale_pcs = flow('dump_sales')
    mandi_resale_qty, mandi_resale_pcs = flow('mandi_resales')
    b_grade_sales_qty, b_grade_sales_pcs = flow('b_grade_sales')

    total_quantity = stock_today + purchase_received + rejection_received - vendor_rejection
    total_sales = sales_qty + dump_sale_qty + mandi_resale_qty + b_grade_sales_qty
    check_stock = total_quantity - total_sales - stock_next_day

    total_quantity_pcs = stock_today_pcs + purchase_received_pcs + rejection_received_pcs - vendor_rejection_pcs
    total_sales_pcs = sales_pcs + dump_sale_pcs + mandi_resale_pcs + b_grade_sales_pcs
    check_stock_pcs = total_quantity_pcs - total_sales_pcs - stock_next_day_pcs

    kg_values = {
        'stock_today': stock_today, 'stock_next_day': stock_next_day,
        'purchase_received': purchase_received, 'rejection_received': rejection_received,
        'vendor_rejection': vendor_rejection, 'sales': sales_qty, 'dump_sale': dump_sale_qty,
        'mandi_resale': mandi_resale_qty, 'b_grade_sales': b_grade_sales_qty,
        'total_quantity': total_quantity, 'total_sales': total_sales, 'check_stock': check_stock,
    }
    pcs_values = {
        'stock_today_pcs': stock_today_pcs, 'stock_next_day_pcs': stock_next_day_pcs,
        'purchase_received_pcs': purchase_received_pcs, 'rejection_received_pcs': rejection_received_pcs,
        'vendor_rejection_pcs': vendor_rejection_pcs, 'sales_pcs': sales_pcs,
        'dump_sale_pcs': dump_sale_pcs, 'mandi_resale_pcs': mandi_resale_pcs,
        'b_grade_sales_pcs': b_grade_sales_pcs, 'total_quantity_pcs': total_quantity_pcs,
        'total_sales_pcs': total_sales_pcs, 'check_stock_pcs': check_stock_pcs,
    }
    kg_values = {k: round(v, 3) for k, v in kg_values.items()}
    pcs_values = {k: round(v, 3) for k, v in pcs_values.items()}

    # Papaya / pineapple are reported in pcs: kg columns are blanked (as before)
    # so the screen shows the pcs columns.
    if is_pcs_item and not keep_kg:
        kg_values = {k: 0 for k in kg_values}

    row = {
        'date': report_date,      # the picked date, always 'YYYY-MM-DD'
        'iteam': item_name,       # key name kept: the app reads 'iteam'
        'item': item_name,
        'is_pcs_item': is_pcs_item,
        'unit': 'pcs' if is_pcs_item else 'kg',
        'has_closing_stock': has_closing_stock,
    }
    row.update(kg_values)
    row.update(pcs_values)
    return row


def _report_values_to_save(row):
    """Values stored in admin_report: pcs for papaya/pineapple, kg for the rest."""
    suffix = '_pcs' if row['is_pcs_item'] else ''
    return {f: row[f + suffix] for f in _REPORT_FIELDS}


def _upsert_admin_report(conn, row):
    """Insert or update the saved report for (item, date). Returns (id, created)."""
    cur = conn.cursor()
    _, aliases = _load_item_catalog(cur)
    keys = sorted(_keys_for_item(row['item'], aliases))
    placeholders = ','.join('?' * len(keys))
    cur.execute(
        f'SELECT id FROM admin_report WHERE date = ? AND norm_item(item) IN ({placeholders}) ORDER BY id',
        (row['date'], *keys),
    )
    ids = [r[0] for r in cur.fetchall()]
    values = _report_values_to_save(row)
    cols = ', '.join(f'{f} = ?' for f in _REPORT_FIELDS)
    if ids:
        cur.execute(
            f'UPDATE admin_report SET item = ?, {cols} WHERE id = ?',
            (row['item'], *[values[f] for f in _REPORT_FIELDS], ids[0]),
        )
        if len(ids) > 1:  # remove duplicates of the same item + date
            cur.execute(
                f"DELETE FROM admin_report WHERE id IN ({','.join('?' * (len(ids) - 1))})",
                ids[1:],
            )
        return ids[0], False
    cur.execute(
        f"INSERT INTO admin_report (date, item, {', '.join(_REPORT_FIELDS)}) "
        f"VALUES (?, ?, {', '.join('?' * len(_REPORT_FIELDS))})",
        (row['date'], row['item'], *[values[f] for f in _REPORT_FIELDS]),
    )
    return cur.lastrowid, True


def _refresh_report(conn, item_name, report_date):
    """Recalculate a saved report. A missing report is created only when the
    closing stock (stock update of the next day) has been entered."""
    row = _compute_admin_report(conn, item_name, report_date)
    cur = conn.cursor()
    _, aliases = _load_item_catalog(cur)
    keys = sorted(_keys_for_item(row['item'], aliases))
    cur.execute(
        f"SELECT 1 FROM admin_report WHERE date = ? AND norm_item(item) IN ({','.join('?' * len(keys))}) LIMIT 1",
        (report_date, *keys),
    )
    if cur.fetchone() or row['has_closing_stock']:
        _upsert_admin_report(conn, row)


# ---------- automatic refresh ----------------------------------------
# SQLite triggers write every change of a report source table into
# report_refresh_queue (whatever route made the change). After each
# write request the queue is processed and the affected reports are
# regenerated / updated.
def _process_report_queue(timeout=30):
    with _REPORT_LOCK:
        conn = _report_conn(timeout=timeout)
        try:
            cur = conn.cursor()
            processed = 0
            while True:
                # lock the database for this batch so two server workers
                # never update the same report at the same time
                cur.execute('BEGIN IMMEDIATE')
                cur.execute('SELECT id, source, item, day FROM report_refresh_queue ORDER BY id LIMIT 2000')
                rows = cur.fetchall()
                if not rows:
                    conn.rollback()
                    break
                canon, aliases = _load_item_catalog(cur)
                targets = set()
                for _id, source, item, day in rows:
                    d = _to_iso_date(day)
                    item_name = _resolve_item(item, canon, aliases)
                    if not d or not item_name:
                        continue  # not an item from the Admin item list
                    targets.add((item_name, d))
                    if source == 'stock_updates':
                        # this stock is also the closing stock of the previous day
                        targets.add((item_name, _shift_date(d, -1)))
                for item_name, d in sorted(targets):
                    _refresh_report(conn, item_name, d)
                cur.execute('DELETE FROM report_refresh_queue WHERE id <= ?', (rows[-1][0],))
                conn.commit()
                processed += len(targets)
            return processed
        finally:
            conn.close()


def _process_report_queue_safe(timeout=10):
    try:
        _process_report_queue(timeout=timeout)
    except Exception as e:  # never break the main request
        print(f'⚠️ [admin_report] auto refresh failed: {e}')


def _create_report_triggers(cursor):
    sources = {t: (c['date_col'], [c['qty'], c['unit'], c['pcs']]) for t, c in _REPORT_SOURCES.items()}
    sources['stock_updates'] = ('date', [c for g in _STOCK_GRADES for c in g])
    for table, (date_col, value_cols) in sources.items():
        watched = ', '.join(['item', date_col] + value_cols)
        try:
            for suffix in ('ins', 'upd', 'del'):
                cursor.execute(f'DROP TRIGGER IF EXISTS trg_report_{table}_{suffix}')
            cursor.execute(f"""
                CREATE TRIGGER trg_report_{table}_ins AFTER INSERT ON {table}
                BEGIN
                    INSERT INTO report_refresh_queue (source, item, day) VALUES ('{table}', NEW.item, NEW.{date_col});
                END""")
            cursor.execute(f"""
                CREATE TRIGGER trg_report_{table}_upd AFTER UPDATE OF {watched} ON {table}
                BEGIN
                    INSERT INTO report_refresh_queue (source, item, day) VALUES ('{table}', OLD.item, OLD.{date_col});
                    INSERT INTO report_refresh_queue (source, item, day) VALUES ('{table}', NEW.item, NEW.{date_col});
                END""")
            cursor.execute(f"""
                CREATE TRIGGER trg_report_{table}_del AFTER DELETE ON {table}
                BEGIN
                    INSERT INTO report_refresh_queue (source, item, day) VALUES ('{table}', OLD.item, OLD.{date_col});
                END""")
        except sqlite3.OperationalError as e:
            print(f'⚠️ [admin_report] could not create triggers on {table}: {e}')


def _setup_report_automation():
    """Creates the helper tables + triggers, repairs old saved reports and,
    once, generates reports for all past days that have a closing stock."""
    with _REPORT_LOCK:
        conn = _report_conn()
        try:
            cur = conn.cursor()
            cur.execute('''CREATE TABLE IF NOT EXISTS item_aliases (
                alias_key TEXT PRIMARY KEY,
                alias_name TEXT,
                item_name TEXT NOT NULL,
                created_at TEXT)''')
            cur.execute('''CREATE TABLE IF NOT EXISTS report_refresh_queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source TEXT, item TEXT, day TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP)''')
            cur.execute('CREATE TABLE IF NOT EXISTS app_meta (key TEXT PRIMARY KEY, value TEXT)')
            _create_report_triggers(cur)

            # Repair dates saved as 'Tue, 29 Sep 2026 00:00:00 GMT' by the old code.
            cur.execute('SELECT id, date FROM admin_report')
            for rid, d in cur.fetchall():
                iso = _to_iso_date(d)
                if iso and iso != d:
                    cur.execute('UPDATE admin_report SET date = ? WHERE id = ?', (iso, rid))

            cur.execute("SELECT value FROM app_meta WHERE key = 'admin_report_backfill_v1'")
            if not cur.fetchone():
                # Recalculate every saved report and create the missing ones.
                cur.execute("INSERT INTO report_refresh_queue (source, item, day) SELECT 'admin_report', item, date FROM admin_report")
                cur.execute("INSERT INTO report_refresh_queue (source, item, day) SELECT 'stock_updates', item, date FROM stock_updates")
                cur.execute("INSERT OR REPLACE INTO app_meta (key, value) VALUES ('admin_report_backfill_v1', ?)",
                            (datetime.now().isoformat(timespec='seconds'),))
            conn.commit()
        finally:
            conn.close()
    _process_report_queue()


@app.after_request
def _refresh_reports_after_write(response):
    if request.method in ('POST', 'PUT', 'PATCH', 'DELETE'):
        _process_report_queue_safe()
    return response


# ---------- routes ----------------------------------------------------
@app.route('/get_admin_report_rows', methods=['GET'])
def get_admin_report_rows():
    """AdminReport row for selected item and date.
    Returns both KG and PCS calculations.
    The app sends the picked date as `chosen_date` (query parameter name kept
    unchanged). Inside, that date is `report_date`; the closing-stock day is
    `next_date` = report_date + 1."""
    item = request.args.get('item')
    picked = request.args.get('chosen_date')

    if not item or not picked:
        return jsonify({'error': 'item and chosen_date are required'}), 400

    try:
        report_date = datetime.strptime(picked.strip(), '%Y-%m-%d').strftime('%Y-%m-%d')
    except ValueError:
        return jsonify({'error': 'chosen_date must be yyyy-MM-dd'}), 400

    _process_report_queue_safe()
    conn = _report_conn()
    try:
        row = _compute_admin_report(conn, item, report_date)
    finally:
        conn.close()
    return jsonify({'data': [row]})


def _check_admin_key(key):
    conn = get_db()
    try:
        cur = conn.cursor()
        cur.execute('SELECT password_hash FROM section_groups WHERE group_name = ?', ('admin',))
        result = cur.fetchone()
    finally:
        conn.close()
    return bool(result) and result[0] == (key or '')


@app.route('/get_item_spelling_issues', methods=['GET'])
def get_item_spelling_issues():
    """Item names used in entries (stock update, purchase, sales ...) that are
    not written exactly as in the Admin item list.
    status: 'auto_matched' -> differs only in capitals/spaces, already counted in the report
            'converted'    -> mapped earlier with /convert_item_spelling
            'unmatched'    -> NOT counted in any report until converted
    ?only_unmatched=1 returns just the 'unmatched' ones."""
    only_unmatched = str(request.args.get('only_unmatched', '')).lower() in ('1', 'true', 'yes')
    conn = _report_conn()
    try:
        cur = conn.cursor()
        canon, aliases = _load_item_catalog(cur)
        exact_names = set(canon.values())
        cur.execute('SELECT name FROM items')
        exact_names.update(r[0] for r in cur.fetchall())
        found = {}
        for table in _ITEM_TABLES:
            cur.execute(f"SELECT item, COUNT(*) FROM {table} WHERE item IS NOT NULL AND TRIM(item) != '' GROUP BY item")
            for name, cnt in cur.fetchall():
                if name in exact_names:
                    continue
                entry = found.setdefault(name, {'name': name, 'tables': {}, 'total_rows': 0})
                entry['tables'][table] = cnt
                entry['total_rows'] += cnt
        issues = []
        for name, entry in found.items():
            k = _norm_item(name)
            if k in canon:
                entry['status'], entry['matched_item'] = 'auto_matched', canon[k]
            elif k in aliases and _norm_item(aliases[k]) in canon:
                entry['status'], entry['matched_item'] = 'converted', canon[_norm_item(aliases[k])]
            else:
                entry['status'], entry['matched_item'] = 'unmatched', None
            entry['suggestions'] = [canon[s] for s in _difflib.get_close_matches(k, list(canon.keys()), n=3, cutoff=0.6)]
            if not only_unmatched or entry['status'] == 'unmatched':
                issues.append(entry)
        issues.sort(key=lambda e: ({'unmatched': 0, 'converted': 1, 'auto_matched': 2}[e['status']], -e['total_rows']))
        return jsonify({'success': True, 'count': len(issues), 'data': issues})
    finally:
        conn.close()


@app.route('/get_item_aliases', methods=['GET'])
def get_item_aliases():
    conn = get_db()
    try:
        cur = conn.cursor()
        cur.execute('SELECT alias_name, item_name, created_at FROM item_aliases ORDER BY item_name, alias_name')
        data = [{'alias': a, 'item': i, 'created_at': c} for a, i, c in cur.fetchall()]
        return jsonify({'success': True, 'data': data})
    finally:
        conn.close()


@app.route('/convert_item_spelling', methods=['POST'])
def convert_item_spelling():
    """Convert a different spelling to the item name in the Admin item list.
    JSON: {"from_name": "tori", "to_item": "Torai", "admin_key": "<admin password>",
           "rename_existing": true}
    * remembers the spelling, so future entries written this way are counted
      under the correct item in the report;
    * rename_existing (default true) also rewrites existing entries in stock
      update, purchase, sales, B-grade sales, dump sale, mandi resale,
      rejection received and vendor rejection to the correct name.
    Affected reports are regenerated automatically."""
    data = request.get_json(silent=True) or {}
    from_name = (data.get('from_name') or '').strip()
    to_item = (data.get('to_item') or '').strip()
    rename_existing = data.get('rename_existing', True) not in (False, 'false', 0, '0')

    if not _check_admin_key(data.get('admin_key') or request.args.get('admin_key')):
        return jsonify({'success': False, 'message': 'Invalid admin password'}), 403
    if not from_name or not to_item:
        return jsonify({'success': False, 'message': 'from_name and to_item are required'}), 400

    with _REPORT_LOCK:
        conn = _report_conn()
        try:
            cur = conn.cursor()
            canon, _ = _load_item_catalog(cur)
            target = canon.get(_norm_item(to_item))
            if not target:
                return jsonify({'success': False, 'message': f"'{to_item}' is not in the Admin item list"}), 400
            from_key = _norm_item(from_name)
            if from_key in canon and from_key != _norm_item(target):
                return jsonify({'success': False,
                                'message': f"'{from_name}' is itself an item in the Admin item list; remove it from the list first"}), 400

            if from_key != _norm_item(target):
                cur.execute(
                    'INSERT OR REPLACE INTO item_aliases (alias_key, alias_name, item_name, created_at) VALUES (?, ?, ?, ?)',
                    (from_key, from_name, target, datetime.now().isoformat(timespec='seconds')),
                )

            renamed = {}
            if rename_existing:
                for table in _ITEM_TABLES:
                    cur.execute(
                        f'UPDATE {table} SET item = ? WHERE norm_item(item) = ? AND item != ?',
                        (target, from_key, target),
                    )
                    if cur.rowcount:
                        renamed[table] = cur.rowcount
                # saved reports written with the old spelling
                cur.execute('SELECT id, date FROM admin_report WHERE norm_item(item) = ? AND item != ?', (from_key, target))
                for rid, d in cur.fetchall():
                    cur.execute("INSERT INTO report_refresh_queue (source, item, day) VALUES ('admin_report', ?, ?)", (target, d))
                    cur.execute('UPDATE admin_report SET item = ? WHERE id = ?', (target, rid))

            # spelling only remembered (no rename): refresh reports of the entries using it
            for table in _ITEM_TABLES:
                date_col = _REPORT_SOURCES[table]['date_col'] if table in _REPORT_SOURCES else 'date'
                cur.execute(
                    f"INSERT INTO report_refresh_queue (source, item, day) "
                    f"SELECT '{table}', ?, {date_col} FROM {table} WHERE norm_item(item) = ? GROUP BY {date_col}",
                    (target, from_key),
                )
            conn.commit()
        finally:
            conn.close()

    _process_report_queue_safe()
    return jsonify({
        'success': True,
        'message': f"'{from_name}' is now counted as '{target}'",
        'item': target,
        'renamed_rows': renamed,
    })


@app.route('/delete_item_alias', methods=['DELETE', 'POST'])
def delete_item_alias():
    """Forget a remembered spelling. JSON: {"alias": "tori", "admin_key": "..."}"""
    data = request.get_json(silent=True) or {}
    if not _check_admin_key(data.get('admin_key') or request.args.get('admin_key')):
        return jsonify({'success': False, 'message': 'Invalid admin password'}), 403
    alias = data.get('alias') or request.args.get('alias')
    if not alias:
        return jsonify({'success': False, 'message': 'alias is required'}), 400
    conn = _report_conn()
    try:
        cur = conn.cursor()
        cur.execute('SELECT item_name FROM item_aliases WHERE alias_key = ?', (_norm_item(alias),))
        r = cur.fetchone()
        if not r:
            return jsonify({'success': False, 'message': 'Spelling not found'}), 404
        cur.execute('DELETE FROM item_aliases WHERE alias_key = ?', (_norm_item(alias),))
        # refresh the reports of the item it pointed to
        cur.execute("INSERT INTO report_refresh_queue (source, item, day) SELECT 'admin_report', item, date FROM admin_report WHERE norm_item(item) = ?",
                    (_norm_item(r[0]),))
        conn.commit()
    finally:
        conn.close()
    _process_report_queue_safe()
    return jsonify({'success': True, 'message': 'Spelling removed'})






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


    amount_paid = safe_float(row.get('amount_paid'))

    rate = safe_float(row.get('rate'))
    qty_accept = safe_float(row.get('qty_accept'))

    amount_of_accepted = _accept_amount(row, rate)  # accepted qty converted into the PO unit

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
    total_amount, amount_due = _apply_purchase_extras(cursor, purchase_id, row)

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

    amount_of_accepted = _accept_amount(data, rate)  # accepted qty converted into the PO unit

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
    if affected:
        _apply_purchase_extras(cursor, record_id, data)

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

# @app.route('/update_sale', methods=['PUT'])
# def update_sale():
#     data = request.json['data']
#     # id = data['id']
#     affected = 0
#     id = data['id']
#     conn = get_db()
#     cursor = conn.cursor()
#     cursor.execute('''
#         UPDATE sales SET 
#             item=?, clint=?, po_number=?, quantity=?, unit=?, pcs=?, 
#             date=?, time=?, item_tag=?, payment_status=?, mode_of_payment=?, 
#             amount_paid=?, amount_due=?, rate=?, total_value=? 
#         WHERE id=?
#     ''', (
#         data.get('item'), data.get('clint'), data.get('po_number'), data.get('quantity'), data.get('unit'), data.get('pcs'),
#         data.get('date'), data.get('time'), data.get('item_tag'), data.get('payment_status'), data.get('mode_of_payment'),
#         data.get('amount_paid'), data.get('amount_due'), data.get('rate'), data.get('total_value'),
#         id
#     ))
#     affected = cursor.rowcount
#     print(f"Updated {affected} rows in sales id={id}")
#     conn.commit()
#     conn.close()
#     return jsonify({'success': True})


@app.route('/update_sale', methods=['PUT'])
def update_sale():
    data = request.get_json()

    if not data:
        return jsonify({
            'success': False,
            'message': 'No JSON data received'
        }), 400

    id = data.get('id')

    if id is None:
        return jsonify({
            'success': False,
            'message': 'Missing id'
        }), 400

    conn = get_db()
    cursor = conn.cursor()

    try:
        cursor.execute('''
            UPDATE sales SET 
                item=?,
                clint=?,
                po_number=?,
                quantity=?,
                unit=?,
                pcs=?, 
                date=?,
                time=?,
                item_tag=?,
                payment_status=?,
                mode_of_payment=?, 
                amount_paid=?,
                amount_due=?,
                rate=?,
                total_value=? 
            WHERE id=?
        ''', (
            data.get('item'),
            data.get('clint'),
            data.get('po_number'),
            data.get('quantity'),
            data.get('unit'),
            data.get('pcs'),
            data.get('date'),
            data.get('time'),
            data.get('item_tag'),
            data.get('payment_status'),
            data.get('mode_of_payment'),
            data.get('amount_paid'),
            data.get('amount_due'),
            data.get('rate'),
            data.get('total_value'),
            id
        ))

        affected = cursor.rowcount
        if affected:
            _set_sale_class(cursor, id, data)

        print(f"Updated {affected} rows in sales id={id}")

        conn.commit()

        return jsonify({
            'success': True,
            'affected': affected
        })

    except Exception as e:
        conn.rollback()
        print(f"Error updating sales id={id}: {e}")

        return jsonify({
            'success': False,
            'message': str(e)
        }), 500

    finally:
        conn.close()





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
_setup_report_automation()

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

# @app.route('/get_drivers', methods=['GET'])
# def get_drivers():
#     conn = get_db()
#     cursor = conn.cursor()
#     cursor.execute("""
#         SELECT DISTINCT driver_name FROM lmd_data WHERE driver_name IS NOT NULL AND TRIM(driver_name) != ''
#         UNION 
#         SELECT DISTINCT driver_name FROM fmd_data WHERE driver_name IS NOT NULL AND TRIM(driver_name) != ''
#         ORDER BY driver_name COLLATE NOCASE
#     """)
#     results = [row[0] for row in cursor.fetchall()]
#     conn.close()
#     return jsonify(results)

# @app.route('/get_vehicles', methods=['GET'])
# def get_vehicles():
#     conn = get_db()
#     cursor = conn.cursor()
#     cursor.execute("""
#         SELECT DISTINCT vehicle_number FROM lmd_data WHERE vehicle_number IS NOT NULL AND TRIM(vehicle_number) != ''
#         UNION 
#         SELECT DISTINCT vehicle_number FROM fmd_data WHERE vehicle_number IS NOT NULL AND TRIM(vehicle_number) != ''
#         ORDER BY vehicle_number COLLATE NOCASE
#     """)
#     results = [row[0] for row in cursor.fetchall()]
#     conn.close()
#     return jsonify(results)


@app.route('/get_drivers_vehicles', methods=['GET'])
def get_drivers_vehicles():
    conn = get_db()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT DISTINCT driver_name, vehicle_number
        FROM (
            SELECT driver_name, vehicle_number
            FROM lmd_data

            UNION

            SELECT driver_name, vehicle_number
            FROM fmd_data
        )
        WHERE driver_name IS NOT NULL
          AND TRIM(driver_name) != ''
          AND vehicle_number IS NOT NULL
          AND TRIM(vehicle_number) != ''
        ORDER BY driver_name COLLATE NOCASE,
                 vehicle_number COLLATE NOCASE
    """)

    results = [
        {
            "driver_name": row[0],
            "vehicle_number": row[1]
        }
        for row in cursor.fetchall()
    ]

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
    """Get all section groups for passwords tab.

    NOTE: Never expose password_hash to clients. We only return metadata so the
    admin Passwords tab can render a proper status without leaking secrets.
    """
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute(
        'SELECT group_name, created_at, updated_at FROM section_groups ORDER BY group_name'
    )
    rows = cursor.fetchall()
    conn.close()
    results = []
    for row in rows:
        item = dict(row)
        item['status'] = 'Active' if item.get('updated_at') or item.get('created_at') else 'Unknown'
        results.append(item)
    return jsonify(results)


@app.route('/get_admin_stats', methods=['GET'])
def get_admin_stats():
    """Aggregate row counts + basic health info for the Admin dashboard overview."""
    tables = [
        'purchases', 'packaging_materials', 'sales', 'stock_updates',
        'lmd_data', 'fmd_data', 'generated_pos', 'generated_sos',
        'rejection_received', 'vendor_rejections', 'dump_sales',
        'mandi_resales', 'b_grade_sales', 'items', 'vendors',
        'purchase_vendors', 'b_grade_clients', 'product_managers',
        'admin_report', 'gate_entries',
    ]
    conn = get_db()
    cursor = conn.cursor()
    stats = {}
    total = 0
    for table in tables:
        try:
            cursor.execute(f'SELECT COUNT(*) FROM {table}')
            count = cursor.fetchone()[0]
        except sqlite3.OperationalError:
            count = 0
        stats[table] = count
        total += count
    conn.close()
    return jsonify({
        'success': True,
        'generated_at': datetime.now().isoformat(),
        'total_records': total,
        'tables': stats,
    })

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
    """Save the report for (item, date). Values are recalculated on the server
    from the entries (so they always match the data; pcs for papaya/pineapple).
    If the report already exists (e.g. it was generated automatically), it is
    updated instead of rejected."""
    row = request.get_json(silent=True) or {}
    item = row.get('item') or row.get('iteam')
    report_date = _to_iso_date(row.get('date'))
    if not item or not report_date:
        return jsonify({'success': False, 'message': 'item and date are required'}), 400

    with _REPORT_LOCK:
        conn = _report_conn()
        try:
            conn.execute('BEGIN IMMEDIATE')
            computed = _compute_admin_report(conn, item, report_date)
            inserted_id, created = _upsert_admin_report(conn, computed)
            conn.commit()
        finally:
            conn.close()
    return jsonify({
        'success': True,
        'id': inserted_id,
        'message': 'Report saved' if created else 'Report updated with latest data',
    })


@app.route('/update_admin_report', methods=['PUT'])
def update_admin_report():
    row = request.get_json(silent=True) or {}
    report_id = row.get('id')

    if not report_id:
        return jsonify({
            'success': False,
            'message': 'Report ID is required'
        }), 400

    conn = get_db()
    cursor = conn.cursor()

    try:
        # Prevent duplicate item + date, except this same report.
        cursor.execute("""
            SELECT id
            FROM admin_report
            WHERE date = ? AND item = ? AND id != ?
        """, (row.get('date'), row.get('item'), report_id))

        if cursor.fetchone():
            return jsonify({
                'success': False,
                'message': 'A report for this item and date already exists'
            }), 409

        cursor.execute("""
            UPDATE admin_report
            SET date = ?,
                item = ?,
                stock_today = ?,
                stock_next_day = ?,
                purchase_received = ?,
                rejection_received = ?,
                vendor_rejection = ?,
                sales = ?,
                dump_sale = ?,
                mandi_resale = ?,
                b_grade_sales = ?,
                total_quantity = ?,
                total_sales = ?,
                check_stock = ?
            WHERE id = ?
        """, (
            row.get('date'),
            row.get('item'),
            row.get('stock_today'),
            row.get('stock_next_day'),
            row.get('purchase_received'),
            row.get('rejection_received'),
            row.get('vendor_rejection'),
            row.get('sales'),
            row.get('dump_sale'),
            row.get('mandi_resale'),
            row.get('b_grade_sales'),
            row.get('total_quantity'),
            row.get('total_sales'),
            row.get('check_stock'),
            report_id
        ))

        if cursor.rowcount == 0:
            return jsonify({
                'success': False,
                'message': 'Report not found'
            }), 404

        conn.commit()

        return jsonify({
            'success': True,
            'message': 'Report updated successfully'
        })

    except Exception as e:
        conn.rollback()
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500

    finally:
        conn.close()


@app.route('/delete_admin_report/<int:report_id>', methods=['DELETE'])
def delete_admin_report(report_id):
    conn = get_db()
    cursor = conn.cursor()

    try:
        cursor.execute(
            "DELETE FROM admin_report WHERE id = ?",
            (report_id,)
        )

        if cursor.rowcount == 0:
            return jsonify({
                'success': False,
                'message': 'Report not found'
            }), 404

        conn.commit()

        return jsonify({
            'success': True,
            'message': 'Report deleted successfully'
        })

    except Exception as e:
        conn.rollback()
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500

    finally:
        conn.close()






@app.route('/get_admin_report', methods=['GET'])
def get_admin_report():
    _process_report_queue_safe()
    page = request.args.get('page', type=int)

    if page is not None:
        # Admin dashboard / report screen: paginated envelope (date + search).
        result = _get_paginated_data(
            'admin_report',
            page,
            request.args.get('limit', 50, type=int),
            start_date=request.args.get('start_date'),
            end_date=request.args.get('end_date'),
            search=request.args.get('search'),
            search_fields=['item', 'date'],
        )
        return jsonify(result)

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




# =====================================================================
# PURCHASE RULES  (PO / purchase entry / packaging entry)
# ---------------------------------------------------------------------
# * Every PO line needs a unit (kg, g, ton, pcs, box, bag) and a rate > 0.
# * A purchase entry (GRN) needs a CTRL date and a PO number that exists,
#   and its item must be on that PO. Its rate is always the PO rate.
# * Packaging items (marked in Admin > Item Settings) can only be entered in
#   Packaging Material Entry; fruit/vegetable items only in Purchase Entry.
# The checks run in a before_request hook, so every screen that writes
# these tables (purchase entry, packaging entry, inventory edit dialog,
# PO screens) gets the same rules.
# =====================================================================
_PO_UNITS = {'kg', 'g', 'ton', 'pcs', 'box', 'bag'}
_WEIGHT_TO_KG = {'g': 0.001, 'kg': 1.0, 'ton': 1000.0}
_COUNT_UNITS = {'pcs': 'pcs', 'pc': 'pcs', 'piece': 'pcs', 'pieces': 'pcs', 'nos': 'pcs', 'no': 'pcs',
                'box': 'box', 'boxes': 'box', 'bag': 'bag', 'bags': 'bag'}


def _unit_family(unit):
    """('weight', factor_to_kg) | ('count', 'pcs'|'box'|'bag') | (None, None)"""
    u = _norm_unit(unit)
    if u in _GRAM_UNITS:
        return 'weight', 0.001
    if u in ('kg', 'kgs', 'kilo', 'kilos', 'kilogram', 'kilograms'):
        return 'weight', 1.0
    if u in ('ton', 'tons', 'tonne', 'tonnes', 't'):
        return 'weight', 1000.0
    if u in _COUNT_UNITS:
        return 'count', _COUNT_UNITS[u]
    return None, None


def _qty_in_po_unit(qty, unit, po_unit):
    """Quantity converted into the PO's unit, or None when the units don't
    match (e.g. PO in box, entry in kg). A blank entry unit is taken as the
    PO unit."""
    q = _num(qty)
    if not str(unit or '').strip():
        return q
    fam, f = _unit_family(unit)
    pfam, pf = _unit_family(po_unit)
    if fam is None or pfam is None or fam != pfam:
        return None
    if fam == 'weight':
        return q * f / pf
    return q if f == pf else None


def _item_settings_map(cursor):
    """{normalized item: {'is_packaging': bool, 'avg_piece_weight_kg': float|None}}"""
    try:
        cursor.execute('SELECT item_key, is_packaging, avg_piece_weight_kg, stock_in_pcs, needs_unit FROM item_settings')
    except sqlite3.OperationalError:
        try:
            cursor.execute('SELECT item_key, is_packaging, avg_piece_weight_kg, NULL, 0 FROM item_settings')
        except sqlite3.OperationalError:
            return {}
    return {k: {'is_packaging': bool(p), 'avg_piece_weight_kg': w,
                'stock_in_pcs': None if sp is None else bool(sp), 'needs_unit': bool(nu)}
            for k, p, w, sp, nu in cursor.fetchall()}


# ---------- daily average weight per piece (papaya / pineapple) ----------
def _daily_weights_upto(cur, date):
    """{item_key: weight} - latest daily weight entered on or before `date`."""
    try:
        cur.execute('SELECT item_key, avg_piece_weight_kg FROM item_daily_weights WHERE date <= ? ORDER BY date', (date,))
    except sqlite3.OperationalError:
        return {}
    out = {}
    for k, w in cur.fetchall():
        if w:
            out[k] = w
    return out


def _settings_on(cur, date, base=None):
    """Item settings where the piece weight is the one valid on `date`
    (daily weight entered that day or the latest before it; else the default in Item Settings)."""
    base = base if base is not None else _item_settings_map(cur)
    out = {k: dict(v) for k, v in base.items()}
    for k, w in _daily_weights_upto(cur, date).items():
        out.setdefault(k, {'is_packaging': False, 'avg_piece_weight_kg': None})['avg_piece_weight_kg'] = w
    return out


def _weight_on(cur, item, date, settings=None):
    k = _norm_item(item)
    if date:
        try:
            cur.execute('SELECT avg_piece_weight_kg FROM item_daily_weights WHERE item_key = ? AND date <= ? '
                        'AND avg_piece_weight_kg > 0 ORDER BY date DESC LIMIT 1', (k, str(date)[:10]))
            r = cur.fetchone()
            if r:
                return r[0]
        except sqlite3.OperationalError:
            pass
    base = settings if settings is not None else _item_settings_map(cur)
    return base.get(k, {}).get('avg_piece_weight_kg')


def _is_packaging_item(cursor, item):
    s = _item_settings_map(cursor).get(_norm_item(item))
    return bool(s and s['is_packaging'])


def _find_po_line(cursor, po_number, item):
    """PO line (dict) for po_number + item (spelling-insensitive), or None."""
    cursor.execute(
        'SELECT id, po_number, item_name, vendor_name, rate, unit, qty_ordered, expected_date '
        'FROM generated_pos WHERE TRIM(po_number) = TRIM(?)',
        (str(po_number or ''),),
    )
    rows = cursor.fetchall()
    canon, aliases = _load_item_catalog(cursor)
    key = _norm_item(item)
    target = _resolve_item(item, canon, aliases)
    for r in rows:
        if _norm_item(r[2]) == key or (target and _resolve_item(r[2], canon, aliases) == target):
            return {'id': r[0], 'po_number': r[1], 'item_name': r[2], 'vendor_name': r[3],
                    'rate': _num(r[4]), 'unit': r[5], 'qty_ordered': r[6], 'expected_date': r[7]}
    return {'po_exists': bool(rows)}


def _validate_po_payload(row):
    unit = _norm_unit(row.get('unit'))
    if unit not in _PO_UNITS:
        return f"Unit is required for every PO item (kg, g, ton, pcs, box or bag). Got '{row.get('unit') or ''}'."
    if _num(row.get('rate')) <= 0:
        return 'Rate is required for every PO item and must be more than 0.'
    if 'expected_date' in row and not _to_iso_date(row.get('expected_date')):
        return 'Expected date is required for every PO item.'
    for f in ('item_name', 'po_number', 'vendor_name'):
        if f in row and not str(row.get(f) or '').strip():
            return f"{f.replace('_', ' ').capitalize()} is required."
    row['unit'] = unit
    return None


def _validate_receipt_payload(cursor, row, kind):
    """kind = 'produce' (purchases) or 'packaging' (packaging_materials).
    Checks the entry and sets row['rate'] to the PO rate. Returns error text or None."""
    ctrl = _to_iso_date(row.get('ctrl_date'))
    if not ctrl:
        return 'CTRL date is required.'
    row['ctrl_date'] = ctrl
    item = str(row.get('item') or '').strip()
    po_number = str(row.get('po_number') or '').strip()
    if not item:
        return 'Item is required.'
    if not po_number:
        return 'PO number is required. Select the PO this material was received against.'
    po = _find_po_line(cursor, po_number, item)
    if 'rate' not in po:
        if not po.get('po_exists'):
            return f"PO number '{po_number}' does not exist."
        return f"'{item}' is not on PO {po_number}."
    is_pack = _is_packaging_item(cursor, po['item_name'])
    if kind == 'produce' and is_pack:
        return f"'{po['item_name']}' is a packaging item. Enter it in Packaging Material Entry."
    if kind == 'packaging' and not is_pack:
        return (f"'{po['item_name']}' is not marked as a packaging item. "
                'Mark it in Admin > Item Settings, or enter it in Purchase Entry.')
    if po['rate'] <= 0:
        return f"PO {po_number} has no rate for '{po['item_name']}'. Correct the PO first."
    if _norm_unit(po['unit']) not in _PO_UNITS:
        return f"PO {po_number} has no unit for '{po['item_name']}'. Correct the PO first."
    for qty_f, unit_f, label in (('qty_receive', 'unit_receive', 'received'),
                                 ('qty_accept', 'unit_accept', 'accepted'),
                                 ('qty_reject', 'unit_reject', 'rejected')):
        if row.get(qty_f) not in (None, '') and _num(row.get(qty_f)) != 0:
            if _qty_in_po_unit(row.get(qty_f), row.get(unit_f), po['unit']) is None:
                return (f"PO {po_number} is in '{po['unit']}', but the {label} quantity is in "
                        f"'{row.get(unit_f)}'. Enter it in {po['unit']}"
                        f"{' (or g)' if _unit_family(po['unit'])[0] == 'weight' else ''}.")
    if _num(row.get('qty_receive')) <= 0:
        return 'Quantity received is required.'
    row['item'] = po['item_name']
    row['rate'] = po['rate']  # rate always comes from the PO
    if kind == 'packaging':
        accepted = row.get('qty_accept')
        use_qty, use_unit = (accepted, row.get('unit_accept')) if _num(accepted) > 0 else (row.get('qty_receive'), row.get('unit_receive'))
        row['total_value'] = round((_qty_in_po_unit(use_qty, use_unit, po['unit']) or 0) * po['rate'], 2)
        row['amount_due'] = round(row['total_value'] - _num(row.get('amount_paid')), 2)
    return None


@app.before_request
def _enforce_purchase_rules():
    ep = request.path.rstrip('/')
    if request.method not in ('POST', 'PUT'):
        return None
    if ep not in ('/insert_generated_po', '/update_po_item', '/insert_purchase', '/update_purchase',
                  '/insert_packaging_material', '/update_packaging_material'):
        return None
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return None
    row = payload.get('data') if ep == '/update_purchase' and isinstance(payload.get('data'), dict) else payload
    if ep in ('/insert_generated_po', '/update_po_item'):
        err = _validate_po_payload(row)
    else:
        conn = _report_conn()
        try:
            kind = 'packaging' if 'packaging' in ep else 'produce'
            err = _validate_receipt_payload(conn.cursor(), row, kind)
        finally:
            conn.close()
    if err:
        return jsonify({'success': False, 'error': err, 'message': err}), 400
    return None


def _accept_amount(row, rate):
    """rate x accepted quantity (converted into the PO unit)."""
    conn = _report_conn()
    try:
        po = _find_po_line(conn.cursor(), row.get('po_number'), row.get('item'))
    finally:
        conn.close()
    qty = row.get('qty_accept')
    if 'unit' in po:
        q = _qty_in_po_unit(qty, row.get('unit_accept'), po['unit'])
        if q is not None:
            return rate * q
    return rate * _num(qty)


# ---------- PO lines for the purchase / packaging entry screens ----------
@app.route('/get_pos_for_entry', methods=['GET'])
def get_pos_for_entry():
    """PO lines a purchase (kind=produce) or packaging (kind=packaging) entry
    can be made against, for a CTRL date.
    Lines whose expected date = CTRL date have date_match = true.
    include_other_dates=1 also returns lines expected 15 days before to
    7 days after the CTRL date (date_match = false) for late/early deliveries."""
    ctrl = _to_iso_date(request.args.get('ctrl_date'))
    if not ctrl:
        return jsonify({'error': 'ctrl_date (yyyy-MM-dd) is required'}), 400
    kind = request.args.get('kind', 'produce')
    other = str(request.args.get('include_other_dates', '')).lower() in ('1', 'true', 'yes')
    lo, hi = (_shift_date(ctrl, -15), _shift_date(ctrl, 7)) if other else (ctrl, ctrl)
    conn = _report_conn()
    try:
        cur = conn.cursor()
        settings = _item_settings_map(cur)
        cur.execute(
            'SELECT po_number, item_name, vendor_name, rate, unit, qty_ordered, expected_date '
            'FROM generated_pos WHERE expected_date BETWEEN ? AND ? ORDER BY expected_date, po_number',
            (lo, hi),
        )
        lines = []
        for po_number, item, vendor, rate, unit, qty, exp in cur.fetchall():
            is_pack = bool(settings.get(_norm_item(item), {}).get('is_packaging'))
            if (kind == 'packaging') != is_pack:
                continue
            table = 'packaging_materials' if kind == 'packaging' else 'purchases'
            cur.execute(
                f'SELECT qty_receive, unit_receive FROM {table} WHERE TRIM(po_number) = TRIM(?) AND norm_item(item) = ?',
                (po_number, _norm_item(item)),
            )
            received = sum((_qty_in_po_unit(q, u, unit) or 0) for q, u in cur.fetchall())
            problem = None
            if _num(rate) <= 0:
                problem = 'PO has no rate - correct the PO first'
            elif _norm_unit(unit) not in _PO_UNITS:
                problem = 'PO has no unit - correct the PO first'
            lines.append({
                'po_number': po_number, 'item_name': item, 'vendor_name': vendor,
                'rate': _num(rate), 'unit': unit, 'qty_ordered': _num(qty),
                'received_so_far': round(received, 3), 'expected_date': exp,
                'date_match': exp == ctrl, 'problem': problem,
            })
        return jsonify({'ctrl_date': ctrl, 'kind': kind, 'data': lines})
    finally:
        conn.close()


# ---------- item settings: packaging flag + average piece weight ----------
@app.route('/get_item_settings', methods=['GET'])
def get_item_settings():
    conn = _report_conn()
    try:
        cur = conn.cursor()
        canon, _ = _load_item_catalog(cur)
        settings = _item_settings_map(cur)
        data = []
        for key, name in sorted(canon.items(), key=lambda kv: kv[1].lower()):
            s = settings.get(key, {})
            data.append({
                'item': name,
                'is_packaging': bool(s.get('is_packaging')),
                'avg_piece_weight_kg': s.get('avg_piece_weight_kg'),
                'is_pcs_item': _is_pcs_item(name),
                'stock_in_pcs': s.get('stock_in_pcs'),
                'needs_unit': bool(s.get('needs_unit')) and s.get('stock_in_pcs') is None,
            })
        return jsonify({'success': True, 'data': data})
    finally:
        conn.close()


@app.route('/update_item_settings', methods=['POST'])
def update_item_settings():
    """JSON: {"item": "Papaya Box", "is_packaging": true, "avg_piece_weight_kg": 1.2, "admin_key": "..."}"""
    data = request.get_json(silent=True) or {}
    if not _check_admin_key(data.get('admin_key')):
        return jsonify({'success': False, 'message': 'Invalid admin password'}), 403
    item = str(data.get('item') or '').strip()
    if not item:
        return jsonify({'success': False, 'message': 'item is required'}), 400
    conn = _report_conn()
    try:
        cur = conn.cursor()
        canon, aliases = _load_item_catalog(cur)
        name = _resolve_item(item, canon, aliases)
        if not name:
            return jsonify({'success': False, 'message': f"'{item}' is not in the Admin item list"}), 400
        cur.execute('SELECT is_packaging, avg_piece_weight_kg, stock_in_pcs, needs_unit FROM item_settings WHERE item_key = ?', (_norm_item(name),))
        old = cur.fetchone() or (0, None, None, 0)
        stock_in_pcs, needs_unit = old[2], old[3]
        if 'stock_in_pcs' in data:
            stock_in_pcs = 1 if data.get('stock_in_pcs') in (True, 1, '1', 'true') else 0
            needs_unit = 0
        is_pack = old[0] if 'is_packaging' not in data else (1 if data.get('is_packaging') in (True, 1, '1', 'true') else 0)
        weight = old[1]
        if 'avg_piece_weight_kg' in data:
            w = data.get('avg_piece_weight_kg')
            weight = None if w in (None, '') else _num(w)
            if weight is not None and weight <= 0:
                return jsonify({'success': False, 'message': 'Average weight must be more than 0'}), 400
        cur.execute(
            'INSERT OR REPLACE INTO item_settings (item_key, item_name, is_packaging, avg_piece_weight_kg, stock_in_pcs, needs_unit, updated_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            (_norm_item(name), name, is_pack, weight, stock_in_pcs, needs_unit, datetime.now().isoformat(timespec='seconds')),
        )
        if 'stock_in_pcs' in data and old[2] != stock_in_pcs:
            # kg <-> pieces changed: recalculate this item's saved Admin Reports
            cur.execute("INSERT INTO report_refresh_queue (source, item, day) SELECT 'admin_report', item, date FROM admin_report "
                        "WHERE norm_item(item) = ?", (_norm_item(name),))
        conn.commit()
        _PCS_CACHE['at'] = 0.0
        _process_report_queue_safe()
        return jsonify({'success': True, 'item': name, 'is_packaging': bool(is_pack), 'avg_piece_weight_kg': weight,
                        'stock_in_pcs': None if stock_in_pcs is None else bool(stock_in_pcs), 'is_pcs_item': _is_pcs_item(name)})
    finally:
        conn.close()


# =====================================================================
# GPM ANALYSIS
# ---------------------------------------------------------------------
# Item-wise GP  = Closing value + Sales - Purchases - Opening value
# Overall GP    = Closing + Sales - Purchases - Opening
#                 - Packaging (optional) - LMD/FMD (optional)
# * Dates are CTRL dates (purchase entries, packaging, LMD/FMD, uploaded
#   sales/purchase reports).
# * Purchases come from the app: accepted x PO rate + low grade x low-grade
#   rate; when accepted/low grade is not entered, WORST CASE = received x
#   PO rate.
# * Sales come from the uploaded Sales Report; product IDs are matched to
#   app items once and remembered.
# * Opening / closing stock = Admin Report (stock today on the start date,
#   stock next day on the end date), valued at the rate of the latest PO
#   received for the item. Vendor returns in the period are taken off the
#   opening stock.
# =====================================================================
def _setup_gpm_tables():
    conn = _report_conn()
    try:
        cur = conn.cursor()
        cur.execute('''CREATE TABLE IF NOT EXISTS item_settings (
            item_key TEXT PRIMARY KEY, item_name TEXT, is_packaging INTEGER DEFAULT 0,
            avg_piece_weight_kg REAL, updated_at TEXT)''')
        cur.execute('''CREATE TABLE IF NOT EXISTS gpm_report_uploads (
            id INTEGER PRIMARY KEY AUTOINCREMENT, report_type TEXT, filename TEXT,
            uploaded_at TEXT, min_date TEXT, max_date TEXT, invoice_rows INTEGER,
            line_rows INTEGER, info_json TEXT)''')
        cur.execute('''CREATE TABLE IF NOT EXISTS gpm_report_invoices (
            id INTEGER PRIMARY KEY AUTOINCREMENT, upload_id INTEGER, report_type TEXT,
            control_date TEXT, date_source TEXT, invoice_no TEXT, party TEXT, amount REAL)''')
        cur.execute('''CREATE TABLE IF NOT EXISTS gpm_report_lines (
            id INTEGER PRIMARY KEY AUTOINCREMENT, upload_id INTEGER, report_type TEXT,
            control_date TEXT, date_source TEXT, invoice_no TEXT, product_key TEXT,
            product_id TEXT, product_name TEXT, qty REAL, amount REAL)''')
        cur.execute('''CREATE TABLE IF NOT EXISTS gpm_product_map (
            product_key TEXT PRIMARY KEY, product_id TEXT, product_name TEXT,
            item_name TEXT, updated_at TEXT)''')
        try:
            cur.execute('ALTER TABLE gpm_report_invoices ADD COLUMN po_number TEXT')
        except sqlite3.OperationalError:
            pass  # column already there
        cur.execute('CREATE INDEX IF NOT EXISTS idx_gpm_lines_date ON gpm_report_lines (report_type, control_date)')
        cur.execute('CREATE INDEX IF NOT EXISTS idx_gpm_inv_date ON gpm_report_invoices (report_type, control_date)')
        conn.commit()
    finally:
        conn.close()


# ---------- reading the uploaded Excel reports ----------
_HDR_HINTS = ('date', 'invoice', 'bill', 'party', 'amount', 'total', 'item', 'product', 'qty',
              'quantity', 'control', 'order', 'customer', 'vendor', 'supplier', 'rate', 'value')


def _hnorm(s):
    return _re.sub(r'\s+', ' ', str(s or '').replace('\n', ' ').strip().lower())


def _pick_col(headers, *groups, exclude=()):
    """First header containing all tokens of a group (groups tried in order)."""
    for tokens in groups:
        tokens = tokens if isinstance(tokens, (list, tuple)) else (tokens,)
        for i, h in enumerate(headers):
            if h and all(t in h for t in tokens) and not any(x in h for x in exclude):
                return i
    return None


def _cell_date(v):
    if v is None or v == '':
        return None
    if isinstance(v, datetime):
        return v.strftime('%Y-%m-%d')
    if hasattr(v, 'strftime'):
        return v.strftime('%Y-%m-%d')
    if isinstance(v, (int, float)) and 20000 < v < 80000:  # Excel serial date
        return (datetime(1899, 12, 30) + timedelta(days=float(v))).strftime('%Y-%m-%d')
    s = str(v).strip()
    for fmt in ('%Y-%m-%d', '%Y/%m/%d', '%d-%m-%Y', '%d/%m/%Y', '%d-%m-%y', '%d/%m/%y', '%d.%m.%Y',
                '%d %b %Y', '%d-%b-%Y', '%d-%b-%y', '%d %B %Y', '%b %d, %Y'):
        for cand in (s, s[:10]):
            try:
                return datetime.strptime(cand, fmt).strftime('%Y-%m-%d')
            except ValueError:
                continue
    return _to_iso_date(s)


def _cell_amount(v):
    if v is None or v == '':
        return None
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).strip()
    neg = s.startswith('(') and s.endswith(')')
    s = _re.sub(r'[^0-9.\-]', '', s)
    try:
        f = float(s)
    except ValueError:
        return None
    return -abs(f) if neg else f


def _read_sheet_rows(ws):
    rows = [list(r) for r in ws.iter_rows(values_only=True)]
    best, best_score = None, 0
    for i, r in enumerate(rows[:15]):
        hs = [_hnorm(c) for c in r]
        score = sum(1 for h in hs if h and len(h) < 60 and any(k in h for k in _HDR_HINTS))
        if score > best_score:
            best, best_score = i, score
    if best is None or best_score < 2:
        return None, []
    headers = [_hnorm(c) for c in rows[best]]
    body = [r for r in rows[best + 1:] if any(c not in (None, '') for c in r)]
    return headers, body


def _po_key(value):
    """'PO-11395' / 'po no 11395' / 11395.0 -> '11395' (for matching PO numbers)."""
    if value is None:
        return ''
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    s = str(value).strip().upper()
    s = _re.sub(r'^(P\.?\s*O\.?|PURCHASE\s*ORDER)(?![A-Z])\s*(NO\.?|NUMBER|#)?[\s#:\-]*', '', s)
    return s.strip()


def _pick_po_col(headers):
    for i, h in enumerate(headers):
        if not h:
            continue
        if _re.search(r'(^|[^a-z])p\.?\s?o\.?([^a-z]|$)', h) or 'purchase order' in h:
            if 'date' not in h:
                return i
    for i, h in enumerate(headers):
        if h and 'order' in h and ('no' in h or 'number' in h or '#' in h) and 'date' not in h:
            return i
    return None


def _parse_report_workbook(data, report_type):
    """Reads a Sales/Purchase Report workbook.
    * invoice-level sheet: date (control date preferred), invoice no, party, total amount
    * item-level sheet: product ID / item, amount (+ invoice no to pick up the
      invoice's control date when the item sheet has no date)"""
    try:
        from openpyxl import load_workbook
    except ImportError:
        raise RuntimeError('The server needs the openpyxl package: pip install openpyxl')
    import io as _io
    wb = load_workbook(_io.BytesIO(data), data_only=True, read_only=True)
    invoices, lines, info = [], [], {'sheets': {}}
    item_sheets = []
    for ws in wb.worksheets:
        headers, body = _read_sheet_rows(ws)
        if not headers:
            continue
        c_ctrl = _pick_col(headers, ('control', 'date'), ('ctrl', 'date'), 'control date')
        c_date = _pick_col(headers, ('invoice', 'date'), ('bill', 'date'), ('order', 'date'), 'date', exclude=('due', 'control', 'ctrl'))
        c_inv = _pick_col(headers, ('invoice', 'no'), ('invoice', 'number'), ('bill', 'no'), ('voucher', 'no'), ('order', 'no'), 'invoice', exclude=('date',))
        c_party = _pick_col(headers, ('party', 'name'), 'party', 'customer', 'supplier', 'vendor')
        c_pid = _pick_col(headers, ('product', 'id'), ('product', 'code'), ('item', 'code'), ('item', 'id'), 'sku')
        c_pname = _pick_col(headers, ('item', 'name'), ('product', 'name'), 'item', 'product', 'description', 'particular',
                            exclude=('code', ' id', 'qty', 'quantity', 'amount', 'rate', 'unit', 'hsn'))
        c_qty = _pick_col(headers, 'quantity', 'qty')
        c_po = _pick_po_col(headers)
        is_item_sheet = c_pid is not None or c_pname is not None
        if is_item_sheet:
            c_amt = _pick_col(headers, ('net', 'amount'), ('total', 'amount'), 'amount', ('total',), 'value',
                              exclude=('tax', 'gst', 'discount', 'rate', 'paid', 'balance', 'due'))
        else:
            c_amt = _pick_col(headers, ('total', 'amount'), ('grand', 'total'), ('net', 'amount'), ('invoice', 'amount'),
                              'amount', 'total', exclude=('tax', 'gst', 'discount', 'paid', 'balance', 'due', 'received'))
        info['sheets'][ws.title] = {
            'type': 'items' if is_item_sheet else 'invoices',
            'columns': {k: headers[v] for k, v in (('control_date', c_ctrl), ('date', c_date), ('invoice', c_inv),
                        ('party', c_party), ('product_id', c_pid), ('product_name', c_pname), ('qty', c_qty),
                        ('po_number', c_po), ('amount', c_amt)) if v is not None},
            'rows': len(body),
        }
        if c_amt is None:
            info['sheets'][ws.title]['skipped'] = 'no amount column'
            continue
        get = lambda r, c: r[c] if c is not None and c < len(r) else None
        if is_item_sheet:
            item_sheets.append((ws.title, body, c_ctrl, c_date, c_inv, c_pid, c_pname, c_qty, c_amt))
            continue
        for r in body:
            amt = _cell_amount(get(r, c_amt))
            inv = get(r, c_inv)
            if amt is None or (inv in (None, '') and get(r, c_date) in (None, '') and get(r, c_ctrl) in (None, '')):
                continue  # totals / blank rows
            if inv is None and str(get(r, c_party) or '').strip().lower() in ('total', 'grand total'):
                continue
            ctrl = _cell_date(get(r, c_ctrl))
            src = 'control_date'
            if not ctrl:
                ctrl, src = _cell_date(get(r, c_date)), 'date'
            invoices.append({'control_date': ctrl, 'date_source': src if ctrl else 'missing',
                             'invoice_no': None if inv is None else str(inv).strip(),
                             'party': None if get(r, c_party) is None else str(get(r, c_party)).strip(),
                             'po_number': _po_key(get(r, c_po)) if c_po is not None and get(r, c_po) not in (None, '') else None,
                             'amount': amt})
    inv_dates = {}
    for i in invoices:
        if i['invoice_no']:
            inv_dates.setdefault(i['invoice_no'], (i['control_date'], i['date_source']))
    for title, body, c_ctrl, c_date, c_inv, c_pid, c_pname, c_qty, c_amt in item_sheets:
        get = lambda r, c: r[c] if c is not None and c < len(r) else None
        for r in body:
            amt = _cell_amount(get(r, c_amt))
            pid = get(r, c_pid)
            pname = get(r, c_pname)
            if amt is None or (pid in (None, '') and pname in (None, '')):
                continue
            if str(pname or '').strip().lower() in ('total', 'grand total') and pid in (None, ''):
                continue
            inv = None if get(r, c_inv) is None else str(get(r, c_inv)).strip()
            ctrl, src = _cell_date(get(r, c_ctrl)), 'control_date'
            if not ctrl and inv in inv_dates:
                ctrl, src = inv_dates[inv]
            if not ctrl:
                ctrl, src = _cell_date(get(r, c_date)), 'date'
            pid_s = None if pid in (None, '') else (str(int(pid)) if isinstance(pid, float) and pid.is_integer() else str(pid).strip())
            pname_s = None if pname in (None, '') else str(pname).strip()
            lines.append({'control_date': ctrl, 'date_source': src if ctrl else 'missing', 'invoice_no': inv,
                          'product_key': pid_s if pid_s else 'name:' + _norm_item(pname_s),
                          'product_id': pid_s, 'product_name': pname_s,
                          'qty': _cell_amount(get(r, c_qty)), 'amount': amt})
    if not invoices and not lines:
        raise ValueError('Could not find any rows with an amount in this file. Check that it is the '
                         f'{report_type} report exported from the billing software.')
    return invoices, lines, info


@app.route('/gpm/upload_report', methods=['POST'])
def gpm_upload_report():
    """JSON: {"report_type": "sales"|"purchase", "filename": "...", "file_b64": "<base64 xlsx>"}
    Rows of the new file replace earlier uploaded rows of the same report type
    for the same dates."""
    import base64
    data = request.get_json(silent=True) or {}
    rtype = data.get('report_type')
    if rtype not in ('sales', 'purchase'):
        return jsonify({'success': False, 'message': "report_type must be 'sales' or 'purchase'"}), 400
    try:
        raw = base64.b64decode(data.get('file_b64') or '')
        invoices, lines, info = _parse_report_workbook(raw, rtype)
    except Exception as e:
        return jsonify({'success': False, 'message': f'Could not read the file: {e}'}), 400
    dates = sorted({r['control_date'] for r in invoices + lines if r['control_date']})
    min_d, max_d = (dates[0], dates[-1]) if dates else (None, None)
    conn = _report_conn()
    try:
        cur = conn.cursor()
        cur.execute('BEGIN IMMEDIATE')
        if min_d:
            for t in ('gpm_report_invoices', 'gpm_report_lines'):
                cur.execute(f'DELETE FROM {t} WHERE report_type = ? AND control_date BETWEEN ? AND ?', (rtype, min_d, max_d))
        cur.execute(
            'INSERT INTO gpm_report_uploads (report_type, filename, uploaded_at, min_date, max_date, invoice_rows, line_rows, info_json) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            (rtype, data.get('filename'), datetime.now().isoformat(timespec='seconds'), min_d, max_d,
             len(invoices), len(lines), json.dumps(info)),
        )
        uid = cur.lastrowid
        cur.executemany(
            'INSERT INTO gpm_report_invoices (upload_id, report_type, control_date, date_source, invoice_no, party, amount, po_number) VALUES (?,?,?,?,?,?,?,?)',
            [(uid, rtype, i['control_date'], i['date_source'], i['invoice_no'], i['party'], i['amount'], i.get('po_number')) for i in invoices])
        cur.executemany(
            'INSERT INTO gpm_report_lines (upload_id, report_type, control_date, date_source, invoice_no, product_key, product_id, product_name, qty, amount) VALUES (?,?,?,?,?,?,?,?,?,?)',
            [(uid, rtype, l['control_date'], l['date_source'], l['invoice_no'], l['product_key'], l['product_id'],
              l['product_name'], l['qty'], l['amount']) for l in lines])
        conn.commit()
    finally:
        conn.close()
    no_ctrl = sum(1 for r in invoices + lines if r['date_source'] != 'control_date')
    return jsonify({
        'success': True, 'upload_id': uid, 'report_type': rtype,
        'from_date': min_d, 'to_date': max_d, 'invoice_rows': len(invoices), 'item_rows': len(lines),
        'rows_without_control_date': no_ctrl, 'detected': info,
        'message': f"{rtype.capitalize()} report saved: {len(invoices)} invoices, {len(lines)} item rows"
                   + (f", {min_d} to {max_d}" if min_d else ''),
    })


@app.route('/gpm/uploads', methods=['GET'])
def gpm_uploads():
    conn = _report_conn()
    try:
        cur = conn.cursor()
        cur.execute('SELECT id, report_type, filename, uploaded_at, min_date, max_date, invoice_rows, line_rows '
                    'FROM gpm_report_uploads ORDER BY id DESC LIMIT 30')
        keys = ['id', 'report_type', 'filename', 'uploaded_at', 'from_date', 'to_date', 'invoice_rows', 'item_rows']
        data = [dict(zip(keys, r)) for r in cur.fetchall()]
        coverage = {}
        for t in ('sales', 'purchase'):
            cur.execute('SELECT MIN(control_date), MAX(control_date) FROM (SELECT control_date FROM gpm_report_invoices WHERE report_type = ? '
                        'UNION ALL SELECT control_date FROM gpm_report_lines WHERE report_type = ?)', (t, t))
            coverage[t] = dict(zip(('from_date', 'to_date'), cur.fetchone()))
        return jsonify({'success': True, 'data': data, 'coverage': coverage})
    finally:
        conn.close()


# ---------- product ID <-> item matching ----------
@app.route('/gpm/products', methods=['GET'])
def gpm_products():
    """Products seen in uploaded Sales Reports with their matched item.
    Optional start/end limit it to products sold in that period."""
    start, end = _to_iso_date(request.args.get('start')), _to_iso_date(request.args.get('end'))
    conn = _report_conn()
    try:
        cur = conn.cursor()
        where, args = "WHERE report_type = 'sales'", []
        if start and end:
            where += ' AND control_date BETWEEN ? AND ?'
            args = [start, end]
        cur.execute(f'SELECT product_key, MAX(product_id), MAX(product_name), SUM(amount), COUNT(*) '
                    f'FROM gpm_report_lines {where} GROUP BY product_key ORDER BY SUM(amount) DESC', args)
        rows = cur.fetchall()
        cur.execute('SELECT product_key, item_name, updated_at FROM gpm_product_map')
        mapping = {k: (i, u) for k, i, u in cur.fetchall()}
        canon, aliases = _load_item_catalog(cur)
        data = []
        for key, pid, pname, amt, cnt in rows:
            m = mapping.get(key)
            sugg = None
            if not m and pname:
                n = _norm_item(pname)
                sugg = _resolve_item(pname, canon, aliases)
                if not sugg:
                    for ck, cname in canon.items():
                        if ck and (ck in n or n in ck):
                            sugg = cname
                            break
            data.append({'product_key': key, 'product_id': pid, 'product_name': pname,
                         'amount': round(amt or 0, 2), 'rows': cnt,
                         'item': m[0] if m else None, 'updated_at': m[1] if m else None,
                         'mapped': bool(m), 'suggested_item': sugg})
        return jsonify({'success': True, 'data': data})
    finally:
        conn.close()


@app.route('/gpm/map_product', methods=['POST'])
def gpm_map_product():
    """JSON: {"product_key": "...", "item": "Papaya"}  (item "" / null = not a tracked item)
    or {"mappings": [{...}, ...]} to save several at once."""
    data = request.get_json(silent=True) or {}
    maps = data.get('mappings') or [data]
    conn = _report_conn()
    try:
        cur = conn.cursor()
        canon, aliases = _load_item_catalog(cur)
        saved = 0
        for m in maps:
            key = str(m.get('product_key') or '').strip()
            if not key:
                continue
            item = str(m.get('item') or '').strip()
            name = None
            if item:
                name = _resolve_item(item, canon, aliases)
                if not name:
                    return jsonify({'success': False, 'message': f"'{item}' is not in the Admin item list"}), 400
            cur.execute('SELECT MAX(product_id), MAX(product_name) FROM gpm_report_lines WHERE product_key = ?', (key,))
            pid, pname = cur.fetchone() or (None, None)
            cur.execute('INSERT OR REPLACE INTO gpm_product_map (product_key, product_id, product_name, item_name, updated_at) '
                        'VALUES (?, ?, ?, ?, ?)', (key, pid, pname, name or '', datetime.now().isoformat(timespec='seconds')))
            saved += 1
        conn.commit()
        return jsonify({'success': True, 'saved': saved})
    finally:
        conn.close()


# ---------- calculation ----------
def _date_range(start, end):
    d, out = start, []
    while d <= end:
        out.append(d)
        d = _shift_date(d, 1)
    return out


def _receipt_cost(cur, row, settings, flags, kind):
    """Cost of one purchase / packaging entry.
    row: dict with item, po_number, qty/unit receive & accept, low grade, rate, ctrl_date, date."""
    po = _find_po_line(cur, row['po_number'], row['item']) if row.get('po_number') else {'po_exists': False}
    ref = f"{row.get('item')} | PO {row.get('po_number') or '-'} | {row.get('ctrl_date') or row.get('date')}"
    res = {'basis': None, 'rate': None, 'po_unit': None, 'qty': None, 'amount': 0.0, 'issues': []}
    if 'rate' in po and po['rate'] > 0:
        rate, unit = po['rate'], po['unit']
        if _norm_unit(unit) not in _PO_UNITS:
            res['issues'].append('po_no_unit')
    else:
        rate, unit = _num(row.get('rate')), po.get('unit') or row.get('unit_receive')
        if 'rate' in po:
            res['issues'].append('po_no_rate')
        elif po.get('po_exists'):
            res['issues'].append('item_not_on_po')
        elif row.get('po_number'):
            res['issues'].append('po_not_found')
        else:
            res['issues'].append('no_po_number')
    res['rate'], res['po_unit'] = rate, unit

    def conv(q, u):
        c = _qty_in_po_unit(q, u, unit)
        if c is None:
            # pieces entered against a kg PO: use the average piece weight if set
            fam_u, _ = _unit_family(u)
            fam_p, pf = _unit_family(unit)
            w = _weight_on(cur, row['item'], row.get('ctrl_date') or row.get('date'), settings)
            if fam_u == 'count' and fam_p == 'weight' and w:
                res['issues'].append('pcs_converted_with_avg_weight')
                return _num(q) * w / pf
            res['issues'].append('unit_mismatch')
            res['mismatch'] = True
            return _num(q)
        return c

    accepted = _num(row.get('qty_accept'))
    low = _num(row.get('low_grade_qty'))
    under = _num(row.get('underweight_qty'))
    over = _num(row.get('overweight_qty'))
    # underweight / overweight are paid at their own rates; extra expense is
    # added in both actual and worst case (empty fields count as 0)
    weight_adj = under * _num(row.get('underweight_rate')) + over * _num(row.get('overweight_rate'))
    extra = _num(row.get('extra_expense'))
    if accepted > 0 or low > 0 or under > 0 or over > 0:
        q = conv(row.get('qty_accept'), row.get('unit_accept')) if accepted > 0 else 0.0
        res['basis'] = 'actual'
        res['qty'] = q
        res['amount'] = q * rate + low * _num(row.get('low_grade_rate')) + weight_adj
    else:
        q = conv(row.get('qty_receive'), row.get('unit_receive'))
        res['basis'] = 'worst_case'
        res['qty'] = q
        res['amount'] = q * rate
    if res.get('mismatch'):
        # PO unit and entry unit can't be converted (e.g. PO per box, entry in kg):
        # cost the entry with its own rate instead of the PO rate
        entry_rate = _num(row.get('rate'))
        res['rate'], res['po_unit'] = entry_rate, row.get('unit_accept') if res['basis'] == 'actual' else row.get('unit_receive')
        res['amount'] = res['qty'] * entry_rate + (low * _num(row.get('low_grade_rate')) + weight_adj if res['basis'] == 'actual' else 0)
    res['amount'] += extra
    res['extra_expense'] = extra
    if not row.get('ctrl_date'):
        res['issues'].append('no_ctrl_date')
    if 'expected_date' in po and po['expected_date'] and row.get('ctrl_date') and po['expected_date'] != row['ctrl_date']:
        res['issues'].append('ctrl_date_differs_from_po_date')
    if kind == 'produce' and settings.get(_norm_item(row['item']), {}).get('is_packaging'):
        res['issues'].append('packaging_in_purchase_entry')
    res['amount'] = round(res['amount'], 2)
    res['ref'] = ref
    return res


def _latest_po_price(cur, item_name, keys, on_date):
    """Rate of the latest PO received for the item up to on_date:
    the latest purchase entry (CTRL date <= on_date) joined to its PO line.
    Falls back to the latest PO line expected on/before on_date."""
    ph = ','.join('?' * len(keys))
    cur.execute(
        f"SELECT po_number, item, COALESCE(NULLIF(ctrl_date, ''), date) d FROM purchases "
        f"WHERE norm_item(item) IN ({ph}) AND COALESCE(NULLIF(ctrl_date, ''), date) <= ? ORDER BY d DESC, id DESC LIMIT 20",
        (*keys, on_date),
    )
    for po_number, item, d in cur.fetchall():
        po = _find_po_line(cur, po_number, item)
        if po.get('rate', 0) > 0 and _norm_unit(po.get('unit')) in _PO_UNITS:
            return {'rate': po['rate'], 'unit': _norm_unit(po['unit']), 'po_number': po['po_number'], 'date': d, 'source': 'received'}
    cur.execute(
        f'SELECT po_number, rate, unit, expected_date FROM generated_pos WHERE norm_item(item_name) IN ({ph}) '
        f'AND expected_date <= ? AND rate > 0 ORDER BY expected_date DESC, id DESC LIMIT 1',
        (*keys, on_date),
    )
    r = cur.fetchone()
    if r and _norm_unit(r[2]) in _PO_UNITS:
        return {'rate': _num(r[1]), 'unit': _norm_unit(r[2]), 'po_number': r[0], 'date': r[3], 'source': 'po_not_received'}
    return None


def _stock_value(qty_kg, qty_pcs, is_pcs, avg_w, price):
    """(value, qty_used, unit_used, problem)"""
    if not price:
        return 0.0, None, None, 'no_price'
    fam, f = _unit_family(price['unit'])
    if fam == 'weight':
        if is_pcs:
            if not avg_w:
                return 0.0, None, None, 'no_avg_weight'
            kg = qty_pcs * avg_w
        else:
            kg = qty_kg
        return kg / f * price['rate'], kg, 'kg', None
    # PO priced per piece / box / bag
    if is_pcs:
        return qty_pcs * price['rate'], qty_pcs, price['unit'], None
    return 0.0, None, None, 'price_unit_mismatch'


def _po_payment_check(cur, receipts, start, end, flag):
    """Compares what the app says is owed per PO (purchase + packaging entries
    in the period) with what the uploaded Purchase Report shows as paid.
    Only paid POs appear in the Purchase Report, so:
      * PO missing from the report         -> unpaid
      * report amount < app amount          -> balance due
      * report amount > app amount          -> extra payment (flag)
    Payments are matched on PO number across all uploaded Purchase Report
    dates (a PO may be paid on a later date than it was received)."""
    cur.execute("SELECT COUNT(*), SUM(CASE WHEN po_number IS NOT NULL AND po_number != '' THEN 1 ELSE 0 END) "
                "FROM gpm_report_invoices WHERE report_type = 'purchase'")
    total_rows, po_rows = cur.fetchone()
    if not total_rows:
        flag('purchase_report_missing', 'info', 'No Purchase Report uploaded - PO payments not checked')
        return []
    if not po_rows:
        flag('purchase_report_no_po', 'warning',
             'Purchase Report has no PO number column - PO payments cannot be matched. Include the PO / order number in the export.')
        return []
    paid = {}
    cur.execute("SELECT po_number, SUM(amount), COUNT(*), GROUP_CONCAT(DISTINCT control_date), MAX(party) "
                "FROM gpm_report_invoices WHERE report_type = 'purchase' AND po_number IS NOT NULL AND po_number != '' GROUP BY po_number")
    for po, amt, cnt, dates, party in cur.fetchall():
        k = _po_key(po)
        p = paid.setdefault(k, {'amount': 0.0, 'rows': 0, 'dates': set(), 'party': party})
        p['amount'] += amt or 0.0
        p['rows'] += cnt
        p['dates'].update((dates or '').split(','))
    owed = {}
    for e in receipts:
        k = _po_key(e.get('po_number'))
        if not k:
            continue
        o = owed.setdefault(k, {'po_number': e['po_number'], 'vendor': e.get('vendor'), 'amount': 0.0,
                                'entries': 0, 'worst_case': False, 'items': set()})
        o['amount'] += e['amount']
        o['entries'] += 1
        o['worst_case'] = o['worst_case'] or e['basis'] == 'worst_case'
        o['items'].add(e['item_as_entered'])
    out = []
    for k, o in owed.items():
        p = paid.get(k)
        paid_amt = round(p['amount'], 2) if p else 0.0
        app_amt = round(o['amount'], 2)
        diff = round(paid_amt - app_amt, 2)
        tol = max(1.0, 0.005 * app_amt)
        if not p:
            status = 'unpaid'
        elif diff < -tol:
            status = 'balance_due'
        elif diff > tol:
            status = 'extra_paid'
        else:
            status = 'paid'
        ref = f"PO {o['po_number']} | {o['vendor'] or ''} | app {app_amt:,.2f} | paid {paid_amt:,.2f}"
        if status == 'unpaid':
            flag('po_unpaid', 'warning', 'PO not in Purchase Report - unpaid', app_amt, ref)
        elif status == 'balance_due':
            flag('po_balance_due', 'warning', 'Paid less than the app amount - balance due', -diff, ref)
        elif status == 'extra_paid':
            flag('po_extra_paid', 'error', 'EXTRA PAYMENT - paid more than the app amount', diff, ref)
        out.append({'po_number': o['po_number'], 'vendor': o['vendor'], 'items': sorted(o['items']),
                    'entries': o['entries'], 'app_amount': app_amt, 'app_basis': 'worst case' if o['worst_case'] else 'actual',
                    'paid_amount': paid_amt, 'difference': diff, 'status': status,
                    'paid_on': sorted(d for d in (p['dates'] if p else []) if d)})
    # paid in the report for this period, but no purchase entry in the app for that PO
    cur.execute("SELECT po_number, SUM(amount) FROM gpm_report_invoices WHERE report_type = 'purchase' "
                "AND control_date BETWEEN ? AND ? AND po_number IS NOT NULL AND po_number != '' GROUP BY po_number", (start, end))
    for po, amt in cur.fetchall():
        k = _po_key(po)
        if k in owed:
            continue
        cur.execute("SELECT COUNT(*) FROM (SELECT po_number FROM purchases UNION ALL SELECT po_number FROM packaging_materials) "
                    "WHERE TRIM(po_number) = ?", (k,))
        anywhere = cur.fetchone()[0]
        if anywhere:
            flag('po_paid_entries_other_dates', 'info', 'Paid in this period; the purchase entries are on other dates', amt, f'PO {po}')
        else:
            flag('po_paid_no_entry', 'error', 'Paid in Purchase Report but no purchase entry in the app for this PO', amt, f'PO {po}')
        out.append({'po_number': po, 'vendor': paid.get(k, {}).get('party'), 'items': [], 'entries': 0,
                    'app_amount': 0.0, 'app_basis': '-', 'paid_amount': round(amt or 0, 2),
                    'difference': round(amt or 0, 2), 'status': 'paid_entries_other_dates' if anywhere else 'paid_no_entry',
                    'paid_on': []})
    order = {'extra_paid': 0, 'paid_no_entry': 1, 'balance_due': 2, 'unpaid': 3, 'paid_entries_other_dates': 4, 'paid': 5}
    return sorted(out, key=lambda r: (order[r['status']], -abs(r['difference'])))


def _gpm_compute(start, end):
    conn = _report_conn()
    try:
        cur = conn.cursor()
        canon, aliases = _load_item_catalog(cur)
        settings = _item_settings_map(cur)
        flags = {}

        def flag(code, severity, message, amount=None, detail=None):
            f = flags.setdefault(code, {'code': code, 'severity': severity, 'message': message,
                                        'count': 0, 'amount': 0.0, 'details': []})
            f['count'] += 1
            if amount:
                f['amount'] = round(f['amount'] + amount, 2)
            if detail and len(f['details']) < 200:
                f['details'].append(detail)

        issue_text = {
            'po_no_rate': ('error', 'PO has no rate - entry rate used instead'),
            'po_no_unit': ('warning', 'PO has no unit'),
            'item_not_on_po': ('error', 'Item is not on the PO - entry rate used'),
            'po_not_found': ('error', 'PO number not found - entry rate used'),
            'no_po_number': ('error', 'No PO number - entry rate used'),
            'unit_mismatch': ('error', 'Entry unit does not match PO unit (e.g. PO per box, entry in kg) - entry rate used'),
            'pcs_converted_with_avg_weight': ('info', 'Pieces converted to kg with the average piece weight'),
            'no_ctrl_date': ('warning', 'No CTRL date - entry date used'),
            'ctrl_date_differs_from_po_date': ('info', 'CTRL date differs from PO expected date'),
            'packaging_in_purchase_entry': ('warning', 'Packaging item entered in Purchase Entry - counted as packaging'),
        }

        # ----- purchases (produce + packaging entered in purchase entry) -----
        cur.execute(
            "SELECT id, item, vendor, po_number, qty_receive, unit_receive, qty_accept, unit_accept, "
            "low_grade_qty, low_grade_rate, rate, ctrl_date, date, underweight_qty, underweight_rate, "
            "overweight_qty, overweight_rate, extra_expense FROM purchases "
            "WHERE COALESCE(NULLIF(ctrl_date, ''), date) BETWEEN ? AND ?", (start, end))
        cols = ['id', 'item', 'vendor', 'po_number', 'qty_receive', 'unit_receive', 'qty_accept', 'unit_accept',
                'low_grade_qty', 'low_grade_rate', 'rate', 'ctrl_date', 'date', 'underweight_qty', 'underweight_rate',
                'overweight_qty', 'overweight_rate', 'extra_expense']
        purchases, packaging = [], []
        for r in cur.fetchall():
            row = dict(zip(cols, r))
            row['ctrl_date'] = _to_iso_date(row['ctrl_date'])
            c = _receipt_cost(cur, row, settings, flags, 'produce')
            entry = {'source': 'purchase_entry', 'id': row['id'], 'ctrl_date': row['ctrl_date'] or row['date'],
                     'item': _resolve_item(row['item'], canon, aliases) or row['item'], 'item_as_entered': row['item'],
                     'vendor': row['vendor'], 'po_number': row['po_number'],
                     'qty_received': _num(row['qty_receive']), 'unit_received': row['unit_receive'],
                     'qty_accepted': _num(row['qty_accept']), 'low_grade_qty': _num(row['low_grade_qty']),
                     'rate': c['rate'], 'po_unit': c['po_unit'], 'qty_costed': round(c['qty'] or 0, 3),
                     'basis': c['basis'], 'amount': c['amount'], 'issues': c['issues']}
            (packaging if 'packaging_in_purchase_entry' in c['issues'] else purchases).append(entry)
        cur.execute(
            "SELECT id, item, vendor, po_number, qty_receive, unit_receive, qty_accept, unit_accept, rate, ctrl_date, date "
            "FROM packaging_materials WHERE COALESCE(NULLIF(ctrl_date, ''), date) BETWEEN ? AND ?", (start, end))
        pcols = ['id', 'item', 'vendor', 'po_number', 'qty_receive', 'unit_receive', 'qty_accept', 'unit_accept', 'rate', 'ctrl_date', 'date']
        for r in cur.fetchall():
            row = dict(zip(pcols, r))
            row['ctrl_date'] = _to_iso_date(row['ctrl_date'])
            c = _receipt_cost(cur, row, settings, flags, 'packaging')
            packaging.append({'source': 'packaging_entry', 'id': row['id'], 'ctrl_date': row['ctrl_date'] or row['date'],
                              'item': row['item'], 'item_as_entered': row['item'], 'vendor': row['vendor'],
                              'po_number': row['po_number'], 'qty_received': _num(row['qty_receive']),
                              'unit_received': row['unit_receive'], 'qty_accepted': _num(row['qty_accept']),
                              'low_grade_qty': 0.0, 'rate': c['rate'], 'po_unit': c['po_unit'],
                              'qty_costed': round(c['qty'] or 0, 3), 'basis': c['basis'], 'amount': c['amount'],
                              'issues': c['issues']})
        for e in purchases + packaging:
            ref = f"{e['ctrl_date']} | {e['item_as_entered']} | PO {e['po_number'] or '-'} | {e['vendor'] or ''}"
            for code in e['issues']:
                sev, msg = issue_text[code]
                flag(code, sev, msg, e['amount'], ref)
            if e['basis'] == 'worst_case':
                flag('worst_case', 'warning',
                     'Accepted / low-grade quantity not entered - WORST CASE used (received x PO rate)', e['amount'], ref)

        # ----- items with stock update in the period -----
        cur.execute('SELECT DISTINCT item FROM stock_updates WHERE date BETWEEN ? AND ?', (start, end))
        stock_items = sorted({n for (raw,) in cur.fetchall() for n in [_resolve_item(raw, canon, aliases)] if n}, key=str.lower)

        # ----- sales (uploaded report) -----
        cur.execute("SELECT product_key, item_name FROM gpm_product_map")
        pmap = {k: i for k, i in cur.fetchall()}
        cur.execute("SELECT product_key, MAX(product_id), MAX(product_name), SUM(amount), "
                    "SUM(CASE WHEN date_source != 'control_date' THEN 1 ELSE 0 END) "
                    "FROM gpm_report_lines WHERE report_type = 'sales' AND control_date BETWEEN ? AND ? GROUP BY product_key", (start, end))
        sales_products, sales_by_item, sales_lines_total = [], {}, 0.0
        for key, pid, pname, amt, no_ctrl in cur.fetchall():
            amt = amt or 0.0
            sales_lines_total += amt
            item = pmap.get(key)
            item_name = _resolve_item(item, canon, aliases) if item else None
            sales_products.append({'product_key': key, 'product_id': pid, 'product_name': pname,
                                   'amount': round(amt, 2), 'item': item_name, 'mapped': key in pmap})
            if item_name:
                sales_by_item[item_name] = sales_by_item.get(item_name, 0.0) + amt
            elif key not in pmap:
                flag('product_not_matched', 'error', 'Sales Report product not matched to an app item - left out of item-wise GPM',
                     amt, f"{pid or ''} {pname or ''}".strip())
            if no_ctrl:
                flag('sales_no_control_date', 'warning', 'Sales Report rows without control date - invoice date used', None,
                     f"{pid or pname}: {no_ctrl} rows")
        cur.execute("SELECT SUM(amount), COUNT(*), SUM(CASE WHEN date_source != 'control_date' THEN 1 ELSE 0 END) "
                    "FROM gpm_report_invoices WHERE report_type = 'sales' AND control_date BETWEEN ? AND ?", (start, end))
        inv_total, inv_count, inv_no_ctrl = cur.fetchone()
        if inv_count:
            sales_total, sales_source = inv_total or 0.0, 'invoice totals'
            if sales_lines_total and abs((inv_total or 0) - sales_lines_total) > max(1.0, 0.005 * abs(inv_total or 0)):
                flag('sales_invoice_vs_items', 'info',
                     f'Invoice totals ({inv_total:,.2f}) differ from item rows ({sales_lines_total:,.2f}) - '
                     'taxes, discounts or round-off; overall GPM uses invoice totals')
            if inv_no_ctrl:
                flag('sales_no_control_date', 'warning', 'Sales Report rows without control date - invoice date used',
                     None, f'{inv_no_ctrl} invoices')
        else:
            sales_total, sales_source = sales_lines_total, 'item rows'
        cur.execute("SELECT DISTINCT control_date FROM gpm_report_invoices WHERE report_type='sales' AND control_date BETWEEN ? AND ? "
                    "UNION SELECT DISTINCT control_date FROM gpm_report_lines WHERE report_type='sales' AND control_date BETWEEN ? AND ?",
                    (start, end, start, end))
        sales_days = {r[0] for r in cur.fetchall()}
        missing_days = [d for d in _date_range(start, end) if d not in sales_days]
        if missing_days:
            flag('sales_days_missing', 'error' if len(missing_days) == len(_date_range(start, end)) else 'warning',
                 'No Sales Report data for these dates - upload the Sales Report covering them', None, ', '.join(missing_days))

        # ----- uploaded purchase report (cross-check only) -----
        cur.execute("SELECT SUM(amount), COUNT(*) FROM gpm_report_invoices WHERE report_type = 'purchase' AND control_date BETWEEN ? AND ?", (start, end))
        pr_total, pr_count = cur.fetchone()
        if not pr_count:
            cur.execute("SELECT SUM(amount), COUNT(*) FROM gpm_report_lines WHERE report_type = 'purchase' AND control_date BETWEEN ? AND ?", (start, end))
            pr_total, pr_count = cur.fetchone()

        # ----- item-wise -----
        items_out = []
        for item in stock_items:
            keys = sorted(_keys_for_item(item, aliases))
            ph = ','.join('?' * len(keys))
            is_pcs = _is_pcs_item(item)
            avg_w_start = _weight_on(cur, item, start, settings)   # weight valid on the start date
            avg_w = _weight_on(cur, item, end, settings)            # weight valid on the end date
            first = _compute_admin_report(conn, item, start, keep_kg=True)
            last = _compute_admin_report(conn, item, end, keep_kg=True)
            cur.execute(f'SELECT quantity_sent, unit, pcs FROM vendor_rejections WHERE norm_item(item) IN ({ph}) AND date BETWEEN ? AND ?',
                        (*keys, start, end))
            vr_kg = vr_pcs = 0.0
            for q, u, p in cur.fetchall():
                vr_kg += _qty_to_kg(q, u)
                vr_pcs += _entry_pcs(q, u, p, is_pcs)
            open_kg = max(first['stock_today'] - vr_kg, 0.0)
            open_pcs = max(first['stock_today_pcs'] - vr_pcs, 0.0)
            close_kg, close_pcs = last['stock_next_day'], last['stock_next_day_pcs']
            p_open = _latest_po_price(cur, item, keys, start)
            p_close = _latest_po_price(cur, item, keys, end)
            o_val, o_qty, o_unit, o_prob = _stock_value(open_kg, open_pcs, is_pcs, avg_w_start, p_open)
            c_val, c_qty, c_unit, c_prob = _stock_value(close_kg, close_pcs, is_pcs, avg_w, p_close)
            for prob in {o_prob, c_prob} - {None}:
                msg = {'no_price': 'No PO rate found for the item - stock valued at 0',
                       'no_avg_weight': 'Average weight per piece not entered (daily weights / Item Settings) - stock valued at 0',
                       'price_unit_mismatch': 'Latest PO is per piece/box but stock is in kg - stock valued at 0'}[prob]
                flag('stock_' + prob, 'error', msg, None, item)
            for p in (p_open, p_close):
                if p and p['source'] == 'po_not_received':
                    flag('price_from_unreceived_po', 'info', 'No received PO before the date - latest PO rate used for stock value', None, item)
            if not last['has_closing_stock']:
                flag('no_closing_stock', 'error', f'No stock update on {_shift_date(end, 1)} (closing stock) - closing taken as 0', None, item)
            cur.execute(f'SELECT 1 FROM stock_updates WHERE norm_item(item) IN ({ph}) AND date = ? LIMIT 1', (*keys, start))
            if not cur.fetchone():
                flag('no_opening_stock', 'info', f'No stock update on {start} (opening stock) - opening taken as 0', None, item)
            if vr_kg or vr_pcs:
                flag('vendor_return_adjusted', 'info', 'Vendor returns in the period taken off the opening stock', None,
                     f"{item}: {round(vr_pcs if is_pcs else vr_kg, 3)} {'pcs' if is_pcs else 'kg'}")
            item_purch = [e for e in purchases if _norm_item(e['item']) == _norm_item(item)]
            p_amt = sum(e['amount'] for e in item_purch)
            worst = [e for e in item_purch if e['basis'] == 'worst_case']
            s_amt = sales_by_item.get(item, 0.0)
            if s_amt == 0:
                flag('no_sales_for_item', 'warning', 'Item has stock but no matched sales in the period', None, item)
            gp = c_val + s_amt - p_amt - o_val
            items_out.append({
                'item': item, 'stock_unit': 'pcs' if is_pcs else 'kg',
                'opening_stock': round(first['stock_today_pcs'] if is_pcs else first['stock_today'], 3),
                'vendor_returns': round(vr_pcs if is_pcs else vr_kg, 3),
                'opening_stock_adjusted': round(open_pcs if is_pcs else open_kg, 3),
                'opening_rate': p_open['rate'] if p_open else None, 'opening_rate_unit': p_open['unit'] if p_open else None,
                'opening_rate_po': p_open['po_number'] if p_open else None,
                'opening_value': round(o_val, 2),
                'closing_stock': round(close_pcs if is_pcs else close_kg, 3),
                'closing_rate': p_close['rate'] if p_close else None, 'closing_rate_unit': p_close['unit'] if p_close else None,
                'closing_rate_po': p_close['po_number'] if p_close else None,
                'closing_value': round(c_val, 2),
                'purchase_amount': round(p_amt, 2), 'purchase_entries': len(item_purch),
                'worst_case_entries': len(worst), 'worst_case_amount': round(sum(e['amount'] for e in worst), 2),
                'sales_amount': round(s_amt, 2),
                'gross_profit': round(gp, 2),
                'gp_percent': round(gp / s_amt * 100, 2) if s_amt else None,
                'avg_piece_weight_kg': avg_w if is_pcs else None,
            })

        # ----- LMD / FMD -----
        logistics = {}
        for t in ('lmd_data', 'fmd_data'):
            held = _pending_entry_ids(cur, t)  # 2nd entries waiting for head approval are left out
            held_sql = f" AND id NOT IN ({','.join(str(int(x)) for x in held)})" if held else ''
            cur.execute(f"SELECT SUM(total_amount), COUNT(*), SUM(CASE WHEN ctrl_date IS NULL OR ctrl_date = '' THEN 1 ELSE 0 END) "
                        f"FROM {t} WHERE COALESCE(NULLIF(ctrl_date, ''), date) BETWEEN ? AND ?{held_sql}", (start, end))
            if held:
                flag('logistics_held', 'warning', 'LMD/FMD entries waiting for head approval - left out of the total', None,
                     f"{t.split('_')[0].upper()}: {len(held)}")
            amt, cnt, no_ctrl = cur.fetchone()
            logistics[t] = {'amount': round(amt or 0, 2), 'entries': cnt}
            if no_ctrl:
                flag('logistics_no_ctrl_date', 'warning', 'LMD/FMD entries without CTRL date - entry date used', None,
                     f"{t.split('_')[0].upper()}: {no_ctrl}")

        purchase_total = round(sum(e['amount'] for e in purchases), 2)
        packaging_total = round(sum(e['amount'] for e in packaging), 2)
        lmd, fmd = logistics['lmd_data']['amount'], logistics['fmd_data']['amount']
        opening_total = round(sum(i['opening_value'] for i in items_out), 2)
        closing_total = round(sum(i['closing_value'] for i in items_out), 2)
        base = closing_total + sales_total - purchase_total - opening_total
        variants = {
            'excluding_packaging_and_lmd_fmd': round(base, 2),
            'including_packaging': round(base - packaging_total, 2),
            'including_lmd_fmd': round(base - lmd - fmd, 2),
            'including_packaging_and_lmd_fmd': round(base - packaging_total - lmd - fmd, 2),
        }
        app_total = purchase_total + packaging_total
        if pr_count and abs((pr_total or 0) - app_total) > max(1.0, 0.02 * abs(pr_total or 0)):
            flag('purchase_report_differs', 'warning',
                 f'Uploaded Purchase Report total ({(pr_total or 0):,.2f}) differs from app purchases + packaging ({app_total:,.2f})')
        po_payments = _po_payment_check(cur, purchases + packaging, start, end, flag)
        worst_entries = [e for e in purchases + packaging if e['basis'] == 'worst_case']
        sev_order = {'error': 0, 'warning': 1, 'info': 2}
        return {
            'start': start, 'end': end,
            'is_worst_case': bool(worst_entries),
            'worst_case_entries': len(worst_entries),
            'worst_case_amount': round(sum(e['amount'] for e in worst_entries), 2),
            'overall': {
                'sales_total': round(sales_total, 2), 'sales_source': sales_source,
                'purchase_total': purchase_total, 'packaging_total': packaging_total,
                'lmd_total': lmd, 'fmd_total': fmd,
                'opening_stock_value': opening_total, 'closing_stock_value': closing_total,
                'purchase_report_total': round(pr_total, 2) if pr_count else None,
                'gross_profit': variants,
                'gp_percent': {k: (round(v / sales_total * 100, 2) if sales_total else None) for k, v in variants.items()},
            },
            'items': sorted(items_out, key=lambda i: -i['gross_profit']),
            'purchases': purchases, 'packaging': packaging,
            'logistics': logistics,
            'sales_products': sorted(sales_products, key=lambda p: -p['amount']),
            'po_payments': po_payments,
            'flags': sorted(flags.values(), key=lambda f: (sev_order[f['severity']], -f['count'])),
        }
    finally:
        conn.close()


def _gpm_dates_from_request():
    start = _to_iso_date(request.args.get('start'))
    end = _to_iso_date(request.args.get('end')) or start
    if not start:
        return None, None, (jsonify({'success': False, 'message': 'start date (yyyy-MM-dd) is required'}), 400)
    if end < start:
        start, end = end, start
    return start, end, None


@app.route('/gpm/analyze', methods=['GET'])
def gpm_analyze():
    """?start=yyyy-MM-dd&end=yyyy-MM-dd (CTRL dates, same date allowed)"""
    start, end, err = _gpm_dates_from_request()
    if err:
        return err
    _process_report_queue_safe()
    return jsonify({'success': True, **_gpm_compute(start, end)})


@app.route('/gpm/export', methods=['GET'])
def gpm_export():
    """Same as /gpm/analyze but returns an Excel workbook."""
    start, end, err = _gpm_dates_from_request()
    if err:
        return err
    try:
        from openpyxl import Workbook
        from openpyxl.styles import Font, PatternFill, Alignment
    except ImportError:
        return jsonify({'success': False, 'message': 'The server needs the openpyxl package: pip install openpyxl'}), 500
    import io as _io
    from flask import send_file
    _process_report_queue_safe()
    r = _gpm_compute(start, end)
    o = r['overall']
    wb = Workbook()
    bold = Font(bold=True)
    head_fill = PatternFill('solid', fgColor='DDE3F0')

    def sheet(title, headers, rows, first=False):
        ws = wb.active if first else wb.create_sheet()
        ws.title = title
        ws.append(headers)
        for c in ws[1]:
            c.font, c.fill = bold, head_fill
        for row in rows:
            ws.append(row)
        for col in ws.columns:
            width = max(len(str(c.value)) if c.value is not None else 0 for c in col)
            ws.column_dimensions[col[0].column_letter].width = min(max(10, width + 2), 60)
        ws.freeze_panes = 'A2'
        return ws

    title = f"GPM {start}" + ('' if start == end else f" to {end}")
    summary = [
        ['Period (CTRL dates)', f'{start} to {end}'],
        ['Pricing', 'WORST CASE - some purchase entries have no accepted quantity' if r['is_worst_case'] else 'Actual'],
        ['Worst-case entries', r['worst_case_entries']],
        ['Worst-case amount', r['worst_case_amount']],
        [],
        ['Sales (Sales Report, ' + o['sales_source'] + ')', o['sales_total']],
        ['Purchases (app, fruits & vegetables)', o['purchase_total']],
        ['Opening stock value', o['opening_stock_value']],
        ['Closing stock value', o['closing_stock_value']],
        ['Packaging', o['packaging_total']],
        ['LMD', o['lmd_total']],
        ['FMD', o['fmd_total']],
        ['Purchase Report total (uploaded, for cross-check)', o['purchase_report_total']],
        [],
        ['Gross profit', 'Amount', 'GP % of sales'],
    ]
    labels = {'excluding_packaging_and_lmd_fmd': 'Excluding packaging and LMD/FMD',
              'including_packaging': 'Including packaging',
              'including_lmd_fmd': 'Including LMD/FMD',
              'including_packaging_and_lmd_fmd': 'Including packaging and LMD/FMD'}
    for k, lbl in labels.items():
        summary.append([lbl, o['gross_profit'][k], o['gp_percent'][k]])
    ws = sheet('Summary', [title, ''], summary, first=True)
    ws['A1'].font = Font(bold=True, size=13)
    sheet('Item-wise GPM',
          ['Item', 'Unit', 'Opening stock', 'Vendor returns', 'Opening (adjusted)', 'Opening rate', 'Rate unit', 'Opening value',
           'Closing stock', 'Closing rate', 'Closing value', 'Purchases', 'Worst-case purchases', 'Sales', 'Gross profit', 'GP %'],
          [[i['item'], i['stock_unit'], i['opening_stock'], i['vendor_returns'], i['opening_stock_adjusted'], i['opening_rate'],
            i['opening_rate_unit'], i['opening_value'], i['closing_stock'], i['closing_rate'], i['closing_value'],
            i['purchase_amount'], i['worst_case_amount'], i['sales_amount'], i['gross_profit'], i['gp_percent']] for i in r['items']])
    rec_head = ['CTRL date', 'Item', 'Vendor', 'PO', 'Received', 'Unit', 'Accepted', 'Low grade', 'PO rate', 'PO unit',
                'Qty costed', 'Basis', 'Amount', 'Issues']
    rec_row = lambda e: [e['ctrl_date'], e['item_as_entered'], e['vendor'], e['po_number'], e['qty_received'], e['unit_received'],
                         e['qty_accepted'], e['low_grade_qty'], e['rate'], e['po_unit'], e['qty_costed'],
                         'WORST CASE' if e['basis'] == 'worst_case' else 'actual', e['amount'], ', '.join(e['issues'])]
    sheet('Purchases', rec_head, [rec_row(e) for e in r['purchases']])
    sheet('Packaging', rec_head, [rec_row(e) for e in r['packaging']])
    sheet('Sales by product', ['Product ID', 'Product name', 'Matched item', 'Amount'],
          [[p['product_id'], p['product_name'], p['item'] or ('(not tracked)' if p['mapped'] else 'NOT MATCHED'), p['amount']]
           for p in r['sales_products']])
    status_txt = {'unpaid': 'UNPAID', 'balance_due': 'BALANCE DUE', 'extra_paid': 'EXTRA PAID', 'paid': 'Paid',
                  'paid_no_entry': 'PAID - NO ENTRY IN APP', 'paid_entries_other_dates': 'Paid - entries on other dates'}
    sheet('PO payments', ['PO', 'Vendor', 'Items', 'App amount', 'App basis', 'Paid (Purchase Report)', 'Difference', 'Status', 'Paid on'],
          [[p['po_number'], p['vendor'], ', '.join(p['items']), p['app_amount'], p['app_basis'], p['paid_amount'],
            p['difference'], status_txt.get(p['status'], p['status']), ', '.join(p['paid_on'])] for p in r['po_payments']])
    sheet('LMD-FMD', ['Type', 'Entries', 'Amount'],
          [['LMD', r['logistics']['lmd_data']['entries'], r['logistics']['lmd_data']['amount']],
           ['FMD', r['logistics']['fmd_data']['entries'], r['logistics']['fmd_data']['amount']]])
    fl = sheet('Flags', ['Severity', 'Issue', 'Count', 'Amount', 'Details'],
               [[f['severity'].upper(), f['message'], f['count'], f['amount'] or None, '; '.join(f['details'][:50])] for f in r['flags']])
    for row in fl.iter_rows(min_row=2):
        row[4].alignment = Alignment(wrap_text=True, vertical='top')
    buf = _io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    name = f"GPM_{start}" + ('' if start == end else f"_to_{end}") + ('_WORST_CASE' if r['is_worst_case'] else '') + '.xlsx'
    return send_file(buf, as_attachment=True, download_name=name,
                     mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')


_setup_gpm_tables()




# =====================================================================
# DAILY CHECKS (ALERTS) AND STOCK FORECAST
# ---------------------------------------------------------------------
# Times are India time (IST). "Control date" = a past day; the checks
# look at the last 10 control dates (yesterday and the 9 days before).
#   Stock     - today's stock entered before 12 noon; days without stock
#   Purchase  - POs expected on a control date with no purchase entry;
#               purchase entries without accepted quantity
#   Logistics - SOs dispatched without an LMD entry / with 2+ LMD entries;
#               POs received without an FMD entry / with 2+ FMD entries
#   Sales     - SO items missing in sales or with no weight
#   Quality   - after 9 AM: mandi resale, dump sale or rejection received
#               above 20 kg for an item on the previous control date;
#               after 12 noon: B grade in today's stock (closing stock of the
#               previous control date) above 30 kg
#   Forecast  - items that need ordering to keep 3 days of stock (sales kg)
# =====================================================================
ALERT_DAYS = 10
QUALITY_LIMIT_KG = 20.0
B_GRADE_LIMIT_KG = 30.0
FORECAST_WINDOW_DAYS = 7
FORECAST_COVER_DAYS = 3
FORECAST_STOCK_LOOKBACK_DAYS = 10


def _ist_now():
    """Current India time (naive datetime). ?now=YYYY-MM-DDTHH:MM can override it for testing."""
    from flask import has_request_context
    override = request.args.get('now') if has_request_context() else None
    if override:
        try:
            return datetime.strptime(override[:16], '%Y-%m-%dT%H:%M')
        except ValueError:
            pass
    return datetime.utcnow() + timedelta(hours=5, minutes=30)


def _so_key(value):
    """'so-10083' / 'SO 10083' / 10083.0 -> '10083'"""
    if value is None:
        return ''
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    s = str(value).strip().upper()
    s = _re.sub(r'^S\.?\s*O\.?(?![A-Z])\s*(NO\.?|NUMBER|#)?[\s#:\-]*', '', s)
    return s.strip()


def _split_refs(value):
    """FMD po_number may hold several POs: '11394, 11394' -> {'11394'}"""
    return {k for k in (_po_key(p) for p in _re.split(r'[,;/&\s]+', str(value or ''))) if k}


def _kg_with_pcs(qty, unit, settings, item):
    """kg of an entry; piece entries use the item's average piece weight when set."""
    if _is_pcs_unit(unit):
        w = settings.get(_norm_item(item), {}).get('avg_piece_weight_kg')
        return _num(qty) * w if w else 0.0
    return _qty_to_kg(qty, unit)


ALERT_SECTIONS = ['Stock', 'Purchase', 'Sales', 'B grade', 'Mandi', 'Dump', 'Rejection received',
                  'LMD/FMD', 'Verification', 'Forecast']


def _value_of_kg(cur, item, aliases, settings, kg, on_date):
    """Rupee value of `kg` of an item at the rate of the latest PO received
    up to on_date. Returns (value or None, rate text)."""
    if kg <= 0:
        return 0.0, ''
    keys = sorted(_keys_for_item(item, aliases))
    price = _latest_po_price(cur, item, keys, on_date)
    if not price:
        return None, 'no PO rate'
    fam, f = _unit_family(price['unit'])
    if fam == 'weight':
        return kg / f * price['rate'], f"@ ₹{price['rate']:g}/{price['unit']} (PO {price['po_number']})"
    w = _weight_on(cur, item, on_date, settings)
    if fam == 'count' and w:
        return kg / w * price['rate'], f"@ ₹{price['rate']:g}/{price['unit']} (PO {price['po_number']}, {w:g} kg/pc)"
    return None, f"PO priced per {price['unit']}"


def _split_so_refs(value):
    """LMD po_number may hold several SOs: '9775, 9776' -> {'9775', '9776'}"""
    return {k for k in (_so_key(p) for p in _re.split(r'[,;/&]+', str(value or ''))) if k}


def _pending_or_approved_refs(cur, table):
    """refs (SO / PO keys) whose duplicate entries were approved or are waiting for the head"""
    try:
        cur.execute('SELECT ref, status FROM entry_verifications WHERE table_name = ? AND status IN (?, ?)',
                    (table, 'pending', 'approved'))
    except sqlite3.OperationalError:
        return set()
    return {r for r, _ in cur.fetchall()}


def _compute_alerts(now, days=ALERT_DAYS):
    today = now.strftime('%Y-%m-%d')
    yesterday = _shift_date(today, -1)
    ctrl_dates = [_shift_date(today, -i) for i in range(days, 0, -1)]
    first = ctrl_dates[0]
    conn = _report_conn()
    try:
        cur = conn.cursor()
        canon, aliases = _load_item_catalog(cur)
        settings = _item_settings_map(cur)
        resolve = lambda n: _resolve_item(n, canon, aliases) or (str(n).strip() if n else '')
        alerts = {}

        def add(code, severity, category, title, control_date=None, detail=None, amount=None):
            key = (code, control_date)
            a = alerts.setdefault(key, {'code': code, 'severity': severity, 'category': category, 'title': title,
                                        'control_date': control_date, 'count': 0, 'amount': 0.0, 'details': []})
            a['count'] += 1
            if amount:
                a['amount'] = round(a['amount'] + amount, 2)
            if detail and len(a['details']) < 300:
                a['details'].append(detail)

        # ---------------- Stock ----------------
        cur.execute('SELECT item, date FROM stock_updates WHERE date BETWEEN ? AND ?', (_shift_date(first, -1), today))
        stock_by_day = {}
        for item, d in cur.fetchall():
            stock_by_day.setdefault(d, set()).add(resolve(item))
        if today not in stock_by_day:
            if now.hour >= 12:
                add('stock_not_entered', 'error', 'Stock', "Today's stock not entered (due before 12 noon)", today)
            else:
                add('stock_due', 'info', 'Stock', "Today's stock is due before 12 noon", today)
        elif now.hour >= 12:
            missing = sorted(stock_by_day.get(yesterday, set()) - stock_by_day[today], key=str.lower)
            for m in missing:
                add('stock_items_missing', 'warning', 'Stock', "Items in yesterday's stock but not in today's stock", today, m)
        for d in ctrl_dates:
            if d not in stock_by_day:
                add('stock_missing_day', 'warning', 'Stock', 'No stock update entered', d)

        # daily average weight per piece (papaya / pineapple)
        need = _piece_weight_items(cur, canon, settings, today)
        done = set()
        try:
            cur.execute('SELECT item_key FROM item_daily_weights WHERE date = ? AND avg_piece_weight_kg > 0', (today,))
            done = {r[0] for r in cur.fetchall()}
        except sqlite3.OperationalError:
            pass
        for name in need:
            if _norm_item(name) not in done:
                add('piece_weight_missing', 'warning', 'Stock', "Enter today's average weight per piece", today, name)
        for k, sset in settings.items():
            if sset.get('needs_unit') and sset.get('stock_in_pcs') is None and k in canon:
                add('item_unit_missing', 'warning', 'Stock', 'New item: choose whether its stock is counted in kg or pieces (Item Settings)',
                    today, canon[k])

        # ---------------- Purchase ----------------
        received = set()
        for table in ('purchases', 'packaging_materials'):
            cur.execute(f'SELECT po_number, item FROM {table}')
            for po, item in cur.fetchall():
                received.add((_po_key(po), _norm_item(resolve(item))))
        cur.execute('SELECT po_number, item_name, vendor_name, expected_date, qty_ordered, unit FROM generated_pos '
                    'WHERE expected_date BETWEEN ? AND ?', (first, yesterday))
        for po, item, vendor, exp, qty, unit in cur.fetchall():
            if (_po_key(po), _norm_item(resolve(item))) not in received:
                add('po_not_received', 'warning', 'Purchase', 'PO expected but no purchase entry made', exp,
                    f'PO {po} · {item} · {vendor or ""} · {_num(qty):g} {unit or ""}')
        for table, label in (('purchases', 'Purchase entry'), ('packaging_materials', 'Packaging entry')):
            low = ", low_grade_qty" if table == 'purchases' else ", 0"
            cur.execute(f"SELECT po_number, item, vendor, COALESCE(NULLIF(ctrl_date, ''), date), qty_accept{low} FROM {table} "
                        f"WHERE COALESCE(NULLIF(ctrl_date, ''), date) BETWEEN ? AND ?", (first, today))
            for po, item, vendor, d, acc, lowq in cur.fetchall():
                if _num(acc) <= 0 and _num(lowq) <= 0:
                    add('accepted_pending', 'warning', 'Purchase', f'{label}: accepted quantity not entered', d,
                        f'PO {po} · {item} · {vendor or ""}')

        # ---------------- LMD (one entry may carry several SOs: "9775, 9776") ----------------
        lmd_ok_refs = _pending_or_approved_refs(cur, 'lmd_data')
        cur.execute("SELECT po_number, client_name, COALESCE(NULLIF(ctrl_date, ''), date) FROM lmd_data "
                    "WHERE COALESCE(NULLIF(ctrl_date, ''), date) BETWEEN ? AND ?", (_shift_date(first, -3), today))
        lmd_by_so, lmd_client_day = {}, set()
        for so, clients, d in cur.fetchall():
            for k in _split_so_refs(so):
                lmd_by_so[k] = lmd_by_so.get(k, 0) + 1
            for client in _re.split(r',', str(clients or '')):
                lmd_client_day.add((_norm_item(client), d))
        cur.execute('SELECT id, client_name, so_number, date_of_dispatch FROM generated_sos WHERE date_of_dispatch BETWEEN ? AND ?',
                    (first, yesterday))
        sos = cur.fetchall()
        for so_id, client, so_no, d in sos:
            k = _so_key(so_no)
            n = lmd_by_so.get(k, 0)
            if n == 0:
                if (_norm_item(client), d) in lmd_client_day:
                    add('lmd_without_so', 'info', 'LMD/FMD', 'LMD entered for the client but without the SO number', d,
                        f'SO {so_no} · {client}')
                else:
                    add('lmd_missing', 'error', 'LMD/FMD', 'SO dispatched but no LMD entry', d, f'SO {so_no} · {client}')
            elif n > 1 and k not in lmd_ok_refs:
                add('lmd_duplicate', 'warning', 'LMD/FMD', 'More than one LMD entry for the same SO', d,
                    f'SO {so_no} · {client} · {n} entries')

        # ---------------- FMD ----------------
        fmd_ok_refs = _pending_or_approved_refs(cur, 'fmd_data')
        cur.execute('SELECT po_number FROM fmd_data')
        fmd_count = {}
        for (refs,) in cur.fetchall():
            for k in _split_refs(refs):
                fmd_count[k] = fmd_count.get(k, 0) + 1
        po_days = {}
        for table in ('purchases', 'packaging_materials'):
            cur.execute(f"SELECT po_number, vendor, COALESCE(NULLIF(ctrl_date, ''), date) FROM {table} "
                        f"WHERE COALESCE(NULLIF(ctrl_date, ''), date) BETWEEN ? AND ?", (first, yesterday))
            for po, vendor, d in cur.fetchall():
                k = _po_key(po)
                if k:
                    po_days.setdefault(k, (po, vendor, d))
        for k, (po, vendor, d) in po_days.items():
            n = fmd_count.get(k, 0)
            if n == 0:
                add('fmd_missing', 'warning', 'LMD/FMD', 'Purchase received but no FMD entry for the PO', d, f'PO {po} · {vendor or ""}')
            elif n > 1 and k not in fmd_ok_refs:
                add('fmd_duplicate', 'warning', 'LMD/FMD', 'PO appears in more than one FMD entry', d, f'PO {po} · {n} entries')

        # ---------------- Verification (2nd LMD/FMD entry waiting for the head) ----------------
        try:
            cur.execute("SELECT table_name, ref, entry_id, created_at FROM entry_verifications WHERE status = 'pending' ORDER BY id")
            for table, ref, eid, created in cur.fetchall():
                label = 'LMD' if table == 'lmd_data' else 'FMD'
                add('verification_pending', 'error', 'Verification', 'Second LMD/FMD entry waiting for head approval',
                    (created or today)[:10], f"{label} entry #{eid} · {'SO' if label == 'LMD' else 'PO'} {ref}")
        except sqlite3.OperationalError:
            pass

        # ---------------- Sales vs SO ----------------
        if sos:
            so_ids = [s[0] for s in sos]
            cur.execute(f"SELECT so_id, item_name, quantity_kg, quantity_pcs FROM so_items WHERE so_id IN ({','.join('?' * len(so_ids))})", so_ids)
            so_items = {}
            for so_id, item, kg, pcs in cur.fetchall():
                if _num(kg) > 0 or _num(pcs) > 0:
                    so_items.setdefault(so_id, []).append((item, kg, pcs))
            cur.execute('SELECT po_number, item, quantity, pcs FROM sales WHERE date BETWEEN ? AND ?',
                        (_shift_date(first, -3), today))
            sold = {}  # (SO, item) -> total weight entered in sales
            for so, item, q, pcs in cur.fetchall():
                key = (_so_key(so), _norm_item(resolve(item)))
                sold[key] = sold.get(key, 0.0) + _num(q)
            for so_id, client, so_no, d in sos:
                for item, kg, pcs in so_items.get(so_id, []):
                    key = (_so_key(so_no), _norm_item(resolve(item)))
                    if key not in sold:
                        add('so_item_not_in_sales', 'error', 'Sales', 'SO item not entered in sales', d,
                            f'SO {so_no} · {client} · {item} ({_num(kg):g} kg{f", {_num(pcs):g} pcs" if _num(pcs) else ""})')
                    elif sold[key] <= 0:
                        add('sales_weight_missing', 'error', 'Sales', 'Sales entry without weight / quantity', d,
                            f'SO {so_no} · {client} · {item}')

        # ---------------- Mandi / Dump / Rejection (previous control date, after 9 AM) ----------------
        settings_y = _settings_on(cur, yesterday, settings)
        if now.hour >= 9:
            for table, date_col, section in (('mandi_resales', 'date', 'Mandi'), ('dump_sales', 'date', 'Dump'),
                                             ('rejection_received', 'ctrl_date', 'Rejection received')):
                cur.execute(f'SELECT item, quantity, unit FROM {table} WHERE {date_col} = ?', (yesterday,))
                per_item = {}
                for item, q, u in cur.fetchall():
                    name = resolve(item)
                    per_item[name] = per_item.get(name, 0.0) + _kg_with_pcs(q, u, settings_y, name)
                for name, kg in sorted(per_item.items()):
                    if kg > QUALITY_LIMIT_KG:
                        value, how = _value_of_kg(cur, name, aliases, settings, kg, yesterday)
                        txt = f'{name}: {round(kg, 2)} kg' + (f' ≈ ₹{value:,.0f} {how}' if value is not None else f' ({how})')
                        add('quality_' + table, 'warning', section, f'{section} above {QUALITY_LIMIT_KG:g} kg - cost of this material',
                            yesterday, txt, value)

        # ---------------- B grade (stock entered today = closing of previous control date, after 12 noon) ----------------
        if now.hour >= 12:
            cur.execute('SELECT item, b_grade_qty, b_grade_unit, pcs_b_grade FROM stock_updates WHERE date = ?', (today,))
            per_item = {}
            for item, q, u, p in cur.fetchall():
                name = resolve(item)
                kg = _qty_to_kg(q, u)
                if kg <= 0 and _num(p) > 0:
                    w = _weight_on(cur, name, today, settings)
                    kg = _num(p) * w if w else 0.0
                per_item[name] = per_item.get(name, 0.0) + kg
            for name, kg in sorted(per_item.items()):
                if kg > B_GRADE_LIMIT_KG:
                    value, how = _value_of_kg(cur, name, aliases, settings, kg, yesterday)
                    txt = f'{name}: {round(kg, 2)} kg' + (f' ≈ ₹{value:,.0f} {how}' if value is not None else f' ({how})')
                    add('b_grade_high', 'warning', 'B grade',
                        f'B grade above {B_GRADE_LIMIT_KG:g} kg - will cost this much if not addressed', yesterday, txt, value)

        # ---------------- Forecast ----------------
        fc = _compute_forecast(conn, today, FORECAST_WINDOW_DAYS)
        for f in fc['items']:
            if f['status'] == 'order_now':
                add('forecast_order_now', 'warning', 'Forecast', f'Order now to keep {FORECAST_COVER_DAYS} days of stock', today,
                    f"{f['item']}: order {f['suggested_order_qty']} {f['unit']} (stock {f['stock']} {f['unit']}, "
                    f"{f['days_of_cover'] if f['days_of_cover'] is not None else '-'} days)")
            elif f['status'] == 'needs_expected_qty':
                add('forecast_needs_qty', 'info', 'Forecast', 'New item in forecast - enter expected daily order quantity', today, f['item'])

        sev_order = {'error': 0, 'warning': 1, 'info': 2}
        out = sorted(alerts.values(), key=lambda a: (ALERT_SECTIONS.index(a['category']) if a['category'] in ALERT_SECTIONS else 99,
                                                     sev_order[a['severity']], -(int((a['control_date'] or '0').replace('-', '')))))
        summary = {s: sum(1 for a in out if a['severity'] == s) for s in ('error', 'warning', 'info')}
        sections = []
        for name in ALERT_SECTIONS:
            items = [a for a in out if a['category'] == name]
            if items:
                sections.append({'section': name, 'count': len(items),
                                 'errors': sum(1 for a in items if a['severity'] == 'error'),
                                 'warnings': sum(1 for a in items if a['severity'] == 'warning'),
                                 'amount': round(sum(a['amount'] for a in items), 2)})
        return {'generated_at': now.strftime('%Y-%m-%d %H:%M'), 'today': today, 'control_dates': ctrl_dates,
                'summary': summary, 'sections': sections, 'alerts': out}
    finally:
        conn.close()


@app.route('/alerts', methods=['GET'])
def get_alerts():
    """Daily checks for the last 10 control dates. ?days=10"""
    days = max(1, min(request.args.get('days', ALERT_DAYS, type=int), 60))
    _process_report_queue_safe()
    return jsonify({'success': True, **_compute_alerts(_ist_now(), days)})


@app.route('/alerts/count', methods=['GET'])
def get_alerts_count():
    r = _compute_alerts(_ist_now(), ALERT_DAYS)
    return jsonify({'success': True, **r['summary'], 'generated_at': r['generated_at']})


# ---------------- Forecast ----------------
def _setup_forecast_tables():
    conn = _report_conn()
    try:
        conn.execute('''CREATE TABLE IF NOT EXISTS forecast_items (
            item_key TEXT PRIMARY KEY, item_name TEXT, expected_daily_qty REAL,
            added_manually INTEGER DEFAULT 0, updated_at TEXT)''')
        conn.commit()
    finally:
        conn.close()


def _compute_forecast(conn, today, window=FORECAST_WINDOW_DAYS, cover_days=FORECAST_COVER_DAYS):
    """Everything in kg.
    Items: in stock update during the last 10 days (+ items added to the forecast).
    Demand: average daily SALES (app sales entries, kg) over the last `window` days
            = forecast for tomorrow.
    Stock:  A grade + ungraded (kg) in the latest stock update.
    Plus open POs, days of cover and what to order to keep cover_days days."""
    cur = conn.cursor()
    canon, aliases = _load_item_catalog(cur)
    settings = _item_settings_map(cur)
    resolve = lambda n: _resolve_item(n, canon, aliases)
    cur.execute('SELECT DISTINCT item FROM stock_updates WHERE date BETWEEN ? AND ?',
                (_shift_date(today, -FORECAST_STOCK_LOOKBACK_DAYS), today))
    items = {r for (raw,) in cur.fetchall() for r in [resolve(raw)] if r}
    cur.execute('SELECT item_name, expected_daily_qty, added_manually FROM forecast_items')
    overrides = {}
    for name, qty, manual in cur.fetchall():
        n = resolve(name)
        if n:
            overrides[n] = {'qty': qty, 'manual': bool(manual)}
            if manual:
                items.add(n)

    def weight_of(item):
        return _weight_on(cur, item, today, settings)

    # sales (kg) in the window
    w_start, w_end = _shift_date(today, -window), _shift_date(today, -1)
    cur.execute('SELECT item, quantity, unit, date FROM sales WHERE date BETWEEN ? AND ?', (w_start, w_end))
    demand = {}
    for name, q, u, d in cur.fetchall():
        n = resolve(name)
        if not n:
            continue
        dm = demand.setdefault(n, {'kg': 0.0, 'days': set(), 'pcs_without_weight': 0})
        if _is_pcs_unit(u):
            w = weight_of(n)
            if w:
                dm['kg'] += _num(q) * w
            else:
                dm['pcs_without_weight'] += 1
        else:
            dm['kg'] += _qty_to_kg(q, u)
        dm['days'].add(d)
    cur.execute('SELECT DISTINCT item FROM sales')
    ever_sold = {r for (raw,) in cur.fetchall() for r in [resolve(raw)] if r}

    out = []
    for item in sorted(items, key=str.lower):
        keys = sorted(_keys_for_item(item, aliases))
        ph = ','.join('?' * len(keys))
        avg_w = weight_of(item)
        notes = []

        dm = demand.get(item)
        total = dm['kg'] if dm else 0.0
        if dm and dm['pcs_without_weight']:
            notes.append(f"{dm['pcs_without_weight']} sales entries are in pieces - set the weight per piece in Item Settings")
        sales_avg = total / window if window else 0.0
        avg = sales_avg
        basis = 'sales (last %d days)' % window
        ov = overrides.get(item)
        if ov and ov['qty'] is not None:
            # quantity entered by the user replaces the sales average
            avg, basis = _num(ov['qty']), 'expected (entered)'
        elif total <= 0:
            if item in ever_sold:
                avg = 0.0
            else:
                basis = None  # never sold: ask for the expected quantity

        # latest stock: A grade + ungraded, kg
        cur.execute(f'SELECT MAX(date) FROM stock_updates WHERE norm_item(item) IN ({ph}) AND date <= ?', (*keys, today))
        sdate = cur.fetchone()[0]
        stock = 0.0
        pcs_only = 0.0
        if sdate:
            cur.execute(f'SELECT a_grade_qty, a_grade_unit, pcs_a_grade, ungraded_qty, ungraded_unit, pcs_ungraded '
                        f'FROM stock_updates WHERE norm_item(item) IN ({ph}) AND date = ?', (*keys, sdate))
            for aq, au, ap, uq, uu, up in cur.fetchall():
                for q, u, p in ((aq, au, ap), (uq, uu, up)):
                    kg = _qty_to_kg(q, u)
                    if kg > 0:
                        stock += kg
                    elif _num(p) > 0:
                        # only pieces entered for this grade
                        if avg_w:
                            stock += _num(p) * avg_w
                        else:
                            pcs_only += _num(p)
            if pcs_only:
                notes.append(f'{pcs_only:g} pcs of stock entered only in pieces - set the weight per piece in Item Settings to count them')
            if sdate < _shift_date(today, -1):
                notes.append(f'Latest stock entry is from {sdate}')

        # open POs (expected today or later), quantity not yet received, kg
        incoming = 0.0
        cur.execute(f'SELECT po_number, item_name, qty_ordered, unit FROM generated_pos '
                    f'WHERE norm_item(item_name) IN ({ph}) AND expected_date >= ?', (*keys, today))
        for po, iname, qty, punit in cur.fetchall():
            cur.execute('SELECT qty_receive, unit_receive FROM purchases WHERE TRIM(po_number) = TRIM(?) AND norm_item(item) = ?',
                        (po, _norm_item(iname)))
            got = sum((_qty_in_po_unit(q, u, punit) or 0) for q, u in cur.fetchall())
            left = max(_num(qty) - got, 0.0)
            fam, f = _unit_family(punit)
            if fam == 'weight':
                incoming += left * f
            elif fam == 'count' and avg_w and _unit_family(punit)[1] == 'pcs':
                incoming += left * avg_w

        if basis is None:
            status, cover, order_qty, order_by, stock_out = 'needs_expected_qty', None, None, None, None
        elif avg <= 0:
            status, cover, order_qty, order_by, stock_out = 'no_demand', None, 0.0, None, None
        else:
            cover = stock / avg
            need = cover_days * avg
            order_qty = max(need - stock - incoming, 0.0)
            order_by_days = max(int(cover - cover_days), 0)
            order_by = _shift_date(today, order_by_days)
            stock_out = _shift_date(today, int(cover))
            if order_qty > 0:
                status, order_by = 'order_now', today
            elif (stock + incoming) / avg < cover_days + 1 or order_by_days <= 1:
                status = 'order_soon'
            else:
                status = 'ok'
        r2 = lambda v: None if v is None else round(v, 2)
        out.append({
            'item': item, 'unit': 'kg', 'basis': basis,
            'sales_days': len(dm['days']) if dm else 0,
            'avg_daily_demand': r2(avg) if basis else None,
            'forecast_next_day': r2(avg) if basis else None,
            'stock': r2(stock), 'stock_date': sdate, 'incoming_open_po': r2(incoming),
            'days_of_cover': r2(cover), 'stock_out_date': stock_out,
            'need_for_cover_days': r2(cover_days * avg) if basis else None,
            'suggested_order_qty': r2(order_qty), 'order_by': order_by, 'status': status,
            'sales_avg': r2(sales_avg), 'has_sales_history': item in ever_sold,
            'expected_daily_qty': ov['qty'] if ov else None, 'added_manually': bool(ov and ov['manual']),
            'notes': notes,
        })
    order = {'order_now': 0, 'needs_expected_qty': 1, 'order_soon': 2, 'ok': 3, 'no_demand': 4}
    out.sort(key=lambda f: (order[f['status']], f['days_of_cover'] if f['days_of_cover'] is not None else 1e9))
    return {'today': today, 'window_days': window, 'window': [w_start, w_end],
            'cover_days': cover_days, 'unit': 'kg', 'items': out}


@app.route('/forecast', methods=['GET'])
def get_forecast():
    """?window=7 (days of sales orders to average)"""
    window = max(1, min(request.args.get('window', FORECAST_WINDOW_DAYS, type=int), 60))
    cover = max(1, min(request.args.get('cover_days', FORECAST_COVER_DAYS, type=int), 60))
    now = _ist_now()
    conn = _report_conn()
    try:
        return jsonify({'success': True, **_compute_forecast(conn, now.strftime('%Y-%m-%d'), window, cover)})
    finally:
        conn.close()


@app.route('/forecast/expected_qty', methods=['POST'])
def set_forecast_expected_qty():
    """JSON: {"item": "Avocado", "expected_daily_qty": 25, "add": true}
    add=true also puts the item on the forecast list even without stock."""
    data = request.get_json(silent=True) or {}
    conn = _report_conn()
    try:
        cur = conn.cursor()
        canon, aliases = _load_item_catalog(cur)
        name = _resolve_item(data.get('item'), canon, aliases)
        if not name:
            return jsonify({'success': False, 'message': f"'{data.get('item')}' is not in the Admin item list"}), 400
        q = data.get('expected_daily_qty')
        q = None if q in (None, '') else _num(q)
        if q is not None and q < 0:
            return jsonify({'success': False, 'message': 'Quantity cannot be negative'}), 400
        cur.execute('SELECT added_manually FROM forecast_items WHERE item_key = ?', (_norm_item(name),))
        old = cur.fetchone()
        manual = 1 if data.get('add') in (True, 1, '1', 'true') else (old[0] if old else 0)
        cur.execute('INSERT OR REPLACE INTO forecast_items (item_key, item_name, expected_daily_qty, added_manually, updated_at) '
                    'VALUES (?, ?, ?, ?, ?)', (_norm_item(name), name, q, manual, datetime.now().isoformat(timespec='seconds')))
        conn.commit()
        return jsonify({'success': True, 'item': name, 'expected_daily_qty': q})
    finally:
        conn.close()


@app.route('/forecast/remove_item', methods=['POST', 'DELETE'])
def remove_forecast_item():
    data = request.get_json(silent=True) or {}
    item = data.get('item') or request.args.get('item')
    conn = _report_conn()
    try:
        conn.execute('DELETE FROM forecast_items WHERE item_key = ?', (_norm_item(item),))
        conn.commit()
        return jsonify({'success': True})
    finally:
        conn.close()


_setup_forecast_tables()




# =====================================================================
# PURCHASE EXTRAS, SALES CLASS, HEAD VERIFICATION, B GRADE ANALYSIS
# =====================================================================
import hashlib as _hashlib
import secrets as _secrets

_PURCHASE_EXTRA_COLS = [('underweight_qty', 'REAL'), ('underweight_rate', 'REAL'), ('overweight_qty', 'REAL'),
                        ('overweight_rate', 'REAL'), ('extra_expense', 'REAL'), ('extra_expense_reason', 'TEXT')]


def _setup_v6_tables():
    conn = _report_conn()
    try:
        cur = conn.cursor()
        for col, typ in _PURCHASE_EXTRA_COLS:
            try:
                cur.execute(f'ALTER TABLE purchases ADD COLUMN {col} {typ}')
            except sqlite3.OperationalError:
                pass
        try:
            cur.execute("ALTER TABLE sales ADD COLUMN material_class TEXT DEFAULT 'A'")
        except sqlite3.OperationalError:
            pass
        cur.execute('''CREATE TABLE IF NOT EXISTS head_verification (
            id INTEGER PRIMARY KEY CHECK (id = 1), salt TEXT, password_hash TEXT, set_at TEXT)''')
        cur.execute('''CREATE TABLE IF NOT EXISTS entry_verifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT, table_name TEXT, entry_id INTEGER, ref_type TEXT, ref TEXT,
            other_entry_ids TEXT, status TEXT DEFAULT 'pending', entry_snapshot TEXT,
            created_at TEXT, decided_at TEXT, note TEXT)''')
        cur.execute('''CREATE TABLE IF NOT EXISTS verify_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT, table_name TEXT, entry_id INTEGER)''')
        cur.execute('''CREATE TABLE IF NOT EXISTS bgrade_rates (
            item_key TEXT PRIMARY KEY, item_name TEXT, main_b_rate REAL, mandi_rate REAL, updated_at TEXT)''')
        for t in ('lmd_data', 'fmd_data'):
            cur.execute(f'DROP TRIGGER IF EXISTS trg_verify_{t}_ins')
            cur.execute(f'DROP TRIGGER IF EXISTS trg_verify_{t}_upd')
            cur.execute(f"CREATE TRIGGER trg_verify_{t}_ins AFTER INSERT ON {t} BEGIN "
                        f"INSERT INTO verify_queue (table_name, entry_id) VALUES ('{t}', NEW.id); END")
            cur.execute(f"CREATE TRIGGER trg_verify_{t}_upd AFTER UPDATE OF po_number ON {t} BEGIN "
                        f"INSERT INTO verify_queue (table_name, entry_id) VALUES ('{t}', NEW.id); END")
        conn.commit()
    finally:
        conn.close()


# ---------- purchase: underweight / overweight / extra expense ----------
def _apply_purchase_extras(cursor, purchase_id, row):
    """Stores underweight / overweight / extra expense and recalculates the totals:
    total = accepted x rate + low grade + underweight x UW rate + overweight x OW rate + extra expense
    (empty fields = 0). Returns (total_amount, amount_due)."""
    cursor.execute('SELECT amount_of_accepted, total_low_grade_amount, amount_paid, po_number, '
                   'underweight_qty, underweight_rate, overweight_qty, overweight_rate, extra_expense, extra_expense_reason '
                   'FROM purchases WHERE id = ?', (purchase_id,))
    r = cursor.fetchone()
    if not r:
        return None, None
    aoa, low_amt, paid, po = _num(r[0]), _num(r[1]), _num(r[2]), r[3]
    current = dict(zip([c for c, _ in _PURCHASE_EXTRA_COLS], r[4:]))
    vals = {}
    for col, typ in _PURCHASE_EXTRA_COLS:
        if col in row:  # keep the stored value when the screen did not send the field
            v = row.get(col)
            vals[col] = (str(v).strip() if v is not None else None) if typ == 'TEXT' else _num(v)
        else:
            vals[col] = current[col] if typ == 'TEXT' else _num(current[col])
    total = (aoa + low_amt + vals['underweight_qty'] * vals['underweight_rate']
             + vals['overweight_qty'] * vals['overweight_rate'] + vals['extra_expense'])
    cursor.execute('SELECT advanced_payment FROM generated_pos WHERE po_number = ? LIMIT 1', (po,))
    adv = cursor.fetchone()
    due = total - paid - (_num(adv[0]) if adv else 0.0)
    cursor.execute(
        'UPDATE purchases SET underweight_qty=?, underweight_rate=?, overweight_qty=?, overweight_rate=?, '
        'extra_expense=?, extra_expense_reason=?, total_amount=?, amount_due=? WHERE id=?',
        (vals['underweight_qty'], vals['underweight_rate'], vals['overweight_qty'], vals['overweight_rate'],
         vals['extra_expense'], vals['extra_expense_reason'], round(total, 2), round(due, 2), purchase_id))
    return round(total, 2), round(due, 2)


# ---------- sales: class of material (A / B) ----------
def _set_sale_class(cursor, sale_id, row):
    if 'material_class' not in row:
        return
    cls = str(row.get('material_class') or 'A').strip().upper()
    cls = 'B' if cls.startswith('B') else 'A'
    cursor.execute('UPDATE sales SET material_class = ? WHERE id = ?', (cls, sale_id))


# ---------- head verification of a 2nd LMD / FMD entry ----------
def _hash_pw(salt, pw):
    return _hashlib.sha256((salt + (pw or '')).encode('utf-8')).hexdigest()


def _check_head_password(cur, pw):
    cur.execute('SELECT salt, password_hash FROM head_verification WHERE id = 1')
    r = cur.fetchone()
    return bool(r and r[1] and _hash_pw(r[0], pw) == r[1])


def _entry_refs(table, value):
    return _split_so_refs(value) if table == 'lmd_data' else _split_refs(value)


def _process_verify_queue():
    """New / changed LMD and FMD entries: if an SO (LMD) or PO (FMD) is already in
    another entry, hold the new entry for head approval."""
    conn = _report_conn(timeout=10)
    try:
        cur = conn.cursor()
        cur.execute('BEGIN IMMEDIATE')
        cur.execute('SELECT id, table_name, entry_id FROM verify_queue ORDER BY id')
        rows = cur.fetchall()
        if not rows:
            conn.rollback()
            return
        for _qid, table, eid in rows:
            cur.execute(f'SELECT * FROM {table} WHERE id = ?', (eid,))
            entry = cur.fetchone()
            if not entry:
                continue
            cols = [d[0] for d in cur.description]
            entry = dict(zip(cols, entry))
            refs = _entry_refs(table, entry.get('po_number'))
            if not refs:
                continue
            cur.execute(f'SELECT id, po_number FROM {table} WHERE id != ?', (eid,))
            others = {}
            for oid, oref in cur.fetchall():
                for k in _entry_refs(table, oref) & refs:
                    others.setdefault(k, []).append(oid)
            for k, ids in others.items():
                cur.execute("SELECT 1 FROM entry_verifications WHERE table_name = ? AND entry_id = ? AND ref = ? "
                            "AND status IN ('pending', 'approved')", (table, eid, k))
                if cur.fetchone():
                    continue
                cur.execute('INSERT INTO entry_verifications (table_name, entry_id, ref_type, ref, other_entry_ids, status, '
                            'entry_snapshot, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                            (table, eid, 'SO' if table == 'lmd_data' else 'PO', k, ','.join(map(str, sorted(ids))),
                             'pending', json.dumps(entry, default=str), _ist_now().strftime('%Y-%m-%d %H:%M')))
        cur.execute('DELETE FROM verify_queue WHERE id <= ?', (rows[-1][0],))
        conn.commit()
    except Exception as e:
        conn.rollback()
        print(f'⚠️ [verification] queue failed: {e}')
    finally:
        conn.close()


def _pending_entry_ids(cur, table):
    try:
        cur.execute("SELECT DISTINCT entry_id FROM entry_verifications WHERE table_name = ? AND status = 'pending'", (table,))
        return {r[0] for r in cur.fetchall()}
    except sqlite3.OperationalError:
        return set()


@app.after_request
def _verify_after_write(response):
    path = request.path.rstrip('/')
    if request.method in ('POST', 'PUT') and path in ('/insert_lmd_data', '/insert_fmd_data', '/update_lmd_data', '/update_fmd_data'):
        _process_verify_queue()
        if path.startswith('/insert') and response.status_code in (200, 201) and response.is_json:
            try:
                body = response.get_json()
                table = 'lmd_data' if 'lmd' in path else 'fmd_data'
                if isinstance(body, dict) and body.get('id') is not None:
                    conn = _report_conn()
                    try:
                        cur = conn.cursor()
                        cur.execute("SELECT ref, ref_type FROM entry_verifications WHERE table_name = ? AND entry_id = ? AND status = 'pending'",
                                    (table, body['id']))
                        refs = cur.fetchall()
                    finally:
                        conn.close()
                    if refs:
                        body['verification_pending'] = True
                        body['verification_message'] = (
                            f"Saved, but {', '.join(f'{t} {r}' for r, t in refs)} already has an "
                            f"{'LMD' if table == 'lmd_data' else 'FMD'} entry. This entry is on hold until the head approves it.")
                        response.set_data(json.dumps(body))
            except Exception as e:
                print(f'⚠️ [verification] response note failed: {e}')
    return response


@app.route('/verification/password_status', methods=['GET'])
def verification_password_status():
    conn = _report_conn()
    try:
        cur = conn.cursor()
        cur.execute('SELECT set_at FROM head_verification WHERE id = 1 AND password_hash IS NOT NULL')
        r = cur.fetchone()
        return jsonify({'success': True, 'is_set': bool(r), 'set_at': r[0] if r else None})
    finally:
        conn.close()


@app.route('/verification/set_password', methods=['POST'])
def verification_set_password():
    """First time: {"new_password", "admin_key"}.  Change: {"new_password", "old_password"}.
    This password is separate from all section passwords and is never listed anywhere."""
    data = request.get_json(silent=True) or {}
    new = str(data.get('new_password') or '')
    if len(new) < 4:
        return jsonify({'success': False, 'message': 'Use at least 4 characters'}), 400
    conn = _report_conn()
    try:
        cur = conn.cursor()
        cur.execute('SELECT password_hash FROM head_verification WHERE id = 1')
        r = cur.fetchone()
        if r and r[0]:
            if not _check_head_password(cur, data.get('old_password')):
                return jsonify({'success': False, 'message': 'Old verification password is wrong'}), 403
        elif not _check_admin_key(data.get('admin_key')):
            return jsonify({'success': False, 'message': 'Admin password needed to set the verification password the first time'}), 403
        if new == str(data.get('admin_key') or ''):
            return jsonify({'success': False, 'message': 'Choose a password different from the admin password'}), 400
        cur.execute('SELECT password_hash FROM section_groups')
        if new in {p for (p,) in cur.fetchall()}:
            return jsonify({'success': False, 'message': 'Choose a password different from all section passwords'}), 400
        salt = _secrets.token_hex(8)
        cur.execute('INSERT OR REPLACE INTO head_verification (id, salt, password_hash, set_at) VALUES (1, ?, ?, ?)',
                    (salt, _hash_pw(salt, new), _ist_now().strftime('%Y-%m-%d %H:%M')))
        conn.commit()
        return jsonify({'success': True, 'message': 'Verification password saved'})
    finally:
        conn.close()


@app.route('/verifications', methods=['GET'])
def list_verifications():
    """?status=pending (default) | all"""
    status = request.args.get('status', 'pending')
    _process_verify_queue()
    conn = _report_conn()
    try:
        cur = conn.cursor()
        where = '' if status == 'all' else "WHERE status = 'pending'"
        cur.execute(f'SELECT id, table_name, entry_id, ref_type, ref, other_entry_ids, status, entry_snapshot, created_at, decided_at, note '
                    f'FROM entry_verifications {where} ORDER BY id DESC LIMIT 200')
        out = []
        for vid, table, eid, rtype, ref, others, st, snap, created, decided, note in cur.fetchall():
            cur.execute(f'SELECT * FROM {table} WHERE id = ?', (eid,))
            row = cur.fetchone()
            entry = dict(zip([d[0] for d in cur.description], row)) if row else (json.loads(snap) if snap else {})
            other_rows = []
            for oid in [int(x) for x in (others or '').split(',') if x.strip().isdigit()]:
                cur.execute(f'SELECT * FROM {table} WHERE id = ?', (oid,))
                o = cur.fetchone()
                if o:
                    other_rows.append(dict(zip([d[0] for d in cur.description], o)))
            out.append({'id': vid, 'type': 'LMD' if table == 'lmd_data' else 'FMD', 'entry_id': eid, 'ref_type': rtype,
                        'ref': ref, 'status': st, 'created_at': created, 'decided_at': decided, 'note': note,
                        'entry': entry, 'existing_entries': other_rows})
        return jsonify({'success': True, 'data': out})
    finally:
        conn.close()


@app.route('/verifications/decide', methods=['POST'])
def decide_verification():
    """JSON: {"id": 5, "decision": "approve"|"reject", "password": "<head verification password>", "note": ""}
    Reject removes the held entry."""
    data = request.get_json(silent=True) or {}
    decision = data.get('decision')
    if decision not in ('approve', 'reject'):
        return jsonify({'success': False, 'message': "decision must be 'approve' or 'reject'"}), 400
    conn = _report_conn()
    try:
        cur = conn.cursor()
        if not _check_head_password(cur, data.get('password')):
            return jsonify({'success': False, 'message': 'Wrong verification password'}), 403
        cur.execute("SELECT table_name, entry_id, status FROM entry_verifications WHERE id = ?", (data.get('id'),))
        r = cur.fetchone()
        if not r:
            return jsonify({'success': False, 'message': 'Not found'}), 404
        table, eid, st = r
        if st != 'pending':
            return jsonify({'success': False, 'message': f'Already {st}'}), 400
        now = _ist_now().strftime('%Y-%m-%d %H:%M')
        new_status = 'approved' if decision == 'approve' else 'rejected'
        # one entry may be held for several SOs/POs: decide all of them together
        cur.execute("UPDATE entry_verifications SET status = ?, decided_at = ?, note = ? WHERE table_name = ? AND entry_id = ? AND status = 'pending'",
                    (new_status, now, data.get('note'), table, eid))
        if decision == 'reject':
            cur.execute(f'DELETE FROM {table} WHERE id = ?', (eid,))
        conn.commit()
        return jsonify({'success': True, 'status': new_status,
                        'message': 'Approved' if decision == 'approve' else 'Rejected - the entry was removed'})
    finally:
        conn.close()


# ---------- B grade value analysis ----------
def _bgrade_kg(q, u, p, avg_w):
    kg = _qty_to_kg(q, u)
    if kg <= 0 and _num(p) > 0 and avg_w:
        kg = _num(p) * avg_w
    return kg


def _bgrade_analysis(start, end, rates_in):
    """Day by day, per item:
      opening    = B grade in that day's stock update (the TOTAL B grade counted,
                   which already includes the previous day's leftover).
                   If there is no stock update that day, the previous leftover is used.
      outflow    = main sales marked class B + B-grade sales + mandi resale + dump
      leftover   = opening - outflow
      added next day = next day's counted B grade - today's leftover
                   (new B grade that came in; negative = B grade unaccounted)
      value      = B-grade sales amount + main-sales-B qty x your rate + mandi qty x your rate (dump = 0)
      compared with the purchase value of the same quantity (latest PO rate)."""
    conn = _report_conn()
    try:
        cur = conn.cursor()
        canon, aliases = _load_item_catalog(cur)
        settings = _item_settings_map(cur)
        resolve = lambda n: _resolve_item(n, canon, aliases) or (str(n).strip() if n else '')
        days = _date_range(start, end)

        stock = {}   # (item, day) -> kg B grade in stock update
        pcs_without_weight = {}
        cur.execute('SELECT item, date, b_grade_qty, b_grade_unit, pcs_b_grade FROM stock_updates WHERE date BETWEEN ? AND ?', (start, end))
        for item, d, q, u, p in cur.fetchall():
            n = resolve(item)
            w = _weight_on(cur, n, d, settings)
            stock[(n, d)] = stock.get((n, d), 0.0) + _bgrade_kg(q, u, p, w)
            if _qty_to_kg(q, u) <= 0 and _num(p) > 0 and not w:
                pcs_without_weight[n] = pcs_without_weight.get(n, 0.0) + _num(p)

        cur.execute('SELECT DISTINCT date FROM stock_updates WHERE date BETWEEN ? AND ?', (start, _shift_date(end, 1)))
        stock_dates_after = {r[0] for r in cur.fetchall()}
        # next-day counts (the day after `end` is needed for "added next day")
        cur.execute('SELECT item, b_grade_qty, b_grade_unit, pcs_b_grade FROM stock_updates WHERE date = ?', (_shift_date(end, 1),))
        for item, q, u, p in cur.fetchall():
            n = resolve(item)
            nd = _shift_date(end, 1)
            stock[(n, nd)] = stock.get((n, nd), 0.0) + _bgrade_kg(q, u, p, _weight_on(cur, n, nd, settings))

        day_settings = {}
        def st(d):
            if d not in day_settings:
                day_settings[d] = _settings_on(cur, d, settings)
            return day_settings[d]

        flows = {}   # (item, day) -> dict
        def flow(n, d):
            return flows.setdefault((n, d), {'main_b': 0.0, 'bsales': 0.0, 'bsales_amount': 0.0, 'mandi': 0.0, 'dump': 0.0})
        cur.execute("SELECT item, quantity, unit, pcs, date FROM sales WHERE material_class = 'B' AND date BETWEEN ? AND ?", (start, end))
        for item, q, u, p, d in cur.fetchall():
            n = resolve(item)
            flow(n, d)['main_b'] += _kg_with_pcs(q, u, st(d), n)
        cur.execute('SELECT item, quantity, unit, rate, total_value, date FROM b_grade_sales WHERE date BETWEEN ? AND ?', (start, end))
        for item, q, u, rate, tv, d in cur.fetchall():
            n = resolve(item)
            f = flow(n, d)
            f['bsales'] += _kg_with_pcs(q, u, st(d), n)
            f['bsales_amount'] += _num(tv) if _num(tv) > 0 else _num(q) * _num(rate)
        for table, key in (('mandi_resales', 'mandi'), ('dump_sales', 'dump')):
            cur.execute(f'SELECT item, quantity, unit, date FROM {table} WHERE date BETWEEN ? AND ?', (start, end))
            for item, q, u, d in cur.fetchall():
                n = resolve(item)
                flow(n, d)[key] += _kg_with_pcs(q, u, st(d), n)

        items = sorted({n for n, d in stock if d <= end} | {n for n, _ in flows if any(flows[(n, _)].values())}, key=str.lower)
        rates = {}
        for item in items:
            r = (rates_in or {}).get(item) or {}
            rates[item] = {'main_b_rate': r.get('main_b_rate'), 'mandi_rate': r.get('mandi_rate')}
        # remember the rates entered for next time
        cur.execute('SELECT item_name, main_b_rate, mandi_rate FROM bgrade_rates')
        saved = {n: (a, b) for n, a, b in cur.fetchall()}
        for item in items:
            for k, idx in (('main_b_rate', 0), ('mandi_rate', 1)):
                if rates[item][k] in (None, '') and item in saved and saved[item][idx] is not None:
                    rates[item][k] = saved[item][idx]
        for item, r in (rates_in or {}).items():
            n = resolve(item)
            if n:
                cur.execute('INSERT OR REPLACE INTO bgrade_rates (item_key, item_name, main_b_rate, mandi_rate, updated_at) VALUES (?, ?, ?, ?, ?)',
                            (_norm_item(n), n, None if r.get('main_b_rate') in (None, '') else _num(r.get('main_b_rate')),
                             None if r.get('mandi_rate') in (None, '') else _num(r.get('mandi_rate')), _ist_now().isoformat(timespec='seconds')))
        conn.commit()

        out_items, missing_rates = [], []
        tot = {k: 0.0 for k in ('opening', 'main_b', 'bsales', 'mandi', 'dump', 'outflow', 'value', 'purchase_value', 'leftover', 'leftover_value', 'added')}
        for item in items:
            keys = sorted(_keys_for_item(item, aliases))
            rb = _num(rates[item]['main_b_rate']) if rates[item]['main_b_rate'] not in (None, '') else None
            rm = _num(rates[item]['mandi_rate']) if rates[item]['mandi_rate'] not in (None, '') else None
            carry = None
            rows = []
            it = {k: 0.0 for k in tot}
            it['added'] = 0.0
            no_count_days = []
            for i, d in enumerate(days):
                f = flows.get((item, d), {'main_b': 0.0, 'bsales': 0.0, 'bsales_amount': 0.0, 'mandi': 0.0, 'dump': 0.0})
                has_count = (item, d) in stock
                counted = stock.get((item, d), 0.0)
                if has_count or carry is None:
                    opening = counted
                    source = 'stock update' if has_count else 'none'
                else:
                    opening = carry
                    source = 'previous leftover'
                    no_count_days.append(d)
                outflow = f['main_b'] + f['bsales'] + f['mandi'] + f['dump']
                leftover = opening - outflow
                value = f['bsales_amount'] + f['main_b'] * (rb or 0.0) + f['mandi'] * (rm or 0.0)
                pv, _how = _value_of_kg(cur, item, aliases, settings, outflow, d)
                pv = pv or 0.0
                nd = _shift_date(d, 1)
                if (item, nd) in stock or nd in stock_dates_after:
                    added_next = stock.get((item, nd), 0.0) - leftover
                else:
                    added_next = None
                rows.append({'date': d, 'stock_update_b': round(counted, 2) if has_count else None,
                             'opening': round(opening, 2), 'opening_from': source,
                             'main_sales_b': round(f['main_b'], 2), 'b_grade_sales': round(f['bsales'], 2),
                             'mandi': round(f['mandi'], 2), 'dump': round(f['dump'], 2), 'outflow': round(outflow, 2),
                             'leftover': round(leftover, 2),
                             'added_next_day': None if added_next is None else round(added_next, 2),
                             'value_generated': round(value, 2), 'purchase_value': round(pv, 2)})
                if i == 0:
                    it['opening'] = opening
                for k, v in (('main_b', f['main_b']), ('bsales', f['bsales']), ('mandi', f['mandi']), ('dump', f['dump']),
                             ('outflow', outflow), ('value', value), ('purchase_value', pv)):
                    it[k] += v
                if added_next is not None:
                    it['added'] += added_next
                carry = leftover
            it['leftover'] = carry
            lv, _ = _value_of_kg(cur, item, aliases, settings, max(carry, 0.0), end)
            it['leftover_value'] = lv or 0.0
            if (it['main_b'] > 0 and rb is None) or (it['mandi'] > 0 and rm is None):
                missing_rates.append(item)
            warnings = []
            if item in pcs_without_weight:
                warnings.append(f"B grade entered only in pieces ({pcs_without_weight[item]:g} pcs) on days with no weight per piece - "
                                f"enter the daily average weight (or a default in Item Settings), otherwise it counts as 0 kg")
            if no_count_days:
                warnings.append('No B grade in the stock update on ' + ', '.join(no_count_days) + ' - previous leftover used as opening')
            if any(r['leftover'] < 0 for r in rows):
                warnings.append('More B material went out than was in B-grade stock on some days - check the stock update '
                                'B grade or whether A-grade material was sent as B')
            if it['mandi'] > 0:
                warnings.append('All mandi resale of this item is counted as B grade')
            for k in tot:
                tot[k] += it[k]
            out_items.append({
                'item': item, 'main_b_rate': rb, 'mandi_rate': rm,
                'opening': round(it['opening'], 2), 'main_sales_b': round(it['main_b'], 2), 'b_grade_sales': round(it['bsales'], 2),
                'mandi': round(it['mandi'], 2), 'dump': round(it['dump'], 2), 'outflow': round(it['outflow'], 2),
                'leftover': round(it['leftover'], 2), 'leftover_purchase_value': round(it['leftover_value'], 2),
                'added_b_grade': round(it['added'], 2),
                'value_generated': round(it['value'], 2), 'purchase_value': round(it['purchase_value'], 2),
                'recovery_percent': round(it['value'] / it['purchase_value'] * 100, 1) if it['purchase_value'] else None,
                'warnings': warnings,
                'days': rows,
            })
        out_items.sort(key=lambda x: -x['purchase_value'])
        return {
            'start': start, 'end': end, 'items': out_items, 'missing_rates': missing_rates,
            'totals': {k: round(v, 2) for k, v in tot.items()} | {
                'recovery_percent': round(tot['value'] / tot['purchase_value'] * 100, 1) if tot['purchase_value'] else None},
            'notes': ['Opening each day = total B grade counted in that day\'s stock update (it already includes the previous leftover).',
                      'Added next day = next day\'s counted B grade minus today\'s leftover (new B grade; negative = unaccounted).',
                      'Dump is valued at 0.',
                      'Value = B-grade sales amount + main sales marked "B" x your rate + mandi x your rate.',
                      'Purchase value = the same quantity at the rate of the latest PO received for the item.'],
        }
    finally:
        conn.close()


@app.route('/bgrade/analysis', methods=['POST'])
def bgrade_analysis():
    """JSON: {"start": "2026-10-10", "end": "2026-10-12",
              "rates": {"Papaya": {"main_b_rate": 20, "mandi_rate": 12}, ...}}
    end may equal start (one day). Rates are remembered for next time."""
    data = request.get_json(silent=True) or {}
    start = _to_iso_date(data.get('start'))
    end = _to_iso_date(data.get('end')) or start
    if not start:
        return jsonify({'success': False, 'message': 'start date is required'}), 400
    if end < start:
        start, end = end, start
    _process_report_queue_safe()
    return jsonify({'success': True, **_bgrade_analysis(start, end, data.get('rates') or {})})


_setup_v6_tables()




# =====================================================================
# DAILY AVERAGE WEIGHT PER PIECE (papaya / pineapple)
# The app asks for it every day (alert in the Stock section); each day's
# weight is stored and used for that day in GPM, B grade analysis,
# alerts and forecast. Days without an entry use the latest earlier
# weight, else the default in Item Settings.
# =====================================================================
def _setup_daily_weights():
    conn = _report_conn()
    try:
        conn.execute('''CREATE TABLE IF NOT EXISTS item_daily_weights (
            item_key TEXT, item_name TEXT, date TEXT, avg_piece_weight_kg REAL, entered_at TEXT,
            PRIMARY KEY (item_key, date))''')
        conn.commit()
    finally:
        conn.close()


def _setup_item_unit_columns():
    conn = _report_conn()
    try:
        for col in ('stock_in_pcs INTEGER', 'needs_unit INTEGER DEFAULT 0'):
            try:
                conn.execute(f'ALTER TABLE item_settings ADD COLUMN {col}')
            except sqlite3.OperationalError:
                pass
        conn.commit()
    finally:
        conn.close()


def _record_new_item_unit(name, payload, new_item):
    """insert_item: store "stock in pieces" (+ average weight) when the screen sent it;
    a brand-new item without the answer is flagged so Alerts / Item Settings ask for it."""
    payload = payload or {}
    conn = _report_conn()
    try:
        cur = conn.cursor()
        k = _norm_item(name)
        cur.execute('SELECT is_packaging, avg_piece_weight_kg, stock_in_pcs FROM item_settings WHERE item_key = ?', (k,))
        old = cur.fetchone()
        if 'stock_in_pcs' in payload:
            sp = 1 if payload.get('stock_in_pcs') in (True, 1, '1', 'true') else 0
            w = payload.get('avg_piece_weight_kg')
            w = (None if w in (None, '') else _num(w)) if sp else None
            cur.execute('INSERT OR REPLACE INTO item_settings (item_key, item_name, is_packaging, avg_piece_weight_kg, stock_in_pcs, needs_unit, updated_at) '
                        'VALUES (?, ?, ?, ?, ?, 0, ?)', (k, name, old[0] if old else 0, w if w else (old[1] if old else None), sp,
                                                        datetime.now().isoformat(timespec='seconds')))
            _PCS_CACHE['at'] = 0.0
        elif new_item and not old:
            cur.execute('INSERT INTO item_settings (item_key, item_name, is_packaging, needs_unit, updated_at) VALUES (?, ?, 0, 1, ?)',
                        (k, name, datetime.now().isoformat(timespec='seconds')))
        conn.commit()
    except sqlite3.Error as e:
        print(f'⚠️ [items] could not save stock unit for {name}: {e}')
    finally:
        conn.close()


def _piece_weight_items(cur, canon, settings, today):
    """Piece-counted items (papaya / pineapple) that are in stock in the last
    10 days and are not packaging - these need a daily weight."""
    _, aliases = _load_item_catalog(cur)
    cur.execute('SELECT DISTINCT item FROM stock_updates WHERE date BETWEEN ? AND ?', (_shift_date(today, -10), today))
    names = set()
    for (raw,) in cur.fetchall():
        n = _resolve_item(raw, canon, aliases)
        if n and _is_pcs_item(n) and not settings.get(_norm_item(n), {}).get('is_packaging'):
            names.add(n)
    return sorted(names, key=str.lower)


@app.route('/piece_weights', methods=['GET'])
def get_piece_weights():
    """?date=yyyy-MM-dd (default today). Items needing a weight, with the value
    for that date (if entered) and the last weight entered before it."""
    date = _to_iso_date(request.args.get('date')) or _ist_now().strftime('%Y-%m-%d')
    conn = _report_conn()
    try:
        cur = conn.cursor()
        canon, _ = _load_item_catalog(cur)
        settings = _item_settings_map(cur)
        items = _piece_weight_items(cur, canon, settings, date)
        out = []
        for name in items:
            k = _norm_item(name)
            cur.execute('SELECT avg_piece_weight_kg FROM item_daily_weights WHERE item_key = ? AND date = ?', (k, date))
            r = cur.fetchone()
            cur.execute('SELECT date, avg_piece_weight_kg FROM item_daily_weights WHERE item_key = ? AND date < ? '
                        'ORDER BY date DESC LIMIT 1', (k, date))
            last = cur.fetchone()
            out.append({'item': name, 'weight': r[0] if r else None,
                        'last_weight': last[1] if last else None, 'last_date': last[0] if last else None,
                        'default_weight': settings.get(k, {}).get('avg_piece_weight_kg')})
        cur.execute('SELECT date, item_name, avg_piece_weight_kg FROM item_daily_weights ORDER BY date DESC, item_name LIMIT 60')
        history = [{'date': d, 'item': n, 'weight': w} for d, n, w in cur.fetchall()]
        return jsonify({'success': True, 'date': date, 'items': out, 'history': history})
    finally:
        conn.close()


@app.route('/piece_weights', methods=['POST'])
def save_piece_weights():
    """JSON: {"date": "2026-10-15", "weights": {"Papaya": 1.15, "Pineapple": 1.4}}"""
    data = request.get_json(silent=True) or {}
    date = _to_iso_date(data.get('date')) or _ist_now().strftime('%Y-%m-%d')
    weights = data.get('weights') or {}
    conn = _report_conn()
    try:
        cur = conn.cursor()
        canon, aliases = _load_item_catalog(cur)
        saved = 0
        for item, w in weights.items():
            name = _resolve_item(item, canon, aliases)
            if not name:
                return jsonify({'success': False, 'message': f"'{item}' is not in the Admin item list"}), 400
            if w in (None, ''):
                cur.execute('DELETE FROM item_daily_weights WHERE item_key = ? AND date = ?', (_norm_item(name), date))
                continue
            w = _num(w)
            if w <= 0 or w > 50:
                return jsonify({'success': False, 'message': f'Weight for {name} must be between 0 and 50 kg'}), 400
            cur.execute('INSERT OR REPLACE INTO item_daily_weights (item_key, item_name, date, avg_piece_weight_kg, entered_at) '
                        'VALUES (?, ?, ?, ?, ?)', (_norm_item(name), name, date, w, _ist_now().strftime('%Y-%m-%d %H:%M')))
            saved += 1
        conn.commit()
    finally:
        conn.close()
    return jsonify({'success': True, 'saved': saved, 'date': date})


_setup_daily_weights()
_setup_item_unit_columns()



if __name__ == '__main__':
    init_db()
    _setup_report_automation()
    app.run(host='0.0.0.0', port=5000, debug=True)

