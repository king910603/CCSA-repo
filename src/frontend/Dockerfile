FROM nginx:1.29-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html styles.css app.js /usr/share/nginx/html/
# Scripts in /docker-entrypoint.d run before nginx starts, but only if they are
# executable. chmod in a RUN step because COPY --chmod needs BuildKit, which the
# Ubuntu docker.io package in the VM does not ship.
COPY wait-for-api.sh /docker-entrypoint.d/40-wait-for-api.sh
RUN chmod 755 /docker-entrypoint.d/40-wait-for-api.sh

EXPOSE 80
