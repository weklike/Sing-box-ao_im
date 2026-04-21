# sing-box All-in-One Multi-Protocol Deployment Script

[English](./README.md) | [简体中文](./README_CN.md)

This repository has been refactored from a single-purpose installer into a `sing-box` all-in-one deployment and management script, with an interaction style closer to `vless-all-in-one`, while remaining fully based on `sing-box`.

Core entry points:

- `install-sing-box.sh`
  Installs, reconfigures, validates, manages users, manages routing, exports client configs, restarts, stops, and uninstalls
- `config.json`
  Example server-side `sing-box` configuration in the repository; the real runtime config is generated dynamically at `/etc/sing-box/config.json`
- `DESIGN.md`
  Current design notes for the script

## Supported Protocols

Based on official `sing-box` capabilities and the Debian package, the script currently supports:

- `VLESS`
- `VMess`
- `Trojan`
- `Hysteria2`
- `TUIC`
- `NaiveProxy`
- `SOCKS5`
- `SS2022`

Notes:

- `VLESS` uses `Reality` mode by default, so it can be deployed without certificates
- If you switch `VLESS` to `tls`, a domain and certificate are required
- `VMess`, `Trojan`, `Hysteria2`, `TUIC`, and `NaiveProxy` require TLS certificates
- `SOCKS5` and `SS2022` do not require certificates
- `NaiveProxy` is a newer capability in `sing-box`; the script requires `sing-box >= 1.13.0`

## Current Capabilities

The script currently provides:

- Interactive menu similar in spirit to `vless-all-in-one`
- One-shot multi-protocol inbound deployment
- Persistent multi-user state
- Protocol-level user add/remove management
- Server-side routing policy management
- `sing-box` client config management
- Non-interactive CLI usage
- Automatic installation of the official `SagerNet` APT repository and `sing-box`
- Automatic certificate issuance and installation with `acme.sh`
- Automatic port allocation, or explicit user-defined ports
- Reuse of existing credentials and ports across reruns
- Share link export
- `sing-box` client `outbounds` snippet export
- Full `sing-box` client template export
- Commands: `list-users`, `add-user`, `remove-user`, `regenerate`
- Commands: `routing-menu`, `client-menu`
- Commands: `show-info`, `validate`, `status`, `restart`, `stop`, `uninstall`

## Design Boundaries

To keep the implementation stable and maintainable, this version intentionally does not mirror the entire reference project feature-for-feature.

Current design choices:

- One dedicated listening port per protocol
- `sing-box` only; no dual-core `Xray + sing-box` stack
- No panel, subscription center, user quota, or expiry management
- No heavy in-repo template patching; the script generates config directly

This is deliberate. The goal is to keep the multi-protocol deployment and lifecycle management reliable first.

## Requirements

- OS: `Debian 12`
- Privileges: `root`
- Service manager: `systemd`
- Network access to Debian mirrors, `deb.sagernet.org`, and `get.acme.sh`

## Quick Start

### 1. Interactive Deployment

```bash
chmod +x install-sing-box.sh
./install-sing-box.sh
```

Running the script directly opens the interactive menu.

### 2. Deploy All Supported Protocols at Once

```bash
./install-sing-box.sh install \
  --protocols vless,vmess,trojan,hysteria2,tuic,naive,socks5,ss2022 \
  --domain example.com \
  --email admin@example.com
```

### 3. Deploy Only Protocols That Do Not Require Certificates

```bash
./install-sing-box.sh install \
  --protocols vless,socks5,ss2022 \
  --vless-mode reality
```

### 4. Deploy with Explicit Ports

```bash
./install-sing-box.sh install \
  --protocols vless,trojan,ss2022 \
  --domain example.com \
  --email admin@example.com \
  --vless-port 24443 \
  --trojan-port 24444 \
  --ss2022-port 24445
```

### 5. Show Current Deployment Info

```bash
./install-sing-box.sh show-info
```

### 6. List Users

```bash
./install-sing-box.sh list-users
```

List users for a single protocol:

```bash
./install-sing-box.sh list-users --protocol vmess
```

### 7. Add a User

```bash
./install-sing-box.sh add-user --protocol vmess --user-name alice
```

Example for `SS2022`:

```bash
./install-sing-box.sh add-user --protocol ss2022 --user-name bob
```

### 8. Remove a User

```bash
./install-sing-box.sh remove-user --protocol socks5 --user-name socks-123abc
```

Notes:

- The script does not allow removing the last remaining user of a protocol
- `add-user` and `remove-user` automatically rebuild the config and restart `sing-box`

### 9. Regenerate Runtime Config from Saved State

```bash
./install-sing-box.sh regenerate
```

### 10. Validate the Runtime Config

```bash
./install-sing-box.sh validate
```

### 11. Routing Policy Management

```bash
./install-sing-box.sh routing-menu
```

Current server-side routing toggles:

- `BT/PT blocking`
- `CN direct restriction / block-cn policy`
- `Ads blocking`

The exported client templates also include a richer outbound strategy layer by default:

- `urltest` group: `auto`
- `selector` group: `select`
- Default CN-direct client rules:
  - `geosite-geolocation-cn -> direct`
  - `geoip-cn -> direct`

Notes:

- You mentioned `geosite-location-cn`; in the official `sing-box` rule-set naming, the correct tag is `geosite-geolocation-cn`
- Client templates default to `route.final = select`
- `select` puts `auto` first by default, so the preferred default behavior is automatic testing

### 12. Client Config Management

```bash
./install-sing-box.sh client-menu
```

Current client menu operations:

- Show current client information
- Rebuild all client files
- Show client `outbounds` snippet
- Show full client template (`mixed`)
- Show `TUN` client template

### 13. Show Service Status

```bash
./install-sing-box.sh status
```

### 14. Restart the Service

```bash
./install-sing-box.sh restart
```

### 15. Stop the Service

```bash
./install-sing-box.sh stop
```

### 16. Uninstall

```bash
./install-sing-box.sh uninstall
```

## Common Parameters

- `--protocols`
  Comma-separated protocol list:
  `vless,vmess,trojan,hysteria2,tuic,naive,socks5,ss2022`
- `--vless-mode reality|tls`
- `--domain`
- `--email`
- `--share-host`
- `--cert-mode acme|self-signed`
- `--acme-mode auto|standalone|alpn`
- `--naive-network tcp|udp`
- `--ss2022-method 2022-blake3-aes-128-gcm|2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305`
- `--tuic-cc cubic|new_reno|bbr`
- `--rotate-secrets`
- `--protocol`
- `--user-name`
- `--user-uuid`
- `--user-password`
- `--target-config`

For the complete option list:

```bash
./install-sing-box.sh --help
```

## Output Files

Runtime server-side files are stored under `/etc/sing-box`:

- `/etc/sing-box/config.json`
  Active server runtime configuration
- `/etc/sing-box/rule-set/`
  Local rule-sets used when routing policies are enabled
- `/etc/sing-box/ssl/fullchain.pem`
- `/etc/sing-box/ssl/key.pem`

Script state and exported client artifacts are stored under `/var/lib/sing-box-script`:

- `/var/lib/sing-box-script/install-state.json`
  Persistent state file containing protocols, users, ports, credentials, and routing settings
- `/var/lib/sing-box-script/share-links.txt`
  Share links
- `/var/lib/sing-box-script/client-config.json`
  `sing-box` client `outbounds` snippet
- `/var/lib/sing-box-script/client-full.json`
  Full `sing-box` client template with `selector/urltest` and default `CN -> direct` rules
- `/var/lib/sing-box-script/client-tun.json`
  `TUN` client template with `selector/urltest` and default `CN -> direct` rules
- `/var/lib/sing-box-script/deployment-summary.txt`
  Human-readable deployment summary
- `/var/lib/sing-box-script/acme-issue.log`
  ACME or OpenSSL certificate generation log

## Certificate Modes

The script now supports two certificate modes for TLS-enabled protocols:

- `acme`
  Uses `acme.sh` to request a public certificate
- `self-signed`
  Uses `openssl` to generate a self-signed certificate

Notes:

- `acme` requires a valid domain and email
- `self-signed` does not require ACME and can fall back to the share host or detected public IPv4 as the certificate identity
- In `self-signed` mode, exported `sing-box` client templates automatically set `tls.insecure = true` for TLS-based outbounds

## Certificate Requirements by Protocol

The following cases require `--domain` and `--email`:

- `VMess` with `--cert-mode acme`
- `Trojan` with `--cert-mode acme`
- `Hysteria2` with `--cert-mode acme`
- `TUIC` with `--cert-mode acme`
- `NaiveProxy` with `--cert-mode acme`
- `VLESS` with `--vless-mode tls --cert-mode acme`

The following cases do not require certificates:

- `VLESS` with default `reality`
- `SOCKS5`
- `SS2022`

## Notes

- The repository `config.json` is only an example and is not deployed directly
- Re-running the script reuses existing UUIDs, passwords, Reality keys, user lists, and ports by default
- Use `--rotate-secrets` if you want to regenerate them
- `NaiveProxy` share URIs can vary across clients; the script exports both a `sing-box` snippet and fuller client templates
- The current routing menu intentionally focuses on the most stable baseline: `BT/PT blocking`, `block-cn`, and `ads blocking`
- For self-signed certificates, prefer using the exported `sing-box` client templates instead of relying only on share URIs

## License

This project is licensed under the [MIT License](./LICENSE).
