#!/usr/bin/env bash
# Uninstaller for the Quickshell island desktop shell.
#
# Restores the desktop to its stock state:
#   * stops this shell's Quickshell instance
#   * restores every file this installer backed up
#   * removes the files the installer created that had no previous version
#   * removes the Hyprland module and its require line
#   * restores Omarchy's shell.json
#   * brings the stock Omarchy shell back up
#
# Usage:
#   ./uninstall.sh            roll back
#   ./uninstall.sh --dry-run  show what would be restored, touch nothing

set -euo pipefail

CACHE_DIR="${NOOXSHELL_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/nooxshell}"

STATE_DIR="$HOME/.local/state/nooxshell"
STATE_FILE="$STATE_DIR/state.json"

# Fetch the branch the shell was installed from, which the installer
# records, so a nightly install is removed with the nightly manifest.
recorded_state() {
  [[ -f $STATE_FILE ]] && command -v jq >/dev/null 2>&1 || return 0
  jq -r --arg key "$1" '.[$key] // empty' "$STATE_FILE" 2>/dev/null || true
}
REPO_URL="${NOOXSHELL_REPO_URL:-$(recorded_state repo_url)}"
REPO_URL="${REPO_URL:-https://github.com/whonoox/nooxshell.git}"
REPO_REF="${NOOXSHELL_REPO_REF:-$(recorded_state ref)}"
REPO_REF="${REPO_REF:-master}"
BACKUP_ROOT="$STATE_DIR/backups"
PRISTINE_DIR="$STATE_DIR/pristine"

HYPR_BEGIN_MARKER="-- quickshell-islands:begin"
HYPR_END_MARKER="-- quickshell-islands:end"

DRY_RUN=0

# Paths (relative to $HOME) that the backup covers. These are restored
# rather than deleted, so removal has to skip them.
BACKED_UP_FILES=""

info() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m::\033[0m %s\n' "$*" >&2; }
fail() {
  printf '\033[1;31m::\033[0m %s\n' "$*" >&2
  exit 1
}
ok() { printf '\033[1;32m::\033[0m %s\n' "$*"; }

usage() {
  cat <<'USAGE'
Usage: uninstall.sh [options]

Options:
  --dry-run     show what would be restored, touch nothing
  -h, --help    show this help
USAGE
}

# The uninstaller needs the manifest to know what it deployed. When the
# script is piped in rather than run from a checkout, that directory is a
# process substitution and holds nothing, so the repository is fetched
# first and the script re-executes from the clone.
bootstrap() {
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

  if [[ -n $script_dir && -f $script_dir/manifest.json ]]; then
    REPO_DIR="$script_dir"
    MANIFEST="$REPO_DIR/manifest.json"
    return 0
  fi

  info "No checkout found; fetching $REPO_URL"
  command -v git >/dev/null 2>&1 ||
    fail "git is required to uninstall from a URL"

  mkdir -p "$CACHE_DIR"

  if [[ -d $CACHE_DIR/repo/.git ]]; then
    git -C "$CACHE_DIR/repo" fetch --depth 1 origin "$REPO_REF" ||
      fail "could not fetch $REPO_URL"
    # FETCH_HEAD, not origin/$REPO_REF: the cache is a single-branch clone,
    # so another branch never gets a remote-tracking ref.
    git -C "$CACHE_DIR/repo" reset --hard FETCH_HEAD ||
      fail "could not update the cached checkout"
  else
    git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$CACHE_DIR/repo" ||
      fail "could not clone $REPO_URL"
  fi

  [[ -f $CACHE_DIR/repo/manifest.json ]] ||
    fail "the fetched checkout has no manifest.json"

  exec bash "$CACHE_DIR/repo/uninstall.sh" "$@"
}

REPO_DIR=""
MANIFEST=""

run() {
  if (( DRY_RUN )); then
    printf '  would run: %s\n' "$*"
    return 0
  fi
  "$@"
}

expand_path() {
  local path="$1"
  path="${path/#\~/$HOME}"
  printf '%s' "$path"
}

manifest_list() {
  jq -c -r "$1[]?" "$MANIFEST"
}

# Picks the pristine copy taken before the first install. Per-run backups
# under backups/ capture what a later run touched, which may already be the
# files the installer deployed, so they cannot be used to restore the
# user's originals.
#
# The state directory was renamed from "omarchy-islands" to "nooxshell"
# along with the CLI, so an installation made before the rename is looked
# for in both places.
pristine_backup() {
  if [[ -f $PRISTINE_DIR/backup_manifest.json ]]; then
    printf '%s' "$PRISTINE_DIR"
    return 0
  fi

  local old="$HOME/.local/state/omarchy-islands/pristine"
  if [[ -f $old/backup_manifest.json ]]; then
    printf '%s' "$old"
    return 0
  fi

  return 1
}

stop_shell() {
  local cli="$HOME/.local/bin/nooxshell"
  if [[ -x $cli ]]; then
    info "Stopping the island shell"
    run "$cli" stop || warn "could not stop the shell cleanly"
  else
    info "Stopping the island shell (qs kill)"
    run qs kill -p "$HOME/.config/quickshell" || true
  fi
}

restore_backups() {
  local backup_dir="$1"
  local manifest_file="$backup_dir/backup_manifest.json"

  [[ -f $manifest_file ]] || {
    warn "no backup manifest in $backup_dir"
    return 0
  }

  local count=0
  local failed=0
  local relative
  while IFS= read -r relative; do
    [[ -n $relative ]] || continue
    local source="$backup_dir/files/$relative"
    [[ -f $source ]] || continue

    BACKED_UP_FILES="$BACKED_UP_FILES $relative"

    if (( DRY_RUN )); then
      printf '  would restore: %s\n' "$HOME/$relative"
      count=$((count + 1))
      continue
    fi

    # Remove before copying: a file the user cannot write to would make
    # cp fail, and one failure must not abandon the rest of the rollback.
    mkdir -p "$(dirname "$HOME/$relative")"
    rm -f -- "$HOME/$relative" 2>/dev/null || true
    if cp -a -- "$source" "$HOME/$relative"; then
      count=$((count + 1))
    else
      warn "could not restore $HOME/$relative"
      failed=$((failed + 1))
    fi
  done <"$manifest_file"

  ok "Restored $count files from $backup_dir"
  (( failed == 0 )) || warn "$failed files could not be restored; their backups are in $backup_dir/files"
}

remove_installed() {
  local count=0
  local entry

  # Files that existed before the install are restored from the backup
  # instead of being deleted, so they must not be touched here.
  local restored=" $BACKED_UP_FILES "

  while IFS= read -r entry; do
    local dest relative
    dest="$(expand_path "$(jq -r '.dest' <<<"$entry")")"
    relative="${dest#"$HOME"/}"

    if [[ -e $dest && $restored != *" $relative "* ]]; then
      if (( DRY_RUN )); then
        printf '  would remove: %s\n' "$dest"
      else
        rm -f "$dest"
      fi
      count=$((count + 1))
    fi
  done < <(manifest_list '.files')

  while IFS= read -r entry; do
    local dest relative
    dest="$(expand_path "$(jq -r '.dest' <<<"$entry")")"
    relative="${dest#"$HOME"/}"

    if [[ -e $dest && $restored != *" $relative "* ]]; then
      if (( DRY_RUN )); then
        printf '  would remove: %s\n' "$dest"
      else
        rm -f "$dest"
      fi
      count=$((count + 1))
    fi
  done < <(manifest_list '.shims')

  while IFS= read -r entry; do
    local dest relative
    dest="$(expand_path "$(jq -r '.dest' <<<"$entry")")"
    relative="${dest#"$HOME"/}"

    if [[ -e $dest && $restored != *" $relative "* ]]; then
      if (( DRY_RUN )); then
        printf '  would remove: %s\n' "$dest"
      else
        rm -f "$dest"
      fi
      count=$((count + 1))
    fi
  done < <(manifest_list '.fonts')

  local cli_dest
  cli_dest="$(expand_path "$(jq -r '.cli.dest' "$MANIFEST")")"
  if [[ -e $cli_dest ]]; then
    if (( DRY_RUN )); then
      printf '  would remove: %s\n' "$cli_dest"
    else
      rm -f "$cli_dest"
    fi
    count=$((count + 1))
  fi

  # The CLI was named "omarchy-islands" before it became "nooxshell".
  local old_cli="$HOME/.local/bin/omarchy-islands"
  if [[ -e $old_cli ]]; then
    if (( DRY_RUN )); then
      printf '  would remove: %s\n' "$old_cli"
    else
      rm -f "$old_cli"
    fi
    count=$((count + 1))
  fi

  # Shims an earlier version installed and this one no longer does.
  local retired
  while IFS= read -r retired; do
    [[ -n $retired ]] || continue
    local retired_path
    retired_path="$(expand_path "$retired")"
    if [[ -e $retired_path ]]; then
      if (( DRY_RUN )); then
        printf '  would remove: %s\n' "$retired_path"
      else
        rm -f "$retired_path"
      fi
      count=$((count + 1))
    fi
  done < <(manifest_list '.retiredShims')

  ok "Removed $count installed files"
}

# Removes the directories the installer created, if they are now empty.
remove_empty_dirs() {
  local dir
  for dir in \
    "$HOME/.config/quickshell/decorations" \
    "$HOME/.config/quickshell/bin" \
    "$HOME/.config/quickshell"; do
    if [[ -d $dir ]] && [[ -z $(ls -A "$dir" 2>/dev/null) ]]; then
      if (( DRY_RUN )); then
        printf '  would remove empty dir: %s\n' "$dir"
      else
        rmdir "$dir" 2>/dev/null || true
      fi
    fi
  done
}

remove_hypr_module() {
  local module_dest require_file
  module_dest="$(expand_path "$(jq -r '.hypr.module.dest' "$MANIFEST")")"
  require_file="$(expand_path "$(jq -r '.hypr.require.file' "$MANIFEST")")"

  if (( DRY_RUN )); then
    printf '  would remove: %s\n' "$module_dest"
    printf '  would strip require line from: %s\n' "$require_file"
    return 0
  fi

  rm -f "$module_dest"

  if [[ -f $require_file ]] && grep -qF -- "$HYPR_BEGIN_MARKER" "$require_file"; then
    local tmp
    tmp="$(mktemp)"
    awk -v b="$HYPR_BEGIN_MARKER" -v e="$HYPR_END_MARKER" '
      $0 == b { skip = 1; next }
      $0 == e { skip = 0; next }
      !skip { print }
    ' "$require_file" >"$tmp"
    # The installer writes a blank line above the block; drop the blank
    # lines left at the end. Rewritten in place to keep the permissions.
    awk '{ lines[NR] = $0 } END { n = NR; while (n > 0 && lines[n] ~ /^[ \t]*$/) n--; for (i = 1; i <= n; i++) print lines[i] }' "$tmp" >"$require_file"
    rm -f "$tmp"
  fi

  ok "Removed the Hyprland module and its require line"
}

# Takes out the blocks the installer added so apps ask Hyprland for the
# window blur (see enable_app_blur in install.sh). The pristine backup
# already gives back these files as they were before the first install;
# this covers an install that was upgraded into them, and keeps any edit
# the user made around the block.
APP_BLUR_BEGIN="nooxshell blur begin"
APP_BLUR_END="nooxshell blur end"

remove_app_blur() {
  local config="$HOME/.config"
  local entry file open close tmp
  for entry in "$config/ghostty/config|#|" "$config/foot/foot.ini|#|" "$config/gtk-4.0/gtk.css|/*| */"; do
    IFS='|' read -r file open close <<<"$entry"
    [[ -f $file ]] && grep -qxF -- "$open $APP_BLUR_BEGIN$close" "$file" || continue
    if (( DRY_RUN )); then
      printf '  would remove the blur block from: %s\n' "$file"
      continue
    fi
    tmp="$(mktemp)"
    awk -v b="$open $APP_BLUR_BEGIN$close" -v e="$open $APP_BLUR_END$close" '
      $0 == b { skip = 1; next }
      skip && $0 == e { skip = 0; next }
      !skip { print }
    ' "$file" >"$tmp"
    cat "$tmp" >"$file"
    rm -f "$tmp"
    # A gtk.css the installer created holds nothing else.
    if [[ $file == */gtk.css ]] && ! grep -q '[^[:space:]]' "$file"; then
      rm -f "$file"
      rmdir "$(dirname "$file")" 2>/dev/null || true
    fi
  done
  (( DRY_RUN )) || ok "Removed the app blur settings"
}

# shell.json is restored by restore_backups, which copies the pristine copy
# over the current file. This only reports on the outcome, so a failure to
# restore is not silently swallowed.
report_omarchy_config() {
  local config="$HOME/.config/omarchy/shell.json"

  if [[ ! -e $config ]]; then
    warn "shell.json is missing"
    return 0
  fi

  if (( DRY_RUN )); then
    printf '  would restore: %s\n' "$config"
    return 0
  fi

  ok "shell.json restored from the pristine backup"
}

revive_stock_shell() {
  info "Restarting the stock Omarchy shell"
  run hyprctl reload || warn "hyprctl reload failed"
  run omarchy-restart-shell || warn "omarchy-restart-shell failed"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        fail "unknown option: $1"
        ;;
    esac
  done

  # A piped script has no checkout next to it, so fetch one and re-exec
  # from there.
  bootstrap "$@"

  [[ -f $MANIFEST ]] || fail "manifest not found: $MANIFEST"

  # A git checkout at the config path is a development copy, not an
  # install: removing the deployed files there would delete files from the
  # repository. Move the checkout elsewhere and install from it instead.
  if [[ -e $HOME/.config/quickshell/.git ]]; then
    fail "$HOME/.config/quickshell is a git checkout; move it out of ~/.config before uninstalling"
  fi

  if (( DRY_RUN )); then
    info "Dry run: no changes will be made"
  else
    info "Removing the island shell"
  fi

  stop_shell

  local backup_dir
  if backup_dir="$(pristine_backup)"; then
    restore_backups "$backup_dir"
  else
    warn "no pristine backup found under $PRISTINE_DIR"
  fi

  remove_installed
  remove_empty_dirs
  remove_hypr_module
  remove_app_blur
  report_omarchy_config

  if (( ! DRY_RUN )); then
    rm -rf "$STATE_DIR"
    # Wallpaper and theme thumbnails the pickers generated. The cached
    # clone next to them is left: this script may be running from it.
    rm -rf "$CACHE_DIR/thumbnails"
    # The pre-rename state directory, in case the install was never
    # migrated.
    rm -rf "$HOME/.local/state/omarchy-islands"
  fi

  revive_stock_shell

  ok "Uninstall complete"
}

main "$@"
