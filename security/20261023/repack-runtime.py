#!/usr/bin/env python3
"""Recreate the patched source archive from the public source releases.

Run from the repository root. Source patches are applied by Bazel afterwards.
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
    'nginx-1.31.0.tar.gz': ('https://nginx.org/download/nginx-1.31.0.tar.gz', '6d5b00d45393af2e4e7c52a442d2a198f0ccbc7678ed062a46f403edd833ebaa'),
    'nginx-1.31.8.tar.gz': ('https://nginx.org/download/nginx-1.31.8.tar.gz', '0652b760b3b772d2ec17b47c2fc15d9a95e6fe35cd5b877eadc1a62d9bc75af1'),
    'openresty-1.31.1.1.tar.gz': ('https://openresty.org/download/openresty-1.31.1.1.tar.gz', '65b78baadd3f0984055de89bf13f4a1932e5bfe9c31932037a134ea2b1a0ce42'),
}
MODULES = {
    'LuaJIT-2.1-20260311': 'LuaJIT-2.1-20260415',
    'ngx_lua-0.10.30rc2': 'ngx_lua-0.10.31rc5',
    'ngx_stream_lua-0.0.18RC2': 'ngx_stream_lua-0.0.19rc4',
    'lua-resty-core-0.1.33rc2': 'lua-resty-core-0.1.34rc3',
    'lua-cjson-2.1.0.15': 'lua-cjson-2.1.0.17',
    'lua-resty-mysql-0.28': 'lua-resty-mysql-0.30',
    'resty-cli-0.32': 'resty-cli-0.32',
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
        original = ROOT / 'vendor/openresty/openresty-1.29.2.3-nginx-1.31.0-as1292.tar.gz'
        if hashlib.sha256(original.read_bytes()).hexdigest() != "2741aaa09d95dda7b884ff4210a9610e7d662027345f29becb06c9144c4510e5":
            raise RuntimeError("Original fork archive checksum mismatch")
        with tarfile.open(original) as tf:
            tf.extractall(work, filter='data')
        tree = work / 'openresty-1.29.2.3'
        nginx = tree / 'bundle/nginx-1.29.2'
        delta = subprocess.run(['diff', '-ruN', 'nginx-1.31.0', 'nginx-1.31.8'], cwd=work, capture_output=True)
        if delta.returncode != 1:
            raise RuntimeError('Expected nginx source changes')
        # The custom nginx.h identifies this fork as openresty/1.31.x.3.
        header = nginx / 'src/core/nginx.h'
        original_header = header.read_text()
        header.write_text((work / 'nginx-1.31.0/src/core/nginx.h').read_text())
        run('patch', '--batch', '-p1', '-d', str(nginx), input=delta.stdout)
        header.write_text(original_header.replace('1031000', '1031008').replace('1.31.0', '1.31.8'))
        for path in tree.rglob('*'):
            if path.suffix in ('.orig', '.rej'):
                path.unlink()
        new = work / 'openresty-1.31.1.1/bundle'
        for old_name, new_name in MODULES.items():
            shutil.rmtree(tree / 'bundle' / old_name)
            shutil.copytree(new / new_name, tree / 'bundle' / new_name)
        configure = tree / 'configure'
        text = configure.read_text()
        for old_name, new_name in MODULES.items():
            text = text.replace(old_name, new_name)
        configure.write_text(text)
        shutil.copyfile(ROOT / 'security/20261023/SECURITY-SOURCES.txt', tree / 'SECURITY-SOURCES.txt')
        for directory in (p for p in tree.rglob('*') if p.is_dir()):
            directory.chmod(0o755)
        tree.chmod(0o755)
        target = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / 'vendor/openresty/openresty-1.29.2.3-nginx-1.31.8-sec20261023.tar.gz'
        run('tar', '--sort=name', '--mtime=2026-10-22 15:00:00Z', '--owner=0', '--group=0', '--numeric-owner', '-czf', str(target), '-C', str(work), tree.name)
        print(hashlib.sha256(target.read_bytes()).hexdigest(), target.name)

if __name__ == '__main__':
    main()
