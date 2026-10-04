"""Verify recorded migration archive integrity; never connects to a database."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'supabase' / 'recovery'
manifest = json.loads((root / 'manifest.json').read_text())
expected = {item['file']: item for item in manifest['files']}
actual = {path.name for path in (root / 'history').glob('*.sql')}
if actual != set(expected):
    raise SystemExit(f'Archive file mismatch: missing={set(expected)-actual}, extra={actual-set(expected)}')
for name, item in expected.items():
    content = (root / 'history' / name).read_bytes()
    if len(content) != item['bytes'] or hashlib.sha256(content).hexdigest() != item['sha256']:
        raise SystemExit(f'Archive checksum mismatch: {name}')
if len(expected) != manifest['record_count']:
    raise SystemExit('Archive record count mismatch')
print(f'PASS: {len(expected)} migration files match the recovery manifest. Restore NOT tested.')
