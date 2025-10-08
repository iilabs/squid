# Squid Caching Agent (Container + systemd)

This repository documents how to run Squid with TLS interception (`ssl-bump`) entirely inside the `satishweb/squid-ssl-proxy` container. Configuration remains in the container; the host persists only the generated CA plus cache and log data.

---

## 1. Requirements
- Podman (rootful); the systemd unit invokes `/usr/bin/podman`.
- Root access to manage `/etc/squid/ca`, `/var/cache/squid-ssl-proxy`, `/var/log/squid-ssl-proxy`, and `/etc/systemd/system/`.
- Network access for clients on TCP 3128 (plain proxy) and 4128 (SSL bump / SOCKS5).
- SELinux hosts should allow relabeled bind mounts (`:Z`).

Host directories used by the service:
- `/etc/squid/ca`: container writes `CA.pem`, `CA.der`, and `private.pem` here.
- `/var/cache/squid-ssl-proxy`: persistent cache (`/var/cache/squid` inside the container).
- `/var/log/squid-ssl-proxy`: access/cache logs (`/var/log/squid` inside the container).

Squid configuration inside `/etc/squid` stays in the container. The entrypoint regenerates it from environment variables on each start.

---

## 2. Image Behaviour
See [Docker Hub](https://hub.docker.com/r/satishweb/squid-ssl-proxy) and [GitHub](https://github.com/satishweb/squid-ssl-proxy):
- Entry point uses `/templates/squid.sample.conf` plus environment variables to rebuild `/etc/squid/squid.conf` every launch.
- Regenerates the SSL certificate database (`/var/lib/ssl_db`) and cache metadata (`squid -Nz`) automatically.
- Exposes `SQUID_PROXY_PORT` (default 3128) and `SQUID_PROXY_SSLBUMP_PORT` (default 4128).
- Creates the interception CA in `/etc/squid-cert` if `private.pem` is missing.

Customise via environment variables (`CERT_CN`, `CERT_ORG`, `CERT_OU`, `CERT_COUNTRY`, `SQUID_PROXY_PORT`, `SQUID_PROXY_SSLBUMP_PORT`). Advanced users can mount a replacement template at `/templates/squid.sample.conf` if needed.

---

## 3. Prepare Persistent Paths

```bash
sudo install -d -m 0755 /etc/squid/ca /var/cache/squid-ssl-proxy /var/log/squid-ssl-proxy
```

Populate `/etc/squid/ca` with an existing CA if you do not want the image to generate one.

---

## 4. CA Generation / Distribution
The container generates a CA the first time it runs. To pre-stage or customise the subject:

```bash
sudo podman run --rm -it \
  -e CERT_CN=squid.local \
  -e CERT_ORG=squid \
  -e CERT_OU=squid \
  -e CERT_COUNTRY=US \
  -v /etc/squid/ca:/etc/squid-cert:Z \
  satishweb/squid-ssl-proxy:latest \
  openssl req \
    -new -newkey rsa:4096 -days 825 -nodes -x509 \
    -keyout /etc/squid-cert/private.pem \
    -out /etc/squid-cert/CA.pem \
    -subj "/C=US/ST=State/L=City/O=Squid Proxy/OU=Infra/CN=squid-ca.local"
```

Distribute `/etc/squid/ca/CA.pem` to clients and install it into their trust stores:

```bash
# RHEL/Fedora
sudo install -m 0644 /etc/squid/ca/CA.pem /etc/pki/ca-trust/source/anchors/squid-ssl-proxy.pem
sudo update-ca-trust extract

# Debian/Ubuntu
sudo install -m 0644 /etc/squid/ca/CA.pem /usr/local/share/ca-certificates/squid-ssl-proxy.crt
sudo update-ca-certificates
```

The repository also ships `scripts/install-ca.sh` to automate the host installation step. Run it as root (optionally overriding the CA path):

```bash
sudo scripts/install-ca.sh /etc/squid/ca/CA.pem
```

---

## 5. Install the systemd Unit
Run the helper script to install the unit **and** sync configuration templates/snippets into `/etc/squid/` before the service starts:

```bash
./setup.sh
```

Enable/start the service:

```bash
sudo systemctl enable --now squid-ssl-proxy.service
```

Manual alternative:

```bash
sudo install -m 0644 systemd/squid-ssl-proxy.service /etc/systemd/system/squid-ssl-proxy.service
sudo systemctl daemon-reload
```

### Service Flow
1. Ensures `/etc/squid`, `/etc/squid/ca`, `/etc/squid/conf.d`, `/var/cache/squid-ssl-proxy`, and `/var/log/squid-ssl-proxy` exist.
2. Seeds `/etc/squid/squid.envsubst.conf` on first run (copied from the image if the file is missing).
3. Pulls the image only if it is not already cached (`podman image exists`).
4. Runs the container with the custom template plus `/etc/squid/conf.d` snippets, alongside the CA/cache/log mounts.
5. Copies `CA.pem` into the host trust store on RPM-family systems (edit `ExecStartPost` to suit other distros).

Edit the `Environment=` lines in the unit to change certificate metadata or port bindings.

### Template and Runtime Controls
- `config/squid.sample.conf` is copied to `/etc/squid/squid.envsubst.conf` and mounted at `/templates/squid.sample.conf`; update this file to change Squid defaults before running `./setup.sh`.
- `config/conf.d/*.conf` synchronises into `/etc/squid/conf.d/` and is included automatically (`include /etc/squid/conf.d/*.conf`).
- Systemd sets the following environment variables by default: `CERT_CN=ii.coop`, `CERT_ORG=iilabs`, `CERT_OU=squid`, `CERT_COUNTRY=US`, `SQUID_PROXY_PORT=3128`, `SQUID_PROXY_SSLBUMP_PORT=4128`. Override them by editing the unit before rerunning `./setup.sh`.
- At runtime the container honours `/run/secrets/ENVNAME` entries; drop files such as `/run/secrets/DEBUG` containing `1` to enable entrypoint debugging (`set -x`).
- To control the DNS server, add `--dns=<address>` to the `podman run` line in the unit (or duplicate the unit and customise it) so Squid resolves through the host of your choice.
- Advanced launches can provide `/app-config` inside the container to wrap the final command. Create a shell script, mount it at `/app-config`, and it will be sourced to launch the proxy.

---

## 6. Managing the Service

```bash
sudo systemctl status squid-ssl-proxy.service
sudo systemctl restart squid-ssl-proxy.service
sudo systemctl stop squid-ssl-proxy.service
sudo journalctl -u squid-ssl-proxy.service -f
```

Check the running container:

```bash
sudo podman logs -f squid-ssl-proxy
sudo podman exec -it squid-ssl-proxy tail -n50 /var/log/squid/cache.log
sudo podman exec -it squid-ssl-proxy squidclient -p 3128 mgr:info
```

Cleanup:

```bash
sudo systemctl disable --now squid-ssl-proxy.service
sudo rm -rf /var/cache/squid-ssl-proxy /var/log/squid-ssl-proxy /etc/squid/ca
```

---

## 7. Client Usage

```bash
export HTTP_PROXY=http://squid.host.local:3128
export HTTPS_PROXY=http://squid.host.local:3128
export NO_PROXY=127.0.0.1,localhost,::1

export ALL_PROXY=socks5h://squid.host.local:4128
```

See `PROXY_ENV.md` for ways to set these variables globally (shell startup files, systemd user environment, or PAM-based logins).

Custom tuning is supported through files mounted under `/etc/squid/conf.d/`; this repository ships examples in `config/conf.d/` (e.g., `refresh_patterns.conf`, `test_marker.conf`). The container’s template includes `include /etc/squid/conf.d/*.conf` so new snippets are picked up on restart.

Tool-specific examples:
- **DNF/RPM**: add `proxy=http://squid.host.local:3128` to `/etc/dnf/dnf.conf` or `/etc/yum.conf`.
- **OSTree**: `ostree remote add --proxy=http://squid.host.local:3128 ...`.
- **Homebrew**: rely on `HTTP(S)_PROXY`; optionally set `HOMEBREW_NO_AUTO_UPDATE=1`.
- **Container engines**: provide proxy variables via `/etc/containers/registries.conf.d/` (Podman) or `/etc/systemd/system/docker.service.d/proxy.conf` (Docker).

Ensure clients trust `/etc/squid/ca/CA.pem`; SSL-bumped connections fail without it.

---

## 8. Updates and Maintenance
- Change environment variables in the unit as needed, then `sudo systemctl daemon-reload` and restart the service.
- Clear `/etc/squid/ca/*` and restart to regenerate the CA, redistributing the new certificate.
- Pull new images when desired:
  ```bash
  sudo podman pull satishweb/squid-ssl-proxy:latest
  sudo systemctl restart squid-ssl-proxy.service
  ```

Cache/log retention is determined by the mounted directories; prune them manually when required.

---

## 9. Container Builds Behind the Proxy
To build container images that use the Squid proxy during `podman build`, follow the workflow in `CONTAINER_BUILD.md` (proxy-aware `Containerfile`, CA installation, and `--build-arg` usage).

## 10. Troubleshooting
- `sudo systemctl status squid-ssl-proxy.service` – service health.
- `sudo journalctl -u squid-ssl-proxy.service` – lifecycle events (directory checks, pull decisions, CA install).
- `sudo podman logs squid-ssl-proxy` – Squid stdout/stderr.
- Validate proxying:
  ```bash
  curl -x http://squid.host.local:3128 https://registry-1.docker.io/v2/ -I
  ```
- Reset cache:
  ```bash
  sudo systemctl stop squid-ssl-proxy.service
  sudo rm -rf /var/cache/squid-ssl-proxy/*
  sudo systemctl start squid-ssl-proxy.service
  ```

For deeper customisation, version control a custom template and mount it at `/templates/squid.sample.conf` in the unit.
