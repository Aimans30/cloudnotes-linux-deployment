# CloudNotes

CloudNotes is a small notes application: create, view, edit and delete notes, with
timestamps on every note.

This repository is being built up in stages. The `main` branch holds only the
repository setup; the application itself lives on the `feature/linux-deploy` branch.

## Planned stack

- **Flask** backend with an application factory
- **Gunicorn** as the production WSGI server
- **PostgreSQL** as the only database, accessed through SQLAlchemy and Flask-Migrate
- **Docker Compose** deployment on a Linux container, with automatic restart on crash
