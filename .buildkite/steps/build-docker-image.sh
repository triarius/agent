#!/usr/bin/env bash

set -Eeufo pipefail

## This script can be run locally like this:
##
## .buildkite/steps/build-docker-image.sh (alpine|alpine-k8s|ubuntu-18.04|ubuntu-20.04|sidecar) (image tag) (codename) (version)
## e.g: .buildkite/steps/build-docker-image.sh alpine buildkiteci/agent:lox-manual-build stable 3.1.1
##
## You can then publish that image with
##
## .buildkite/steps/publish-docker-image.sh alpine buildkiteci/agent:lox-manual-build stable 3.1.1
##
## You will need to have the ability to build multiarch docker images.
## This requires packages that are typically named `qemu-user-static` and `qemu-user-static-binfmt`
## to be installed

apk add docker-cli-buildx aws-cli

variant="${1:-}"
image_tag="${2:-}"
codename="${3:-}"
version="${4:-}"
push="${PUSH_IMAGE:-true}"

if [[ ! "$variant" =~ ^(alpine|alpine-k8s|ubuntu-18\.04|ubuntu-20\.04|sidecar)$ ]] ; then
  echo "Unknown docker variant $variant"
  exit 1
fi

# Disable pushing if run manually
if [[ -n "$image_tag" ]] ; then
  push="false"
fi

packaging_dir="packaging/docker/$variant"

rm -rf pkg
mkdir -p pkg

for arch in amd64 arm64 ; do
  if [[ -z "$version" ]] ; then
    echo '--- Downloading :linux: binaries from artifacts'
    buildkite-agent artifact download "pkg/buildkite-agent-linux-$arch" .
  else
    echo "--- Downloading :linux: binaries for version $version and architecture $arch"
    curl -Lf -o "pkg/buildkite-agent-linux-$arch" \
      "https://download.buildkite.com/agent/${codename}/${version}/buildkite-agent-linux-$arch"
  fi
  chmod +x "pkg/buildkite-agent-linux-$arch"
done

if [[ -z "$image_tag" ]] ; then
  echo "--- Getting docker image tag for $variant from build meta data"
  image_tag=$(buildkite-agent meta-data get "agent-docker-image-$variant")
  echo "Docker Image Tag for $variant: $image_tag"
fi

echo "--- Logging into ECR :ECR:"
aws ecr get-login-password --region ap-southeast-2 \
  | docker login \
    --username AWS \
    --password-stdin \
    253213882263.dkr.ecr.ap-southeast-2.amazonaws.com

builder_name=$(docker buildx create \
  --driver remote \
  --driver-opt cacert=/buildkit/certs/ca.pem,cert=/buildkit/certs/cert.pem,key=/buildkit/certs/key.pem \
  tcp://buildkitd.buildkite.svc:1234 \
  --use \
)
# shellcheck disable=SC2064 # we want the current $builder_name to be trapped, not the runtime one
trap "docker buildx rm $builder_name || true" EXIT

cp -a packaging/linux/root/usr/share/buildkite-agent/hooks/ "${packaging_dir}/hooks/"
cp pkg/buildkite-agent-linux-{amd64,arm64} "$packaging_dir"

if [[ $push == "true" ]] ; then
  echo "--- Building and pushing to ECR :ecr:"
  # Do another build with all architectures. The layers should be cached from the previous build
  # with all architectures.
  # Pushing to the docker registry in this way greatly simplifies creating the manifest list on the
  # docker registry so that either architecture can be pulled with the same tag.
  docker buildx build \
    --progress plain \
    --builder "$builder_name" \
    --tag "$image_tag" \
    --platform linux/amd64,linux/arm64 \
    --push \
    "$packaging_dir"
fi
