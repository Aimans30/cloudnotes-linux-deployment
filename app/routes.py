"""HTTP routes for CloudNotes."""

from flask import Blueprint, current_app, flash, jsonify, redirect, render_template, request, url_for
from sqlalchemy import select, text
from sqlalchemy.exc import SQLAlchemyError

from app.extensions import db
from app.models import Note
from app.validation import parse_note_form

bp = Blueprint("notes", __name__)


def _commit():
    """Commit the session, rolling back and re-raising on database failure."""
    try:
        db.session.commit()
    except SQLAlchemyError:
        db.session.rollback()
        current_app.logger.exception("Database commit failed")
        raise


@bp.get("/health")
def health():
    try:
        db.session.execute(text("SELECT 1"))
    except SQLAlchemyError:
        db.session.rollback()
        current_app.logger.exception("Health check failed: database unreachable")
        return jsonify(status="unhealthy", database="unreachable"), 503
    return jsonify(status="ok", database="ok"), 200


@bp.get("/")
def index():
    notes = db.session.execute(
        select(Note).order_by(Note.updated_at.desc(), Note.id.desc())
    ).scalars().all()
    return render_template("index.html", notes=notes)


@bp.get("/notes/new")
def new_note():
    return render_template("create_note.html", form={}, errors={})


@bp.post("/notes")
def create_note():
    data, errors = parse_note_form(request.form)
    if errors:
        return render_template("create_note.html", form=data, errors=errors), 400

    note = Note(**data)
    db.session.add(note)
    _commit()
    flash("Note created.", "success")
    return redirect(url_for("notes.view_note", note_id=note.id))


@bp.get("/notes/<int:note_id>")
def view_note(note_id):
    note = db.get_or_404(Note, note_id)
    return render_template("view_note.html", note=note)


@bp.get("/notes/<int:note_id>/edit")
def edit_note(note_id):
    note = db.get_or_404(Note, note_id)
    form = {"title": note.title, "content": note.content}
    return render_template("edit_note.html", note=note, form=form, errors={})


@bp.post("/notes/<int:note_id>/edit")
def update_note(note_id):
    note = db.get_or_404(Note, note_id)
    data, errors = parse_note_form(request.form)
    if errors:
        return render_template("edit_note.html", note=note, form=data, errors=errors), 400

    note.title = data["title"]
    note.content = data["content"]
    _commit()
    flash("Note updated.", "success")
    return redirect(url_for("notes.view_note", note_id=note.id))


@bp.post("/notes/<int:note_id>/delete")
def delete_note(note_id):
    note = db.get_or_404(Note, note_id)
    title = note.title
    db.session.delete(note)
    _commit()
    flash(f'Deleted "{title}".', "success")
    return redirect(url_for("notes.index"))


@bp.get("/api/notes")
def api_list_notes():
    notes = db.session.execute(
        select(Note).order_by(Note.id)
    ).scalars().all()
    return jsonify([note.to_dict() for note in notes])


@bp.get("/api/notes/<int:note_id>")
def api_get_note(note_id):
    note = db.get_or_404(Note, note_id)
    return jsonify(note.to_dict())
