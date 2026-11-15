# syntax=docker/dockerfile:1

FROM ghcr.io/actions/actions-runner:2.337.0

ARG RUST_VERSION=1.98.1
ARG PROTOC_VERSION=27.5
ARG PROTOC_SHA256=33abede6330dd22fb9af47c2d9804ead3d86c82e025b9eef361a9ac2e955ecce

USER root

# `file` is intentionally omitted until more than one org repo needs it (see issue #1).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      musl-tools \
      gcc-mingw-w64-x86-64 \
      binutils-mingw-w64-x86-64 \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip" -o /tmp/protoc.zip \
 && echo "${PROTOC_SHA256}  /tmp/protoc.zip" | sha256sum -c - \
 && unzip -q /tmp/protoc.zip -d /usr/local bin/protoc 'include/*' \
 && chmod 0755 /usr/local/bin/protoc \
 && chmod -R a+rX /usr/local/include/google \
 && rm /tmp/protoc.zip

# Runner pods mount a shared NFS cache volume over /home/runner/.cache, shadowing image files there.
# Keep rustup proxy binaries read-only in /usr/local/cargo/bin while directing runtime CARGO_HOME to /home/runner/.cache/cargo.
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/home/runner/.cache/cargo \
    PATH=/home/runner/.cache/cargo/bin:/usr/local/cargo/bin:$PATH

RUN curl -fsSL https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init -o /tmp/rustup-init \
 && chmod +x /tmp/rustup-init \
 && CARGO_HOME=/usr/local/cargo /tmp/rustup-init -y --no-modify-path --profile minimal \
      --default-toolchain "${RUST_VERSION}" \
      --component clippy --component rustfmt \
 && CARGO_HOME=/usr/local/cargo /usr/local/cargo/bin/rustup target add \
      x86_64-unknown-linux-musl \
      x86_64-pc-windows-gnu \
      wasm32-unknown-unknown \
 && rm /tmp/rustup-init \
 && chmod -R a+w /usr/local/rustup \
 && chmod -R a+rX,go-w /usr/local/cargo \
 && mkdir -p /home/runner/.cache/cargo \
 && chown -R runner:runner /home/runner/.cache

USER runner

RUN rustc --version \
 && cargo --version \
 && cargo clippy --version \
 && cargo fmt --version \
 && protoc --version \
 && x86_64-w64-mingw32-gcc --version \
 && x86_64-w64-mingw32-dlltool --version \
 && musl-gcc --version \
 && ! test -w /usr/local/cargo/bin \
 && printf 'syntax = "proto3"; import "google/protobuf/timestamp.proto"; message Smoke { google.protobuf.Timestamp ts = 1; }\n' > /tmp/smoke.proto \
 && protoc -I/tmp -I/usr/local/include --descriptor_set_out=/tmp/smoke.desc /tmp/smoke.proto \
 && printf 'pub extern "C" fn smoke() -> u32 { 1 }\n' | rustc --target wasm32-unknown-unknown --crate-type cdylib - -o /tmp/smoke.wasm \
 && printf '#[link(name = "kernel32", kind = "raw-dylib")] extern "system" { fn GetCurrentProcessId() -> u32; } fn main() { unsafe { let _ = GetCurrentProcessId(); } }\n' > /tmp/win_smoke.rs \
 && rustc --target x86_64-pc-windows-gnu /tmp/win_smoke.rs -o /tmp/win_smoke.exe \
 && printf 'fn main() {}\n' | rustc --target x86_64-unknown-linux-musl - -o /tmp/musl_smoke \
 && rm -f /tmp/smoke.proto /tmp/smoke.desc /tmp/smoke.wasm /tmp/win_smoke.rs /tmp/win_smoke.exe /tmp/musl_smoke
