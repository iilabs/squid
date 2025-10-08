# Persistent Proxy Environment Variables

Squid exposes two endpoints on the host running `squid-ssl-proxy.service`:

- `http://<proxy-host>:3128` – traditional HTTP(S) proxy without SSL bump.
- `http://<proxy-host>:4128` – SSL-bump-enabled proxy (also handles SOCKS when clients request it).

Clients typically set the following variables:

```bash
HTTP_PROXY=http://<proxy-host>:4128
HTTPS_PROXY=http://<proxy-host>:4128
NO_PROXY=127.0.0.1,localhost,::1
```

To make these variables available to every process started by your user, choose one of the approaches below. Replace `<proxy-host>` with the actual hostname or IP of the proxy.

## 1. Shell Startup Files (Bash/Zsh)

Add the exports to your shell configuration so interactive shells inherit them. For Bash:

```bash
echo 'export HTTP_PROXY=http://<proxy-host>:4128' >> ~/.bashrc
echo 'export HTTPS_PROXY=http://<proxy-host>:4128' >> ~/.bashrc
echo 'export NO_PROXY=127.0.0.1,localhost,::1' >> ~/.bashrc
```

If you use login shells (e.g., SSH), also update `~/.bash_profile` or `~/.profile`. After editing, reload the file (`source ~/.bashrc`) or log out and back in.

## 2. systemd User Environment

To cover user services and GUI applications managed by `systemd --user`, create an environment drop-in:

```bash
mkdir -p ~/.config/environment.d
cat <<'ENV' > ~/.config/environment.d/proxy.conf
HTTP_PROXY=http://<proxy-host>:4128
HTTPS_PROXY=http://<proxy-host>:4128
NO_PROXY=127.0.0.1,localhost,::1
ENV
```

Reload the environment for the current session:

```bash
systemctl --user import-environment HTTP_PROXY HTTPS_PROXY NO_PROXY
systemctl --user daemon-reexec
```

New user services and shells spawned by systemd will inherit the values. Log out/in to cover graphical sessions launched before the change.

## 3. PAM / Login Manager (`~/.pam_environment`)

On desktop distributions that honour PAM environment files, you can provide defaults that apply to all login methods (TTY, SSH, graphical logins):

```bash
echo 'HTTP_PROXY DEFAULT=http://<proxy-host>:4128' >> ~/.pam_environment
echo 'HTTPS_PROXY DEFAULT=http://<proxy-host>:4128' >> ~/.pam_environment
echo 'NO_PROXY DEFAULT=127.0.0.1,localhost,::1' >> ~/.pam_environment
```

This file is evaluated before the session starts, so it catches applications that launch outside a shell. Log out completely and log back in to activate the settings.

## Tips

- Always set `NO_PROXY` for localhost addresses to avoid proxying loopback traffic.
- If you prefer the non-bumping listener, substitute the `3128` port in the examples above.
- Avoid storing credentials in plain text; if authentication is required, consider using per-application configuration or dedicated credential helpers.
- Some older applications only look for http_proxy / https_proxy lowercase, and ignore uppercase. You may need to set both.
