#!/usr/bin/env python3
"""Build the 2026-11-19 patched OpenResty source archive.

Starts from the reviewed 2026-10-23 archive (nginx 1.31.8 in the fork's
openresty-1.29.2.3 layout), applies the public nginx 1.31.8 -> 1.31.9 delta and
swaps the Lua modules for the ones bundled in OpenResty 1.31.8.1.
Run from the repository root. Kong's own source patches are applied by Bazel.
"""
import hashlib
import pathlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES = {
    'nginx-1.31.8.tar.gz': ('https://nginx.org/download/nginx-1.31.8.tar.gz', '0652b760b3b772d2ec17b47c2fc15d9a95e6fe35cd5b877eadc1a62d9bc75af1'),
    'nginx-1.31.9.tar.gz': ('https://nginx.org/download/nginx-1.31.9.tar.gz', 'a11c5eeee2e257f4478f0e649f84b0040787d277d2d3e5233952aa6b6dcb80ad'),
    'openresty-1.31.8.1.tar.gz': ('https://openresty.org/download/openresty-1.31.8.1.tar.gz', 'b569c63b420f80a4ac8466f2deffe73ed93ab760026532e039c3658409a997f4'),
}
BASE = ROOT / 'vendor/openresty/openresty-1.29.2.3-nginx-1.31.8-sec20261023.tar.gz'

MODULES = {
    'LuaJIT-2.1-20260415': 'LuaJIT-2.1-20261023',
    'ngx_lua-0.10.31rc5': 'ngx_lua-0.10.32rc7',
    'ngx_stream_lua-0.0.19rc4': 'ngx_stream_lua-0.0.20rc3',
    'lua-resty-core-0.1.34rc3': 'lua-resty-core-0.1.35rc2',
    'lua-cjson-2.1.0.17': 'lua-cjson-2.1.0.20',
    'lua-resty-mysql-0.30': 'lua-resty-mysql-0.31',
    'resty-cli-0.32': 'resty-cli-0.36',
}


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def main():
    (ROOT / '.work').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=ROOT / '.work', prefix='repack-') as temp:
        work = pathlib.Path(temp)
        for filename, (url, digest) in SOURCES.items():
            data = urllib.request.urlopen(url, timeout=120).read()
            if hashlib.sha256(data).hexdigest() != digest:
                raise RuntimeError('SHA-256 mismatch: ' + filename)
            archive = work / filename
            archive.write_bytes(data)
            with tarfile.open(archive) as tf:
                tf.extractall(work, filter='data')
        # The base archive must be the committed one (no local edits).
        run('git', '-C', str(ROOT), 'diff', '--quiet', 'HEAD', '--', str(BASE.relative_to(ROOT)))
        with tarfile.open(BASE) as tf:
            tf.extractall(work, filter='data')
        tree = work / 'openresty-1.29.2.3'
        nginx = tree / 'bundle/nginx-1.29.2'
        delta = subprocess.run(['diff', '-ruN', 'nginx-1.31.8', 'nginx-1.31.9'], cwd=work, capture_output=True)
        if delta.returncode != 1:
            raise RuntimeError('Expected nginx source changes')
        header = nginx / 'src/core/nginx.h'
        fork_header = header.read_text()
        header.write_text((work / 'nginx-1.31.8/src/core/nginx.h').read_text())
        run('patch', '--batch', '-p1', '-d', str(nginx), input=delta.stdout)
        header.write_text(fork_header.replace('1031008', '1031009').replace('1.31.8', '1.31.9'))
        for path in tree.rglob('*'):
            if path.suffix in ('.orig', '.rej'):
                raise RuntimeError('Leftover patch file: ' + str(path))
        new = work / 'openresty-1.31.8.1/bundle'
        for old_name, new_name in MODULES.items():
            shutil.rmtree(tree / 'bundle' / old_name)
            shutil.copytree(new / new_name, tree / 'bundle' / new_name)
        configure = tree / 'configure'
        text = configure.read_text()
        for old_name, new_name in MODULES.items():
            text = text.replace(old_name, new_name)
        configure.write_text(text)
        shutil.copyfile(ROOT / 'security/20261119/SECURITY-SOURCES.txt', tree / 'SECURITY-SOURCES.txt')
        for directory in (p for p in tree.rglob('*') if p.is_dir()):
            directory.chmod(0o755)
        tree.chmod(0o755)
        target = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / 'vendor/openresty/openresty-1.29.2.3-nginx-1.31.9-sec20261119.tar.gz'
        run('tar', '--sort=name', '--mtime=2026-11-19 00:00:00Z', '--owner=0', '--group=0', '--numeric-owner', '-czf', str(target), '-C', str(work), tree.name)
        print(hashlib.sha256(target.read_bytes()).hexdigest(), target.name)


if __name__ == '__main__':
    main()
