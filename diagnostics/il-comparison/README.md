# FFI `.address`: generated IL and ARM64 disassembly

This comparison uses the same reproduction source, native library, VM, platform
kernel, and VM flags for both runs. Only the compiler's `.address` use-site
transformer changes.

- Buggy transformer: SDK base `c979dd065b6b4a648858a940c7e4598fa2152209`.
- Fixed transformer: PR commit `fb896406c0af3cd78680adf75d4f12b52e3a97d2`.
- Reproduction: commit `903132128b2dab585665520f857a48175382d7fb`.
- Runtime: Dart 3.14.0-248.0.dev, macOS arm64.
- Capture: JIT, with unoptimized Dart wrappers and optimized FFI entry points.

The compiler packages are identical except for `ffi/use_sites.dart`. The buggy
version is copied from the SDK base into an isolated compiler package; neither
checkout is modified. The reproduction's ordinary-Pointer controls run too.

| File | Contents |
|---|---|
| [PR-excerpt.md](PR-excerpt.md) | Short comparison to paste into the PR |
| [buggy.il.txt](buggy.il.txt) / [fixed.il.txt](fixed.il.txt) | Complete IL graphs for the two `.address` helpers and their new native bindings |
| [buggy.asm.txt](buggy.asm.txt) / [fixed.asm.txt](fixed.asm.txt) | Complete ARM64 function disassemblies for the same helpers |
| [buggy.log](buggy.log) / [fixed.log](fixed.log) | Raw combined stdout/stderr, including Pointer controls and all 21 check results |
| [metadata.json](metadata.json) | Revisions, source hashes, exact compilation/run commands, and exit codes |
| [capture.py](capture.py) | Script to repeat compilation and capture |

## What the dumps show

Before the fix, `#nativeBigFromAddressLeaf#T` and `#nativeIntFromPeer#T` both return
`Constant(#null)`. Neither calls a native binding. Their assembly loads the null
register (`nr`) and returns that value. Debugger and stack-check calls in the
same functions are VM machinery, not the native function from the reproduction.

After the fix, each wrapper calls a generated `#_...$Method$FfiNative#T` binding.
Those bindings contain `FfiCall` in IL and a leaf call through `blr r9` in ARM64.
The native-field wrapper also retains `_getNativeField`, pointer construction,
and `ReachabilityFence`.

The buggy run has 16 passing checks and five failures (exit 1). The fixed run
passes all 21 checks (exit 0). The full logs also include native calls from the
ordinary-Pointer controls, which work in both runs; the extracted files isolate
the `.address` functions.

This capture demonstrates the JIT failure and restored native calls. It is not
an AOT dump or evidence for the particular cause of an AOT crash.

## Repeat the capture

The saved dumps above come from the earlier 21-check reproduction. The current
source removes five `lookupFunction` controls and uses only `@Native` bindings.
The capture script now expects 11 passes / five failures before the fix and
16 passes after it; the two `.address` cases selected for IL capture are unchanged.

Use the fixed SDK checkout with its dependencies and `.dart_tool/package_config.json`
prepared, plus the compatible Dart 3.14.0-248.0.dev SDK. Run `./run.sh` in this
reproduction first to build its native code asset and create
`.dart_tool/native_assets.yaml`; exit 1 is expected with an affected SDK.

```sh
python3 diagnostics/il-comparison/capture.py \
  --sdk-checkout /path/to/fixed/dart-sdk \
  --dart-sdk /path/to/dart-3.14.0-248.0.dev/dart-sdk \
  --repro /path/to/dart_ffi_leaf_struct_repro \
  --output /tmp/ffi-il-comparison
```

The checkout must contain the baseline Git object named above. For a source copy
without `.git`, also pass `--repro-revision` with the source commit ID.
The script compiles both kernels, captures the dumps, checks the expected
outcomes, and extracts the `.address` functions. Temporary compiler copies and
kernels go into the output directory's `work/` subdirectory.

The VM flags used for both runs are:

```text
--deterministic --no-background-compilation
--print-flow-graph --print-flow-graph-optimized
--disassemble --disassemble-optimized --disassemble-relative
--print-flow-graph-filter=nativeBigFromAddressLeaf,nativeIntFromPeer
```

The disassembler reports function-relative instruction offsets. Full paths,
private-name suffixes, and some offsets may differ on another checkout.
