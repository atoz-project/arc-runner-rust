# Explicit toolchain pinning everywhere; no `stable` channel

The image pins the Rust toolchain (`ARG RUST_VERSION=1.98.1` in the Dockerfile),
consumer repos pin the same version in `rust-toolchain.toml`, and the scale set
pins a SemVer image tag (originally `:1.98.1`, amended below to `:vX.Y.Z` in
`deploy/values.yaml`). Nothing in the system references the `stable` channel. On
an ephemeral ARC pod, a `stable`-referencing setup action makes `rustup`
re-download the toolchain on every cold pod, silently voiding the preinstall,
and gives no reproducibility because clippy gates can change outcome without any
commit when a new `stable` release ships new lints.

The pin therefore lives in **three** places, and that is deliberate. The
Dockerfile pin decides what the image preinstalls, the repository pin covers
GitHub-hosted runners and local checkouts (one file, identical clippy semantics
in all three environments), and the SemVer image tag makes each image bump an
explicit, auditable step. Upgrading Rust follows the four-step sequence
documented in the README. A consumer that has not bumped yet downloads the old
toolchain on demand, which is slower but never broken.

## Considered options

- **Dual toolchain (pin plus `stable` channel in the image).** Serves drifting
  consumers without repo changes, at about 400 MB of extra image size and a
  weekly rebuild cron to keep `stable` fresh. Rejected because drift should be
  impossible, not convenient.
- **Consumers keep `@stable` or empty toolchain input.** Zero repo changes, but
  every cold pod pays a toolchain download and clippy gates drift. Rejected
  after confirming the org's clippy gates (`-D warnings` in `trustlink-cli` and
  `setup-coder`) require reproducibility.
- **Cargo registry baked into the image.** Bloats the image with a low hit rate
  across repos. Originally rejected in favor of `Swatinem/rust-cache@v2` before
  shared NAS cache storage was provisioned (see Amendment below).

## Consequences

- Deferred until a real consumer appears: `cargo-nextest`, `libssl-dev` with
  `pkg-config` (the org uses `rustls`; `setup-coder` constrains pure-Rust TLS
  for cross-compilation), and `sccache` with a local cache server.

## Amendment (2026-11-15)

Two operational constraints revealed in production revised the image tag and
Cargo cache parts of this decision:

1. **SemVer image tags (`:vX.Y.Z`) replace mutable `:1.98.1`.** Adding targets or
   system tools (`gcc-mingw-w64-x86-64`, `binutils-mingw-w64-x86-64`,
   `wasm32-unknown-unknown`, and `protoc`) without bumping Rust caused mutable
   `:1.98.1` tags to diverge across nodes under `IfNotPresent` and Alibaba
   Cloud ECI `ImageCache`, forcing temporary `sha-e1b89c8` workarounds. Image
   releases now take a `:vX.Y.Z` tag from root `VERSION`, guarded in `build.yml`
   against duplicate git and GHCR tags, matching `arc-runner-golang`.
2. **Shared NAS cache volume at `/home/runner/.cache` replaces container-layer
   `CARGO_HOME`.** `CARGO_HOME` moves to `/home/runner/.cache/cargo` (backed by
   the org's shared in-tree NFS volume with `1777` root permissions, matching
   `arc-runner-node`), while preinstalled `rustup` proxy binaries remain
   read-only in `/usr/local/cargo/bin` so the volume mount never shadows them.
