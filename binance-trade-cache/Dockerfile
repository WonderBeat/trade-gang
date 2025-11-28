FROM --platform=$BUILDPLATFORM debian:bookworm

ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG ZIG_VERSION=0.15.2
WORKDIR /usr/src

RUN apt-get update && \
  apt-get install -y curl tar xz-utils && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

COPY docker-zig-manager /usr/local/bin/docker-zig-manager
RUN /usr/local/bin/docker-zig-manager fetch "$BUILDPLATFORM" $ZIG_VERSION \
  && /usr/local/bin/docker-zig-manager extract

ENV PATH="/usr/local/bin/zig:${PATH}"

WORKDIR /app

ENTRYPOINT ["/usr/local/bin/zig/zig"]

COPY *.zig.zon ./
COPY build.zig ./
RUN zig build --fetch

COPY build.sh ./
COPY src ./src/

RUN ./build.sh "$TARGETPLATFORM" "/application"

FROM alpine:3.21.3
COPY nc-web.sh /
COPY --from=0 /application/bin/* /

CMD ["/app"]
