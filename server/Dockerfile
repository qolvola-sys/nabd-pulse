FROM node:24-alpine

WORKDIR /app

ENV NODE_ENV=production
ENV DATA_DIR=/data
ENV QUIET=1

COPY package.json package-lock.json* ./
RUN npm install --omit=dev --no-audit --no-fund

COPY src ./src
COPY scripts ./scripts

RUN mkdir -p /data
VOLUME ["/data"]
EXPOSE 8787

CMD ["node", "src/index.js"]
