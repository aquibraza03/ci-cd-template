# Use official Node runtime
FROM node:20-alpine

# Create app directory
WORKDIR /app

# Copy package files first (better caching)
COPY package*.json ./

# Install dependencies
RUN npm ci --omit=dev

# Copy source
COPY . .

# App runs on port 3000 (change if needed)
EXPOSE 3000

# Start the app
CMD ["node", "index.js"]
