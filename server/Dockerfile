FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm install --omit=dev && npm install tsx
COPY . .
EXPOSE 8787
CMD ["npx", "tsx", "src/local-server.ts"]
