"""CloudNotes application factory.

Gunicorn loads the app with ``app:create_app()``.
"""

import logging
from datetime import timezone

from flask import Flask, render_template
from flask_wtf.csrf import CSRFError
from sqlalchemy.exc import DBAPIError, OperationalError, SQLAlchemyError

from app.config import load_config, validate_database_url
from app.extensions import csrf, db, migrate

logger = logging.getLogger(__name__)


def format_timestamp(value):
    """Render a timezone-aware datetime as a UTC string for templates."""
    if value is None:
        return ""
    return value.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


def create_app(test_config=None):
    app = Flask(__name__)
    app.config.update(load_config())
    if test_config:
        app.config.update(test_config)

    if not app.config.get("SECRET_KEY"):
        raise RuntimeError("SECRET_KEY is not set. Set it in .env (see .env.example).")
    validate_database_url(app.config["SQLALCHEMY_DATABASE_URI"])

    db.init_app(app)
    migrate.init_app(app, db)
    csrf.init_app(app)

    from app.routes import bp

    app.register_blueprint(bp)
    app.add_template_filter(format_timestamp, "timestamp")
    _register_error_handlers(app)
    return app


def _register_error_handlers(app):
    @app.errorhandler(404)
    def not_found(error):
        return render_template(
            "error.html",
            code=404,
            title="Note not found",
            message="The page you requested does not exist or the note was deleted.",
        ), 404

    @app.errorhandler(CSRFError)
    def csrf_failed(error):
        return render_template(
            "error.html",
            code=400,
            title="Form expired",
            message="Your session may have expired. Reload the page and try again.",
        ), 400

    @app.errorhandler(OperationalError)
    @app.errorhandler(DBAPIError)
    def database_unavailable(error):
        db.session.rollback()
        logger.error("Database unavailable: %s", error.__class__.__name__)
        return render_template(
            "error.html",
            code=503,
            title="Database unavailable",
            message="CloudNotes cannot reach its PostgreSQL database. Your changes were not saved. Try again shortly.",
        ), 503

    @app.errorhandler(SQLAlchemyError)
    def database_error(error):
        db.session.rollback()
        logger.exception("Unexpected database error")
        return render_template(
            "error.html",
            code=500,
            title="Something went wrong",
            message="The database rejected the request. Your changes were not saved.",
        ), 500

    @app.errorhandler(500)
    def internal_error(error):
        return render_template(
            "error.html",
            code=500,
            title="Something went wrong",
            message="An unexpected error occurred. Please try again.",
        ), 500
