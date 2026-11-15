# arc-runner-rust

Custom [ARC (actions-runner-controller)](https://github.com/actions/actions-runner-controller)
runner image with the Rust toolchain, cross-compilation targets, and `protoc`
preinstalled. Built on top of the official
`ghcr.io/actions/actions-runner` image.

Image URL is `ghcr.io/atoz-project/arc-runner-rust` (public, anonymous pull works).

## Image tags

New releases publish SemVer tags (`:v1.0.0`, and so on) read from the
[VERSION](VERSION) file at the repository root. Every release tag maps to a
matching `vX.Y.Z` git tag. The build workflow fails before building or pushing
if either the git tag or the GHCR tag already exists.

New releases no longer update `:latest` or mutable Rust-version tags; legacy
`:latest` and `:1.98.1` tags remain unreferenced on GHCR. Pinning a specific
`:vX.Y.Z` tag prevents Kubernetes `IfNotPresent` node caches and Alibaba Cloud
ECI `ImageCache` snapshots from serving stale layers after non-Rust toolchain
updates.

## Using it in a workflow

The scale set `arc-runner-set-rust` (runner group `arc-public`) serves this
image. Select it per job so `runs-on` matches the scale set name:

```yaml
jobs:
  test:
    runs-on: arc-runner-set-rust
    steps:
      - uses: actions/checkout@v4
      - run: cargo test --locked
```

Pin the toolchain in your repository to match the image so the preinstalled
toolchain runs without network downloads:

```toml
# rust-toolchain.toml
[toolchain]
channel = "1.98.1"
```

The same file pins GitHub-hosted runners and local checkouts so clippy gates
behave identically across all three environments. See
[docs/adr/0001-explicit-toolchain-pinning.md](docs/adr/0001-explicit-toolchain-pinning.md).

You can remove these setup steps compared to the default runner image:

- `apt-get install` for `build-essential`, `musl-tools`,
  `gcc-mingw-w64-x86-64`, and `binutils-mingw-w64-x86-64`.
- `dtolnay/rust-toolchain` and `rustup target add` for
  `x86_64-unknown-linux-musl`, `x86_64-pc-windows-gnu`, and
  `wasm32-unknown-unknown`.
- `arduino/setup-protoc`.

`python3`, `unzip`, `git`, `curl`, `jq`, and `sudo` come from the base image.
Do not apt-install them in consumer workflows.

## Cache and paths

`RUSTUP_HOME` is `/usr/local/rustup` (writable by `runner` so unpinned jobs can
still download an extra toolchain on demand). `CARGO_HOME` is
`/home/runner/.cache/cargo`, while read-only `rustup` proxy binaries live in
`/usr/local/cargo/bin` (`PATH=/home/runner/.cache/cargo/bin:/usr/local/cargo/bin:$PATH`).

On `arc-runner-set-rust`, `/home/runner/.cache` is backed by a shared NFS
volume, so Cargo registry downloads and git checkouts persist across ephemeral
runner pods without shadowing `/usr/local/cargo/bin`. Keep
`Swatinem/rust-cache@v2` only if a workflow also needs per-repository `target`
artifacts cached across pods or runs on GitHub-hosted runners.

## Preinstalled components

| Component | Version or source | Notes |
|---|---|---|
| GitHub Actions Runner | `2.337.0` (`ghcr.io/actions/actions-runner:2.337.0`) | Inherits `git`, `curl`, `jq`, `sudo`, `unzip`, and `python3` |
| Rust | `1.98.1` via `rustup` (minimal profile) | `clippy`, `rustfmt`, targets `x86_64-unknown-linux-musl`, `x86_64-pc-windows-gnu`, `wasm32-unknown-unknown` |
| Protobuf compiler (`protoc`) | `27.5` (SHA256-verified zip) | Binary at `/usr/local/bin/protoc`; well-known protos at `/usr/local/include/google/protobuf/` |
| Build tools | `build-essential`, `musl-tools`, `gcc-mingw-w64-x86-64`, `binutils-mingw-w64-x86-64` | Provides native `cc`, musl linker, mingw linker, and `x86_64-w64-mingw32-dlltool` |

## No DinD by design

No Docker daemon runs in the pod, `/var/run/docker.sock` is absent, and there is
no `dind` sidecar. The CLI and runtime binaries in `/usr/bin` come from the
base image and stay inert without a socket or privileges. Pure Rust CI
(`cargo build`, `cargo test`, and `cargo clippy`) does not require a Docker
socket, which keeps runner pods unprivileged. Workflows that build container
images or run Docker Compose remain on GitHub-hosted runners.

## Deploying the scale set

[deploy/values.yaml](deploy/values.yaml) is the source of truth for
`arc-runner-set-rust` in namespace `arc-runners` on `k8s-sg-dev`. It sets:

- `4` CPU and `8Gi` memory Guaranteed QoS (`requests` equal `limits`) to prevent
  release LTO builds from hitting OOM on the `2` CPU and `4Gi` cluster default.
- An in-tree `nfs` volume pointing to the shared Alibaba Cloud NAS
  (`071wrg7528z1wkkb61l-fbj64.ap-southeast-1.nas.aliyuncs.com`) at
  `/home/runner/.cache`. The export root carries mode `1777`, so `uid 1001`
  (`runner`) creates `/home/runner/.cache/cargo` directly (`fsGroup: 1001` is
  kept for CSI volume portability and is ignored by in-tree `nfs`).

Apply changes with chart `0.14.2` to match the live controller minor version:

```bash
helm upgrade --install arc-runner-set-rust \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version 0.14.2 -n arc-runners --kube-context k8s-sg-dev -f deploy/values.yaml
```

Wait for `.github/workflows/build.yml` to publish the target `:vX.Y.Z` tag on
GHCR before running `helm upgrade`, because upgrading to an unpublished tag puts
the scale set into `ImagePullBackOff`. Pending jobs drain to existing pods
automatically.

## Building

[.github/workflows/build.yml](.github/workflows/build.yml) builds and runs the
smoke tests on pull requests affecting `Dockerfile`, `VERSION`, or `build.yml`.
On push to `main` or manual dispatch, it pushes `:vX.Y.Z` to GHCR and creates a
matching `vX.Y.Z` git tag.

## Upgrading Rust

Follow this four-step sequence (see the ADR for rationale):

1. Bump `ARG RUST_VERSION` in [Dockerfile](Dockerfile) and bump [VERSION](VERSION).
2. Merge to `main` and wait for `.github/workflows/build.yml` to publish `:vX.Y.Z`.
3. Update the tag in [deploy/values.yaml](deploy/values.yaml) and run `helm upgrade`.
4. Bump `rust-toolchain.toml` in each consumer repository.

Until a consumer repository bumps `rust-toolchain.toml`, its pods download the
old toolchain on demand without failing.

## License

[MIT](LICENSE)
