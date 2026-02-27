# syntax=docker/dockerfile:1

ARG ALPINE_VER=3.23
FROM alpine:${ALPINE_VER}

RUN apk update && apk add alpine-sdk git bash ccache ca-certificates tar

# abuild config
RUN echo "JOBS=$(nproc)" >> /etc/abuild.conf && \
    echo 'CC="ccache gcc"'  >> /etc/abuild.conf && \
    echo 'CXX="ccache g++"' >> /etc/abuild.conf

# Builder user + group
RUN adduser -D builder && addgroup builder abuild

# Put vendored linux-lts package recipe where abuild expects it
WORKDIR /aports/main/linux-ec2-tpm
COPY linux-ec2-tpm/ /aports/main/linux-ec2-tpm/

# Permissions for building
RUN chown -R builder:builder /aports

USER builder
RUN abuild-keygen -a -n

USER root
RUN mkdir -p /etc/apk/keys \
 && cp /home/builder/.abuild/*.pub /etc/apk/keys/ \
 && chmod a+r /etc/apk/keys/*

VOLUME ["/home/builder/.cache/ccache", "/out"]

USER builder
WORKDIR /aports/main/linux-ec2-tpm
CMD ["/bin/sh"]
