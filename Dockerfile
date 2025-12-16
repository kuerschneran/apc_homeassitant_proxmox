
FROM debian:stable-slim

RUN apt-get update && apt-get install -y \
    apcupsd \
    apcupsd-cgi \
    mosquitto-clients \
    bash \
    cron \
    apache2 \
    && rm -rf /var/lib/apt/lists/*

RUN a2enmod cgi

COPY apc.sh /usr/local/bin/apc.sh
COPY apc.conf /usr/local/bin/apc.conf
COPY apccontrol /etc/apcupsd/apccontrol
COPY apcupsd.conf /etc/apcupsd/apcupsd.conf
COPY startup.sh /usr/local/bin/startup.sh
COPY 000-default.conf /etc/apache2/sites-enabled/000-default.conf

RUN chmod +x /usr/local/bin/apc.sh \
    && chmod +x /etc/apcupsd/apccontrol \
    && chmod +x /usr/local/bin/startup.sh \
    && echo "*/10 * * * * root /usr/local/bin/apc.sh status" >> /etc/crontab

EXPOSE 80

CMD ["/usr/local/bin/startup.sh"]

