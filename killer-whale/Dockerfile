FROM --platform=$BUILDPLATFORM debian:bookworm

ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG ZIG_VERSION=0.15.1
WORKDIR /usr/src

RUN apt-get update && \
    apt-get install -y curl tar xz-utils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY docker-zig-manager /usr/local/bin/docker-zig-manager
RUN /usr/local/bin/docker-zig-manager fetch "$BUILDPLATFORM" $ZIG_VERSION
RUN /usr/local/bin/docker-zig-manager extract

ENV PATH="/usr/local/bin/zig:${PATH}"

WORKDIR /app

RUN dpkg --add-architecture amd64 && dpkg --add-architecture arm64 && apt-get update 
RUN apt-get install -y libcurl4-openssl-dev:amd64 libcurl4-openssl-dev:arm64

ENTRYPOINT ["/usr/local/bin/zig/zig"]

COPY *.zig.zon ./
COPY build.zig ./
RUN zig build --fetch

COPY build.sh ./
COPY src ./src/

RUN ./build.sh "$TARGETPLATFORM" "/application"

FROM alpine:3.21.3
RUN apk add --no-cache curl-dev socat
COPY nc-web.sh /
COPY --from=0 /application/bin/* /

CMD ["/binance"]
