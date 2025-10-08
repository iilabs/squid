# Building Container Images Behind the Squid Proxy

When you run `podman build` or `buildah bud` on the same host as `squid-ssl-proxy.service`, you can reuse the proxy for internet access while adding the generated CA so TLS downloads succeed. This document shows how to wire proxy variables and trust the Squid CA during an image build.

## 1. Export the Proxy CA into Your Build Context

Copy the interception CA that Squid generated (or the CA you staged) into the directory where you run the build:

```bash
cp /etc/squid/ca/CA.pem build-context/squid-proxy-ca.pem
```

Keep this file alongside your `Containerfile` so you can `COPY` it at build time.

## 2. Sample Containerfile

```Dockerfile
# syntax=docker/dockerfile:1.6
FROM registry.fedoraproject.org/fedora:40

# Accept proxy settings from build arguments
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ENV http_proxy=${HTTP_PROXY} \
    https_proxy=${HTTPS_PROXY} \
    no_proxy=${NO_PROXY}

# Install packages using the proxy
RUN dnf install -y git curl && dnf clean all

# Install the Squid-generated CA so SSL interception is trusted
COPY squid-proxy-ca.pem /tmp/
RUN install -m 0644 /tmp/squid-proxy-ca.pem /etc/pki/ca-trust/source/anchors/squid-proxy-ca.pem \
    && update-ca-trust extract \
    && rm -f /tmp/squid-proxy-ca.pem

# Optional: unset proxy variables if the final image should not propagate them
ENV http_proxy= \
    https_proxy= \
    no_proxy=
```

### Notes
- On Debian/Ubuntu bases replace the CA install command with:
  ```bash
  RUN install -m 0644 /tmp/squid-proxy-ca.pem /usr/local/share/ca-certificates/squid-proxy-ca.crt \
      && update-ca-certificates \
      && rm -f /tmp/squid-proxy-ca.pem
  ```
- If you need the proxy available at runtime, skip the final `ENV` block or set new runtime defaults there instead.

## 3. Build Command

Specify the proxy endpoints and CA hostname when building. `host.containers.internal` resolves to the host’s IP inside Podman’s network namespace (Podman ≥4.2). Adjust the host name if you prefer a real interface address.

```bash
cd build-context
podman build \
  --build-arg HTTP_PROXY=http://host.containers.internal:4128 \
  --build-arg HTTPS_PROXY=http://host.containers.internal:4128 \
  --build-arg NO_PROXY=localhost,127.0.0.1,::1,host.containers.internal \
  -t my-proxied-image:latest .
```

If your tooling honours environment variables automatically, you can export them instead of passing `--build-arg`, but using `--build-arg` keeps the build self-contained and avoids leaking the proxy values into your shell.

## 4. Verifying Trust

Inside the built image, confirm that the CA was installed correctly (for example, using `podman run --rm my-proxied-image:latest trust list | grep squid`). Your build steps that fetch HTTPS URLs through Squid should now succeed without additional flags.

## 5. Cleanup

If the build context is shared, remove `squid-proxy-ca.pem` after the build or move it to a secure location—it contains the public side of the interception CA and can be distributed to other build agents as needed.
