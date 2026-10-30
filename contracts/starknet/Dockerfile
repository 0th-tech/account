FROM python:3.12-slim

ARG GARAGA_VERSION=1.1.0
ARG SCARB_VERSION=2.21.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV HOME=/root
ENV PATH=/root/.local/bin:${PATH}

RUN curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh \
    | bash -s -- -v ${SCARB_VERSION} \
    && scarb --version

RUN pip install --no-cache-dir "garaga==${GARAGA_VERSION}" "fastecdsa==3.0.1"

RUN chmod -R a+rX /root

WORKDIR /work
