from flask import Flask, request, jsonify
from flask_cors import CORS
import sqlite3
import os
import json

app = Flask(__name__)
CORS(app)

db_path = 'mydata.db'

def init_db():
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    # Create all tables as per _createAllTables
    cursor.execute('''CREATE TABLE IF NOT EXISTS product_managers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS generated_sos (id INTEGER PRIMARY KEY AUTOINCREMENT, client_name TEXT, so_number TEXT, date_of_dispatch TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS so_items (id INTEGER PRIMARY KEY AUTOINCREMENT, so_id INTEGER, item_name TEXT, quantity_kg REAL, quantity_pcs REAL, FOREIGN KEY (so_id) REFERENCES generated_sos (id) ON DELETE CASCADE)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS generated_pos (id INTEGER PRIMARY KEY AUTOINCREMENT, product_manager TEXT, item_name TEXT, po_number TEXT, qty_ordered REAL, rate REAL, unit TEXT, vendor_name TEXT, expected_date TEXT, quality_specifications TEXT, note TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS lmd_data (id INTEGER PRIMARY KEY AUTOINCREMENT, client_name TEXT, po_number TEXT, vehicle_number TEXT, driver_name TEXT, client_location TEXT, vehicle_type TEXT, booking_person TEXT, km REAL, price_per_km REAL, extra_expenses REAL, reason TEXT, total_amount REAL, payment_status TEXT, mode_of_payment TEXT, amount_paid REAL, amount_due REAL, date TEXT, time TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS fmd_data (id INTEGER PRIMARY KEY AUTOINCREMENT, vendor_name TEXT, vendor_location TEXT, vehicle_number TEXT, driver_name TEXT, po_number TEXT, items TEXT, vehicle_type TEXT, booking_person TEXT, km REAL, price_per_km REAL, extra_expenses REAL, reason TEXT, total_amount REAL, payment_status TEXT, mode_of_payment TEXT, amount_paid REAL, amount_due REAL, date TEXT, time TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS payment_history (id INTEGER PRIMARY KEY AUTOINCREMENT, parent_table_name TEXT NOT NULL, parent_id INTEGER NOT NULL, amount_paid REAL NOT NULL, mode_of_payment TEXT NOT NULL, payment_date TEXT NOT NULL, payment_time TEXT NOT NULL)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS purchases (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, vendor TEXT, po_number TEXT, qty_receive REAL, unit_receive TEXT, pcs_receive REAL, qty_accept REAL, unit_accept TEXT, pcs_accept REAL, qty_reject REAL, unit_reject TEXT, pcs_reject REAL, reason_for_rejection TEXT, date TEXT, time TEXT, ctrl_date TEXT, item_tag TEXT, payment_status TEXT, mode_of_payment TEXT, amount_paid REAL, amount_due REAL, rate REAL, total_value REAL)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS stock_updates (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT NOT NULL, a_grade_qty REAL, a_grade_unit TEXT, pcs_a_grade REAL, b_grade_qty REAL, b_grade_unit TEXT, pcs_b_grade REAL, c_grade_qty REAL, c_grade_unit TEXT, pcs_c_grade REAL, ungraded_qty REAL, ungraded_unit TEXT, pcs_ungraded REAL, dump_qty REAL, dump_unit TEXT, pcs_dump REAL, total_qty REAL, date TEXT, time TEXT, po_number TEXT, a_grade_tags TEXT, b_grade_tags TEXT, c_grade_tags TEXT, ungraded_tags TEXT, dump_tags TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS b_grade_sales (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, clint TEXT, quantity REAL, rate REAL, unit TEXT, total_value REAL, date TEXT, time TEXT, po_number TEXT, pcs REAL, item_tag TEXT, payment_status TEXT, mode_of_payment TEXT, amount_paid REAL, amount_due REAL)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS sales (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, clint TEXT, quantity REAL, unit TEXT, pcs REAL, date TEXT, time TEXT, po_number TEXT, item_tag TEXT, payment_status TEXT, mode_of_payment TEXT, amount_paid REAL, amount_due REAL, rate REAL, total_value REAL)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS sales_waitlist(id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, clint TEXT, po_number TEXT, quantity REAL, unit TEXT, pcs REAL, item_tag TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS rejection_received (id INTEGER PRIMARY KEY AUTOINCREMENT, client_name TEXT, item TEXT, quantity REAL, unit TEXT, pcs REAL, sample_quantity REAL, reason TEXT, date TEXT, time TEXT, ctrl_date TEXT, po_number TEXT, item_tag TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS vendor_rejections (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, vendor TEXT, po_number TEXT, quantity_sent REAL, unit TEXT, pcs REAL, date TEXT, time TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS dump_sales (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, quantity REAL, unit TEXT, pcs REAL, date TEXT, time TEXT, po_number TEXT, item_tag TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS mandi_resales (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, quantity REAL, unit TEXT, pcs REAL, date TEXT, time TEXT, item_tag TEXT)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS vendors (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, location TEXT, km REAL)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS purchase_vendors (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS b_grade_clients (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)''')

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

    initial_clients = ["Zomato- (CPC-LDH1)", "Zomato- (Rajpura)", "Zomato- (CPC-GGN2)", "Zomato- (CPC-DEL3)", "Zomato- (CPC-NOIDA2)", "Zomato- (CPC NOIDA)", "B2B", "KD Enterprises", "Sarasvi Foods Pvt. LTD.", "Safe and Healthy Food", "Red Otter Farms Pvt Ltd", "Sara Vaninetti", "Gurprakash Singh", "Madan's Back2Basics", "Utsav Mandir Foundation", "KSKT Agromart Private Limited", "PJTJ Technologies Private Limited", "PJTJ Rajpura", "Kiranakart Wholesale (DEL FRESH MH-2)", "Kiranakart Wholesale (DEL FRESH MH-5)", "Eliot India Food Services LLP"]
    for client in initial_clients:
        cursor.execute('INSERT OR IGNORE INTO vendors (name) VALUES (?)', (client,))
        cursor.execute('INSERT OR IGNORE INTO b_grade_clients (name) VALUES (?)', (client,))

    conn.commit()
    conn.close()

# Helper function to get db connection
def get_db():
    return sqlite3.connect(db_path)

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
        row.get('po_number'),
        row.get('pcs'),
        row.get('date'),
        row.get('time'),
        row.get('item_tag'),
        row.get('payment_status'),
        row.get('mode_of_payment'),
        row.get('amount_paid'),
        row.get('amount_due')
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
    query = f'SELECT so.id as so_id, so.client_name, so.so_number, so.date_of_dispatch, item.id as item_id, item.item_name, item.quantity_kg, item.quantity_pcs, v.location, v.km FROM generated_sos so JOIN so_items item ON so.id = item.so_id LEFT JOIN vendors v ON so.client_name = v.name {f"WHERE {where_clause}" if where_clause else ""} ORDER BY so.id DESC, item.id ASC'
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
    cursor = conn.cursor()
    cursor.execute('SELECT name FROM product_managers ORDER BY name COLLATE NOCASE')
    results = [row[0] for row in cursor.fetchall()]
    conn.close()
    return jsonify(results)

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

@app.route('/update_lmd_data', methods=['PUT'])
def update_lmd_data():
    row = request.json
    id = row['id']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('UPDATE lmd_data SET client_name=?, po_number=?, vehicle_number=?, driver_name=?, client_location=?, vehicle_type=?, booking_person=?, km=?, price_per_km=?, extra_expenses=?, reason=?, total_amount=?, payment_status=?, mode_of_payment=?, amount_paid=?, amount_due=?, date=?, time=? WHERE id=?', (row['client_name'], row['po_number'], row['vehicle_number'], row['driver_name'], row['client_location'], row['vehicle_type'], row['booking_person'], row['km'], row['price_per_km'], row['extra_expenses'], row['reason'], row['total_amount'], row['payment_status'], row['mode_of_payment'], row['amount_paid'], row['amount_due'], row['date'], row['time'], id))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

@app.route('/update_fmd_data', methods=['PUT'])
def update_fmd_data():
    row = request.json
    id = row['id']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('UPDATE fmd_data SET vendor_name=?, vendor_location=?, vehicle_number=?, driver_name=?, po_number=?, items=?, vehicle_type=?, booking_person=?, km=?, price_per_km=?, extra_expenses=?, reason=?, total_amount=?, payment_status=?, mode_of_payment=?, amount_paid=?, amount_due=?, date=?, time=? WHERE id=?', (row['vendor_name'], row['vendor_location'], row['vehicle_number'], row['driver_name'], row['po_number'], row['items'], row['vehicle_type'], row['booking_person'], row['km'], row['price_per_km'], row['extra_expenses'], row['reason'], row['total_amount'], row['payment_status'], row['mode_of_payment'], row['amount_paid'], row['amount_due'], row['date'], row['time'], id))
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

@app.route('/insert_generated_po', methods=['POST'])
def insert_generated_po():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('INSERT INTO generated_pos (product_manager, item_name, po_number, qty_ordered, rate, unit, vendor_name, expected_date, quality_specifications, note) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', (row['product_manager'], row['item_name'], row['po_number'], row['qty_ordered'], row['rate'], row['unit'], row['vendor_name'], row['expected_date'], row['quality_specifications'], row['note']))
    conn.commit()
    conn.close()
    return jsonify({'id': cursor.lastrowid})

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

@app.route('/get_items', methods=['GET'])
def get_items():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT name FROM items ORDER BY name COLLATE NOCASE')
    results = [row[0] for row in cursor.fetchall()]
    conn.close()
    return jsonify(results)

@app.route('/get_purchased_items', methods=['GET'])
def get_purchased_items():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT DISTINCT item FROM purchases ORDER BY item COLLATE NOCASE')
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
    cursor.execute('SELECT name FROM purchase_vendors ORDER BY name COLLATE NOCASE')
    results = [row[0] for row in cursor.fetchall()]
    conn.close()
    return jsonify(results)

@app.route('/get_b_grade_clients', methods=['GET'])
def get_b_grade_clients():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT name FROM b_grade_clients ORDER BY name COLLATE NOCASE')
    results = [row[0] for row in cursor.fetchall()]
    conn.close()
    return jsonify(results)

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
    cursor.execute('INSERT INTO lmd_data (client_name, po_number, vehicle_number, driver_name, client_location, vehicle_type, booking_person, km, price_per_km, extra_expenses, reason, total_amount, payment_status, mode_of_payment, amount_paid, amount_due, date, time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', (row['client_name'], row['po_number'], row['vehicle_number'], row['driver_name'], row['client_location'], row['vehicle_type'], row['booking_person'], row['km'], row['price_per_km'], row['extra_expenses'], row['reason'], row['total_amount'], row['payment_status'], row['mode_of_payment'], row['amount_paid'], row['amount_due'], row['date'], row['time']))
    conn.commit()
    conn.close()
    return jsonify({'id': cursor.lastrowid})

@app.route('/insert_fmd_data', methods=['POST'])
def insert_fmd_data():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('INSERT INTO fmd_data (vendor_name, vendor_location, vehicle_number, driver_name, po_number, items, vehicle_type, booking_person, km, price_per_km, extra_expenses, reason, total_amount, payment_status, mode_of_payment, amount_paid, amount_due, date, time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', (row['vendor_name'], row['vendor_location'], row['vehicle_number'], row['driver_name'], row['po_number'], row['items'], row['vehicle_type'], row['booking_person'], row['km'], row['price_per_km'], row['extra_expenses'], row['reason'], row['total_amount'], row['payment_status'], row['mode_of_payment'], row['amount_paid'], row['amount_due'], row['date'], row['time']))
    conn.commit()
    conn.close()
    return jsonify({'id': cursor.lastrowid})

@app.route('/get_all_lmd_data', methods=['GET'])
def get_all_lmd_data():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM lmd_data ORDER BY id DESC')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

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
    cursor.execute('SELECT * FROM fmd_data ORDER BY id DESC')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
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
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM purchases ORDER BY id DESC')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/get_latest_purchases', methods=['GET'])
def get_latest_purchases():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM purchases ORDER BY id DESC LIMIT 5')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/get_all_stock_updates', methods=['GET'])
def get_all_stock_updates():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM stock_updates ORDER BY id DESC')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/get_all_b_grade_sales', methods=['GET'])
def get_all_b_grade_sales():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM b_grade_sales ORDER BY id DESC')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

@app.route('/get_all_sales', methods=['GET'])
def get_all_sales():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM sales ORDER BY id DESC')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

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

@app.route('/insert_sale', methods=['POST'])
def insert_sale():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()
    query = '''INSERT INTO sales
               (item, clint, po_number, quantity, unit, pcs, date, time, item_tag, payment_status, mode_of_payment, amount_paid, amount_due, rate, total_value)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'''
    params = (
        row.get('item'),
        row.get('clint'),
        row.get('po_number'),
        row.get('quantity'),
        row.get('unit'),
        row.get('pcs'),
        row.get('date'),
        row.get('time'),
        row.get('item_tag'),
        row.get('payment_status', 'Unpaid'),
        row.get('mode_of_payment'),
        row.get('amount_paid', 0.0),
        row.get('amount_due', 0.0),
        row.get('rate', 0.0),
        row.get('total_value', 0.0)
    )
    cursor.execute(query, params)
    conn.commit()
    last_id = cursor.lastrowid
    conn.close()
    return jsonify({'id': last_id})

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
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM rejection_received ORDER BY id DESC')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

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
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM vendor_rejections ORDER BY id DESC')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

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
    cursor.execute('INSERT INTO vendor_rejections (item, vendor, po_number, quantity_sent, unit, pcs, date, time) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', (row.get('item'), row.get('vendor'), row.get('po_number'), row.get('quantity_sent'), row.get('unit'), row.get('pcs'), row.get('date'), row.get('time')))
    conn.commit()
    conn.close()
    return jsonify({'id': cursor.lastrowid})

@app.route('/get_all_dump_sales', methods=['GET'])
def get_all_dump_sales():
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM dump_sales ORDER BY id DESC')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

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
    conn = get_db()
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM mandi_resales ORDER BY id DESC')
    rows = cursor.fetchall()
    conn.close()
    results = [dict(row) for row in rows]
    return jsonify(results)

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

@app.route('/insert_stock_update', methods=['POST'])
def insert_stock_update():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('INSERT INTO stock_updates (item, a_grade_qty, a_grade_unit, pcs_a_grade, b_grade_qty, b_grade_unit, pcs_b_grade, c_grade_qty, c_grade_unit, pcs_c_grade, ungraded_qty, ungraded_unit, pcs_ungraded, dump_qty, dump_unit, pcs_dump, total_qty, date, time, po_number, a_grade_tags, b_grade_tags, c_grade_tags, ungraded_tags, dump_tags) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', (row.get('item'), row.get('a_grade_qty'), row.get('a_grade_unit'), row.get('pcs_a_grade'), row.get('b_grade_qty'), row.get('b_grade_unit'), row.get('pcs_b_grade'), row.get('c_grade_qty'), row.get('c_grade_unit'), row.get('pcs_c_grade'), row.get('ungraded_qty'), row.get('ungraded_unit'), row.get('pcs_ungraded'), row.get('dump_qty'), row.get('dump_unit'), row.get('pcs_dump'), row.get('total_qty'), row.get('date'), row.get('time'), row.get('po_number'), row.get('a_grade_tags'), row.get('b_grade_tags'), row.get('c_grade_tags'), row.get('ungraded_tags'), row.get('dump_tags')))
    conn.commit()
    conn.close()
    return jsonify({'id': cursor.lastrowid})

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

@app.route('/insert_purchase', methods=['POST'])
def insert_purchase():
    row = request.json
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('INSERT INTO purchases (item, vendor, po_number, qty_receive, unit_receive, pcs_receive, qty_accept, unit_accept, pcs_accept, qty_reject, unit_reject, pcs_reject, reason_for_rejection, date, time, ctrl_date, item_tag, payment_status, mode_of_payment, amount_paid, amount_due, rate, total_value) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', (row.get('item'), row.get('vendor'), row.get('po_number'), row.get('qty_receive'), row.get('unit_receive'), row.get('pcs_receive'), row.get('qty_accept'), row.get('unit_accept'), row.get('pcs_accept'), row.get('qty_reject'), row.get('unit_reject'), row.get('pcs_reject'), row.get('reason_for_rejection'), row.get('date'), row.get('time'), row.get('ctrl_date'), row.get('item_tag'), row.get('payment_status', 'Unpaid'), row.get('mode_of_payment'), row.get('amount_paid', 0.0), row.get('amount_due', 0.0), row.get('rate', 0.0), row.get('total_value', 0.0)))
    conn.commit()
    conn.close()
    return jsonify({'id': cursor.lastrowid})

@app.route('/update_purchase', methods=['PUT'])
def update_purchase():
    row = request.json
    id = row['id']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('UPDATE purchases SET item=?, vendor=?, po_number=?, qty_receive=?, unit_receive=?, pcs_receive=?, qty_accept=?, unit_accept=?, pcs_accept=?, qty_reject=?, unit_reject=?, pcs_reject=?, reason_for_rejection=?, date=?, time=?, ctrl_date=?, item_tag=?, payment_status=?, mode_of_payment=?, amount_paid=?, amount_due=?, rate=?, total_value=? WHERE id=?', (row.get('item'), row.get('vendor'), row.get('po_number'), row.get('qty_receive'), row.get('unit_receive'), row.get('pcs_receive'), row.get('qty_accept'), row.get('unit_accept'), row.get('pcs_accept'), row.get('qty_reject'), row.get('unit_reject'), row.get('pcs_reject'), row.get('reason_for_rejection'), row.get('date'), row.get('time'), row.get('ctrl_date'), row.get('item_tag'), row.get('payment_status', 'Unpaid'), row.get('mode_of_payment'), row.get('amount_paid', 0.0), row.get('amount_due', 0.0), row.get('rate', 0.0), row.get('total_value', 0.0), id))
    conn.commit()
    conn.close()
    return jsonify({'success': True})

# ... other update endpoints remain similar but use proper table mappings ...

@app.route('/get_next_item_tag_sequence', methods=['GET'])
def get_next_item_tag_sequence():
    vendor_prefix = request.args.get('vendor_prefix')
    day_part = request.args.get('day_part')
    conn = get_db()
    cursor = conn.cursor()
    pattern = f'{vendor_prefix}-{day_part}-%'
    cursor.execute('SELECT item_tag FROM purchases WHERE item_tag LIKE ? ORDER BY id DESC', (pattern,))
    results = cursor.fetchall()
    conn.close()
    if not results:
        return jsonify({'sequence': 1})
    for row in results:
        tag = row[0]
        if not tag: continue
        parts = tag.split('-')
        if len(parts) == 3:
            try:
                last_num = int(parts[2])
                return jsonify({'sequence': last_num + 1})
            except ValueError:
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
    row = request.json
    id = row['id']
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        UPDATE sales SET 
            item=?, clint=?, po_number=?, quantity=?, unit=?, pcs=?, 
            date=?, time=?, item_tag=?, payment_status=?, mode_of_payment=?, 
            amount_paid=?, amount_due=?, rate=?, total_value=? 
        WHERE id=?
    ''', (
        row.get('item'), row.get('clint'), row.get('po_number'), row.get('quantity'), row.get('unit'), row.get('pcs'),
        row.get('date'), row.get('time'), row.get('item_tag'), row.get('payment_status'), row.get('mode_of_payment'),
        row.get('amount_paid'), row.get('amount_due'), row.get('rate'), row.get('total_value'),
        id
    ))
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

init_db()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
