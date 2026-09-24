Reproduction of Dart compiler bug where leaf `@Native` call using `.address` when returning struct by value or accepts a `NativeFieldWrapperClass1` object.

Requires Dart and a host C compiler.

To run the reproduction in JIT mode:
```sh
dart pub get && dart run bin/repro.dart
```

```sh
dart build cli -t bin/repro.dart -o build/aot
build/aot/bundle/bin/repro
```

This compiles `native/lib.c` through Dart's build hook and runs `bin/repro.dart`, which shows five failures. All five fail in JIT mode on an affected SDK (.address with struct-return and the native-field argument) and will crash in AOT mode (at least, on macos).

`Peer` is a user-defined subclass of `NativeFieldWrapperClass1`. A separate,
non-leaf call to `Dart_SetNativeInstanceField` initializes its native pointer.
The tested leaf calls receive that pointer automatically. Its storage remains
allocated until all calls finish.

See [related PR](https://github.com/nmfisher/dart-sdk/pull/4) for cause and fix.

Run `python3 dump_il.py` to generate IL under `il_output`


