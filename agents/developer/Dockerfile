FROM ghcr.io/openclaw/openclaw:latest

ENV NODE_ENV=production
ENV OPENCLAW_HOME=/data/.openclaw
ENV OPENCLAW_WORKSPACE=/data/workspace
ENV OPENCLAW_NO_RESPAWN=1

USER root

RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    jq \
    vim \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /data/.openclaw /data/workspace /data/agents/developer && \
    chown -R node:node /data

COPY --chown=node:node entrypoint.sh /data/entrypoint.sh
RUN chmod +x /data/entrypoint.sh

USER node
WORKDIR /data

EXPOSE 3000

ENTRYPOINT ["/data/entrypoint.sh"]
