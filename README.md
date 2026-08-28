<p align="center">
  <a href="https://odio.love"><img src="https://odio.love/logo.png" alt="odio" width="160" /></a>   
  </p>
  <h1 align="center">odio-apt-repo</h1>
  <p align="center"><em>Automated APT repository for the odio ecosystem.</em></p>
  <p align="center">
  <a href="https://github.com/b0bbywan/odio-apt-repo/actions/workflows/update-repo.yml"><img src="https://github.com/b0bbywan/odio-apt-repo/actions/workflows/update-repo.yml/badge.svg" alt="Update APT Repository"
   /></a>   
  <a href="https://github.com/sponsors/b0bbywan"><img src="https://img.shields.io/github/sponsors/b0bbywan?label=Sponsor&logo=GitHub" alt="GitHub Sponsors" /></a>
  </p>
  <p align="center">
  <a href="https://apt.odio.love"><img src="https://img.shields.io/badge/Live%20repo-5ab81e" alt="Live at apt.odio.love" /></a>
  <a href="https://docs.odio.love/api/installation/"><img src="https://img.shields.io/badge/Install%20guide-0082FC" alt="Install guide" /></a>   
  </p>
  <p align="center">   
  Part of the <a href="https://odio.love">odio</a> project — <a href="https://docs.odio.love/operations/apt-repository/">full documentation</a>.
  </p>
  <p align="center">
  <a href="https://www.debian.org/"><img src="https://img.shields.io/badge/Debian-A81D33?logo=debian&logoColor=white" alt="Debian" /></a>
  <a href="https://pages.github.com/"><img src="https://img.shields.io/badge/GitHub%20Pages-181717?logo=githubpages&logoColor=white" alt="GitHub Pages" /></a>
  <a href="https://github.com/features/actions"><img src="https://img.shields.io/badge/GitHub%20Actions-2088FF?logo=githubactions&logoColor=white" alt="GitHub Actions" /></a>
  <a href="https://www.gnu.org/software/bash/"><img src="https://img.shields.io/badge/GNU%20Bash-4EAA25?logo=gnubash&logoColor=white" alt="GNU Bash" /></a>   
  </p>

# Odio APT Repository

Automated APT repository for the Odio ecosystem, served via GitHub Pages.

## Packages

| Package | Source |
|---------|--------|
| `go-odio-api` | [b0bbywan/go-odio-api](https://github.com/b0bbywan/go-odio-api) |
| `go-mpd-discplayer` | [b0bbywan/go-mpd-discplayer](https://github.com/b0bbywan/go-mpd-discplayer) |
| `spotifyd` | [b0bbywan/spotifyd](https://github.com/b0bbywan/spotifyd) |
| `mympd` | [b0bbywan/odio-mympd](https://github.com/b0bbywan/odio-mympd) (build of upstream [jcorporation/myMPD](https://github.com/jcorporation/myMPD)) |
| `qbzd` | [b0bbywan/odio-qbz](https://github.com/b0bbywan/odio-qbz) (daemon-only build of upstream [vicrodh/qbz](https://github.com/vicrodh/qbz)) |
| `mpd2mpris` | [b0bbywan/mpd2mpris](https://github.com/b0bbywan/mpd2mpris) (formerly `mpDris2`) — tracks latest |
| `mpdris2` | [b0bbywan/mpd2mpris](https://github.com/b0bbywan/mpd2mpris) pinned at `v0.11.1` (last release shipping `mpdris2_*.deb`) so `apt install mpdris2` keeps working |

## User Install

### Stable releases

```bash
# Add GPG key
curl -fsSL https://apt.odio.love/key.gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/odio.gpg

# Add repository
echo "deb [signed-by=/usr/share/keyrings/odio.gpg] https://apt.odio.love stable main" \
  | sudo tee /etc/apt/sources.list.d/odio.list

# Install
sudo apt update
sudo apt install go-odio-api go-mpd-discplayer spotifyd mympd mpd2mpris
```

### Testing (release candidates)

```bash
# Add testing repo (after adding the GPG key above)
echo "deb [signed-by=/usr/share/keyrings/odio.gpg] https://apt.odio.love testing main" \
  | sudo tee /etc/apt/sources.list.d/odio-testing.list

sudo apt update
sudo apt install go-odio-api
```

Tags containing `-rc`, `-beta`, or `-alpha` go to `testing`. Everything else goes to `stable`.

> **Rename note:** `mpDris2` was renamed to `mpd2mpris`. New installs should use
> `mpd2mpris`; the `mpdris2` package stays in the repo (pinned at `v0.11.1`, the
> last release shipping `mpdris2_*.deb`) so existing `apt install mpdris2` setups
> keep resolving. The two carry different package names, so both coexist.

## How it works

1. A source project (`go-odio-api`, `go-mpd-discplayer`, `spotifyd`, `odio-mympd`, `odio-qbz`, or `mpd2mpris`) publishes a GitHub Release with `.deb` artifacts
2. Its CI triggers a `repository_dispatch` on this repo
3. This repo's CI downloads the `.deb` from each source project's latest stable and prerelease tags, skipping any release already fetched in a previous run (a cached `debs/` keyed on the resolved versions)
4. `reprepro` builds the APT repository metadata for both `stable` and `testing` suites
5. GitHub Pages serves the result

A scheduled rebuild (Monday and Thursday 04:00 UTC) catches any missed releases and keeps the `.deb` cache warm (GitHub evicts caches after 7 days without access). Thanks to the cache, a rebuild with no new releases re-downloads nothing — keeping source projects' GitHub download counters honest. No binaries stored in git — source projects remain the single source of truth.

## Setup (one-time)

### 1. GPG signing key

```bash
# Generate a key (no passphrase for CI)
gpg --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: Odio APT Repository
Name-Email: apt@odio.love
Expire-Date: 2y
%commit
EOF

# Export private key → GitHub secret GPG_PRIVATE_KEY
gpg --armor --export-secret-keys "apt@odio.love"
```

### 2. GitHub secrets

| Secret | Where | Description |
|--------|-------|-------------|
| `GPG_PRIVATE_KEY` | `apt-repo` | GPG private key for signing |
| `APT_REPO_TOKEN` | `go-odio-api`, `go-mpd-discplayer`, `spotifyd`, `odio-mympd`, `odio-qbz`, `mpd2mpris` | PAT with `repo` scope to trigger dispatch |

### 3. Enable GitHub Pages

In `apt-repo` → Settings → Pages → Source: **GitHub Actions**.

### 4. Add trigger to source projects

Add the job from `trigger-snippet.yml` to the release workflow of each source project.

## Manual rebuild

```
gh workflow run update-repo.yml
```

Or with specific versions (any subset of inputs):
```
gh workflow run update-repo.yml \
  -f odio_version=v0.9.0 \
  -f discplayer_version=v0.8.0 \
  -f spotifyd_version=v0.3.5 \
  -f mympd_version=v25.0.1 \
  -f qbzd_version=v2.0.2 \
  -f mpd2mpris_version=v0.12.0
```

If a manually supplied version contains `-rc`, `-beta`, or `-alpha`, it is routed to `testing` and the latest stable for that package is kept in `stable`.

## Build script

The repository-build logic lives in `scripts/build-apt-repo.sh` (called by the workflow):

```
./scripts/build-apt-repo.sh configure --gpg-key-id "$GPG_KEY_ID"
./scripts/build-apt-repo.sh resolve [--odio-version vX.Y.Z ...] >> "$GITHUB_ENV"
./scripts/build-apt-repo.sh download
./scripts/build-apt-repo.sh build --gpg-key-id "$GPG_KEY_ID"
```

Run `./scripts/build-apt-repo.sh --help` for full subcommand documentation.

## License

BSD 2-Clause — see [LICENSE](LICENSE).
