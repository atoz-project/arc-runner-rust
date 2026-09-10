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
      - uses: Swatinem/rust-cache@v2   # cargo registry + target cache
      - run: cargo test --locked       # no toolchain setup at all
```

Pin the toolchain in your repo to match the image, so the preinstalled
toolchain is a rustup no-op on the pod:

```toml
# rust-toolchain.toml
[toolchain]
channel = "1.98.1"
```

The same file also pins GitHub-hosted runners and local checkouts, so clippy
gates behave identically in all three environments. See
[docs/adr/0001-explicit-toolchain-pinning.md](docs/adr/0001-explicit-toolchain-pinning.md).

What you can drop compared to the default runner image:

- `apt-get install build-essential` / musl packages — baked in
- `dtolnay/rust-toolchain` / `setup-rust-toolchain` — a versioned setup action
  on an ephemeral pod just re-downloads the toolchain. Only use one if you
  need a *different* version than the image pin, or extra components

`Swatinem/rust-cache` is the standard cache; don't combine it with
`setup-rust-toolchain`'s built-in cache (double caching). `python3`, `unzip`,
`git`, `curl`, `jq`, `sudo` are inherited from the base image — don't
apt-install them either.

## What's inside

| Component | Version / source | Notes |
|---|---|---|
| GitHub Actions Runner | pinned base `ghcr.io/actions/actions-runner` | inherits git, curl, jq, sudo |
| Rust | 1.98.1 via rustup (minimal profile) | `clippy`, `rustfmt`, `x86_64-unknown-linux-musl` target |
| Build tools | `build-essential`, `musl-tools`, `file` | via apt; `binutils` (`readelf`/`strings`) ships with gcc |

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

To roll out a new image build, bump the version tag in
[deploy/values.yaml](deploy/values.yaml) and re-run the helm command above —
pending jobs drain to the old pods automatically.

## Building

[.github/workflows/build.yml](.github/workflows/build.yml) builds and pushes
on every `main` push touching the Dockerfile and on manual dispatch. Tags:
`latest`, `sha-<commit>`, and the pinned Rust version (e.g. `1.98.1`,
extracted from the Dockerfile — single source of truth). The scale set pins
the version tag; `latest` is never referenced by the deployment.

## Upgrading Rust

Explicit four-step sequence (see the ADR for why):

1. Bump `--default-toolchain` in the [Dockerfile](Dockerfile) → merge; the
   build workflow pushes a new `<version>` tag
2. Bump the tag in [deploy/values.yaml](deploy/values.yaml) → `helm upgrade`
3. Bump `rust-toolchain.toml` in each consumer repo
4. Until a consumer bumps, its pods download the old toolchain on demand —
   slower, never broken

## License

[MIT](LICENSE)
