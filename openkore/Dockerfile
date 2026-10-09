FROM debian:bookworm-slim
ARG OPENKORE_REF=master
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
