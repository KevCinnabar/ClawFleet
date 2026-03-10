FROM ghcr.io/openclaw/openclaw:latest

ENV NODE_ENV = production
ENV OPENCLAW_HOME = /data/.openclaw
ENV OPENCLAW_WORKSPACE = /data/workspace

USER root

RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    jq \
    vim \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /data/ .openclaw /data/workspace && \
    chown -R node:node /data \

USER node
WORKDIR /DATA

EXPOSE 3000

CMD ["openclaw", "gateway", "start", "--host", "0.0.0.0", "--port", "3000", "--config", "/data/agents/manager/agent.yaml"]