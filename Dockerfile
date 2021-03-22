FROM klakegg/hugo:0.81.0-ext-alpine AS build

WORKDIR /build

COPY . .
RUN hugo

FROM nginx:stable-alpine
COPY --from=build /build/public /usr/share/nginx/html

WORKDIR /usr/share/nginx/html
