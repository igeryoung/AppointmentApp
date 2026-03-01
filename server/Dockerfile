FROM dart:stable AS build

WORKDIR /app

COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart pub get --offline
RUN mkdir -p build && dart compile exe main.dart -o build/server

FROM dart:stable AS runtime

WORKDIR /app

COPY --from=build /app/build/server /app/server
COPY --from=build /app/openapi.yaml /app/openapi.yaml
COPY --from=build /app/public /app/public

ENV SERVER_HOST=0.0.0.0
ENV PORT=8080

EXPOSE 8080

CMD ["/app/server"]
