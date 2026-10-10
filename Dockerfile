FROM --platform=linux/amd64 debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    WINEARCH=win64 \
    WINEPREFIX=/opt/wineprefix \
    WINEDEBUG=-all \
    DISPLAY=

RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      wine wine32 wine64 \
      python3 \
      procps \
      netcat-openbsd \
      iproute2 \
      cabextract \
      openssh-client \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /opt/sc /data/db /logs /opt/entry \
 && wine --version

WORKDIR /opt/sc/cloud

COPY entrypoint.sh /opt/entry/entrypoint.sh
COPY scripts/patch-addr-assert.py /opt/entry/patch-addr-assert.py
COPY scripts/patch-security-check.py /opt/entry/patch-security-check.py
RUN chmod +x /opt/entry/entrypoint.sh

VOLUME ["/logs"]

EXPOSE 27017 3800-3850/tcp 3800-3850/udp 3850/tcp 3850/udp

ENTRYPOINT ["/opt/entry/entrypoint.sh"]
