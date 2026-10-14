# oneclick-images

Container images for open-source apps that do not publish an official image.

Each image is a rebuild of a tagged upstream release. Nothing is added to the app: the build pins
its base images, builds both `linux/amd64` and `linux/arm64`, runs a smoke test, and publishes one
multi-arch tag with signed build provenance. Licences stay with the upstream projects.

## Pull

```bash
docker pull ghcr.io/xcloud-oneclick/<image>:<upstream-version>-xcloud.<n>
```

Tags are immutable: a rebuild of the same upstream release gets the next `-xcloud.<n>`.

Verify the provenance of an image:

```bash
gh attestation verify oci://ghcr.io/xcloud-oneclick/<image>:<tag> --owner xCloud-Oneclick
```

## Layout

```
apps/<slug>/
  build.yaml    upstream repo, release ref and commit, image name, version
  Dockerfile    used when upstream ships none, or ships one that needs pinning
  test.sh       smoke test, receives IMAGE=<local image ref>
```

`build.yaml`:

```yaml
image: example-web            # ghcr.io/xcloud-oneclick/<image>
version: 1.2.3-xcloud.1       # published tag; bump -xcloud.<n> to rebuild
upstream: https://github.com/example/example
ref: v1.2.3                   # upstream tag
commit: 0123456789abcdef0123456789abcdef01234567   # must match ref
dockerfile: Dockerfile        # relative to apps/<slug>/; build context is the upstream tree
```

## Flow

1. A pull request adds or changes `apps/<slug>/`. CI builds both architectures and runs `test.sh`.
   Nothing is published from a pull request.
2. A maintainer merges. CI rebuilds, tests, publishes the tag, scans it and attaches provenance.
   A version that already exists is never overwritten.

Only maintainers can merge. Outside contributions are welcome as pull requests from forks.
