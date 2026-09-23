import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final builder = CBuilder.library(
      name: 'repro',
      assetName: 'repro.dart',
      sources: ['native/lib.c'],
    );
    await builder.run(input: input, output: output);
  });
}
