FROM dart:stable AS build

WORKDIR /app

COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart pub get --offline
RUN dart compile exe main.dart -o build/server

FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /runtime/ /
COPY --from=build /app/build/server /app/server
COPY --from=build /app/openapi.yaml /app/openapi.yaml
COPY --from=build /app/public /app/public

ENV SERVER_HOST=0.0.0.0
ENV PORT=8080

EXPOSE 8080

CMD ["/app/server"]
