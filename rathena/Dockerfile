FROM ubuntu:24.04 AS build
ARG RATHENA_REF=d4b8e7b8f16061cc2496d377ac8f777ce72a4f39
ARG PACKETVER=20200401
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git build-essential zlib1g-dev libpcre3-dev \
    libmariadb-dev libmariadb-dev-compat libssl-dev libxml2-dev python3 pkg-config \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN git clone https://github.com/rathena/rathena.git . \
    && git checkout "${RATHENA_REF}" \
    && git submodule update --init --recursive
RUN test -s sql-files/main.sql \
    && test -s sql-files/logs.sql \
    && test -s sql-files/web.sql \
    && grep -Eiq "CREATE[[:space:]]+TABLE[[:space:]]+IF[[:space:]]+NOT[[:space:]]+EXISTS" sql-files/web.sql
RUN ./configure --enable-packetver="${PACKETVER}" && make server

# Assemble only what the three servers and the entrypoint need at runtime, so the
# final image does not carry the source tree, object files, 3rdparty, .git or the
# optional web-server's source. Runtime file use was verified by tracing a full startup:
#   login-server, char-server, map-server  the daemons the entrypoint launches
#   web-server  started only when ENABLE_WEB_SERVER=true (see docker-compose.web.yml)
#   conf/       configuration (the entrypoint also seeds an empty bind mount from it)
#   db/, npc/   databases and scripts loaded by the map server
#   sql-files/  schemas the entrypoint imports into empty databases
# rAthena prints a "Git Hash" banner by reading .git/refs/heads/master; keep that one
# line (the commit that was actually checked out) instead of the whole repository.
RUN mkdir -p /runtime/.git/refs/heads \
    && cp login-server char-server map-server web-server /runtime/ \
    && cp -a conf db npc sql-files /runtime/ \
    && git rev-parse HEAD > /runtime/.git/refs/heads/master

FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates gosu mariadb-client libmariadb3 libpcre3 zlib1g libssl3 libxml2 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --create-home --home-dir /rathena --shell /usr/sbin/nologin rathena
WORKDIR /rathena
COPY --from=build --chown=rathena:rathena /runtime/ /rathena/
COPY --from=build --chown=rathena:rathena /src/conf/ /usr/share/rathena-default-conf/
COPY --chmod=755 entrypoint.sh /usr/local/bin/rathena-entrypoint
EXPOSE 6900/tcp 6121/tcp 5121/tcp
ENTRYPOINT ["/usr/local/bin/rathena-entrypoint"]
