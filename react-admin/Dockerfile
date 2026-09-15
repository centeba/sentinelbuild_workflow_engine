# Builds the React admin and serves the static bundle with nginx.
# Build context: this react-admin/ dir.
FROM node:20-alpine AS build

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
# VITE_API_BASE is relative so the app calls the same origin it is served from;
# nginx (below) proxies /api to the backend.
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
