# wechat_docker

Run WeChat on a Mac in a sandbox it can't see out of, and open it from your
browser. Two clicks to start, two to stop, nothing running in the background.

WeChat is closed-source software that most people install with full access to
their home directory, contacts, camera and microphone. This repo runs it in a
container inside a Linux VM instead, with no path to your files, no capability
to inspect other processes, and a firewall that stops it reaching anything else
on your network.

**Stack:** macOS → Colima VM → hardened container → WeChat 4.1.1
(native `arm64`, so no emulation on Apple Silicon; `amd64` works too.)

---

## Requirements

- macOS on Apple Silicon or Intel
- [Homebrew](https://brew.sh)
- ~10 GB of free disk

## Install

```sh
brew install colima docker docker-compose
mkdir -p ~/.docker/cli-plugins
ln -sfn "$(brew --prefix)/opt/docker-compose/bin/docker-compose" \
        ~/.docker/cli-plugins/docker-compose

git clone https://github.com/chaoyupeng/wechat_docker.git ~/GitHub/wechat_docker
cd ~/GitHub/wechat_docker
cp .env.example .env         # optional; edit your timezone
./build-apps.sh --install    # puts the two apps in /Applications
```

> **Don't clone into `~/Desktop`, `~/Documents` or `~/Downloads`.** macOS TCC
> protects those folders, and an app launched from Finder can't read files
> inside them. The launcher will `cd` in fine and then fail with
> `./wechat: Operation not permitted` — while the same script run from a
> terminal works, which makes this genuinely confusing to diagnose. Anywhere
> else in your home directory is fine. If you must keep it in a protected
> folder, add both apps to **System Settings → Privacy & Security → Full Disk
> Access** instead.

Omit `--install` to build the apps into the repo folder instead. Either way,
re-run `build-apps.sh` if you move the repo — each app bakes in the path it was
built against.

If `docker` isn't found after installing, Homebrew probably couldn't link it
because the deprecated `docker-completion` formula owns the same files:

```sh
brew unlink docker-completion && brew link docker
```

## Use it

Double-click **Start WeChat.app**. It boots the VM if needed, starts the
container, applies the firewall, waits for the UI, and opens your browser.
Log in by scanning the QR code with WeChat on your phone.

Double-click **Stop WeChat.app** when you're done. It stops the container and
shuts the VM down too — unless you have other containers running in it, in
which case it leaves the VM alone and tells you.

Drag both apps to your Dock or `/Applications`; they keep working.

Nothing starts at login, and nothing survives a reboot. WeChat runs only when
you ask it to.

There's a CLI if you prefer:

```sh
./wechat start | stop | status | reset
```

`status` shows what's running, memory use, and whether the firewall is active.
`reset` destroys the volume and starts clean (it asks first).

Cold start is about 40 seconds, most of it VM boot. Warm start is ~7 seconds.

### About the "connection is not private" warning

Use **http://localhost:3000** and you won't see one. Browsers treat
`http://localhost` as a secure context, so the page still gets the clipboard
and microphone APIs it needs, and there's no certificate to complain about.
This is safe *because* the port is loopback-only — the traffic never touches a
network.

Port 3001 serves the same UI over HTTPS with a self-signed certificate. It's
encrypted, but no certificate authority will vouch for `localhost`, so your
browser can't tell it apart from an interception attempt and shows the scary
page. Both ports work; 3000 is just quieter.

---

## What's actually isolated

Verified against a live container (Colima 0.10.3, Docker 29.2.1, WeChat 4.1.1
`arm64`). These aren't design intentions — each was tested:

| Boundary | How | Evidence |
| --- | --- | --- |
| Your files | Named volume only. No bind mount exists anywhere. | `mount` inside the container shows only the VM's own virtual disk. No host path. |
| Your memory | Container namespaces, then the VM. A Linux container can't address host RAM; the VM makes it moot regardless. | Structural. |
| Other processes | `ipc: private`, and `CAP_SYS_PTRACE` isn't held. | `CapEff: 00000000000000cb` — only `chown`, `dac_override`, `fowner`, `setgid`, `setuid`. |
| Runaway resource use | 4 GB RAM with swap off, 4 CPUs, 512 PIDs. | `Memory=4294967296 MemorySwap=4294967296 PidsLimit=512`. Idles ~250 MB. |
| Root escalation | `cap_drop: ALL` + `no-new-privileges`. | `sudo -n id` → *"the 'no new privileges' flag is set"*. The base image ships a passwordless-sudo terminal; this kills it. |
| Your Mac and LAN | `harden-network.sh` drops egress to RFC1918 / link-local / CGNAT. | `curl` from the container to the host's LAN address times out (exit 28). |
| Other containers | Same rules; only WeChat's own `/24` is exempt. | `curl` to an unrelated container on `172.17.0.2` times out (exit 28). |
| Camera, USB | Never passed in; no `/dev` access. | Structural. |
| Network exposure | Ports bound to `127.0.0.1`. | `localhost:3000` → 200; the same port on the LAN address → refused. |

The public internet still works, which WeChat needs to function. Docker's
embedded DNS is unaffected by the egress rules because it forwards upstream
from the VM rather than from the container's subnet.

## What's *not* isolated

Read this part. The container is well sealed; the remaining gaps are elsewhere.

- **Tencent.** WeChat needs the internet, so the telemetry it normally sends
  still goes out. This sandboxes WeChat from *your machine*. It does nothing
  about what WeChat reports to its own servers, and nothing here should be
  read as a claim otherwise.
- **The browser tab is a bridge.** By default the remote-desktop layer runs
  with clipboard sync in both directions, file upload/download, and the
  ability to request *your browser's* microphone. The container has no audio
  hardware, but your browser can hand it a stream if you click allow. All of
  this rides the same loopback WebSocket, so no firewall rule touches it.
  Uncomment the `SELKIES_*` lines in `.env` to close whichever you don't want.
- **No password by default.** `SELKIES_MASTER_TOKEN` is unset, so anyone who
  can open `localhost:3000` on your machine gets your logged-in WeChat
  session. Set it in `.env` if that matters to you.
- **The VM's disk image** is an ordinary file under `~/.colima`, encrypted only
  insofar as FileVault encrypts your disk.
- **The base image is third-party.** It comes from
  [LinuxServer.io](https://docs.linuxserver.io/images/docker-weixin/), which is
  reputable and rebuilds weekly, but it's still someone else's build of
  Tencent's binary. Pin a digest instead of `:latest` if you'd rather review
  updates before taking them.

## Configuration

Everything lives in `.env` (see `.env.example`): timezone, subnet, memory and
CPU ceilings, and the optional lockdown toggles above. `docker-compose.yml` and
`harden-network.sh` both read `WECHAT_SUBNET`, so they can't drift apart.

## Moving files in and out

Deliberate, one file at a time — that's the point:

```sh
docker cp weixin:/config/Downloads/report.pdf ./     # out
docker cp ./photo.jpg weixin:/config/Desktop/        # in
```

Drag-and-drop through the web UI also works, unless you disabled it.

## How it works

```
macOS
└── Colima VM ── Ubuntu 24.04, Linux 6.8, Apple Virtualization.framework
    └── container ── caps dropped, memory capped, no bind mounts, egress filtered
        └── WeChat 4.1.1 on Wayland, streamed to your browser
```

On macOS every container runtime is a Linux VM behind the scenes — Docker
Desktop and OrbStack included. Using Colima just makes that VM visible and
scriptable. The VM is what isolates WeChat from macOS; the container is what
isolates it from the VM and makes the whole thing reproducible from this repo.

| File | Purpose |
| --- | --- |
| `docker-compose.yml` | The container and all its restrictions |
| `wechat` | start / stop / status / reset |
| `harden-network.sh` | Egress firewall, applied inside the VM |
| `build-apps.sh` | Generates the two double-clickable apps |
| `icons/mkicon.py` | Generates the app icons |

## Troubleshooting

**WeChat can suddenly reach my LAN again.** The iptables rules live in the VM
and are wiped by `colima stop`. `./wechat start` reapplies them every time;
if you started things by hand, run `./harden-network.sh apply`. Check with
`./harden-network.sh status`.

**Container crash-loops after an image update.** Suspect the capability drop
first. Comment out `cap_drop`/`cap_add` in `docker-compose.yml`, confirm it
starts, then reintroduce them one at a time. `docker compose logs weixin` names
the failing service.

**Black or frozen screen.** Raise `shm_size` to `2gb`.

**Apps do nothing when clicked.** They log to `/tmp/wechat-sandbox.log`. Two
common causes: you moved the repo after building them (re-run
`./build-apps.sh --install`), or the repo is in a TCC-protected folder and the
log shows `Operation not permitted` — see the note under [Install](#install).

## Not on macOS?

The container and firewall are portable; the wrapper isn't. `wechat` and
`build-apps.sh` assume `colima` and `open`. On Linux, skip both and use
`docker compose up -d` directly with your own `DOCKER-USER` rules — you don't
need a VM there, but you also lose the VM boundary that does most of the work
in this design.

## License

MIT — see [LICENSE](LICENSE).

Not affiliated with Tencent or LinuxServer.io. WeChat is Tencent's software,
subject to their terms.
