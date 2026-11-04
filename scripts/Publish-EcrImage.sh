#!/usr/bin/env bash
# Run on the existing EC2 Docker host as root; IAM comes from its instance role.
set -euo pipefail
image=${1:?local image required}
repository=${2:?ECR repository URI required}
tag=${3:?immutable tag required}
registry=${repository%%/*}
auth_dir=$(mktemp -d /tmp/mosquizto-ecr-auth.XXXXXX)
trap 'rm -f "$auth_dir/config.json"; rmdir "$auth_dir"' EXIT

test "$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")" = 'linux/amd64'
test "$(docker run --rm --entrypoint id "$image" -u)" = '10001'
docker run --rm --entrypoint sh "$image" -ec '
  cd /models/1110a243fdf4706b3f48f1d95db1a4f5529b4d41
  printf "%s  %s\n" \
    6fd5d72fe4589f189f8ebc006442dbb529bb7ce38f8082112682524616046452 model.onnx \
    be50c3628f2bf5bb5e3a7f17b1f74611b2561a3a27eeab05e5aa30f411572037 tokenizer.json |
    sha256sum -c -
'
# Generate the ECR token on the same host using LabRole. Never pass it in argv.
docker run --rm --network host -e AWS_DEFAULT_REGION=us-east-1 \
  public.ecr.aws/aws-cli/aws-cli@sha256:ffc86d09f89a84eba131d429bc6050510a179af77d2d04364548842853673692 \
  ecr get-login-password |
  docker --config "$auth_dir" login --username AWS --password-stdin "$registry"
docker tag "$image" "$repository:$tag"
docker --config "$auth_dir" push "$repository:$tag"
