#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
mkdir -p build
cc -shared -fPIC -o build/libstruct.dylib native/lib.c
dart pub get >/dev/null
dart run bin/repro.dart
