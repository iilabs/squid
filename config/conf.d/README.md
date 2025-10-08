# Additional Squid Configuration

Place custom ACLs, refresh patterns, or cache tuning snippets in this directory. Files are mounted under `/etc/squid/conf.d/` inside the container and loaded by the main configuration via `include /etc/squid/conf.d/*.conf`.

Example files:
- `cache_tuning.conf` – 1-year refresh patterns for container layers, RPM/DEB payloads, and OSTree objects.
- `offline_build_tweaks.conf` – helper directives (`offline_mode`, `collapsed_forwarding`, LFUDA policies) for artifact-heavy build environments.
