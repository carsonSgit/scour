# Build context supplies precompiled binaries: scour-linux-x86_64 (and optionally
# scour-linux-aarch64) next to this file. Build: docker build -t scour:<tag> .
# Runs with a dedicated non-root user; GIT + tar/curl/sha256 preinstalled.
FROM debian:stable-slim
ARG TARGETARCH
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git tar gzip \
    && rm -rf /var/lib/apt/lists/*
COPY scour-linux-${TARGETARCH:-x86_64} /usr/local/bin/scour
RUN chmod 0755 /usr/local/bin/scour \
    && useradd --uid 34214 --user-home --shell /usr/sbin/nologin scour
USER scour
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/scour"]
