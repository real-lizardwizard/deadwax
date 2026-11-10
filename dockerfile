# The interface is built here rather than committed, so a checkout never carries generated
# output and the image can't drift from the source it was built from.
FROM node:22-alpine AS ui

WORKDIR /ui

# lockfile first: this layer only busts when dependencies actually change, so ordinary
# frontend edits reuse the cached npm ci
COPY ui/package.json ui/package-lock.json ./
RUN npm ci

COPY ui/ ./
# vite.config.ts sets outDir to ../interface/dist, so this lands at /interface/dist. The
# build also runs tsc --noEmit first, which makes a type error fail the image build rather
# than ship.
RUN npm run build


FROM python:3.14-slim

# gosu drops privileges cleanly in the entrypoint. su/sudo both leave the process re-parented
# with a TTY attached, which breaks signal handling - the container then ignores SIGTERM and
# takes the full timeout to stop.
RUN apt-get update \
    && apt-get install -y --no-install-recommends gosu \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
COPY interface/ ./interface/
# after the interface copy, so a stale dist/ left behind by a local build is overwritten
# rather than shipped
COPY --from=ui /interface/dist ./interface/dist
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# (2.0.3) The container's own side of the downloads and music mounts, so a compose file needn't name
# them: docker-compose.example.yml mounts slskd's finished downloads at /downloads and the library at
# /music. Only defaults - a value from compose's environment: or env_file: replaces them, and one saved
# in Server settings beats both, as for any setting. Outside the image (the dev setup, a plain
# `python -m src.main`) the code still has no default for either, and organizing stays off until both
# are set. DB_PATH needs none here: the code defaults it to /config/deadwax.db (or an older
# /config/jimbrainz.db) itself.
ENV PYTHONUNBUFFERED=1 \
    PUID=1000 \
    PGID=1000 \
    SLSKD_DOWNLOAD_PATH=/downloads \
    LIBRARY_PATH=/music

# So Komodo (or anything else watching) can tell "running" from "working" - see /deadwax/health
# in src/api/app.py for what it does and deliberately doesn't count. Python rather than curl,
# which the slim image doesn't have; the port is fixed at 8080 in src/main.py. The start period
# covers a first start's database setup.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["python", "-c", "import sys, urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/deadwax/health', timeout=4).status == 200 else 1)"]

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["python", "-m", "src.main"]
