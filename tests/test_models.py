"""Database model tests (PostgreSQL)."""

import time

import pytest
from sqlalchemy.exc import IntegrityError

from app.extensions import db
from app.models import Note


def test_note_persists_with_timestamps(app_context):
    note = Note(title="Shopping", content="Milk, eggs")
    db.session.add(note)
    db.session.commit()

    saved = db.session.get(Note, note.id)
    assert saved.title == "Shopping"
    assert saved.content == "Milk, eggs"
    assert saved.created_at is not None
    assert saved.updated_at is not None
    assert saved.created_at.tzinfo is not None


def test_updated_at_changes_on_edit_but_created_at_does_not(app_context):
    note = Note(title="Draft", content="v1")
    db.session.add(note)
    db.session.commit()
    created, first_update = note.created_at, note.updated_at

    time.sleep(0.01)
    note.content = "v2"
    db.session.commit()

    assert note.created_at == created
    assert note.updated_at > first_update


def test_title_is_required_at_database_level(app_context):
    db.session.add(Note(title=None, content="no title"))
    with pytest.raises(IntegrityError):
        db.session.commit()
    db.session.rollback()


def test_to_dict_returns_serialisable_fields(app_context):
    note = Note(title="API", content="body")
    db.session.add(note)
    db.session.commit()

    data = note.to_dict()
    assert set(data) == {"id", "title", "content", "created_at", "updated_at"}
    assert data["title"] == "API"
