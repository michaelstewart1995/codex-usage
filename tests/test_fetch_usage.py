import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('reader', Path(__file__).parents[1] / 'scripts/fetch_usage.py')
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)


class UsageTests(unittest.TestCase):
    def test_multiple_buckets_override_legacy_and_missing_is_not_zero(self):
        result = reader.normalize({'rateLimits': {'primary': {'usedPercent': 99}}, 'rateLimitsByLimitId': {
            'other': {'primary': {'usedPercent': 120, 'windowDurationMins': 60}},
            'codex': {'primary': {'usedPercent': 81, 'windowDurationMins': 300},
                      'secondary': {'usedPercent': None}}}})
        self.assertEqual([w['remaining'] for w in result['windows']], [19, 0])
        self.assertEqual(result['windows'][0]['label'], '5-hour')
        self.assertIsNone(result['windows'][0]['resetsAt'])

    def test_account_details_are_not_exported(self):
        import json
        result = reader.normalize({'accountId': 'private-account', 'email': 'private@example.test',
            'rateLimitResetCredits': {'credits': [{'id': 'private-reset'}]},
            'rateLimits': {'credits': {'balance': 'private-balance'},
                           'primary': {'usedPercent': 10, 'windowDurationMins': 300}}})
        self.assertNotIn('private-', json.dumps(result))
        self.assertEqual(set(result), {'fetchedAt', 'windows'})

    def test_legacy(self):
        self.assertEqual(reader.normalize({'rateLimits': {'secondary': {
            'usedPercent': 13, 'windowDurationMins': 10080}}})['windows'][0]['remaining'], 87)

    def test_unavailable(self):
        with self.assertRaisesRegex(RuntimeError, 'No usage windows'):
            reader.normalize({'rateLimits': None})

    def mock_server(self, source):
        file = tempfile.NamedTemporaryFile(mode='w', delete=False)
        file.write('#!' + os.sys.executable + '\n' + source)
        file.close()
        os.chmod(file.name, 0o700)
        self.addCleanup(lambda: os.unlink(file.name))
        return patch.dict(os.environ, {'CODEX_BINARY': file.name})

    def test_handshake_and_notifications(self):
        with self.mock_server('''import json, sys
first = json.loads(sys.stdin.readline())
assert first['method'] == 'initialize'
print(json.dumps({'id': 1, 'result': {}}), flush=True)
assert json.loads(sys.stdin.readline())['method'] == 'initialized'
assert json.loads(sys.stdin.readline())['method'] == 'account/rateLimits/read'
print(json.dumps({'method': 'some/notification'}), flush=True)
print(json.dumps({'id': 2, 'result': {'rateLimits': {'primary': {'usedPercent': 42}}}}), flush=True)
sys.stdin.read()
'''):
            self.assertEqual(reader.fetch()['windows'][0]['remaining'], 58)

    def test_timeout(self):
        with self.mock_server('import time\ntime.sleep(10)\n'):
            with self.assertRaisesRegex(RuntimeError, 'timed out'):
                reader.fetch(timeout=0.1)


if __name__ == '__main__':
    unittest.main()
