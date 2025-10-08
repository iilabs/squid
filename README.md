# Squid SSL Proxy

Run the `satishweb/squid-ssl-proxy` container with TLS interception (`ssl-bump`) using either Podman Compose or a systemd-managed container. Configuration lives in this repository while the proxy state (cache, logs, generated CA) persists on the host.

## Requirements
- Podman (rootful recommended for the systemd unit).
- Root access when installing the systemd service or writing to `/etc/squid`.
- TCP ports 3128 (plain HTTP proxy) and 4128 (SSL bump / SOCKS5) reachable from clients.
- SELinux: bind mounts use the `:Z` label, so relabeling must be allowed.

## Repository Layout
- `compose.yaml` – Podman Compose definition.
- `config/squid.sample.conf` – baseline Squid template copied into the container.
- `config/conf.d/` – optional snippets automatically included by the template.
- `config/ca/` – holds the generated or pre-staged CA when using Compose.
- `state/cache`, `state/log` – cache and log directories for Compose deployments.
- `systemd/squid-ssl-proxy.service` – systemd unit for running the container.
- `setup-systemd.sh` – helper that installs the unit and synchronises configuration.
- `install-ca.sh` – convenience script for installing the interception CA into the host trust store.

## Podman Compose Workflow

### 1. Prepare local directories
From the repository root:

```bash
mkdir -p config/ca state/cache state/log
```

Populate `config/ca` with `CA.pem`, `CA.der`, and `private.pem` if you want to use an existing certificate authority; otherwise the container generates them on first start.

### 2. Launch the stack
If you use the Python `podman-compose` shim, export the provider path first:

```bash
export PODMAN_COMPOSE_PROVIDER=/usr/sbin/podman-compose
export PODMAN_COMPOSE_WARNING_LOGS=false
```

Start the proxy:

```bash
podman compose up -d
```

Key bind mounts:
- `./config/squid.sample.conf` → `/templates/squid.sample.conf`
- `./config/conf.d` → `/etc/squid/conf.d`
- `./config/ca` → `/etc/squid-cert`
- `./state/cache` → `/var/cache/squid`
- `./state/log` → `/var/log/squid`

`podman compose logs -f` tails the container output. Stop the stack with `podman compose down`.

### 3. Customise the proxy (optional)
- Edit `config/squid.sample.conf` before starting to adjust defaults.
- Drop additional `.conf` files into `config/conf.d/`; the template includes `/etc/squid/conf.d/*.conf` automatically.
- Override certificate metadata or ports via environment variables in `compose.yaml`.

## Systemd Unit Workflow

### 1. Review configuration
Adjust defaults in `config/squid.sample.conf` and drop any desired snippets into `config/conf.d/`.

Edit `systemd/squid-ssl-proxy.service` if you need to change certificate subject values, ports, image tag, DNS settings, or add extra `podman run` options.

### 2. Install the unit
The helper script copies configuration into `/etc/squid` and installs the unit under `/etc/systemd/system`:

```bash
./setup-systemd.sh
```

The script requires `sudo` for privileged operations and performs the following:
- Creates `/etc/squid`, `/etc/squid/ca`, `/etc/squid/conf.d`.
- Synchronises `config/conf.d` into `/etc/squid/conf.d`.
- Installs `config/squid.sample.conf` as `/etc/squid/squid.envsubst.conf`.
- Installs and reloads the systemd unit.

### 3. Enable and start the service

```bash
sudo systemctl enable --now squid-ssl-proxy.service
```

The unit ensures cache/log directories exist, copies the Squid template from the image if missing, pulls the image only when needed, runs the container, and (on RPM-family hosts) installs the generated `CA.pem` into `/etc/pki/ca-trust/source/anchors/`.

Manage the service with:

```bash
sudo systemctl status squid-ssl-proxy.service
sudo systemctl restart squid-ssl-proxy.service
sudo journalctl -u squid-ssl-proxy.service -f
```

## Certificate Distribution

The container generates `CA.pem`, `CA.der`, and `private.pem` the first time it starts (when the files do not already exist in the mounted directory).

Install the CA into the host trust store (RPM-family example shown):

```bash
sudo ./install-ca.sh config/ca/CA.pem
```

For manual steps:

```bash
# RHEL/Fedora
sudo install -m 0644 config/ca/CA.pem /etc/pki/ca-trust/source/anchors/squid-ssl-proxy.pem
sudo update-ca-trust extract

# Debian/Ubuntu
sudo install -m 0644 config/ca/CA.pem /usr/local/share/ca-certificates/squid-ssl-proxy.crt
sudo update-ca-certificates
```

Distribute `CA.pem` to client systems and add it to their trust stores so SSL-bumped connections succeed.

## Client Proxy Settings

```bash
export HTTP_PROXY=http://squid.host.local:3128
export HTTPS_PROXY=http://squid.host.local:3128
export NO_PROXY=127.0.0.1,localhost,::1
export ALL_PROXY=socks5h://squid.host.local:4128
```

See `PROXY_ENV.md` for approaches to set those variables globally.

## Maintenance and Troubleshooting
- Update environment variables in the Compose file or systemd unit, then restart (`podman compose down && podman compose up -d` or `sudo systemctl daemon-reload && sudo systemctl restart squid-ssl-proxy.service`).
- Refresh the CA by deleting the existing files from the mounted directory and restarting the container.
- Pull a new image:

  ```bash
  sudo podman pull satishweb/squid-ssl-proxy:latest
  sudo systemctl restart squid-ssl-proxy.service
  # or podman compose down && podman compose up -d
  ```

- Inspect runtime logs: `podman logs -f squid-ssl-proxy`, `podman exec -it squid-ssl-proxy tail -n50 /var/log/squid/cache.log`.
- Validate proxying: `curl -x http://squid.host.local:3128 https://registry-1.docker.io/v2/ -I`.

