FROM --platform=$BUILDPLATFORM alpine:3.21.3

ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG ZIG_VERSION=0.13.0
WORKDIR /usr/src

COPY docker-zig-manager /usr/local/bin/docker-zig-manager
RUN /usr/local/bin/docker-zig-manager fetch "$BUILDPLATFORM" $ZIG_VERSION
RUN /usr/local/bin/docker-zig-manager extract

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
COPY --from=0 /application/bin/app /app

CMD ["/app"]
