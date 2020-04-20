FROM jackharrhy/crystal-imagemagick-7-docker

RUN apt update && apt install -y \
  libsqlite3-dev

WORKDIR /build

COPY shard.yml /build/
COPY shard.lock /build/
RUN mkdir src
COPY ./src /build/src

RUN shards
RUN shards build gik --release

RUN apt install -y \
  libevent-2.1-6 \
  sqlite3 \
  libssl1.1 \
  ca-certificates

WORKDIR /app
COPY ./.env.dist /app/.env
RUN mv /build/bin/gik /app/gik

RUN rm -rf /imagemagick /build

CMD ["/app/gik"]
