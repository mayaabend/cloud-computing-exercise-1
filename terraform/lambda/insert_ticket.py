import json
import pymysql
import os
import uuid

from db_utils import get_connection, ensure_database_and_table

# Environment variables for database configuration
DB_HOST = os.getenv("DB_HOST")
DB_USER = os.getenv("DB_USER_NAME")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_NAME = os.getenv("DB_NAME")
TABLE_NAME = "PARKING_LOT"

def lambda_handler(event, context):
    """
            AWS Lambda entry point for entering the parking lot.

            Expects a POST request with query parameter:
                - plate: license plate string
                - parkingLot: parking lot id string

            - Validates that the table exists (calls ensure_database_and_table)
            - create new entry for the car

            Returns:
                JSON response with the ticket id, parking lot id and license plate.
                500 on error.
        """
    # Ensure the database and table exist (creates if missing)
    ensure_database_and_table(db_name=DB_NAME, table_name=TABLE_NAME)

    # Connect to MySQL
    connection = get_connection()

    # Get query parameters dictionary
    query_params = event.get("queryStringParameters", {})

    # Parse plate and parking_lot from POST request query params
    plate = query_params.get("plate")
    parking_lot = query_params.get("parkingLot")

    # Create new unique identifier for the ticket
    ticket_id = str(uuid.uuid4())


    print(f"plate: {plate}, Param2: {parking_lot}")

    try:
        with connection.cursor() as cursor:
            # Insert new row to database
            sql = f"INSERT INTO {TABLE_NAME} (ticket_id, plate, parking_lot) VALUES (%s, %s, %s)"
            cursor.execute(sql, (ticket_id, plate, parking_lot))
            connection.commit()

        return {
            'statusCode': 200,
            "headers": {
                "Content-Type": "application/json"
            },
            'body': json.dumps({'message': f'Row inserted successfully ticket_id: {ticket_id}'})
        }

    except Exception as e:
        return {
            'statusCode': 500,
            "headers": {
                "Content-Type": "application/json"
            },
            'body': json.dumps({'error': str(e)})
        }

    finally:
        connection.close()

