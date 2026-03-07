# Odio APT Repository

Automated APT repository for the Odio ecosystem, served via GitHub Pages.

## Packages

| Package | Source |
|---------|--------|
| `go-odio-api` | [b0bbywan/go-odio-api](https://github.com/b0bbywan/go-odio-api) |
| `go-mpd-discplayer` | [b0bbywan/go-mpd-discplayer](https://github.com/b0bbywan/go-mpd-discplayer) |

## User Install

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
