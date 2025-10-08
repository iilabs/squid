# Additional Squid Configuration

Place custom ACLs, refresh patterns, or cache tuning snippets in this directory. Files are mounted under `/etc/squid/conf.d/` inside the container and loaded by the main configuration via `include /etc/squid/conf.d/*.conf`.

Example files:
- `refresh_patterns.conf` – add long-lived caching rules.
- `acl_allowlist.conf` – define networks or hosts allowed to use the proxy.
