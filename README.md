# Dart FFI: leaf `.address` call with a struct return

This reproduces a Dart compiler bug: a leaf `@Native` call with both a
`TypedData.address` argument and a struct-by-value return silently returns
`null` in JIT. The native function is never invoked. The same functions work
with ordinary `Pointer` arguments, and `.address` works with an integer return.

The project was recreated from the reviewed reproduction after its temporary
working directory was cleaned up. It retains the 15-check matrix, native-assets
build hook, and DynamicLibrary controls. Revalidated on 2026-09-23 with Dart
3.12.1 on macOS arm64: 13 controls passed, both failing cases returned null,
and the process exited 1. `dart analyze` reported no issues.

## Run (macOS)

Requires Dart, a C compiler (`cc`), and access to pub.dev for dependencies.

```sh
./run.sh
```

The script creates `build/`, compiles the DynamicLibrary control library,
resolves dependencies, and runs the reproduction. Dart also runs the build hook
for the `@Native` code asset. The DynamicLibrary path is made absolute to work
with hardened macOS Dart executables.

On an affected SDK, 13 controls pass and the last two checks fail:

```text
  -> returned null
FAIL @Native leaf + .address argument + big return (original failure)
  -> returned null
FAIL @Native leaf + .address argument + small return
2 check(s) failed - see above.
```

**Exit code 1 is expected when reproducing the bug.** A fixed compiler should
print `All checks passed.` and exit 0. Running this project does not patch the
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

On macOS arm64, Small is 8 bytes (register return), and Big is 24 bytes
(hidden-pointer return). C consumes the input synchronously, does not retain
its pointer, and does not call Dart or Dart VM APIs.

## Confirmed cause

The native transformer introduces a Dart wrapper for compound returns to keep
the compound constructor alive during AOT tree shaking. The `.address` use-site
transformer specializes this wrapper using `CloneProcedureWithoutBody`. The
result is a non-external Dart helper with no body; it returns null without
calling C.

Inspect its generated flow graph:

```sh
dart --print-flow-graph --print-flow-graph-filter=nativeBigFromAddressLeaf run bin/repro.dart
```

On the affected compiler, `#nativeBigFromAddressLeaf#T` contains
`Constant(#null)` followed by `DartReturn`, with no native call. The small-return
helper behaves the same way.

The SDK fix specializes the underlying external entry point and preserves the
compound constructor's `_nativeEffect` at the call site:
[fix PR in nmfisher/dart-sdk](https://github.com/nmfisher/dart-sdk/pull/4),
branch `fix/ffi-address-compound-return`, commit
`581a838f298c2b9bf70b25c6dee4d67e00b754f6`.

Related feature tracking:
[dart-lang/sdk#44589](https://github.com/dart-lang/sdk/issues/44589).
That issue concerns the original TypedData-unwrapping feature, not this exact
compound-return failure.

## AOT

The original review reproduced the bug on Dart 3.12.2/macOS arm64: the JIT
checks returned null and the AOT executable crashed at the first failing case.
To test AOT after running `./run.sh` (even if it exits 1):

```sh
dart build cli -t bin/repro.dart -o build/aot
build/aot/bundle/bin/repro
```

During the original fix validation, all 15 checks passed in JIT and AOT with
the patched frontend. That historical result does not imply the system Dart
installation includes the fix.

## Workaround

Copy input into allocated native memory and pass its `Pointer`, as the malloc
control demonstrates. `isLeaf: true` can remain. Removing `isLeaf` alone is
insufficient: `.address` is only valid as an argument to a leaf `@Native` call.
