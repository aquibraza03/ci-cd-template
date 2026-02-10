FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci && npm run build

# Use nginx for serving static files
FROM nginx:alpine

COPY --from=0 /app/dist /usr/share/nginx/html

# Run as non-root user (nginx already non-root safe in alpine)
USER nginx

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost || exit 1

