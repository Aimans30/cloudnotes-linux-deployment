# CloudNotes application image: Linux container running Gunicorn.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONPATH=/app

WORKDIR /app

# Unprivileged runtime user. Gunicorn runs as this user, not root.
RUN groupadd --system --gid 10001 cloudnotes \
 && useradd --system --uid 10001 --gid cloudnotes --no-create-home --shell /usr/sbin/nologin cloudnotes

COPY requirements.txt requirements-dev.txt ./
RUN pip install -r requirements.txt

COPY app ./app
COPY migrations ./migrations
COPY scripts ./scripts
COPY tests ./tests
COPY pytest.ini ./
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Normalise line endings in case the script was checked out with CRLF on Windows.
RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh \
 && chmod 0755 /usr/local/bin/docker-entrypoint.sh

USER cloudnotes

EXPOSE 5000

ENTRYPOINT ["docker-entrypoint.sh"]
