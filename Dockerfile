# Reproducible dev/CI environment: Aptos CLI + Node. (Not built in the authoring environment; verify once.)
FROM ubuntu:22.04
ARG APTOS_CLI_VERSION=9.6.0
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates unzip git make jq \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && apt-get install -y nodejs \
    && curl -fsSL -o /tmp/aptos.zip "https://github.com/aptos-labs/aptos-core/releases/download/aptos-cli-v${APTOS_CLI_VERSION}/aptos-cli-${APTOS_CLI_VERSION}-Ubuntu-22.04-x86_64.zip" \
    && unzip /tmp/aptos.zip -d /usr/local/bin && chmod +x /usr/local/bin/aptos && rm -rf /var/lib/apt/lists/* /tmp/aptos.zip
WORKDIR /work
COPY . .
CMD ["make", "test"]
