ARG BASE=node:20-alpine
FROM ${BASE}
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY src ./src
EXPOSE 8080
CMD ["node", "src/server.js"]
