"""Shared pytest fixtures.

Tests run against a separate PostgreSQL database. By default it is derived from
DATABASE_URL by appending "_test" to the database name, giving cloudnotes_test.
Set TEST_DATABASE_URL to override. The suite refuses to run against any database
whose name does not end in "_test", so the development database is never touched.
"""

import os
from pathlib import Path

import pytest
from sqlalchemy import text
from sqlalchemy.engine import make_url

from app import create_app
from app.extensions import db

ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS_DIR = str(ROOT / "migrations")
TEST_SECRET_KEY = "test-only-secret-key"


def _resolve_test_database_url():
    explicit = os.environ.get("TEST_DATABASE_URL")
    if explicit:
        url = make_url(explicit)
    else:
        base = os.environ.get("DATABASE_URL")
        if not base:
            pytest.exit("Set TEST_DATABASE_URL or DATABASE_URL before running tests.", returncode=2)
        url = make_url(base).set(database=f"{make_url(base).database}_test")
    if not (url.database or "").endswith("_test"):
        pytest.exit(
            f"Refusing to run tests against database '{url.database}'. "
            "Test database names must end in '_test'.",
            returncode=2,
        )
    return url.render_as_string(hide_password=False)


def _drop_schema(app):
    with app.app_context():
        db.drop_all()
        db.session.execute(text("DROP TABLE IF EXISTS alembic_version"))
        db.session.commit()


@pytest.fixture(scope="session")
def app():
    from flask_migrate import upgrade

    test_app = create_app(
        {
            "TESTING": True,
            "SECRET_KEY": TEST_SECRET_KEY,
            "SQLALCHEMY_DATABASE_URI": _resolve_test_database_url(),
            "WTF_CSRF_ENABLED": False,
        }
    )
    _drop_schema(test_app)
    with test_app.app_context():
        # Build the schema with the real migrations, not db.create_all().
        upgrade(directory=MIGRATIONS_DIR)
    yield test_app
    _drop_schema(test_app)
    with test_app.app_context():
        db.engine.dispose()


@pytest.fixture(autouse=True)
def clean_notes_table(app):
    with app.app_context():
        db.session.execute(text("TRUNCATE TABLE notes RESTART IDENTITY"))
        db.session.commit()
    yield


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture
def app_context(app):
    with app.app_context():
        yield
