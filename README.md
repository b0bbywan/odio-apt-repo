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
  Part of the <a href="https://odio.love">odio</a> project — <a href="https://docs.odio.love/api/installation/">full documentation</a>.
  </p>
  <p align="center">
  <a href="https://www.debian.org/"><img src="https://img.shields.io/badge/Debian-A81D33?logo=debian&logoColor=white" alt="Debian" /></a>
  <a href="https://pages.github.com/"><img src="https://img.shields.io/badge/GitHub%20Pages-181717?logo=githubpages&logoColor=white" alt="GitHub Pages" /></a>
  <a href="https://github.com/features/actions"><img src="https://img.shields.io/badge/GitHub%20Actions-2088FF?logo=githubactions&logoColor=white" alt="GitHub Actions" /></a>   
  </p>

# Odio APT Repository

Automated APT repository for the Odio ecosystem, served via GitHub Pages.

## Packages

| Package | Source |
|---------|--------|
| `go-odio-api` | [b0bbywan/go-odio-api](https://github.com/b0bbywan/go-odio-api) |
| `go-mpd-discplayer` | [b0bbywan/go-mpd-discplayer](https://github.com/b0bbywan/go-mpd-discplayer) |
| `spotifyd` | [b0bbywan/spotifyd](https://github.com/b0bbywan/spotifyd) |

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
sudo apt install go-odio-api go-mpd-discplayer
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

## How it works

1. `go-odio-api` or `go-mpd-discplayer` publishes a GitHub Release with `.deb` artifacts
2. Their CI triggers a `repository_dispatch` on this repo
3. This repo's CI downloads all `.deb` from both projects' latest releases
4. `reprepro` builds the APT repository metadata
5. GitHub Pages serves the result

No binaries stored in git. Source projects remain the single source of truth.

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
| `APT_REPO_TOKEN` | `go-odio-api` + `go-mpd-discplayer` | PAT with `repo` scope to trigger dispatch |

### 3. Enable GitHub Pages

In `apt-repo` → Settings → Pages → Source: **GitHub Actions**.

### 4. Add trigger to source projects

Add the job from `trigger-snippet.yml` to the release workflow of each source project.

## Manual rebuild

```
gh workflow run update-repo.yml
```

Or with specific versions:
```
gh workflow run update-repo.yml -f odio_version=v0.9.0 -f discplayer_version=v0.8.0
```
