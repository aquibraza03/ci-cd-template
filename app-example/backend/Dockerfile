FROM node:20-alpine

# Create non-root user
RUN addgroup -S nodejs && adduser -S nodeuser -G nodejs

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY server.js .

EXPOSE 3000

# Switch to non-root user
USER nodeuser

# Healthcheck for container monitoring
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["npm", "start"]
