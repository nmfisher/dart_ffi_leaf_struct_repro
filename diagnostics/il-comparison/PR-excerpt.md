### Generated IL and ARM64 code

Captured from the same reproduction and Dart 3.14.0-248.0.dev VM on macOS arm64,
using the original `.address` transformer (`c979dd065b6b`) and the fixed transformer
(`fb896406c0a`). These are JIT dumps: unoptimized wrapper IL and optimized FFI
binding IL. The full reproduction reports 16 passes / five failures before the
fix, and 21 passes after it.

**Before:** the generated `.address` helper `#nativeBigFromAddressLeaf#T` returns
null without invoking the native binding. Its complete IL body is:

```text
B0[graph]:0
B1[function entry]:2
    CheckStackOverflow:8(stack=0, loop=0)
    DebugStepCheck:10()
    t0 <- Constant(#null)
    DebugStepCheck:12()
    DartReturn:14(t0)
```

**After:** the same helper calls the rewritten native binding and returns its
result:

```text
B0[graph]:0
B1[function entry]:2
    CheckStackOverflow:8(stack=0, loop=0)
    DebugStepCheck:10()
    Constant(#null)
    t0 <- LoadLocal(x @1)
    RecordCoverage()
    t0 <- StaticCall:18( #_nativeBigFromAddressLeaf$Method$FfiNative#T<0> t0)
    DartReturn:20(t0)
```

The called binding, `#_nativeBigFromAddressLeaf$Method$FfiNative#T`, contains the actual
native call and constructs the returned `Big` object (excerpt):

```text
 14:     v10 <- FfiCall:14( pointer=v6, compound_return_typed_data=v9, v2 T{<:TypedData} (@r0 int64)) T{<:*?}
 16:     v11 <- AllocateObject:16(cls=Big) T{Big}
 17:     ParallelMove r0 <- r0, r1 <- fp[-4]
 18:     StoreField(v11 . _typedDataBase@9050071 = v9, NoStoreBarrier)
 20:     StoreField(v11 . _offsetInBytes@9050071 = v12, NoStoreBarrier)
 22:     DartReturn:18(v11)
```

The ARM64 disassembly confirms the difference. Before the fix, the wrapper loads
`nr` (the null register), saves that value across a debugger check, and returns it:

```text
0x6c    aa1603e0               mov r0, nr
0x70    f81f8de0               str r0, [sp, #-8]!
0x74    f9401378               ldr r24, [pp, #32]   Code([Stub] DebugStepCheck)
0x78    f840731e               ldr lr, [r24, #7]
0x7c    d63f03c0               blr lr
0x80    f84085e0               ldr r0, [sp], #8 !
0x84    f85f03bb               ldr pp, [fp, #-16]
0x88    d100077b               sub pp, pp, #0x1
0x8c    aa1d03ef               mov sp, fp
0x90    a8c179fd               ldp fp, lr, [sp], #16 !
0x94    d65f03c0               ret
```

After the fix, the called FFI binding loads the typed-data buffer address and
calls the resolved C function through `r9`:

```text
0x98    f8407000               ldr r0, [r0, #7]
0x9c    f9036f5d               str fp, [thr, #1752]
0xa0    f9038349               str r9, [thr, #1792]
0xa4    910003f9               mov r25, csp
0xa8    910001ff               mov csp, sp
0xac    d63f0120               blr r9
```

The native-field/integer case shows the same failure: `#nativeIntFromPeer#T`
previously returned null. With the fix, its IL includes `_getNativeField`, the
call to `#_nativeIntFromPeer$Method$FfiNative#T`, and `ReachabilityFence`. The
binding contains `FfiCall` and its ARM64 code executes `blr r9` as well.
