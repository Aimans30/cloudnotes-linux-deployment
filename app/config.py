"""Application configuration, read from environment variables.

PostgreSQL is the only supported database. Any other DATABASE_URL is rejected at
startup so the application never silently falls back to another database.
"""

import os

from sqlalchemy.engine import make_url

ALLOWED_DRIVERS = ("postgresql", "postgresql+psycopg2", "postgresql+psycopg")


def validate_database_url(url):
    """Raise a clear error unless ``url`` points at PostgreSQL."""
    if not url:
        raise RuntimeError(
            "DATABASE_URL is not set. Copy .env.example to .env and set DATABASE_URL "
            "to a PostgreSQL URL, e.g. postgresql://user:password@db:5432/cloudnotes."
        )
    parsed = make_url(url)
    if parsed.drivername not in ALLOWED_DRIVERS:
        raise RuntimeError(
            f"Unsupported DATABASE_URL driver '{parsed.drivername}'. CloudNotes only "
            "supports PostgreSQL (SQLite is not supported)."
        )
    return url


def load_config():
    """Build the Flask configuration dictionary from the environment."""
    return {
        "SECRET_KEY": os.environ.get("SECRET_KEY"),
        "SQLALCHEMY_DATABASE_URI": os.environ.get("DATABASE_URL"),
        "SQLALCHEMY_TRACK_MODIFICATIONS": False,
        # Detect and replace connections dropped by a PostgreSQL restart.
        "SQLALCHEMY_ENGINE_OPTIONS": {
            "pool_pre_ping": True,
            "pool_recycle": 1800,
            "connect_args": {"connect_timeout": 5},
        },
        "APP_ENV": os.environ.get("FLASK_ENV", "production"),
        "WTF_CSRF_TIME_LIMIT": None,
    }
