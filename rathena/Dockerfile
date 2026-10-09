FROM ubuntu:24.04 AS build
ARG RATHENA_REF=master
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git build-essential zlib1g-dev libpcre3-dev \
    libmariadb-dev libssl-dev libxml2-dev python3 pkg-config \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN git clone https://github.com/rathena/rathena.git . \
    && git checkout "${RATHENA_REF}" \
    && git submodule update --init --recursive
RUN ./configure && make server

FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libmariadb3 libpcre3 zlib1g libssl3 libxml2 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --create-home --home-dir /rathena --shell /usr/sbin/nologin rathena
WORKDIR /rathena
COPY --from=build --chown=rathena:rathena /src/ /rathena/
COPY --chmod=755 entrypoint.sh /usr/local/bin/rathena-entrypoint
EXPOSE 6900/tcp 6121/tcp 5121/tcp
USER rathena
ENTRYPOINT ["/usr/local/bin/rathena-entrypoint"]
