# import sqlite3
# from datetime import datetime, timedelta

# MAIN_DB = "mydata.db"
# BACKUP_DB = "mydata_backup.db"

# # 20 din purani date
# cutoff_date = (datetime.now() - timedelta(days=20)).strftime("%Y-%m-%d")

# main_conn = sqlite3.connect(MAIN_DB)
# backup_conn = sqlite3.connect(BACKUP_DB)

# main_cur = main_conn.cursor()
# backup_cur = backup_conn.cursor()

# # Saari user tables nikalo
# main_cur.execute("""
# SELECT name
# FROM sqlite_master
# WHERE type='table'
# AND name NOT LIKE 'sqlite_%'
# """)

# tables = [row[0] for row in main_cur.fetchall()]

# # Possible date column names
# DATE_COLUMNS = [
#     "date",
#     "payment_date",
#     "record_date",
# ]

# for table in tables:

#     print(f"\n========== {table} ==========")

#     # Table ke columns nikalo
#     main_cur.execute(f"PRAGMA table_info({table})")
#     info = main_cur.fetchall()

#     columns = [c[1] for c in info]

#     # Date column find karo
#     date_column = None
#     for col in DATE_COLUMNS:
#         if col in columns:
#             date_column = col
#             break

#     if date_column is None:
#         print("⏭ Skipped (No supported date column)")
#         continue

#     print(f"Using date column: {date_column}")

#     # Old rows
#     main_cur.execute(
#         f"""
#         SELECT *
#         FROM {table}
#         WHERE DATE({date_column}) <= DATE(?)
#         """,
#         (cutoff_date,)
#     )

#     rows = main_cur.fetchall()

#     if not rows:
#         print("No old records.")
#         continue

#     column_names = [d[0] for d in main_cur.description]

#     insert_sql = f"""
#         INSERT OR IGNORE INTO {table}
#         ({",".join(column_names)})
#         VALUES ({",".join(["?"] * len(column_names))})
#     """

#     try:
#         # Backup
#         backup_cur.executemany(insert_sql, rows)
#         backup_conn.commit()

#         # Delete
#         main_cur.execute(
#             f"""
#             DELETE FROM {table}
#             WHERE DATE({date_column}) <= DATE(?)
#             """,
#             (cutoff_date,)
#         )

#         main_conn.commit()

#         print(f"✅ {len(rows)} rows moved.")

#     except Exception as e:
#         backup_conn.rollback()
#         main_conn.rollback()
#         print(f"❌ Error: {e}")

# main_conn.close()
# backup_conn.close()

# print("\n🎉 Backup Completed Successfully.")






import sqlite3
from datetime import datetime, timedelta

MAIN_DB = "mydata.db"
BACKUP_DB = "mydata_backup.db"

# 20 din purani date
cutoff_date = (datetime.now() - timedelta(days=20)).strftime("%Y-%m-%d")

# Har table ke liye date column
TABLE_DATE_COLUMN = {
    # SO
    "generated_sos": "date_of_dispatch",
    "so_items": None,

    # Purchase
    "generated_pos": "expected_date",
    "purchases": "date",
    "packaging_materials": "date",

    # Logistics
    "lmd_data": "date",
    "fmd_data": "date",

    # Payment
    "payment_history": "payment_date",

    # Stock
    "stock_updates": "date",

    # Sales
    "sales": "date",
    "b_grade_sales": "date",
    "sales_waitlist": None,

    # Rejections
    "rejection_received": "date",
    "vendor_rejections": "date",

    # Other Sales
    "dump_sales": "date",
    "mandi_resales": "date",

    # Admin
    "admin_report": "date",

    # Gate
    "gate_tracker": "record_date",
    "gate_entries": "date",

    # Master Tables (Skip)
    "section_groups": None,
    "purchase_vendors": None,
    "purchase_vendors__old_varchar_id": None,
    "b_grade_clients": None,
    "product_managers": None,
    "items": None,
    "vendors": None,
    "packaging_vendors": None,
}

main_conn = sqlite3.connect(MAIN_DB)
backup_conn = sqlite3.connect(BACKUP_DB)

main_cur = main_conn.cursor()
backup_cur = backup_conn.cursor()

# Sabhi user tables
main_cur.execute("""
SELECT name
FROM sqlite_master
WHERE type='table'
AND name NOT LIKE 'sqlite_%'
""")

tables = [row[0] for row in main_cur.fetchall()]

for table in tables:

    print(f"\n========== {table} ==========")

    # Mapping check
    date_column = TABLE_DATE_COLUMN.get(table)

    if date_column is None:
        print("⏭ Skipped")
        continue

    # Columns check
    main_cur.execute(f"PRAGMA table_info({table})")
    info = main_cur.fetchall()

    columns = [c[1] for c in info]

    if date_column not in columns:
        print(f"⏭ Skipped ({date_column} column not found)")
        continue

    print(f"Using date column: {date_column}")

    # Old rows
    main_cur.execute(
        f"""
        SELECT *
        FROM {table}
        WHERE DATE({date_column}) <= DATE(?)
        """,
        (cutoff_date,)
    )

    rows = main_cur.fetchall()

    if not rows:
        print("No old records.")
        continue

    column_names = [d[0] for d in main_cur.description]

    insert_sql = f"""
    INSERT OR IGNORE INTO {table}
    ({",".join(column_names)})
    VALUES ({",".join(["?"] * len(column_names))})
    """

    try:
        # Backup
        backup_cur.executemany(insert_sql, rows)
        backup_conn.commit()

        # Delete from main DB
        main_cur.execute(
            f"""
            DELETE FROM {table}
            WHERE DATE({date_column}) <= DATE(?)
            """,
            (cutoff_date,)
        )

        main_conn.commit()

        print(f"✅ {len(rows)} rows moved.")

    except Exception as e:
        backup_conn.rollback()
        main_conn.rollback()
        print(f"❌ Error: {e}")

main_conn.close()
backup_conn.close()

print("\n🎉 Backup Completed Successfully.")