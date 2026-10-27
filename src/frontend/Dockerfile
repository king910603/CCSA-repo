FROM nginx:1.29-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html styles.css app.js /usr/share/nginx/html/
# Scripts in /docker-entrypoint.d run before nginx starts.
COPY --chmod=755 wait-for-api.sh /docker-entrypoint.d/40-wait-for-api.sh

EXPOSE 80
