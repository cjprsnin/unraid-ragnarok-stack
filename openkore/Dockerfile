FROM debian:bookworm-slim
ARG OPENKORE_REF=51de1ddfc4449ae5217f6886de702f87ca934030
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git perl make gcc g++ libssl-dev zlib1g-dev \
    libio-socket-ssl-perl libwww-perl libxml-simple-perl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/openkore
RUN git clone https://github.com/OpenKore/openkore.git . \
    && git checkout "${OPENKORE_REF}"
COPY entrypoint.sh /usr/local/bin/openkore-entrypoint
RUN chmod +x /usr/local/bin/openkore-entrypoint
ENTRYPOINT ["/usr/local/bin/openkore-entrypoint"]
