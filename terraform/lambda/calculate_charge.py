import json
import pymysql
import os
from datetime import datetime, timezone

from db_utils import get_connection, ensure_database_and_table

# Environment variables for database configuration
DB_HOST = os.getenv("DB_HOST")
DB_USER = os.getenv("DB_USER_NAME")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_NAME = os.getenv("DB_NAME")
TABLE_NAME = "PARKING_LOT"


def lambda_handler(event, context):
    """
        AWS Lambda entry point for calculating parking charges.

        Expects a POST request with query parameter:
            - ticketId: UUID-string

        - Validates that the table exists (calls ensure_database_and_table)
        - Fetches the parking session by ticket_id
        - Calculates duration in minutes
        - Charges $2.5 per 15-minute interval

        Returns:
            JSON response with plate number, lot name, parked duration and total charge.
            404 if ticket not found.
            500 on error.
    """
    # Ensure the database and table exist (creates if missing)
    ensure_database_and_table(db_name=DB_NAME, table_name=TABLE_NAME)

    # Parse ticketId from POST request query params
    query_params = event.get("queryStringParameters", {})
    ticket_id = query_params.get("ticketId")

    # Connect to MySQL
    connection = get_connection()

    try:
        with connection.cursor() as cursor:
            # Fetch ticket info by ticket_id
            sql = f"SELECT plate, parking_lot, created_at FROM {TABLE_NAME} WHERE ticket_id = %s"
            cursor.execute(sql, (ticket_id,))
            row = cursor.fetchone()

            # return 404 if ticket id not found
            if not row:
                return {
                    'statusCode': 404,
                    'body': json.dumps({'error': 'Ticket not found'})
                }

            plate, parking_lot, created_at = row
            now = datetime.now()

            # Calculate parking duration in minutes
            parked_minutes = (now - created_at).total_seconds() / 60

            #pricing logic
            charge = round((int(parked_minutes / 15) * 2.5), 2)  # $10/hr = $2.5 per 15 min

            return {
                'statusCode': 200,
                'body': json.dumps({
                    'ticket_id': ticket_id,
                    'plate': plate,
                    'parking_lot': parking_lot,
                    'parked_minutes': int(parked_minutes),
                    'charge_usd': charge
                })
            }

    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

    finally:
        connection.close()
