# Explicit toolchain pinning everywhere; no `stable` channel

The image pins the Rust toolchain (`--default-toolchain 1.98.1` in the
Dockerfile), consumer repos pin the same version in `rust-toolchain.toml`, and
the scale set pins the image by version tag (`:1.98.1` in
`deploy/values.yaml`). Nothing in the system references the `stable` channel:
on an ephemeral ARC pod, a `stable`-referencing setup action makes rustup
re-download the toolchain on every cold pod, silently voiding the preinstall —
and it gives no reproducibility, since clippy gates can change outcome without
any commit when a new stable ships new lints.

The pin therefore lives in **three** places, and that is deliberate: the
Dockerfile pin decides what the image preinstalls, the repo pin is the only
mechanism that also covers GitHub-hosted runners and local checkouts (one
file, identical clippy semantics in all three environments), and the version
tag makes the image bump itself an explicit, auditable step. Upgrading Rust is
the four-step sequence documented in the README; a consumer that hasn't bumped
yet simply downloads the old toolchain on demand — slower, never broken.

## Considered options

- **Dual toolchain (pin + `stable` channel in the image)**: serves drifting
  consumers without repo changes, at +~400MB of image and a weekly rebuild
  cron to keep `stable` fresh. Rejected: we want the drift to be impossible,
  not convenient.
- **Consumers keep `@stable` / empty toolchain input**: zero repo changes, but
  every cold pod pays a toolchain download and clippy gates drift. Rejected
  after confirming the org's clippy gates (`-D warnings` in trustlink-cli and
  setup-coder) want reproducibility.
- **Cargo registry baked into the image**: bloats the image with a low hit
  rate across repos. Rejected; caching lives in the consumer template
  (`Swatinem/rust-cache@v2`), which travels over the GitHub cache service and
  needs no PVC.

## Consequences

- Deferred until a real consumer appears: `cargo-nextest`, `libssl-dev` /
  `pkg-config` (the org is rustls-only; setup-coder even hard-constrains
  pure-Rust TLS for cross-compile), `sccache` + a local cache server (GitHub
  cache service suffices today; revisit via `ACTIONS_CACHE_URL` env override
  if a local server ever materializes).
