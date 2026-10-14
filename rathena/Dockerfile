FROM ubuntu:24.04 AS build
ARG RATHENA_REF=d4b8e7b8f16061cc2496d377ac8f777ce72a4f39
ARG PACKETVER=20200401
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git build-essential cmake zlib1g-dev libpcre3-dev \
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
# Build the SQL converter with all prompts disabled, tied to this pinned source.
RUN ./configure --enable-packetver="${PACKETVER}" && make server \
    && sed -i '/#if defined(BUILDBOT)/i #define CONVERT_ALL' src/tool/yaml2sql.cpp \
    && cmake -S . -B /tmp/yaml2sql-build -DPACKETVER="${PACKETVER}" \
    && cmake --build /tmp/yaml2sql-build --target yaml2sql --parallel "$(nproc)" \
    && cp sql-files/item_db2_re.sql sql-files/item_db2_re.schema.sql \
    && cp sql-files/mob_db_re.sql sql-files/mob_db_re.schema.sql \
    && cp sql-files/mob_db2_re.sql sql-files/mob_db2_re.schema.sql \
    && ./yaml2sql \
    && if grep -Eq '^(INSERT INTO|REPLACE INTO)' sql-files/item_db2_re.sql; then sed -n '/^REPLACE INTO/,$p' sql-files/item_db2_re.sql > sql-files/item_db2_re.data.sql; else printf '%s\n' '-- no renewal import-item data in pinned source' > sql-files/item_db2_re.data.sql; fi \
    && if grep -Eq '^(INSERT INTO|REPLACE INTO)' sql-files/mob_db_re.sql; then sed -n '/^REPLACE INTO/,$p' sql-files/mob_db_re.sql > sql-files/mob_db_re.data.sql; else printf '%s\n' '-- no renewal monster data generated' > sql-files/mob_db_re.data.sql; fi \
    && if grep -Eq '^(INSERT INTO|REPLACE INTO)' sql-files/mob_db2_re.sql; then sed -n '/^REPLACE INTO/,$p' sql-files/mob_db2_re.sql > sql-files/mob_db2_re.data.sql; else printf '%s\n' '-- no renewal import-monster data in pinned source' > sql-files/mob_db2_re.data.sql; fi \
    && test -s sql-files/item_db_re.sql \
    && test -s sql-files/item_db_re_equip.sql \
    && test -s sql-files/item_db_re_etc.sql \
    && test -s sql-files/item_db_re_usable.sql \
    && test -s sql-files/item_db2_re.schema.sql \
    && test -s sql-files/item_db2_re.data.sql \
    && test -s sql-files/mob_db_re.schema.sql \
    && test -s sql-files/mob_db2_re.schema.sql \
    && test -s sql-files/mob_db_re.data.sql \
    && test -s sql-files/mob_db2_re.data.sql \
    && rows="$(grep -hEc '^(INSERT INTO|REPLACE INTO)' sql-files/item_db_re_equip.sql sql-files/item_db_re_etc.sql sql-files/item_db_re_usable.sql | awk '{sum += $1} END {print sum+0}')" \
    && mob_rows="$(grep -c '^REPLACE INTO' sql-files/mob_db_re.data.sql || true)" \
    && test "${rows}" -gt 20000 \
    && test "${mob_rows}" -gt 1000 \
    && printf 'EXPECTED_ITEM_ROWS=%s\nEXPECTED_MOB_ROWS=%s\n' "${rows}" "${mob_rows}" > sql-files/renewal-data-counts.env \
    && echo "Generated renewal SQL rows: items=${rows}, monsters=${mob_rows}"

FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates gosu mariadb-client libmariadb3 libpcre3 zlib1g libssl3 libxml2 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --create-home --home-dir /rathena --shell /usr/sbin/nologin rathena
WORKDIR /rathena
COPY --from=build --chown=rathena:rathena /src/ /rathena/
COPY --from=build --chown=rathena:rathena /src/conf/ /usr/share/rathena-default-conf/
COPY --chmod=755 entrypoint.sh /usr/local/bin/rathena-entrypoint
EXPOSE 6900/tcp 6121/tcp 5121/tcp
ENTRYPOINT ["/usr/local/bin/rathena-entrypoint"]
