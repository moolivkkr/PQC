FROM node:24-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY . .
ENV NODE_ENV=production
# Build-time guard: fails the build if this Node can't do ML-KEM.
RUN node pq-check.js
USER node
EXPOSE 8443
CMD ["node", "server.js"]
