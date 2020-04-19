# gik

---

## the sad tales of the failed dockerfiles

i tried hard to dockerize this project, but i am not big brain enough it seems for that to be possible

imagemagick seems to just output black images with the following dockerfiles

### guesses for why this is:

- imagemagick 6 is all ubuntu has (even on the latest `focal` as of the time of this bots dev), and the crystal shard im using is based on 7, with _support_ for 6 in a diff branch, which seems to also produce the same results as the 7 one anywasy
- honestly thats my only guess im at my wits end at this point lol

### the attempts:

1. first of which is a `ubuntu:focal` base image, which does everything by hand because i wasn't sure if there was an issue with the `crystallang:crystal*` images

```dockerfile
# build
FROM ubuntu:focal as build

RUN apt update && apt install -y curl gnupg
RUN curl -sL "https://keybase.io/crystal/pgp_keys.asc" | apt-key add -
RUN echo "deb https://dist.crystal-lang.org/apt crystal main" | tee /etc/apt/sources.list.d/crystal.list
RUN apt update

RUN export DEBIAN_FRONTEND=noninteractive
RUN apt install -y tzdata
RUN ln -fs /usr/share/zoneinfo/Europe/London /etc/localtime
RUN dpkg-reconfigure --frontend noninteractive tzdata

RUN apt install -y \
  crystal \
  libsqlite3-dev \
  libmagickwand-dev

WORKDIR /build
COPY shard.yml /build/
COPY shard.lock /build/
RUN mkdir src
COPY ./src /build/src

RUN shards
RUN shards build gik --release

# prod
FROM ubuntu:focal

RUN apt update && apt install -y \
  imagemagick-6.q16 \
  libssl1.1 \
  libevent-2.1-7 \
  sqlite3 \
  ca-certificates

WORKDIR /app
COPY ./.env.dist /app/.env
COPY --from=build /build/bin/gik /app/gik

CMD ["/app/gik"]
```

2. next is a the OG `crystallang/crystal*` image i have worked with with other bots, same deal still BORKED

```dockerfile
# build
FROM crystallang/crystal:0.34.0-build as build

RUN apt update && apt install -y \
  libsqlite3-dev \
  libmagickwand-dev

WORKDIR /build

COPY shard.yml /build/
COPY shard.lock /build/
RUN mkdir src
COPY ./src /build/src

RUN shards
RUN shards build gik --release

# prod
FROM ubuntu:bionic

RUN apt update && apt install -y \
  libevent-2.1-6 \
  libmagickwand-6.q16-3 \
  sqlite3 \
  libssl1.1 \
  ca-certificates

WORKDIR /app
COPY ./.env.dist /app/.env
COPY --from=build /build/bin/gik /app/gik

CMD ["/app/gik"]
```
