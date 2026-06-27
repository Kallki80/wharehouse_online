# import sqlite3

# # Apni copied database ka path
# DATABASE_PATH = "mydata_backup.db"

# def clear_database(db_path):
#     conn = sqlite3.connect(db_path)

#     try:
#         cursor = conn.cursor()

#         # Transaction Start
#         cursor.execute("BEGIN")

#         # Foreign Keys Temporary Disable
#         cursor.execute("PRAGMA foreign_keys = OFF;")

#         # Sabhi user tables nikalo
#         cursor.execute("""
#             SELECT name
#             FROM sqlite_master
#             WHERE type='table'
#             AND name NOT LIKE 'sqlite_%'
#             ORDER BY name;
#         """)

#         tables = cursor.fetchall()

#         print(f"Total Tables: {len(tables)}\n")

#         # Har table ka data delete karo
#         for (table_name,) in tables:
#             print(f"Clearing: {table_name}")
#             cursor.execute(f'DELETE FROM "{table_name}";')

#         # AUTOINCREMENT reset karo (agar use hua hai)
#         cursor.execute("""
#             SELECT name
#             FROM sqlite_master
#             WHERE type='table'
#             AND name='sqlite_sequence';
#         """)

#         if cursor.fetchone():
#             cursor.execute("DELETE FROM sqlite_sequence;")

#         # Commit
#         conn.commit()

#         print("\nDatabase cleaned successfully.")

#     except Exception as e:
#         conn.rollback()
#         print("\nError:", e)
#         print("Rollback completed. No data was deleted.")

#     finally:
#         # Foreign Keys dubara ON
#         try:
#             conn.execute("PRAGMA foreign_keys = ON;")
#         except:
#             pass

#         conn.close()


# if __name__ == "__main__":
#     clear_database(DATABASE_PATH)





# import sqlite3

# conn = sqlite3.connect("mydata.db")
# cursor = conn.cursor()

# cursor.execute("""
# SELECT name
# FROM sqlite_master
# WHERE type='table'
# AND name NOT LIKE 'sqlite_%';
# """)

# for (table,) in cursor.fetchall():
#     print(f"\n===== {table} =====")
#     cursor.execute(f'PRAGMA table_info("{table}")')
#     for col in cursor.fetchall():
#         print(col)

# conn.close()





# import sqlite3

# DATABASE_PATH = "mydata.db"   # Apna database path

# conn = sqlite3.connect(DATABASE_PATH)
# conn.row_factory = sqlite3.Row

# cursor = conn.cursor()

# # Pehli 10 entries
# cursor.execute("SELECT * FROM b_grade_sales LIMIT 10")

# rows = cursor.fetchall()

# if not rows:
#     print("Table is empty.")
# else:
#     # Column names
#     print("Columns:")
#     print(rows[0].keys())
#     print("-" * 80)

#     # Data
#     for i, row in enumerate(rows, start=1):
#         print(f"\nRow {i}")
#         for column in row.keys():
#             print(f"{column}: {row[column]}")
#         print("-" * 80)

# conn.close()



import sqlite3

DB_PATH = "mydata.db"  # 👈 apna db file path yahan daalna

def fix_b_grade_sale():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Step 1: fetch corrupted rows
    cursor.execute("""
        SELECT id, date, time, po_number, pcs
        FROM b_grade_sales
        WHERE id BETWEEN 0 AND 92
    """)

    rows = cursor.fetchall()

    for row in rows:
        id = row[0]
        date = row[1]
        time = row[2]
        po_number = row[3]
        pcs = row[4]

        # 🔥 Correct mapping fix
        correct_date = po_number
        correct_time = pcs
        correct_po = date
        correct_pcs = time

        # Step 2: update row
        cursor.execute("""
            UPDATE b_grade_sales
            SET date = ?,
                time = ?,
                po_number = ?,
                pcs = ?
            WHERE id = ?
        """, (correct_date, correct_time, correct_po, correct_pcs, id))

    conn.commit()
    conn.close()

    print("✅ b_grade_sale table successfully fixed (SQLite)")

# Run
fix_b_grade_sale()