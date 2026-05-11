#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
#
# Build the Odio APT repository: resolve versions, download .deb artifacts
# from GitHub Releases, and assemble a signed reprepro layout.
#
# Subcommands:
#   configure   write conf/distributions and conf/options
#   resolve     print <NAME>_STABLE / <NAME>_TESTING = <tag> on stdout
#   download    fetch .deb artifacts into <debs-dir>/{stable,testing}
#   build       run reprepro includedeb and assemble Pages output
#
# Run `build-apt-repo.sh <subcommand> --help` for per-subcommand options.

set -euo pipefail

PACKAGES=(
  "go-odio-api:ODIO"
  "go-mpd-discplayer:DISCPLAYER"
  "spotifyd:SPOTIFYD"
  "odio-mympd:MYMPD"
  "mpDris2:MPDRIS2"
  "snapclientmpris:SNAPCLIENTMPRIS"
)

GH_OWNER="${GH_OWNER:-b0bbywan}"
ARCHITECTURES_DEFAULT="amd64 arm64 armhf armv7hf"
CNAME_DEFAULT="apt.odio.love"

die() { echo "error: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: build-apt-repo.sh <subcommand> [options]

Subcommands:
  configure   Write conf/distributions and conf/options (needs --gpg-key-id)
  resolve     Resolve stable/testing tag for each package and print
              <NAME>_STABLE / <NAME>_TESTING = <tag> on stdout
  download    Download .deb artifacts using <NAME>_STABLE / <NAME>_TESTING env
  build       reprepro includedeb + write key.gpg, CNAME, index.html

Environment:
  GH_OWNER    GitHub owner of source repos (default: b0bbywan)
  GH_TOKEN    Required by gh for resolve/download

Run 'build-apt-repo.sh <subcommand> --help' for details.
EOF
}

# ---------- helpers ----------

# Get the first matching release tag from a repo.
#   $1: repo name (under GH_OWNER)
#   $2: prerelease filter, "true" or "false"
get_latest() {
  local repo="$1" filter="$2"
  gh release list --repo "${GH_OWNER}/${repo}" --limit 20 --json tagName,isPrerelease \
    | jq -r "[.[] | select(.isPrerelease == ${filter})] | first // empty | .tagName"
}

is_prerelease_tag() {
  [[ "$1" =~ -(rc|beta|alpha) ]]
}

# Map a long flag like --discplayer-version to the NAME used in PACKAGES.
# Echoes the NAME (e.g. DISCPLAYER) on stdout, or returns 1 if unknown.
flag_to_name() {
  case "$1" in
    --odio-version)          echo ODIO ;;
    --discplayer-version)    echo DISCPLAYER ;;
    --spotifyd-version)      echo SPOTIFYD ;;
    --mympd-version)         echo MYMPD ;;
    --mpdris2-version)       echo MPDRIS2 ;;
    --snapclientmpris-version) echo SNAPCLIENTMPRIS ;;
    *) return 1 ;;
  esac
}

# ---------- configure ----------

cmd_configure_help() {
  cat <<EOF
Usage: build-apt-repo.sh configure --gpg-key-id <ID> [--basedir <PATH>]

Writes ./conf/distributions and ./conf/options for reprepro.

Options:
  --gpg-key-id ID   GPG key id used to sign Release files (required)
  --basedir PATH    Value of reprepro 'basedir' option (default: \$PWD/repo)
  --architectures S Space-separated arch list (default: "${ARCHITECTURES_DEFAULT}")
EOF
}

cmd_configure() {
  local gpg_key_id="" basedir="" architectures="${ARCHITECTURES_DEFAULT}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --gpg-key-id)     gpg_key_id="$2"; shift 2 ;;
      --basedir)        basedir="$2"; shift 2 ;;
      --architectures)  architectures="$2"; shift 2 ;;
      -h|--help)        cmd_configure_help; return 0 ;;
      *) die "configure: unknown option: $1" ;;
    esac
  done
  [ -n "${gpg_key_id}" ] || die "configure: --gpg-key-id is required"
  [ -n "${basedir}" ]   || basedir="${PWD}/repo"

  mkdir -p conf
  cat > conf/distributions <<EOF
Origin: ${GH_OWNER}
Label: Odio APT Repository
Codename: stable
Architectures: ${architectures}
Components: main
Description: Odio stable releases
SignWith: ${gpg_key_id}

Origin: ${GH_OWNER}
Label: Odio APT Repository
Codename: testing
Architectures: ${architectures}
Components: main
Description: Odio release candidates and pre-releases
SignWith: ${gpg_key_id}
EOF

  cat > conf/options <<EOF
verbose
basedir ${basedir}
EOF

  echo "wrote conf/distributions and conf/options (basedir=${basedir})"
}

# ---------- resolve ----------

cmd_resolve_help() {
  cat <<EOF
Usage: build-apt-repo.sh resolve [--<package>-version <TAG>]...

For each package, query GitHub Releases to find the latest stable and the
latest prerelease tag. If a manual override is supplied and the tag looks
like a prerelease (-rc/-beta/-alpha), it is routed to testing and stable is
left as the latest non-prerelease.

Prints two lines per package on stdout:
  <NAME>_STABLE=<tag>
  <NAME>_TESTING=<tag>

Suitable for: build-apt-repo.sh resolve ... | tee -a "\$GITHUB_ENV"

Override options (any subset):
  --odio-version TAG
  --discplayer-version TAG
  --spotifyd-version TAG
  --mympd-version TAG
  --mpdris2-version TAG
  --snapclientmpris-version TAG
EOF
}

cmd_resolve() {
  declare -A MANUAL=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) cmd_resolve_help; return 0 ;;
      --*-version)
        local name
        name="$(flag_to_name "$1")" || die "resolve: unknown option: $1"
        [ $# -ge 2 ] || die "resolve: $1 requires a value"
        MANUAL["${name}"]="$2"
        shift 2
        ;;
      *) die "resolve: unknown option: $1" ;;
    esac
  done

  command -v gh >/dev/null || die "resolve: gh CLI not found in PATH"
  command -v jq >/dev/null || die "resolve: jq not found in PATH"

  local entry repo name manual stable testing
  for entry in "${PACKAGES[@]}"; do
    repo="${entry%%:*}"
    name="${entry##*:}"
    manual="${MANUAL[${name}]:-}"

    if [ -n "${manual}" ] && ! is_prerelease_tag "${manual}"; then
      stable="${manual}"
    else
      stable="$(get_latest "${repo}" false)"
    fi

    if [ -n "${manual}" ] && is_prerelease_tag "${manual}"; then
      testing="${manual}"
    else
      testing="$(get_latest "${repo}" true)"
    fi

    echo "${name}_STABLE=${stable}"
    echo "${name}_TESTING=${testing}"
  done
}

# ---------- download ----------

cmd_download_help() {
  cat <<EOF
Usage: build-apt-repo.sh download [--debs-dir <PATH>]

Reads <NAME>_STABLE / <NAME>_TESTING from the environment (set by 'resolve')
and downloads each *.deb asset into <debs-dir>/stable or <debs-dir>/testing.
Missing/empty versions are skipped with a warning.

Options:
  --debs-dir PATH   Output directory (default: ./debs)
EOF
}

cmd_download() {
  local debs_dir="./debs"
  while [ $# -gt 0 ]; do
    case "$1" in
      --debs-dir) debs_dir="$2"; shift 2 ;;
      -h|--help)  cmd_download_help; return 0 ;;
      *) die "download: unknown option: $1" ;;
    esac
  done

  command -v gh >/dev/null || die "download: gh CLI not found in PATH"

  mkdir -p "${debs_dir}/stable" "${debs_dir}/testing"

  local entry repo name target version_var version
  for entry in "${PACKAGES[@]}"; do
    repo="${entry%%:*}"
    name="${entry##*:}"
    for target in stable testing; do
      version_var="${name}_$(echo "${target}" | tr '[:lower:]' '[:upper:]')"
      version="${!version_var:-}"
      if [ -z "${version}" ]; then
        echo "skipping ${repo} (${target}): no version"
        continue
      fi
      echo "downloading ${repo} ${version} -> ${target}"
      gh release download "${version}" \
        --repo "${GH_OWNER}/${repo}" \
        --pattern "*.deb" \
        --dir "${debs_dir}/${target}/" \
        --clobber
    done
  done

  echo "stable packages:"
  ls -lh "${debs_dir}/stable/" 2>/dev/null || echo "  (none)"
  echo "testing packages:"
  ls -lh "${debs_dir}/testing/" 2>/dev/null || echo "  (none)"
}

# ---------- build ----------

cmd_build_help() {
  cat <<EOF
Usage: build-apt-repo.sh build --gpg-key-id <ID> [options]

Runs 'reprepro includedeb' for every .deb under <debs-dir>/{stable,testing},
then exports the public GPG key and writes CNAME + index.html under <repo-dir>.

Options:
  --gpg-key-id ID   GPG key id whose public key is exported as key.gpg (required)
  --debs-dir PATH   Input .deb directory (default: ./debs)
  --repo-dir PATH   Output repo directory (default: ./repo)
  --cname DOMAIN    Value written to <repo-dir>/CNAME (default: ${CNAME_DEFAULT}; empty = skip)
EOF
}

cmd_build() {
  local gpg_key_id="" debs_dir="./debs" repo_dir="./repo" cname="${CNAME_DEFAULT}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --gpg-key-id) gpg_key_id="$2"; shift 2 ;;
      --debs-dir)   debs_dir="$2"; shift 2 ;;
      --repo-dir)   repo_dir="$2"; shift 2 ;;
      --cname)      cname="$2"; shift 2 ;;
      -h|--help)    cmd_build_help; return 0 ;;
      *) die "build: unknown option: $1" ;;
    esac
  done
  [ -n "${gpg_key_id}" ] || die "build: --gpg-key-id is required"
  [ -d conf ] || die "build: ./conf not found (run 'configure' first)"

  command -v reprepro >/dev/null || die "build: reprepro not found in PATH"
  command -v gpg >/dev/null      || die "build: gpg not found in PATH"

  mkdir -p "${repo_dir}"
  cp -r conf "${repo_dir}/"

  local target deb
  for target in stable testing; do
    for deb in "${debs_dir}/${target}"/*.deb; do
      [ -f "${deb}" ] || continue
      echo "adding $(basename "${deb}") -> ${target}"
      reprepro -b "${repo_dir}" includedeb "${target}" "${deb}"
    done
  done

  gpg --armor --export "${gpg_key_id}" > "${repo_dir}/key.gpg"

  if [ -n "${cname}" ]; then
    echo "${cname}" > "${repo_dir}/CNAME"
  fi

  local host="${cname:-apt.example.invalid}"
  cat > "${repo_dir}/index.html" <<HTML
<!DOCTYPE html>
<html><head><title>Odio APT Repository</title></head>
<body>
<h1>Odio APT Repository</h1>
<h2>Stable</h2>
<pre><code>curl -fsSL https://${host}/key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/odio.gpg
echo "deb [signed-by=/usr/share/keyrings/odio.gpg] https://${host} stable main" | sudo tee /etc/apt/sources.list.d/odio.list
sudo apt update
sudo apt install go-odio-api go-mpd-discplayer</code></pre>
<h2>Testing (release candidates)</h2>
<pre><code>echo "deb [signed-by=/usr/share/keyrings/odio.gpg] https://${host} testing main" | sudo tee /etc/apt/sources.list.d/odio-testing.list</code></pre>
</body></html>
HTML
}

# ---------- dispatch ----------

case "${1:-}" in
  configure|resolve|download|build)
    cmd="$1"; shift
    "cmd_${cmd}" "$@"
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    echo "unknown subcommand: $1" >&2
    usage
    exit 2
    ;;
esac
