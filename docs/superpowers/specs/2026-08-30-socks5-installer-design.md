# SOCKS5 Installer Design

## Goal

Provide a single pasteable Bash script that detects a supported Linux environment, installs and configures a SOCKS5 service, supports IP allowlisting or all-interface binding, optionally enables username/password authentication, configures the host firewall, and prints a usable proxy address.

## Architecture

The installer uses Dante where available through the OS package manager. It writes a dedicated `/etc/danted.conf`, a systemd override/service configuration, and firewall rules. Interactive input selects bind scope, port, and optional credentials. The script is idempotent: rerunning it replaces only its own configuration and firewall rule.

## Safety and scope

- Require root and Linux with systemd.
- Bind mode `1` accepts one or more IPv4/CIDR values and restricts clients through Dante rules plus firewall rules where supported.
- Bind mode `2` listens on all interfaces and requires typing `YES` as an explicit confirmation.
- Port is prompted with default `1080`; validate 1–65535.
- Empty username means no authentication. Non-empty username prompts for a hidden password.
- Never store credentials in the repository or command history; print the authenticated URI only at the end.
- Detect public IPv4 for output, but clearly label it as best-effort.

## Deliverables

- `install-socks5.sh`: installer and configurator.
- `README.md`: usage, security warning, supported systems, and GitHub/paste instructions.
- `docs/superpowers/plans/2026-08-30-socks5-installer.md`: implementation plan.
