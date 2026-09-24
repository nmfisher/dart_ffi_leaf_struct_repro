#!/usr/bin/env python3
"""Compile and dump the original and fixed FFI .address pathways on macOS arm64."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
from urllib.parse import urljoin

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sdk-checkout', type=Path, required=True)
parser.add_argument('--dart-sdk', type=Path, required=True)
parser.add_argument('--repro', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--repro-revision', help='Commit ID when --repro is a copy without .git')
parser.add_argument('--baseline', default='c979dd065b6b4a648858a940c7e4598fa2152209')
args = parser.parse_args()
checkout, sdk, repro, out = [p.resolve() for p in
    (args.sdk_checkout, args.dart_sdk, args.repro, args.output)]
out.mkdir(parents=True, exist_ok=True)
work = out / 'work'
work.mkdir(exist_ok=True)
dart = str(sdk / 'bin/dart')
config_path = checkout / '.dart_tool/package_config.json'
assets = repro / '.dart_tool/native_assets.yaml'
if not assets.exists():
    parser.error('Run ./run.sh in the reproduction first to generate native assets.')

# Clone only the compiler package. The checkout and reproduction stay unchanged.
old = work / 'vm-buggy'
for name in ['lib', 'bin']:
    shutil.copytree(checkout / 'pkg/vm' / name, old / name, dirs_exist_ok=True)
shutil.copyfile(checkout / 'pkg/vm/pubspec.yaml', old / 'pubspec.yaml')
relative = 'pkg/vm/lib/modular/transformations/ffi/use_sites.dart'
baseline_source = subprocess.check_output(
    ['git', 'show', args.baseline + ':' + relative], cwd=checkout)
(old / 'lib/modular/transformations/ffi/use_sites.dart').write_bytes(baseline_source)
config = json.loads(config_path.read_text())
for package in config['packages']:
    package['rootUri'] = urljoin(config_path.as_uri(), package['rootUri'])
    if package['name'] == 'vm':
        package['rootUri'] = old.as_uri() + '/'
before_config = work / 'buggy-packages.json'
before_config.write_text(json.dumps(config, indent=2))
flags = [
    '--deterministic', '--no-background-compilation',
    '--print-flow-graph', '--print-flow-graph-optimized',
    '--disassemble', '--disassemble-optimized', '--disassemble-relative',
    '--print-flow-graph-filter=nativeBigFromAddressLeaf,nativeIntFromPeer',
]
metadata = {
    'baseline': args.baseline,
    'fixed': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=checkout, text=True).strip(),
    'reproduction': args.repro_revision or subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=repro, text=True).strip(),
    'vm': subprocess.check_output([dart, '--version'], stderr=subprocess.STDOUT, text=True).strip(),
    'capture_kind': 'JIT: unoptimized Dart wrappers, optimized FFI entry points',
    'reproduction_sha256': {p: hashlib.sha256((repro / p).read_bytes()).hexdigest()
                            for p in ['bin/repro.dart', 'native/lib.c']},
    'transformer_sha256': {
        'buggy': hashlib.sha256(baseline_source).hexdigest(),
        'fixed': hashlib.sha256((checkout / relative).read_bytes()).hexdigest(),
    },
    'runs': {},
}
for mode in ['buggy', 'fixed']:
    driver = old if mode == 'buggy' else checkout / 'pkg/vm'
    compiler_config = before_config if mode == 'buggy' else config_path
    dill = work / (mode + '.dill')
    compile_command = [dart, '--packages=' + str(compiler_config),
        str(driver / 'bin/gen_kernel.dart'),
        '--platform', str(sdk / 'lib/_internal/vm_platform.dill'),
        '--packages', str(repro / '.dart_tool/package_config.json'),
        '--native-assets', str(assets), '-o', str(dill), str(repro / 'bin/repro.dart')]
    subprocess.run(compile_command, cwd=checkout, check=True)
    run_command = [dart, *flags, str(dill)]
    with (out / (mode + '.log')).open('w') as log_file:
        result = subprocess.run(run_command, cwd=repro, stdout=log_file, stderr=subprocess.STDOUT)
    log = (out / (mode + '.log')).read_text()
    graphs = re.findall(r'\*\*\* BEGIN CFG\n.*?\*\*\* END CFG\n', log, re.S)
    graphs = [g for g in graphs if '_::_#' in g]
    assembly = re.findall(r"^Code for (?:optimized )?function '[^\n]+\{\n.*?^}\n", log, re.S | re.M)
    assembly = [a for a in assembly if '_::_#' in a.splitlines()[0]]
    (out / (mode + '.il.txt')).write_text('\n'.join(graphs))
    (out / (mode + '.asm.txt')).write_text('\n'.join(assembly))
    metadata['runs'][mode] = {'compile_cwd': str(checkout), 'compile_command': compile_command,
        'cwd': str(repro), 'command': run_command, 'exit_code': result.returncode,
        'pass_count': log.count('PASS '), 'fail_count': log.count('FAIL ')}
    (out / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    expected = (1, 16, 5, 2) if mode == 'buggy' else (0, 21, 0, 4)
    actual = (result.returncode, log.count('PASS '), log.count('FAIL '), len(graphs))
    if actual != expected or len(assembly) != len(graphs):
        raise SystemExit(f'{mode}: unexpected capture results: {actual}; see {out}')
    print(f'{mode}: exit {result.returncode}; {len(graphs)} IL graphs and disassemblies captured')
