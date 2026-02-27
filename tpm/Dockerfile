# syntax=docker/dockerfile:1

ARG ALPINE_VER=3.23
FROM alpine:${ALPINE_VER}

ARG ALPINE_VER
ARG APORTS_BRANCH

RUN apk update && apk add alpine-sdk git bash ccache ca-certificates tar

RUN echo "JOBS=$(nproc)" >> /etc/abuild.conf && \
    echo 'CC="ccache gcc"'  >> /etc/abuild.conf && \
    echo 'CXX="ccache g++"' >> /etc/abuild.conf

RUN adduser -D builder && addgroup builder abuild

RUN set -e; \
    : "${APORTS_BRANCH:=${ALPINE_VER}-stable}"; \
    git init /aports; \
    cd /aports; \
    git remote add origin https://gitlab.alpinelinux.org/alpine/aports.git; \
    git fetch --depth 1 origin "${APORTS_BRANCH}"; \
    git checkout -b "${APORTS_BRANCH}" FETCH_HEAD; \
    git sparse-checkout init --cone; \
    git sparse-checkout set main/linux-lts

WORKDIR /aports
RUN chown -R builder:builder /aports

USER builder
RUN abuild-keygen -a -n

USER root
RUN mkdir -p /etc/apk/keys \
 && cp /home/builder/.abuild/*.pub /etc/apk/keys/ \
 && chmod a+r /etc/apk/keys/*

VOLUME ["/home/builder/.cache/ccache", "/out"]

USER builder
WORKDIR /aports/main/linux-lts
CMD ["/bin/sh"]
