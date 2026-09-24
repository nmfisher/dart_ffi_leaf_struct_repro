#!/usr/bin/env python3
"""Dump FFI .address IL and disassembly using the installed Dart SDK."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
from urllib.parse import urljoin

parser = argparse.ArgumentParser(
    description=__doc__, formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument('--sdk-checkout', type=Path,
                    help='Optional fixed SDK source checkout for a buggy/fixed comparison')
parser.add_argument('--dart-sdk', type=Path,
                    help='Dart SDK installation; otherwise use dart on PATH')
parser.add_argument('--repro', type=Path, default=Path(__file__).resolve().parent,
                    help='Reproduction checkout')
parser.add_argument('--output', type=Path, default=Path('il_output'),
                    help='Output directory, relative to the current directory')
parser.add_argument('--repro-revision', help='Commit ID when --repro is a copy without .git')
parser.add_argument('--baseline', default='c979dd065b6b4a648858a940c7e4598fa2152209',
                    help='Baseline revision for --sdk-checkout comparisons')
args = parser.parse_args()
repro, out = [p.expanduser().resolve() for p in (args.repro, args.output)]
if args.dart_sdk:
    sdk = args.dart_sdk.expanduser().resolve()
    dart_path = sdk / 'bin/dart'
    if not dart_path.is_file():
        dart_path = sdk / 'bin/dart.exe'
    if not dart_path.is_file():
        parser.error(f'No Dart executable found in {sdk / "bin"}')
    dart = str(dart_path)
else:
    dart = shutil.which('dart')
    if dart is None:
        parser.error('Dart was not found on PATH; install it or provide --dart-sdk.')
    sdk = Path(dart).resolve().parent.parent
out.mkdir(parents=True, exist_ok=True)


def git_revision(directory):
    try:
        return subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=directory,
            stderr=subprocess.DEVNULL, text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


flags = [
    '--deterministic', '--no-background-compilation',
    '--print-flow-graph', '--print-flow-graph-optimized',
    '--disassemble', '--disassemble-optimized', '--disassemble-relative',
    '--print-flow-graph-filter=nativeBigFromAddressLeaf,nativeIntFromPeer',
]
metadata = {
    'reproduction': args.repro_revision or git_revision(repro),
    'vm': subprocess.check_output([dart, '--version'], stderr=subprocess.STDOUT, text=True).strip(),
    'capture_kind': 'JIT: Dart wrappers and FFI entry points',
    'reproduction_sha256': {p: hashlib.sha256((repro / p).read_bytes()).hexdigest()
                            for p in ['bin/repro.dart', 'native/lib.c']},
    'runs': {},
}


def capture(mode, command, compilation=None):
    with (out / (mode + '.log')).open('w') as log_file:
        result = subprocess.run(command, cwd=repro, stdout=log_file, stderr=subprocess.STDOUT)
    log = (out / (mode + '.log')).read_text()
    graphs = re.findall(r'\*\*\* BEGIN CFG\n.*?\*\*\* END CFG\n', log, re.S)
    graphs = [g for g in graphs if '_::_#' in g]
    assembly = re.findall(r"^Code for (?:optimized )?function '[^\n]+\{\n.*?^}\n", log, re.S | re.M)
    assembly = [a for a in assembly if '_::_#' in a.splitlines()[0]]
    (out / (mode + '.il.txt')).write_text('\n'.join(graphs))
    (out / (mode + '.asm.txt')).write_text('\n'.join(assembly))
    run = {'cwd': str(repro), 'command': command, 'exit_code': result.returncode,
           'pass_count': log.count('PASS '), 'fail_count': log.count('FAIL ')}
    if compilation:
        run.update(compilation)
    metadata['runs'][mode] = run
    (out / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    if not graphs or not assembly:
        raise SystemExit(f'{mode}: missing IL or disassembly; see {out / (mode + ".log")}')
    if result.returncode not in (0, 1) or run['pass_count'] + run['fail_count'] != 5:
        raise SystemExit(f'{mode}: reproduction did not complete; see {out / (mode + ".log")}')
    print(f'{mode}: {run["pass_count"]} pass, {run["fail_count"]} fail; '
          f'{len(graphs)} IL graphs and {len(assembly)} disassemblies saved to {out}')
    return result.returncode, run['pass_count'], run['fail_count'], len(graphs), len(assembly)


if args.sdk_checkout is None:
    # dart run resolves dependencies and builds the native code asset.
    # A buggy installed SDK is expected to run all five cases and exit 1.
    capture('current', [dart, *flags, 'run', str(repro / 'bin/repro.dart')])
    raise SystemExit(0)

checkout = args.sdk_checkout.expanduser().resolve()
config_path = checkout / '.dart_tool/package_config.json'
assets = repro / '.dart_tool/native_assets.yaml'
if not config_path.is_file():
    parser.error(f'Prepare the SDK checkout dependencies first: missing {config_path}')
if not assets.exists():
    parser.error('Run dart pub get and dart run bin/repro.dart in the reproduction first to generate native assets.')
work = out / 'work'
work.mkdir(exist_ok=True)

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
metadata.update({
    'baseline': args.baseline,
    'fixed': git_revision(checkout),
    'transformer_sha256': {
        'buggy': hashlib.sha256(baseline_source).hexdigest(),
        'fixed': hashlib.sha256((checkout / relative).read_bytes()).hexdigest(),
    },
})
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
    actual = capture(mode, [dart, *flags, str(dill)],
                     {'compile_cwd': str(checkout), 'compile_command': compile_command})
    expected = (1, 0, 5, 2, 2) if mode == 'buggy' else (0, 5, 0, 4, 4)
    if actual != expected:
        raise SystemExit(f'{mode}: unexpected capture results: {actual}; see {out}')
