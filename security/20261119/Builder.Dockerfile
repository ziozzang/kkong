FROM debian:trixie-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad
RUN apt-get update && apt-get -y upgrade && apt-get install -y --no-install-recommends build-essential ca-certificates curl git unzip zip m4 perl python3 libyaml-dev libssl-dev zlib1g-dev patch pkg-config cmake autoconf automake libtool xz-utils && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://github.com/bazelbuild/bazelisk/releases/download/v1.25.0/bazelisk-linux-amd64 -o /usr/local/bin/bazel && chmod +x /usr/local/bin/bazel
ENV USER=builder
RUN git config --global url.https://github.com/openldap/openldap.git.insteadOf https://git.openldap.org/openldap/openldap.git
WORKDIR /src
