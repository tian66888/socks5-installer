# SOCKS5 Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and document a pasteable Bash installer for a configurable Dante SOCKS5 proxy.

**Architecture:** A single root-only Bash script detects package manager/systemd/firewall, installs Dante, renders configuration, enables the service, and validates listening state. README documents use and risks.

**Tech Stack:** Bash, Dante, systemd, nftables/iptables/firewalld/ufw.

## Global Constraints

- Linux with systemd is required.
- Bind mode `1` uses IP/CIDR allowlist; bind mode `2` requires explicit `YES` confirmation.
- Default port is `1080`; valid range is `1–65535`.
- Empty username means no authentication; non-empty username enables credentials.
- Credentials must not be committed.

### Task 1: Implement installer

**Files:** Create `install-socks5.sh`.

- [ ] Add strict shell mode, root/systemd checks, distro/package-manager detection, and dependency installation.
- [ ] Add validated prompts for bind mode, allowlist, port, username, and hidden password.
- [ ] Render Dante config with generated internal/external interface detection, client rules, auth mode, and safe file permissions.
- [ ] Configure firewall using detected firewalld/ufw/nftables/iptables tool, reload service, and verify port with `ss`.
- [ ] Print public IP, SOCKS5 URI, curl test command, and management commands without writing secrets to disk outside Dante's password database.

### Task 2: Document operation

**Files:** Create `README.md`.

- [ ] Explain one-line download/execute usage, prompts, supported distributions, output format, credential handling, and cleanup.
- [ ] Include explicit warning that mode 2/no-auth creates an open proxy and should not be used on an exposed server.

### Task 3: Validate locally

- [ ] Run `bash -n install-socks5.sh`.
- [ ] Run shellcheck if available and inspect generated script for accidental credential logging.
- [ ] Verify Git status and prepare GitHub push instructions; only push when a configured remote and credentials are available.
