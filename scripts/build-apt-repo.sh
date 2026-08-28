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

# Each entry is "repo:NAME[:TAG[:PATTERN]]":
#   TAG      pin NAME to a fixed tag in both suites (no resolve); empty = latest.
#   PATTERN  glob of .deb assets to download (default "*.deb"). Set this when a
#            repo ships several packages and an entry must take only its own.
#
# mpDris2 was renamed to mpd2mpris. Both packages come from the same repo:
#   - mpd2mpris tracks the latest release but only pulls mpd2mpris_*.deb, so it
#     downloads nothing until the renamed package is first published (no
#     fallback to the old mpdris2_*.deb that current releases still ship).
#   - mpdris2 stays pinned at v0.11.1 (the last tag shipping mpdris2_*.deb) so
#     `apt install mpdris2` keeps working. Different package names => reprepro
#     serves both side by side.
PACKAGES=(
  "go-odio-api:ODIO"
  "odioctl:ODIOCTL"
  "go-mpd-discplayer:DISCPLAYER"
  "spotifyd:SPOTIFYD"
  "odio-mympd:MYMPD"
  "odio-qbz:QBZD"
  "mpd2mpris:MPD2MPRIS::mpd2mpris_*.deb"
  "mpd2mpris:MPDRIS2:v0.11.1:mpdris2_*.deb"
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

# Count a release's assets whose name matches a simple glob (one '*').
#   $1 repo (under GH_OWNER)   $2 tag   $3 glob (e.g. "mpd2mpris_*.deb")
count_assets() {
  local repo="$1" tag="$2" glob="$3" prefix suffix
  prefix="${glob%%\**}"
  suffix="${glob##*\*}"
  gh release view "${tag}" --repo "${GH_OWNER}/${repo}" --json assets \
    --jq "[.assets[].name | select(startswith(\"${prefix}\") and endswith(\"${suffix}\"))] | length"
}

# Map a long flag like --discplayer-version to the NAME used in PACKAGES.
# Echoes the NAME (e.g. DISCPLAYER) on stdout, or returns 1 if unknown.
flag_to_name() {
  case "$1" in
    --odio-version)          echo ODIO ;;
    --odioctl-version)       echo ODIOCTL ;;
    --discplayer-version)    echo DISCPLAYER ;;
    --spotifyd-version)      echo SPOTIFYD ;;
    --mympd-version)         echo MYMPD ;;
    --qbzd-version)          echo QBZD ;;
    --mpd2mpris-version)     echo MPD2MPRIS ;;
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
  --odioctl-version TAG
  --discplayer-version TAG
  --spotifyd-version TAG
  --mympd-version TAG
  --qbzd-version TAG
  --mpd2mpris-version TAG
  --snapclientmpris-version TAG

Packages pinned in PACKAGES (entries with a trailing :TAG) ignore overrides and
always resolve to their pinned tag in both stable and testing.
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

  local entry repo name pin pattern manual stable testing
  for entry in "${PACKAGES[@]}"; do
    IFS=: read -r repo name pin pattern <<< "${entry}"

    # Pinned package: frozen at TAG, served in both suites so it resolves
    # whichever one a machine has enabled.
    if [ -n "${pin}" ]; then
      echo "${name}_STABLE=${pin}"
      echo "${name}_TESTING=${pin}"
      continue
    fi

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
and downloads each *.deb asset into <debs-dir>/<target>/<name>/.

Each dir keeps a .tag file with the last downloaded version; a match skips the
download (cache-friendly), an empty version clears stale artifacts. Dirs are
keyed by NAME so two packages from the same repo (e.g. a renamed package and
its pinned predecessor) download independently.

Only assets matching each entry's PATTERN (default "*.deb", see PACKAGES) are
fetched; an entry whose pattern matches nothing in its release downloads
nothing (and caches the tag), instead of falling back to other assets.

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

  # Prune stale package dirs: a restored cache may hold dirs from an older
  # layout (e.g. keyed by repo) or from a renamed/removed package. Left alone
  # they get re-included by 'build', so drop anything not in PACKAGES now.
  local -A valid_dirs=()
  local pe pname
  for pe in "${PACKAGES[@]}"; do
    IFS=: read -r _ pname _ _ <<< "${pe}"
    valid_dirs["${pname,,}"]=1
  done
  local d bn t0
  for t0 in stable testing; do
    for d in "${debs_dir}/${t0}"/*/; do
      [ -d "${d}" ] || continue
      bn="$(basename "${d}")"
      if [ -z "${valid_dirs[${bn}]:-}" ]; then
        echo "pruning stale dir ${d}"
        rm -rf "${d}"
      fi
    done
  done

  local entry repo name pin pattern dirkey target version_var version pkg_dir tag_file
  for entry in "${PACKAGES[@]}"; do
    IFS=: read -r repo name pin pattern <<< "${entry}"
    pattern="${pattern:-*.deb}"
    # Key the download dir by NAME, not repo: two entries may share one repo
    # (e.g. a renamed package tracking latest plus its pinned predecessor).
    dirkey="${name,,}"
    for target in stable testing; do
      version_var="${name}_$(echo "${target}" | tr '[:lower:]' '[:upper:]')"
      version="${!version_var:-}"
      pkg_dir="${debs_dir}/${target}/${dirkey}"
      tag_file="${pkg_dir}/.tag"

      if [ -z "${version}" ]; then
        echo "skipping ${repo} (${target}): no version"
        rm -rf "${pkg_dir}"
        continue
      fi

      if [ -f "${tag_file}" ] && [ "$(cat "${tag_file}")" = "${version}" ]; then
        echo "cached ${repo} ${version} (${target}), skipping download"
        continue
      fi

      rm -rf "${pkg_dir}"
      mkdir -p "${pkg_dir}"
      if [ "$(count_assets "${repo}" "${version}" "${pattern}")" -gt 0 ]; then
        echo "downloading ${repo} ${version} [${pattern}] -> ${target}"
        gh release download "${version}" \
          --repo "${GH_OWNER}/${repo}" \
          --pattern "${pattern}" \
          --dir "${pkg_dir}/"
      else
        # No matching asset yet (e.g. a renamed package not published under its
        # new name yet). Cache the tag so we do not re-query until it changes.
        echo "no '${pattern}' asset in ${repo} ${version} (${target}), skipping"
      fi
      echo "${version}" > "${tag_file}"
    done
  done

  local t
  for t in stable testing; do
    echo "${t} packages:"
    find "${debs_dir}/${t}" -name '*.deb' -printf '  %p\n' 2>/dev/null | sort || echo "  (none)"
  done
}

# ---------- build ----------

cmd_build_help() {
  cat <<EOF
Usage: build-apt-repo.sh build --gpg-key-id <ID> [options]

Runs 'reprepro includedeb' for every .deb under <debs-dir>/{stable,testing}/*/,
then exports the public GPG key and writes CNAME, index.html (rendered from
README via pandoc), robots.txt, and sitemap.xml under <repo-dir>.

Options:
  --gpg-key-id ID   GPG key id whose public key is exported as key.gpg (required)
  --debs-dir PATH   Input .deb directory (default: ./debs)
  --repo-dir PATH   Output repo directory (default: ./repo)
  --cname DOMAIN    Value written to <repo-dir>/CNAME and used as the host in
                    sitemap.xml / robots.txt (default: ${CNAME_DEFAULT}; empty = skip CNAME)
  --readme PATH     Markdown file rendered to <repo-dir>/index.html (default: ./README.md)
EOF
}

cmd_build() {
  local gpg_key_id="" debs_dir="./debs" repo_dir="./repo" cname="${CNAME_DEFAULT}" readme="./README.md"
  while [ $# -gt 0 ]; do
    case "$1" in
      --gpg-key-id) gpg_key_id="$2"; shift 2 ;;
      --debs-dir)   debs_dir="$2"; shift 2 ;;
      --repo-dir)   repo_dir="$2"; shift 2 ;;
      --cname)      cname="$2"; shift 2 ;;
      --readme)     readme="$2"; shift 2 ;;
      -h|--help)    cmd_build_help; return 0 ;;
      *) die "build: unknown option: $1" ;;
    esac
  done
  [ -n "${gpg_key_id}" ] || die "build: --gpg-key-id is required"
  [ -d conf ]        || die "build: ./conf not found (run 'configure' first)"
  [ -f "${readme}" ] || die "build: readme not found at ${readme}"

  command -v reprepro >/dev/null || die "build: reprepro not found in PATH"
  command -v gpg >/dev/null      || die "build: gpg not found in PATH"
  command -v pandoc >/dev/null   || die "build: pandoc not found in PATH"

  mkdir -p "${repo_dir}"
  cp -r conf "${repo_dir}/"

  local target deb
  for target in stable testing; do
    for deb in "${debs_dir}/${target}"/*/*.deb; do
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

  # Render the README to index.html via pandoc, with a small embedded stylesheet.
  local header_file
  header_file="$(mktemp)"
  cat > "${header_file}" <<'EOF'
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body { max-width: 760px; margin: 2rem auto; padding: 0 1rem;
         font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
         line-height: 1.6; color: #1a1a1a; }
  h1, h2, h3 { line-height: 1.25; }
  pre { background: #f4f4f4; padding: 1rem; border-radius: 4px; overflow-x: auto; }
  code { background: #f4f4f4; padding: 0.1rem 0.3rem; border-radius: 3px; font-size: 0.9em; }
  pre code { background: transparent; padding: 0; font-size: 0.85em; }
  table { border-collapse: collapse; margin: 1rem 0; }
  th, td { border: 1px solid #ddd; padding: 0.5rem 0.75rem; text-align: left; }
  th { background: #f4f4f4; }
  a { color: #0082FC; }
  img { max-width: 100%; }
</style>
EOF
  pandoc "${readme}" --standalone \
    --metadata pagetitle="Odio APT Repository" \
    --include-in-header "${header_file}" \
    -o "${repo_dir}/index.html"
  rm -f "${header_file}"

  # Keep APT internals out of search indexes; expose only the landing page.
  cat > "${repo_dir}/robots.txt" <<EOF
User-agent: *
Disallow: /conf/
Disallow: /db/
Disallow: /dists/
Disallow: /pool/

Sitemap: https://${host}/sitemap.xml
EOF

  cat > "${repo_dir}/sitemap.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://${host}/</loc>
    <lastmod>$(date -u +%Y-%m-%d)</lastmod>
    <changefreq>weekly</changefreq>
  </url>
</urlset>
EOF
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
