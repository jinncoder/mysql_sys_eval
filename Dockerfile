FROM mysql:8.0.42

COPY init.sql /docker-entrypoint-initdb.d/
COPY entrypoint.sh /usr/local/bin/custom-entrypoint.sh

RUN chmod +x /usr/local/bin/custom-entrypoint.sh

ENTRYPOINT ["custom-entrypoint.sh"]
CMD ["mysqld"]
