#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
dart pub get >/dev/null
dart run bin/repro.dart
