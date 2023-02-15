#!/usr/bin/env sh

set -euf

go version
echo arch is "$(uname -m)"

. "$(dirname "$0")/ensure-installed-on-ci.sh"

ensure_installed_on_ci "command -v ssh" openssh
ensure_installed_on_ci "command -v git" git
ensure_installed_on_ci "command -v bash" bash

if ! command -v gotestsum >/dev/null; then
  go install gotest.tools/gotestsum@v1.9.0
fi

echo '+++ Running tests'
gotestsum --junitfile "junit-${BUILDKITE_JOB_ID}.xml" -- -count=1 -failfast "$@" ./...

echo '+++ Running integration tests for git-mirrors experiment'
TEST_EXPERIMENT=git-mirrors gotestsum --junitfile "junit-${BUILDKITE_JOB_ID}-git-mirrors.xml" -- -count=1 -failfast "$@" ./bootstrap/integration
