FROM ubuntu:22.04

LABEL org.opencontainers.image.title="aaPanel for Coolify"
LABEL org.opencontainers.image.description="aaPanel control panel image for a Coolify Dockerfile application."
LABEL org.opencontainers.image.source="https://github.com/Tamicktom/aapanel-coolify"
LABEL org.opencontainers.image.url="https://www.aapanel.com"
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=UTC \
    AAPANEL_PORT=8888 \
    AAPANEL_SSL=off

COPY scripts/install-aapanel.sh /tmp/install-aapanel.sh

RUN chmod 755 /tmp/install-aapanel.sh \
    && /tmp/install-aapanel.sh \
    && rm -f /tmp/install-aapanel.sh

COPY scripts/lib.sh /opt/aapanel/lib.sh
COPY scripts/healthcheck.sh /opt/aapanel/healthcheck.sh
COPY scripts/entrypoint.sh /usr/local/bin/aapanel-entrypoint

RUN chmod 755 /opt/aapanel/lib.sh \
    /opt/aapanel/healthcheck.sh \
    /usr/local/bin/aapanel-entrypoint

EXPOSE 8888

HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=5 \
    CMD ["/opt/aapanel/healthcheck.sh"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/aapanel-entrypoint"]
