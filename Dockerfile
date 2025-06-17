FROM node:lts AS build

ENV NODE_ENV=production \
    DAEMON=false \
    SILENT=false \
    USER=nodebb \
    UID=1001 \
    GID=1001

WORKDIR /usr/src/app/

COPY . /usr/src/app/

# Install corepack to allow usage of other package managers
RUN corepack enable

# Remove unnecessary files
RUN find . -mindepth 1 -maxdepth 1 -name '.*' ! -name '.' ! -name '..' -exec bash -c 'echo "Deleting {}"; rm -rf {}' \;

# Prepare package.json from install directory
RUN cp /usr/src/app/install/package.json /usr/src/app/

# Install system dependencies including tools needed for our production script
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive \
    apt-get -y --no-install-recommends install \
        tini \
        curl \
        netcat-openbsd \
        openssl \
        ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create user and set permissions
RUN groupadd --gid ${GID} ${USER} \
    && useradd --uid ${UID} --gid ${GID} --home-dir /usr/src/app/ --shell /bin/bash ${USER} \
    && chown -R ${USER}:${USER} /usr/src/app/

USER ${USER}

# Install Node.js dependencies
RUN npm install --omit=dev --no-audit --no-fund \
    && rm -rf .npm

FROM node:lts-slim AS final

ENV NODE_ENV=production \
    DAEMON=false \
    SILENT=false \
    USER=nodebb \
    UID=1001 \
    GID=1001 \
    TINI_SUBREAPER=1 \
    PACKAGE_MANAGER=npm \
    CONFIG_DIR=/opt/config \
    START_BUILD=false \
    OVERRIDE_UPDATE_LOCK=false

WORKDIR /usr/src/app/

# Install system dependencies and corepack
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive \
    apt-get -y --no-install-recommends install \
        curl \
        netcat-openbsd \
        openssl \
        ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && corepack enable

# Create user and directories
RUN groupadd --gid ${GID} ${USER} \
    && useradd --uid ${UID} --gid ${GID} --home-dir /usr/src/app/ --shell /bin/bash ${USER} \
    && mkdir -p /usr/src/app/logs/ /opt/config/ /usr/src/app/public/uploads \
    && chown -R ${USER}:${USER} /usr/src/app/ /opt/config/

# Copy application from build stage
COPY --from=build --chown=${USER}:${USER} /usr/src/app/ /usr/src/app/

# Copy tini and our production entrypoint
COPY --from=build /usr/bin/tini /usr/local/bin/tini
COPY docker/production-entrypoint.sh /usr/local/bin/production-entrypoint.sh

# Set executable permissions
RUN chmod +x /usr/local/bin/tini \
    && chmod +x /usr/local/bin/production-entrypoint.sh \
    && chown ${USER}:${USER} /usr/local/bin/production-entrypoint.sh

USER ${USER}

# Create necessary directories
RUN mkdir -p public/assets build logs node_modules

EXPOSE 4567

# Volume mounts for persistent data
VOLUME ["/usr/src/app/node_modules", "/usr/src/app/build", "/usr/src/app/public/uploads", "/opt/config/", "/usr/src/app/logs"]

# Health check with appropriate timing for our build process
HEALTHCHECK --interval=30s --timeout=15s --start-period=900s --retries=3 \
    CMD curl -f http://localhost:4567/api/config || curl -f http://localhost:4567/ || exit 1

# Use tini as init system with our production entrypoint
ENTRYPOINT ["tini", "-s", "--", "/bin/bash", "/usr/local/bin/production-entrypoint.sh"]