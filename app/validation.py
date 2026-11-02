"""Input validation for note forms."""

TITLE_MAX_LENGTH = 200
CONTENT_MAX_LENGTH = 10000


def parse_note_form(form):
    """Return ``(data, errors)`` for a submitted note.

    ``data`` holds the cleaned ``title`` and ``content``. ``errors`` maps field
    names to messages and is empty when the input is valid.
    """
    title = (form.get("title") or "").strip()
    content = (form.get("content") or "").strip()
    errors = {}

    if not title:
        errors["title"] = "Title is required."
    elif len(title) > TITLE_MAX_LENGTH:
        errors["title"] = f"Title must be {TITLE_MAX_LENGTH} characters or fewer."

    if len(content) > CONTENT_MAX_LENGTH:
        errors["content"] = f"Content must be {CONTENT_MAX_LENGTH} characters or fewer."

    # PostgreSQL text columns cannot store NUL bytes.
    if "\x00" in title or "\x00" in content:
        errors["content"] = "Note contains invalid characters."

    return {"title": title, "content": content}, errors
