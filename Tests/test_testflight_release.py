"""Deterministic source guards for the manual TestFlight path; not native signing tests."""
from pathlib import Path
import importlib.util
import datetime as dt
import os
import plistlib
import re
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'tools/testflight_release.py'
spec = importlib.util.spec_from_file_location('testflight_release', SCRIPT)
assert spec is not None and spec.loader is not None
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

ROOT = Path(__file__).resolve().parents[1]


class TestFlightReleaseSourceTests(unittest.TestCase):
    def test_release_team_matches_yanuseu_account(self):
        self.assertEqual(release.TEAM, '2CH5J3W7UH')
        self.assertIn('DEVELOPMENT_TEAM=2CH5J3W7UH', (ROOT / '.github/workflows/testflight.yml').read_text())

    def test_dispatch_is_manual_pinned_and_gated_before_signing(self):
        text = (ROOT / '.github/workflows/testflight.yml').read_text()
        self.assertIn('workflow_dispatch:', text)
        self.assertNotRegex(text, r'(?m)^  (push|pull_request|schedule):')
        self.assertRegex(text, r'actions/checkout@[0-9a-f]{40}')
        self.assertIn('gate-ci', text)
        self.assertIn('needs: gate-ci', text)
        gate = text.split('  gate-ci:', 1)[1].split('  distribute:', 1)[0]
        self.assertIn("if: github.ref == 'refs/heads/main'", gate)
        self.assertNotIn('actions/checkout', gate)
        self.assertNotIn('tools/testflight_release.py', gate)
        self.assertIn("get('/git/ref/heads/main')", gate)
        self.assertIn('CODE_SIGNING_ALLOWED=NO', (ROOT / '.github/workflows/ios.yml').read_text())
        self.assertIn("python3 -m unittest discover -s Tests -p 'test_*.py'", (ROOT / '.github/workflows/ios.yml').read_text())
        self.assertIn('gate-ci', (ROOT / 'tools/testflight_release.py').read_text())
        self.assertIn('head_sha', (ROOT / 'tools/testflight_release.py').read_text())
        self.assertIn('conclusion', (ROOT / 'tools/testflight_release.py').read_text())

    def test_signing_and_export_are_explicit_and_cleaned(self):
        text = (ROOT / '.github/workflows/testflight.yml').read_text()
        for token in ('xcodebuild archive', 'xcodebuild -exportArchive',
                      'altool --validate-app', 'altool --upload-app',
                      'trap cleanup EXIT', 'security delete-keychain',
                      'APP_DISTRIBUTION_P12_BASE64', 'APP_DISTRIBUTION_P12_PASSWORD',
                      'YANUSEU_APP_PROFILE_BASE64', 'ASC_API_KEY_ID',
                      'ASC_API_ISSUER_ID', 'ASC_API_PRIVATE_KEY_P8',
                      'verify-ipa', 'verify-archive', 'preflight'):
            self.assertIn(token, text)
        self.assertLess(text.index('check-identity'), text.index('xcodebuild archive'))
        self.assertLess(text.index('verify-archive'), text.index('xcodebuild -exportArchive'))
        self.assertLess(text.index('verify-ipa'), text.index('altool --validate-app'))
        self.assertLess(text.index('altool --validate-app'), text.index('altool --upload-app'))
        self.assertNotRegex(text.split('jobs:', 1)[1].split('steps:', 1)[0], r'(?m)^    env:')
        for name in ('version', 'build_number', 'commit_sha'):
            self.assertRegex(text, rf'(?m)^      {name}:')

    def test_project_declares_release_archive_and_version(self):
        text = (ROOT / 'project.yml').read_text()
        for token in ('MARKETING_VERSION:', 'CURRENT_PROJECT_VERSION:',
                      'CODE_SIGN_STYLE: Manual', 'archive:', 'config: Release',
                      'PRODUCT_BUNDLE_IDENTIFIER: cool.n0thing.yanuseu'):
            self.assertIn(token, text)


class ReleaseValidationTests(unittest.TestCase):
    def test_inputs_reject_malformed_sha_and_build(self):
        for sha, version, build in [('main', '1.2.3', '4'), ('a' * 40, 'v1.2', '4'),
                                    ('a' * 40, '1.2', '0'), ('a' * 40, '1.2', '1; echo bad')]:
            with self.subTest(sha=sha, version=version, build=build):
                with self.assertRaises(ValueError):
                    release.validate_inputs(sha, version, build)
        release.validate_inputs('a' * 40, '1.2.3', '4')

    def test_missing_secrets_fail_closed(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, 'Missing GitHub Actions secrets'):
                release.preflight()

    def test_profile_rejects_wrong_bundle_or_development_entitlements(self):
        profile = {'TeamIdentifier': [release.TEAM], 'UUID': 'fixture-uuid',
                   'ExpirationDate': dt.datetime.now(dt.timezone.utc).replace(tzinfo=None) + dt.timedelta(days=1),
                   'DeveloperCertificates': [b'fixture-cert'],
                   'Entitlements': {'application-identifier': release.TEAM + '.' + release.BUNDLE,
                                    'com.apple.developer.team-identifier': release.TEAM,
                                    'get-task-allow': False}}
        with patch.object(release, 'command', return_value=plistlib.dumps(profile)):
            data, certs = release.profile_info('fixture')
            self.assertEqual(data['UUID'], 'fixture-uuid')
            self.assertEqual(len(certs), 1)
        for alteration in ({'get-task-allow': True},
                           {'application-identifier': release.TEAM + '.other.app'}):
            bad = dict(profile)
            bad['Entitlements'] = {**profile['Entitlements'], **alteration}
            with patch.object(release, 'command', return_value=plistlib.dumps(bad)):
                with self.assertRaises(ValueError):
                    release.profile_info('fixture')

    def test_gate_requires_matching_sha_successful_unsigned_workflow(self):
        sha = 'a' * 40
        def invalid_runs(url, token):
            if '/git/ref/heads/main' in url:
                return {'object': {'sha': sha}}
            return {'workflow_runs': [
                {'head_sha': 'b' * 40, 'conclusion': 'success', 'event': 'push', 'head_branch': 'main'},
                {'head_sha': sha, 'conclusion': 'failure', 'event': 'push', 'head_branch': 'main'},
                {'head_sha': sha, 'conclusion': 'success', 'event': 'pull_request', 'head_branch': 'main'}]}
        with patch.object(release, 'api_get', side_effect=invalid_runs) as api:
            with self.assertRaisesRegex(ValueError, 'No successful unsigned iOS CI'):
                release.gate_ci('owner/repo', sha, 'token')
            self.assertTrue(any('/actions/workflows/ios.yml/runs?' in call.args[0] for call in api.call_args_list))
        with patch.object(release, 'api_get', return_value={'workflow_runs': [
                {'head_sha': sha, 'conclusion': 'success', 'event': 'push', 'head_branch': 'main'}]}):
            with self.assertRaisesRegex(ValueError, 'main'):
                release.gate_ci('owner/repo', sha, 'token')
        def main_and_ci(url, token):
            if '/git/ref/heads/main' in url:
                return {'object': {'sha': sha}}
            return {'workflow_runs': [{'head_sha': sha, 'conclusion': 'success',
                                       'event': 'push', 'head_branch': 'main'}]}
        with patch.object(release, 'api_get', side_effect=main_and_ci):
            release.gate_ci('owner/repo', sha, 'token')


if __name__ == '__main__':
    unittest.main()
