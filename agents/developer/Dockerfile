FROM ghcr.io/openclaw/openclaw:latest

USER root

RUN apt-get update && apt-get install -y \
    curl wget git jq vim ca-certificates \
    && rm -rf /var/lib/apt/lists/*

USER node

# 预写 gateway 配置：允许非 loopback 的 Control UI
RUN openclaw config set gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback true

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 18789

ENTRYPOINT ["entrypoint.sh"]
