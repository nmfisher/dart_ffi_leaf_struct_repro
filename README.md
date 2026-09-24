# Dart FFI: leaf `.address` calls lose generated wrappers

This reproduces a Dart compiler bug: a leaf `@Native` call using
`TypedData.address` can silently return `null` without calling C when it:

- returns a struct by value; or
- also accepts a `NativeFieldWrapperClass1` object that Dart converts to a native pointer.

Ordinary `Pointer` arguments work. Without the native-field argument, an integer
return also works.

## Run (macOS)

Requires Dart, a C compiler (`cc`), and access to pub.dev for dependencies.

```sh
./run.sh
```

The script builds the DynamicLibrary control library, resolves dependencies,
and runs the reproduction. Dart's build hook builds the `@Native` code asset.

There are **21 checks**. On Dart 3.12.1/macOS arm64, 16 controls pass and five
`.address` calls return null: the two original struct-return cases, plus small
struct, big struct, and integer returns with a native-field argument. The new
cases also show that the native input mutation never happens.

**Exit code 1 is expected on an affected SDK.** A fixed compiler should print
`All checks passed.` and exit 0. Running this project does not patch the
installed SDK.

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

## Validation

Validated on 2026-09-24 on macOS arm64:

- System Dart 3.12.1: 16 pass, five fail as expected; `dart analyze` passes.
- Patched frontend with Dart 3.14.0-248.0.dev: all 21 checks pass in JIT and AOT.

To try AOT with your installed SDK after running `./run.sh`:

```sh
dart build cli -t bin/repro.dart -o build/aot
build/aot/bundle/bin/repro
```

An affected AOT build may crash rather than print a failed check. The original
reproduction exhibited this on Dart 3.12.2/macOS arm64.

## Workaround

Copy the input into allocated native memory and pass its `Pointer`, as the
malloc controls demonstrate. `isLeaf: true` can remain. Removing `isLeaf` alone
is insufficient: `.address` requires a leaf `@Native` call.
