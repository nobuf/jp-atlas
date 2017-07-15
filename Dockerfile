# gdal is not ready for 8.x yet
# https://github.com/naturalatlas/node-gdal/issues/200
# Also, on alpine, it gets "symbol not found" error.
FROM node:6.11

RUN mkdir /app && chown node.node /app
WORKDIR /app

RUN apt-get update
RUN apt-get install -y unzip

USER node

CMD npm install && npm start