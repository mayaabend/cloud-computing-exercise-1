import pymysql
import os

def ensure_database_and_table(db_name, table_name):
    # Step 1: Connect without DB to create DB if missing
    connection = get_connection()
    try:
        with connection.cursor() as cursor:
            cursor.execute("SHOW DATABASES LIKE %s", (db_name,))
            if not cursor.fetchone():
                cursor.execute(f"CREATE DATABASE {db_name}")
                print(f"Database '{db_name}' created.")
        connection.commit()
    finally:
        connection.close()

    # Step 2: Connect to the DB to check/create table
    connection = get_connection()
    try:
        with connection.cursor() as cursor:
            cursor.execute(f"SHOW TABLES LIKE %s", (table_name,))
            if not cursor.fetchone():
                create_table_sql = f"""
                CREATE TABLE PARKING_LOT (
                  ticket_id VARCHAR(36) PRIMARY KEY,
                  plate VARCHAR(50) NOT NULL,
                  parking_lot VARCHAR(100) NOT NULL,
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                """
                cursor.execute(create_table_sql)
                print(f"Table '{table_name}' created.")
        connection.commit()
    finally:
        connection.close()


def get_connection():
    return pymysql.connect(
        host=os.getenv("DB_HOST"),
        user=os.getenv("DB_USER_NAME"),
        password=os.getenv("DB_PASSWORD"),
        database=os.getenv("DB_NAME"),
        connect_timeout=5
    )