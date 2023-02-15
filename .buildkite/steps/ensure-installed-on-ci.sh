#!/usr/bin/env sh

set -euf

ensure_installed_on_ci() {
  if ! $1 >/dev/null; then
    if [ "$CI" = "true" ]; then
      apk add "$2"
    else
      echo "$2 is required to be installed" >&2
      exit 1
    fi
  fi
}
