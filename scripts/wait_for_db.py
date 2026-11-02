"""Block until PostgreSQL accepts connections, or exit non-zero with a clear message.

Used by docker-entrypoint.sh before migrations run. Environment variables:
  DATABASE_URL       PostgreSQL connection string (required)
  DB_WAIT_ATTEMPTS   Number of connection attempts (default 30)
  DB_WAIT_INTERVAL   Seconds between attempts (default 2)
"""

import os
import sys
import time

from sqlalchemy import create_engine, text

from app.config import validate_database_url


def main():
    try:
        url = validate_database_url(os.environ.get("DATABASE_URL"))
    except RuntimeError as error:
        print(f"[wait_for_db] Configuration error: {error}", file=sys.stderr)
        return 1

    attempts = int(os.environ.get("DB_WAIT_ATTEMPTS", "30"))
    interval = float(os.environ.get("DB_WAIT_INTERVAL", "2"))
    engine = create_engine(url, connect_args={"connect_timeout": 3})

    last_error = None
    for attempt in range(1, attempts + 1):
        try:
            with engine.connect() as connection:
                connection.execute(text("SELECT 1"))
            print(f"[wait_for_db] PostgreSQL is ready (attempt {attempt}).")
            return 0
        except Exception as error:  # noqa: BLE001 - report any connection failure
            last_error = error
            print(
                f"[wait_for_db] Attempt {attempt}/{attempts} failed: "
                f"{error.__class__.__name__}. Retrying in {interval:g}s.",
                file=sys.stderr,
            )
            time.sleep(interval)

    print(
        f"[wait_for_db] PostgreSQL did not become available after {attempts} attempts. "
        f"Last error: {last_error}",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
