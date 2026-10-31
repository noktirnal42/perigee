#!/bin/bash
# Regenerates Packages/StarlinkKit/Sources/{RouterAPI,DishAPI} from reference/*.protoset.
# Needs: protoc, protoc-gen-swift and protoc-gen-grpc-swift-2 (build them from swift-protobuf 1.39 and
# grpc-swift-protobuf 2.5: `swift build --product protoc-gen-swift` etc.) — pass their directory as $1.
set -euo pipefail
PLUGINS="${1:?usage: generate-protos.sh /path/to/dir-with-plugins}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for dev in router dish; do
  mod=$([ "$dev" = router ] && echo RouterAPI || echo DishAPI)
  out="$ROOT/Packages/StarlinkKit/Sources/$mod"; rm -rf "$out"; mkdir -p "$out"
  files=$(protoc --decode=google.protobuf.FileDescriptorSet google/protobuf/descriptor.proto < "$ROOT/reference/$dev.protoset" \
          | grep -E '^  name:' | sed 's/.*"\(.*\)"/\1/' | grep -v '^google/')
  protoc --plugin=protoc-gen-swift="$PLUGINS/protoc-gen-swift" --plugin=protoc-gen-grpc-swift-2="$PLUGINS/protoc-gen-grpc-swift-2" \
    --descriptor_set_in="$ROOT/reference/$dev.protoset" \
    --swift_out="$out" --swift_opt=Visibility=Public,FileNaming=PathToUnderscores \
    --grpc-swift-2_out="$out" --grpc-swift-2_opt=Visibility=Public,Server=false,FileNaming=PathToUnderscores $files
done
