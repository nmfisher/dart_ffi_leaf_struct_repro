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

@Native<Small Function(Int)>(assetId: asset, symbol: 'make_small', isLeaf: true)
external Small nativeSmallLeaf(int x);

@Native<Small Function(Int)>(assetId: asset, symbol: 'make_small')
external Small nativeSmallNonLeaf(int x);

@Native<Big Function(Int)>(assetId: asset, symbol: 'make_big', isLeaf: true)
external Big nativeBigLeaf(int x);

@Native<Big Function(Int)>(assetId: asset, symbol: 'make_big')
external Big nativeBigNonLeaf(int x);

@Native<Int Function(Big)>(assetId: asset, symbol: 'take_big', isLeaf: true)
external int nativeTakeBigLeaf(Big s);

@Native<Int Function(Big)>(assetId: asset, symbol: 'take_big')
external int nativeTakeBigNonLeaf(Big s);

@Native<Big Function(Pointer<Uint8>)>(
  assetId: asset,
  symbol: 'make_big_from_ptr',
  isLeaf: true,
)
external Big nativeBigFromAddressLeaf(Pointer<Uint8> x);

@Native<Int Function(Pointer<Uint8>)>(
  assetId: asset,
  symbol: 'make_int_from_ptr',
  isLeaf: true,
)
external int nativeIntFromAddressLeaf(Pointer<Uint8> x);

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
  final dylib = DynamicLibrary.open(
    File('build/libstruct.dylib').absolute.path,
  );
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

  // Small struct (register return).
  check('@Native non-leaf small return', () {
    final s = nativeSmallNonLeaf(9);
    return s.a == 9.0 && s.c == 42;
  });
  check('@Native leaf small return', () {
    final s = nativeSmallLeaf(9);
    return s.a == 9.0 && s.c == 42;
  });
  check('lookupFunction non-leaf small return', () {
    final f = dylib.lookupFunction<Small Function(Int), Small Function(int)>(
      'make_small',
      isLeaf: false,
    );
    final s = f(9);
    return s.a == 9.0 && s.c == 42;
  });
  check('lookupFunction leaf small return', () {
    final f = dylib.lookupFunction<Small Function(Int), Small Function(int)>(
      'make_small',
      isLeaf: true,
    );
    final s = f(9);
    return s.a == 9.0 && s.c == 42;
  });

  // Big struct (hidden-pointer return).
  check('@Native non-leaf big return', () {
    final s = nativeBigNonLeaf(9);
    return s.a == 9.0 && s.c == 42;
  });
  check('@Native leaf big return', () {
    final s = nativeBigLeaf(9);
    return s.a == 9.0 && s.c == 42;
  });
  check('lookupFunction non-leaf big return', () {
    final f = dylib.lookupFunction<Big Function(Int), Big Function(int)>(
      'make_big',
      isLeaf: false,
    );
    final s = f(9);
    return s.a == 9.0 && s.c == 42;
  });
  check('lookupFunction leaf big return', () {
    final f = dylib.lookupFunction<Big Function(Int), Big Function(int)>(
      'make_big',
      isLeaf: true,
    );
    final s = f(9);
    return s.a == 9.0 && s.c == 42;
  });

  // Struct by value as an argument (controls).
  final reference = nativeBigNonLeaf(9);
  check(
    '@Native non-leaf struct argument',
    () => nativeTakeBigNonLeaf(reference) == 51,
  );
  check(
    '@Native leaf struct argument',
    () => nativeTakeBigLeaf(reference) == 51,
  );
  check('lookupFunction leaf struct argument', () {
    final f = dylib.lookupFunction<Int Function(Big), int Function(Big)>(
      'take_big',
      isLeaf: true,
    );
    return f(reference) == 51;
  });

  final list = Uint8List.fromList([9]);
  check('leaf + .address argument + int return (control)', () {
    final v = nativeIntFromAddressLeaf(list.address);
    return v == 51;
  });
  check('@Native leaf + malloc pointer + big return (control)', () {
    final ptr = malloc<Uint8>(1)..[0] = 9;
    try {
      final s = nativeBigFromAddressLeaf(ptr);
      return s.a == 9.0 && s.c == 42;
    } finally {
      malloc.free(ptr);
    }
  });

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
  final input = malloc<Uint8>();
  try {
    final peer = Peer(peerStorage);
    check('native-field argument + malloc pointer + small return', () {
      input.value = 9;
      final result = nativeSmallFromPeer(peer, input);
      return result.a == 16 && result.c == 42 && input.value == 10;
    });
    check('native-field argument + malloc pointer + big return', () {
      input.value = 9;
      final result = nativeBigFromPeer(peer, input);
      return result.a == 16 && result.c == 42 && input.value == 10;
    });
    check('native-field argument + malloc pointer + int return', () {
      input.value = 9;
      return nativeIntFromPeer(peer, input) == 58 && input.value == 10;
    });
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
    malloc.free(input);
    malloc.free(peerStorage);
  }

  print(
    failures == 0
        ? 'All checks passed.'
        : '$failures check(s) failed - see above.',
  );
  exitCode = failures == 0 ? 0 : 1;
}
