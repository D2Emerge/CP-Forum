FROM node:lts

ENV NODE_ENV=production \
    DAEMON=false \
    SILENT=false \
    USER=nodebb \
    UID=1001 \
    GID=1001

WORKDIR /usr/src/app/

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive \
    apt-get -y --no-install-recommends install \
        tini curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid ${GID} ${USER} \
    && useradd --uid ${UID} --gid ${GID} --home-dir /usr/src/app/ --shell /bin/bash ${USER}

COPY . /usr/src/app/

RUN find . -mindepth 1 -maxdepth 1 -name '.*' ! -name '.' ! -name '..' -exec rm -rf {} \; \
    && cp /usr/src/app/install/package.json /usr/src/app/

RUN mkdir -p build/public/templates logs /opt/config \
    && chown -R ${USER}:${USER} /usr/src/app/ /opt/config/

RUN corepack enable

USER ${USER}

RUN npm install --omit=dev \
    && rm -rf .npm

RUN mkdir -p build/public/templates \
    && echo '<?xml version="1.0" encoding="UTF-8"?>' > build/public/templates/sitemap.tpl \
    && echo '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' >> build/public/templates/sitemap.tpl \
    && echo '<!-- IF urls -->{urls}<!-- ENDIF urls -->' >> build/public/templates/sitemap.tpl \
    && echo '</urlset>' >> build/public/templates/sitemap.tpl \
    && echo '<!-- 404 Error -->' > build/public/templates/404.tpl \
    && echo '<!-- 500 Error -->' > build/public/templates/500.tpl \
    && echo '<!DOCTYPE html><html><head><title>{title}</title></head><body><!-- IMPORT partials/header.tpl --><div class="container">{content}</div><!-- IMPORT partials/footer.tpl --></body></html>' > build/public/templates/base.tpl \
    && echo '/* Initial CSS */' > build/public/client.css \
    && echo '/* Initial CSS */' > build/public/client-cerulean.css \
    && printf 'abcdefghijk' > build/cache-buster

EXPOSE 4567

VOLUME ["/usr/src/app/node_modules", "/usr/src/app/public/uploads", "/opt/config/"]

ENTRYPOINT ["tini", "--"]
CMD ["node", "app.js"]