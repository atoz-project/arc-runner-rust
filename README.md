# arc-runner-rust

Custom [ARC (actions-runner-controller)](https://github.com/actions/actions-runner-controller)
runner image with the Rust toolchain baked in. Built on top of the official
`ghcr.io/actions/actions-runner` image.

Image: `ghcr.io/atoz-project/arc-runner-rust` (public, anonymous pull works)

## Using it in a workflow

The scale set `arc-runner-set-rust` (runner group `arc-public`) serves this
image. Select it per job — the label *is* the image choice:

```yaml
jobs:
  test:
    runs-on: arc-runner-set-rust   # Rust toolchain preinstalled, no setup steps
    steps:
      - uses: actions/checkout@v4
      - uses: actions-rust-lang/setup-rust-toolchain@v1   # optional, see below
        with:
          toolchain: ""           # empty: use the image's pinned Rust
      - run: cargo test --locked
```

What you can drop compared to the default runner image:

- `apt-get install build-essential` / musl packages — baked in
- `dtolnay/rust-toolchain` or `setup-rust-toolchain` with a version — the image
  pins Rust (see table below); only keep the action if you need a *different*
  version or extra components

Keep `actions-rust-lang/setup-rust-toolchain` (or `Swatinem/rust-cache`) if you
want the shared cargo registry/target cache — the action manages that cache
even with an empty `toolchain:`.

## What's inside

| Component | Version / source | Notes |
|---|---|---|
| GitHub Actions Runner | pinned base `ghcr.io/actions/actions-runner` | inherits git, curl, jq, sudo |
| Rust | 1.98.1 via rustup (minimal profile) | `clippy`, `rustfmt`, `rust-src`, `x86_64-unknown-linux-musl` target |
| Build tools | `build-essential`, `musl-tools`, `pkg-config` | via apt |

`cargo` / `rustc` are on `PATH` for the `runner` user (`~/.cargo/bin`).

## No DinD by design

No Docker daemon / CLI / sidecar. Pure Rust CI (`cargo build` / `test` /
`clippy`) never needs a docker socket; leaving it out keeps the runner pod
unprivileged. Workflows that build images (buildx, compose) stay on
GitHub-hosted runners.

## Deploying / re-pointing the scale set

The live scale set was installed with:

```bash
helm upgrade --install arc-runner-set-rust \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version 0.13.0 -n arc-runners -f deploy/values.yaml
```

To roll out a new image build, bump the tag in
[deploy/values.yaml](deploy/values.yaml) (or keep `latest` and restart the
listener pods) — pending jobs drain to the old pods automatically.

## Building

[.github/workflows/build.yml](.github/workflows/build.yml) builds and pushes
on every `main` push touching the Dockerfile and on manual dispatch. Tags:
`latest` + `sha-<commit>`.

## License

[MIT](LICENSE)
