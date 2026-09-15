# Builds the example app (which embeds the mit_stack package) as a Flutter web
# bundle and serves it with nginx. Build context: this flutter_package/ dir.
#
# Flutter is pinned to match the analyze gate (see .github/workflows/ci.yml).
FROM ghcr.io/cirruslabs/flutter:3.41.6 AS build

WORKDIR /app
COPY . /app

# Resolve the package (and its vendored siblings under vendor/), then build the
# example web app. API_BASE_URL is relative so the app calls the same origin it
# is served from; nginx (below) proxies /api to the backend.
RUN git config --global --add safe.directory /app \
    && flutter pub get
WORKDIR /app/example
RUN flutter pub get \
    && flutter build web --release \
        --no-tree-shake-icons \
        --dart-define=API_BASE_URL=/api/v1

FROM nginx:alpine
COPY --from=build /app/example/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
