FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY --chown=node:node server.js .

USER node

EXPOSE 3000
CMD ["npm", "start"]
