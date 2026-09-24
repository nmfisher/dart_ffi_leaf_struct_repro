// A leaf @Native call with a TypedData.address argument can produce null
// when it returns a struct or also converts a NativeFieldWrapperClass1 argument.
// Small (8 bytes) and Big (24 bytes) cover register and sret returns on arm64.
import 'dart:ffi';
import 'dart:io';
import 'dart:nativewrappers';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const asset = 'package:dart_ffi_leaf_struct_repro/repro.dart';

final class Small extends Struct {
  @Float()
  external double a;

  @Int32()
  external int c;
}

final class Big extends Struct {
  @Float()
  external double a;

  external Pointer<Char> b;

  @Int32()
  external int c;
}

@Native<Big Function(Pointer<Uint8>)>(
  assetId: asset,
  symbol: 'make_big_from_ptr',
  isLeaf: true,
)
external Big nativeBigFromAddressLeaf(Pointer<Uint8> x);

@Native<Small Function(Pointer<Uint8>)>(
  assetId: asset,
  symbol: 'make_small_from_ptr',
  isLeaf: true,
)
external Small nativeSmallFromAddressLeaf(Pointer<Uint8> x);

// NativeFieldWrapperClass1 arguments need an additional conversion wrapper.
@Native<Handle Function(Handle, IntPtr, IntPtr)>(
  symbol: 'Dart_SetNativeInstanceField',
)
external Object? setNativeField(Object peer, int index, int value);

base class Peer extends NativeFieldWrapperClass1 {
  Peer(Pointer<Uint8> storage) {
    setNativeField(this, 0, storage.address);
  }
}

@Native<Small Function(Pointer<Void>, Pointer<Uint8>)>(
  assetId: asset,
  symbol: 'make_small_from_peer',
  isLeaf: true,
)
external Small nativeSmallFromPeer(Peer peer, Pointer<Uint8> input);

@Native<Big Function(Pointer<Void>, Pointer<Uint8>)>(
  assetId: asset,
  symbol: 'make_big_from_peer',
  isLeaf: true,
)
external Big nativeBigFromPeer(Peer peer, Pointer<Uint8> input);

@Native<Int Function(Pointer<Void>, Pointer<Uint8>)>(
  assetId: asset,
  symbol: 'make_int_from_peer',
  isLeaf: true,
)
external int nativeIntFromPeer(Peer peer, Pointer<Uint8> input);

void main() {
  var failures = 0;

  void check(String label, bool Function() condition) {
    var ok = false;
    var detail = '';
    try {
      ok = condition();
    } catch (e) {
      detail = ' threw: $e';
    }
    print('${ok ? "PASS" : "FAIL"} $label$detail');
    if (!ok) failures++;
  }

  final list = Uint8List.fromList([9]);
  // Assign to Object? to make the unexpected null observable in JIT.
  check('@Native leaf + .address argument + big return (original failure)', () {
    final Object? s = nativeBigFromAddressLeaf(list.address);
    if (s == null) {
      print('  -> returned null');
      return false;
    }
    return s is Big && s.a == 9.0 && s.c == 42;
  });
  check('@Native leaf + .address argument + small return', () {
    final Object? s = nativeSmallFromAddressLeaf(list.address);
    if (s == null) {
      print('  -> returned null');
      return false;
    }
    return s is Small && s.a == 9.0 && s.c == 42;
  });

  // Keep the peer storage alive until all calls complete.
  final peerStorage = malloc<Uint8>()..value = 7;
  try {
    final peer = Peer(peerStorage);
    check('native-field argument + .address + small return', () {
      final data = Uint8List.fromList([9]);
      final Object? result = nativeSmallFromPeer(peer, data.address);
      if (result == null) {
        print('  -> returned null, input remains ${data[0]}');
        return false;
      }
      return result is Small &&
          result.a == 16 &&
          result.c == 42 &&
          data[0] == 10;
    });
    check('native-field argument + .address + big return', () {
      final data = Uint8List.fromList([9]);
      final Object? result = nativeBigFromPeer(peer, data.address);
      if (result == null) {
        print('  -> returned null, input remains ${data[0]}');
        return false;
      }
      return result is Big && result.a == 16 && result.c == 42 && data[0] == 10;
    });
    check('native-field argument + .address + int return', () {
      final data = Uint8List.fromList([9]);
      final Object? result = nativeIntFromPeer(peer, data.address);
      if (result == null) {
        print('  -> returned null, input remains ${data[0]}');
        return false;
      }
      return result == 58 && data[0] == 10;
    });
  } finally {
    malloc.free(peerStorage);
  }

  print(
    failures == 0
        ? 'All checks passed.'
        : '$failures check(s) failed - see above.',
  );
  exitCode = failures == 0 ? 0 : 1;
}
