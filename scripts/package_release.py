#!/usr/bin/env python3
"""Package only explicit release files; reject local paths and unexpected bundle files."""
from pathlib import Path
import hashlib
import plistlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'build' / 'Codex Usage.app'
ALLOWED = {
    'Contents/MacOS/CodexUsage', 'Contents/Resources/fetch_usage.py',
    'Contents/Resources/AppIcon.icns', 'Contents/Info.plist',
    'Contents/_CodeSignature/CodeResources',
}


def main():
    actual = {str(p.relative_to(APP)) for p in APP.rglob('*') if p.is_file()}
    if actual != ALLOWED:
        raise RuntimeError(f'Unexpected or missing bundle files: {actual ^ ALLOWED}')
    info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
    assert 'UsagePythonPath' not in info
    sources = ['LICENSE', 'README.md', 'SHARING.md', '.gitignore', 'build.sh', 'install.sh',
               'Sources/main.swift', 'scripts/fetch_usage.py', 'scripts/package_release.py',
               'tests/test_fetch_usage.py', 'Assets/AppIcon.png']
    app_files = [(APP / p, f'Codex Usage.app/{p}') for p in sorted(ALLOWED)]
    app_files.append((ROOT / 'SHARING.md', 'READ ME.md'))
    app_files.append((ROOT / 'LICENSE', 'LICENSE'))
    source_files = [(ROOT / p, f'CodexUsage/{p}') for p in sources]
    # Scan actual content, including executable strings; zip excludes filesystem xattrs.
    for file, _ in app_files + source_files:
        assert not file.is_symlink(), f'Symlink not allowed: {file}'
        data = file.read_bytes()
        for forbidden in (str(Path.home()).encode(), b'/' + b'Users' + b'/', b'/' + b'private/var/' + b'folders/', b'-----BEGIN ' + b'PRIVATE KEY-----'):
            if forbidden in data:
                raise RuntimeError(f'Private path or key marker in {file.name}')
    output = ROOT / 'dist'
    output.mkdir(exist_ok=True)
    for name, files in [('Codex-Usage-1.1-macOS.zip', app_files), ('Codex-Usage-1.1-source.zip', source_files)]:
        path = output / name
        with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as archive:
            for source, destination in files:
                entry = zipfile.ZipInfo(destination, date_time=(2026, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = (0o100755 if source.name in ('CodexUsage', 'build.sh', 'install.sh') else 0o100644) << 16
                archive.writestr(entry, source.read_bytes(), compress_type=zipfile.ZIP_DEFLATED)
        with zipfile.ZipFile(path) as archive:
            assert archive.testzip() is None
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        (output / (name + '.sha256')).write_text(f'{digest}  {name}\n')
        print(f'Created and audited {path.name}')


if __name__ == '__main__':
    main()
