ARG BASE=node:20-alpine
FROM ${BASE}
# pick up fixed alpine packages (openssl) that the base image tag has not rebuilt yet
RUN apk upgrade --no-cache
WORKDIR /app
COPY package*.json ./
# the runtime does not need npm/yarn; removing them also drops their bundled vulnerable deps (tar, glob, minimatch...)
RUN npm ci --omit=dev \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx /opt/yarn* /usr/local/bin/yarn*
COPY src ./src
EXPOSE 8080
CMD ["node", "src/server.js"]
