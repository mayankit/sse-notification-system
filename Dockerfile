FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
ARG PORT=3001
ENV PORT=${PORT}
EXPOSE ${PORT}
CMD ["node", "src/server.js"]
