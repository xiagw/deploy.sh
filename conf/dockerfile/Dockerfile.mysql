ARG MYSQL_VERSION
FROM mysql:${MYSQL_VERSION}

LABEL maintainer="Mahmoud Zalt <mahmoud@zalt.me>"

#####################################
# Set Timezone
#####################################
ARG TZ=UTC
ENV TZ ${TZ}

ARG MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
ARG MYSQL_SLAVE=false

CMD ["mysqld"]

EXPOSE 3306

COPY ./root/ /

RUN bash /opt/build.sh
