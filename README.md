Reproduction of Dart compiler bug where leaf `@Native` call using `.address` when returning struct by value or accepts a `NativeFieldWrapperClass1` object.

To run the reproduction in JIT mode:
```sh
./run.sh
```

Requires Dart, & C compiler (`cc`).

To run via AOT after running `./run.sh`:

```sh
dart build cli -t bin/repro.dart -o build/aot
build/aot/bundle/bin/repro
```

This compiles `native/lib.c` and runs `bin/repro.dart`, which contains 21 checks (similar to existing Dart SDK FFI test suite). These should all pass, but 5 will fail in JIT mode (.address with struct-return and the native-field argument) and will crash in AOT mode (at least, on macos).

## Coverage

| Call | Argument | Return | Affected SDK result |
|---|---|---|---|
| `@Native` leaf/non-leaf | integer | Small / Big | Pass |
| `lookupFunction` leaf/non-leaf | integer | Small / Big | Pass |
| `@Native` leaf/non-leaf, `lookupFunction` leaf | Big by value | integer | Pass |
| `@Native` leaf | `TypedData.address` | integer | Pass |
| `@Native` leaf | allocated Pointer | Big | Pass |
| `@Native` leaf | `TypedData.address` | Small / Big | **null** |
| `@Native` leaf | native-field object + allocated Pointer | Small / Big / integer | Pass |
| `@Native` leaf | native-field object + `TypedData.address` | Small / Big / integer | **null** |

Small is 8 bytes and Big is 24 bytes on macOS arm64, covering register and
hidden-pointer returns. C consumes the input synchronously and does not retain
its pointer or call Dart.

`Peer` is a user-defined subclass of `NativeFieldWrapperClass1`. A separate,
non-leaf call to `Dart_SetNativeInstanceField` initializes its native pointer.
The tested leaf calls receive that pointer automatically. Its storage remains
allocated until all calls finish.

## Cause and fix

The native transformer generates Dart wrappers to retain compound constructors
for AOT and to convert native-field arguments to pointers. The `.address`
transformer clones the called procedure without its body. When that procedure
is a Dart wrapper, the resulting helper returns null instead of calling C.

The [SDK fix](https://github.com/nmfisher/dart-sdk/pull/4) preserves the wrapper
body and specializes the external native function it calls. This keeps argument
conversions, reachability fences, and the compound-constructor retention code.

The related feature tracking issue is
[dart-lang/sdk#44589](https://github.com/dart-lang/sdk/issues/44589); it concerns
the original TypedData-unwrapping feature, rather than this specific bug.



