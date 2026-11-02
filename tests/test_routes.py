"""HTTP route tests against PostgreSQL."""

import re

import pytest
from sqlalchemy import text

from app.extensions import db
from app.models import Note


def _create(client, title="Hello", content="World"):
    return client.post("/notes", data={"title": title, "content": content})


def _note_id_from_location(response):
    match = re.search(r"/notes/(\d+)$", response.headers["Location"])
    assert match, response.headers["Location"]
    return int(match.group(1))


def test_health_returns_200_when_database_is_up(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok", "database": "ok"}


def test_health_returns_503_when_database_is_down(client, monkeypatch):
    from sqlalchemy.exc import OperationalError

    def broken_execute(*args, **kwargs):
        raise OperationalError("SELECT 1", {}, Exception("connection refused"))

    monkeypatch.setattr(db.session, "execute", broken_execute)
    response = client.get("/health")
    assert response.status_code == 503
    assert response.get_json()["database"] == "unreachable"


def test_index_shows_empty_state_without_notes(client):
    response = client.get("/")
    assert response.status_code == 200
    assert b"No notes yet" in response.data


def test_create_note_saves_to_database_and_redirects(client, app_context):
    response = _create(client, "Groceries", "Milk")
    assert response.status_code == 302

    note = db.session.get(Note, _note_id_from_location(response))
    assert note.title == "Groceries"
    assert note.content == "Milk"


def test_create_note_rejects_blank_title(client, app_context):
    response = _create(client, title="   ", content="no title")
    assert response.status_code == 400
    assert b"Title is required." in response.data
    assert db.session.execute(text("SELECT count(*) FROM notes")).scalar() == 0


def test_create_note_rejects_overlong_title(client):
    response = _create(client, title="x" * 201)
    assert response.status_code == 400
    assert b"200 characters or fewer" in response.data


def test_create_note_rejects_nul_characters(client):
    response = _create(client, title="bad\x00title")
    assert response.status_code == 400
    assert b"invalid characters" in response.data


def test_view_note_shows_title_and_content(client):
    note_id = _note_id_from_location(_create(client, "Viewable", "Body text"))
    response = client.get(f"/notes/{note_id}")
    assert response.status_code == 200
    assert b"Viewable" in response.data
    assert b"Body text" in response.data


def test_missing_note_returns_404_page(client):
    response = client.get("/notes/999999")
    assert response.status_code == 404
    assert b"Note not found" in response.data


def test_edit_note_updates_database(client, app_context):
    note_id = _note_id_from_location(_create(client, "Old", "old body"))

    response = client.post(
        f"/notes/{note_id}/edit", data={"title": "New", "content": "new body"}
    )
    assert response.status_code == 302

    note = db.session.get(Note, note_id)
    db.session.refresh(note)
    assert note.title == "New"
    assert note.content == "new body"


def test_edit_form_prefills_existing_values(client):
    note_id = _note_id_from_location(_create(client, "Prefill", "Prefill body"))
    response = client.get(f"/notes/{note_id}/edit")
    assert response.status_code == 200
    assert b'value="Prefill"' in response.data
    assert b"Prefill body" in response.data


def test_invalid_edit_keeps_original_note(client, app_context):
    note_id = _note_id_from_location(_create(client, "Keep me", "body"))

    response = client.post(f"/notes/{note_id}/edit", data={"title": "", "content": "x"})
    assert response.status_code == 400

    db.session.expire_all()
    assert db.session.get(Note, note_id).title == "Keep me"


def test_delete_note_removes_row(client, app_context):
    note_id = _note_id_from_location(_create(client, "Delete me", "bye"))

    response = client.post(f"/notes/{note_id}/delete")
    assert response.status_code == 302
    assert db.session.get(Note, note_id) is None


def test_deleting_missing_note_returns_404(client):
    response = client.post("/notes/424242/delete")
    assert response.status_code == 404


def test_api_lists_and_fetches_notes_as_json(client):
    first = _note_id_from_location(_create(client, "One", "first"))
    _note_id_from_location(_create(client, "Two", "second"))

    listing = client.get("/api/notes").get_json()
    assert [item["title"] for item in listing] == ["One", "Two"]

    single = client.get(f"/api/notes/{first}").get_json()
    assert single["content"] == "first"


def test_csrf_protection_blocks_forms_without_token(app, client):
    app.config["WTF_CSRF_ENABLED"] = True
    try:
        response = client.post("/notes", data={"title": "No token", "content": "x"})
        assert response.status_code == 400
        assert b"Form expired" in response.data
    finally:
        app.config["WTF_CSRF_ENABLED"] = False


def test_unknown_database_error_shows_friendly_page(client, monkeypatch):
    from sqlalchemy.exc import OperationalError

    def broken_list(*args, **kwargs):
        raise OperationalError("SELECT", {}, Exception("server closed the connection"))

    monkeypatch.setattr(db.session, "execute", broken_list)
    response = client.get("/")
    assert response.status_code == 503
    assert b"Database unavailable" in response.data
