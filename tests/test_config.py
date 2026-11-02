"""Configuration tests: PostgreSQL is the only accepted database backend."""

import pytest

from app.config import validate_database_url


def test_postgresql_url_is_accepted():
    url = "postgresql://cloudnotes_user:secret@db:5432/cloudnotes"
    assert validate_database_url(url) == url


def test_psycopg2_driver_suffix_is_accepted():
    url = "postgresql+psycopg2://u:p@db:5432/cloudnotes"
    assert validate_database_url(url) == url


def test_missing_database_url_gives_clear_error():
    with pytest.raises(RuntimeError, match="DATABASE_URL is not set"):
        validate_database_url(None)


@pytest.mark.parametrize(
    "url",
    ["sqlite:///cloudnotes.db", "sqlite:////app/data/notes.sqlite3", "mysql://u:p@h/db"],
)
def test_non_postgresql_urls_are_rejected(url):
    with pytest.raises(RuntimeError, match="only supports PostgreSQL"):
        validate_database_url(url)


def test_app_refuses_to_start_without_secret_key(monkeypatch):
    from app import create_app

    monkeypatch.delenv("SECRET_KEY", raising=False)
    monkeypatch.setenv("DATABASE_URL", "postgresql://u:p@localhost:5432/cloudnotes_test")
    with pytest.raises(RuntimeError, match="SECRET_KEY is not set"):
        create_app()


def test_app_refuses_sqlite_database_url(monkeypatch):
    from app import create_app

    monkeypatch.setenv("SECRET_KEY", "x")
    monkeypatch.setenv("DATABASE_URL", "sqlite:///should-not-be-used.db")
    with pytest.raises(RuntimeError, match="SQLite is not supported"):
        create_app()
