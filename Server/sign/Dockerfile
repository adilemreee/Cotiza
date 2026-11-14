FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY package.json server.js page.js card-en.png card-es.png ./
USER node
CMD ["node", "--disable-warning=ExperimentalWarning", "server.js"]
