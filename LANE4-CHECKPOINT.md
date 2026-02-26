# Lane 4: Provisioning & Deployment — Checkpoint

Last updated: 2026-02-26

## Current State: VPS RUNNING, DEPLOY NOT YET RUN

NixOS is installed and booting on Hetzner Cloud. The VPS is SSH-accessible.
deploy-rs has NOT been run yet. Secrets have NOT been created on the VPS.

## VPS Details

| Field | Value |
|-------|-------|
| IP | 46.225.140.108 |
| Server name | open-builder |
| Server type | cpx32 (4 vCPU, 8 GB RAM, 160 GB disk) |
| Location | nbg1 (Nuremberg) |
| Hetzner server ID | 122162555 |
| SSH key | `keys/deploy` (ED25519) |
| SSH access | `ssh -i keys/deploy root@46.225.140.108` |
| Interface | enp1s0 (DHCP, systemd-networkd) |
| Kernel | 6.18.13 |

## Files Changed (uncommitted)

| File | Change |
|------|--------|
| `flake.nix` | `hostname` changed from `open-builder.example.com` to `46.225.140.108` |
| `flake.lock` | disko + nixos-anywhere inputs added |
| `configuration.nix` | domain → `tinker.builders`, added `networking.useNetworkd`, added `systemd.network.networks."10-wan"` (DHCP), switched from systemd-boot to GRUB, added `boot.initrd.availableKernelModules` for virtio |
| `disko-config.nix` | Added 1M BIOS boot partition (EF02) before ESP, for GRUB compatibility |
| `scripts/provision.sh` | Server type changed from `cx22` to `cx32` (was `cx32` — note: actual Hetzner type used was `cpx32`) |

## What Worked

1. **Flake lock update** — `nix flake lock --update-input disko --update-input nixos-anywhere` succeeded
2. **Hetzner API** — token works (had to use `export` — `source` without export doesn't propagate to child processes). The token has Read & Write permissions despite initial "permission denied" from hcloud CLI (worked via curl; hcloud CLI bug with ssh-key create, but server create worked)
3. **nixos-anywhere** — installs successfully every time. Key: use `-i keys/deploy` flag (not `--ssh-option "-i keys/deploy"`) and always `cd` to the project directory first
4. **GRUB boot** — GRUB with BIOS boot partition + EFI removable install boots reliably on Hetzner Cloud
5. **systemd-networkd** — DHCP works with `Name = "eth* en*"` match (actual interface is `enp1s0`)
6. **virtio initrd modules** — `virtio_pci virtio_blk virtio_scsi virtio_net ahci` required for initrd to see the disk

## What Failed and Why

### 1. systemd-boot never booted (UEFI NVRAM issue)
Hetzner Cloud UEFI firmware (OVMF) resets NVRAM on every power cycle. The boot order always reverts to PXE first. `efibootmgr -o` changes don't persist across `hcloud server reset` or `poweroff/poweron`. systemd-boot installs a UEFI boot entry that gets wiped.

**Fix:** Switch to GRUB with `efiInstallAsRemovable = true` (installs to `EFI/BOOT/BOOTX64.EFI` fallback path) plus BIOS boot partition (`EF02`) for MBR boot. GRUB gets found via both BIOS MBR fallback and EFI removable media path.

### 2. initrd couldn't find root partition (missing virtio modules)
NixOS Stage 1 loaded but hung at "waiting for device /dev/disk/by-partlabel/disk-main-root to appear". The default initrd doesn't include virtio drivers needed by Hetzner Cloud's KVM/QEMU.

**Fix:** Added `boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_scsi" "virtio_net" "ahci" ]`

### 3. No networking on first attempts
Original configuration.nix had no explicit DHCP config. NixOS defaulted to dhcpcd (scripted networking) which didn't work. Even after adding `networking.useNetworkd = true`, the first fix used `Name = "en*"` which wouldn't match `eth0` (rescue mode interface name). Actual NixOS interface name turned out to be `enp1s0`.

**Fix:** `matchConfig.Name = "eth* en*"` covers all possible interface names.

### 4. nixos-anywhere ran from wrong directory
Second nixos-anywhere invocation ran from `/Users/claude/agicash-mints` (shell cwd resets after each command) instead of the open-builder project. Built the cached old closure without networking fixes.

**Fix:** Always `cd /Users/claude/.superset/projects/open-builder &&` before nixos-anywhere.

### 5. hcloud CLI permission denied on write operations
`hcloud ssh-key create` failed with "permission denied" even though the token has R/W permissions. `hcloud server list` and `hcloud ssh-key list` worked. Direct curl API calls worked for the same write operation.

**Workaround:** Used curl for SSH key creation; hcloud worked for server create.

### 6. Hetzner server type naming
`cx22`/`cx32` types don't exist anymore. Current naming: `cpx32` (shared x86, 4 vCPU, 8 GB). `provision.sh` still says `cx32` but the actual server was created manually with `cpx32`.

## Remaining Steps

### 1. Create secrets on VPS
```bash
ssh -i keys/deploy root@46.225.140.108 "mkdir -p /run/secrets && cat > /run/secrets/openclaw.env << 'EOF'
OPENAI_API_KEY=<ppq.ai-api-key>
DISCORD_BOT_TOKEN=<discord-bot-token>
EOF
chmod 600 /run/secrets/openclaw.env"
```
If secrets aren't ready, use `placeholder` values — the service will start but won't connect.

### 2. Deploy via deploy-rs
```bash
cd ~/.superset/projects/open-builder
nix shell github:serokell/deploy-rs -c deploy .#open-builder
```
Or use the script:
```bash
bash scripts/deploy.sh 46.225.140.108
```
Note: `deploy.sh` uses `ssh "root@${HOST}"` without `-i keys/deploy`. Either fix the script or ensure the key is in the SSH agent.

### 3. Verify
```bash
ssh -i keys/deploy root@46.225.140.108 "systemctl status openclaw-gateway"
ssh -i keys/deploy root@46.225.140.108 "bash /home/openclaw/scripts/check-balance.sh"
```

### 4. Update provision.sh
The script has issues:
- `SERVER_TYPE="cx32"` should be `"cpx32"` (Hetzner renamed types)
- `--ssh-option "-i keys/deploy"` should be `-i keys/deploy` (nixos-anywhere flag)
- `source infra/hetzner.env` doesn't export — need `export $(cat infra/hetzner.env | xargs)`

### 5. Commit
```bash
cd ~/.superset/projects/open-builder
git add flake.nix flake.lock configuration.nix disko-config.nix scripts/provision.sh
git -c commit.gpgsign=false commit -m "infra: wire in production VPS — GRUB boot, virtio modules, networkd"
```

### 6. DNS (optional)
Point `tinker.builders` A record to `46.225.140.108` for the openclaw domain to work with HTTPS.

## Hetzner Cloud NixOS Lessons Learned

1. **Always use GRUB, never systemd-boot** — UEFI NVRAM resets on power cycle
2. **Always add virtio initrd modules** — KVM/QEMU needs them for disk access
3. **Use systemd-networkd** (not dhcpcd) — match `eth* en*` to cover all interface names
4. **Add BIOS boot partition (EF02)** to GPT alongside ESP — GRUB needs it for MBR install
5. **Run nixos-anywhere against live Ubuntu** (not rescue) for first install — reboot goes to disk
6. **After nixos-anywhere:** disable rescue → poweroff → poweron → wait 120s
7. **nixos-anywhere CLI:** use `-i keys/deploy` not `--ssh-option "-i keys/deploy"`
8. **hcloud token:** must `export` it, `source` alone doesn't propagate to child processes
