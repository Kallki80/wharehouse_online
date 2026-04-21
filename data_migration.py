#!/usr/bin/env python3
import sqlite3
import os
import shutil
from datetime import datetime
import re

DB_PATH = 'mydata.db'

TABLES = [
    'product_managers', 'generated_sos', 'so_items', 'generated_pos', 
    'lmd_data', 'fmd_data', 'section_groups', 'payment_history', 
    'purchases', 'stock_updates', 'b_grade_sales', 'sales', 
    'sales_waitlist', 'rejection_received', 'vendor_rejections', 
    'dump_sales', 'mandi_resales', 'items', 'vendors', 
    'purchase_vendors', 'b_grade_clients', 'packaging_materials', 
    'packaging_vendors'
]

def is_numeric(val):
    return val is not None and re.match(r'^\d+$', str(val))

def backup_db():
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_path = f'backup_{timestamp}.db'
    shutil.copy2(DB_PATH, backup_path)
    print(f"✅ Backup created: {backup_path}")

def fix_table(conn, table):
    print(f"\n🔧 Checking table: {table}")
    cursor = conn.cursor()

    # Check if id column exists
    cursor.execute(f"PRAGMA table_info({table})")
    columns = [col[1] for col in cursor.fetchall()]
    if 'id' not in columns:
        print("   ⚠️ Skipped (no id column)")
        return

    # Get max numeric id
    cursor.execute(f"SELECT id FROM {table}")
    rows = cursor.fetchall()

    numeric_ids = [int(r[0]) for r in rows if is_numeric(r[0])]
    max_id = max(numeric_ids) if numeric_ids else 0

    fixed_count = 0

    for (row_id,) in rows:
        if not is_numeric(row_id):
            max_id += 1
            cursor.execute(
                f"UPDATE {table} SET id = ? WHERE id = ?",
                (max_id, row_id)
            )
            fixed_count += 1

    print(f"   ✅ Fixed {fixed_count} rows")

def main():
    if not os.path.exists(DB_PATH):
        print("❌ DB not found")
        return

    conn = sqlite3.connect(DB_PATH)

    try:
        backup_db()

        for table in TABLES:
            try:
                fix_table(conn, table)
            except Exception as e:
                print(f"❌ Error in {table}: {e}")

        print("\n🎉 DONE: Non-numeric IDs converted safely!")

    finally:
        conn.commit()
        conn.close()

if __name__ == "__main__":
    main()