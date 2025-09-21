ARG DEBIAN_VERSION="trixie-slim"

FROM debian:${DEBIAN_VERSION}

LABEL verion="1.0.0" \
    team="devops"

ARG KUBECTL_VERSION=v1.32.0
ENV KUBECTL_VERSION=${KUBECTL_VERSION}

WORKDIR /app

# Update, Install packages and clean cache update
RUN apt-get update && apt-get install --no-install-recommends --no-install-suggests -y \
    apt-transport-https \
    ca-certificates \
    curl \
    jq \
    openssh-client \
    && rm -rf /var/www/html \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

COPY entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/entrypoint.sh

CMD [ "/app/entrypoint.sh" ]