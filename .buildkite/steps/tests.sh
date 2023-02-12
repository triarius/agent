#!/usr/bin/env sh

set -euf

go version
echo arch is "$(uname -m)"

if ! command -v gotestsum >/dev/null; then
  go install gotest.tools/gotestsum@v1.9.0
fi

ensure_installed_on_ci() {
  if ! command -v "$1" >/dev/null; then
    if [ "$CI" = "true" ]; then
      apk add "$2"
    else
      echo "The tests require $2 to be installed" >&2
      exit 1
    fi
  fi
}

ensure_installed_on_ci ssh openssh
ensure_installed_on_ci git git
ensure_installed_on_ci bash bash


echo '+++ Running tests'
gotestsum --junitfile "junit-${BUILDKITE_JOB_ID}.xml" -- -count=1 -failfast "$@" ./...

echo '+++ Running integration tests for git-mirrors experiment'
TEST_EXPERIMENT=git-mirrors gotestsum --junitfile "junit-${BUILDKITE_JOB_ID}-git-mirrors.xml" -- -count=1 -failfast "$@" ./bootstrap/integration
