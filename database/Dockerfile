FROM alpine:3.22

RUN apk add --no-cache sqlite

COPY init.sh /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

ENV DATABASE_PATH=/data/names.db

VOLUME ["/data"]

CMD ["/usr/local/bin/init.sh"]

