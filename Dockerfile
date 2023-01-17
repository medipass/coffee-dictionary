FROM node:18

WORKDIR /usr/src/app

RUN npm install --global pnpm

COPY package*.json ./
RUN pnpm install

COPY . .
RUN pnpm run build

EXPOSE 3000
CMD [ "node", "dist/index.js" ]
