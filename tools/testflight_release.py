#!/usr/bin/env python3
"""Fail-closed checks for the manual, single-target Yanuseu App Store export.

This script does not replace Xcode signing or Apple's server-side validation.
"""
import argparse
import base64
import binascii
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
import zipfile

BUNDLE = 'cool.n0thing.yanus'
TEAM = 'VYJS7JMXU5'
REQUIRED_SECRETS = ('APP_DISTRIBUTION_P12_BASE64', 'APP_DISTRIBUTION_P12_PASSWORD',
                    'YANUSEU_APP_PROFILE_BASE64', 'ASC_API_KEY_ID',
                    'ASC_API_ISSUER_ID', 'ASC_API_PRIVATE_KEY_P8')


def fail(message):
    raise ValueError(message)


def validate_inputs(sha, version, build):
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        fail('commit_sha must be an exact lowercase 40-character git SHA')
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}', version):
        fail('version must be numeric major.minor[.patch]')
    if not re.fullmatch(r'[1-9][0-9]*', build):
        fail('build_number must be a positive decimal integer; check ASC for collisions')


def preflight():
    missing = [key for key in REQUIRED_SECRETS if not os.environ.get(key, '').strip()]
    if missing:
        fail('Missing GitHub Actions secrets: ' + ', '.join(missing))
    for key in ('APP_DISTRIBUTION_P12_BASE64', 'YANUSEU_APP_PROFILE_BASE64'):
        try:
            if not base64.b64decode(os.environ[key], validate=True):
                fail(key + ' is empty after base64 decode')
        except (ValueError, binascii.Error):
            fail(key + ' must be nonempty strict base64')
    if not re.fullmatch(r'[A-Z0-9]{10}', os.environ['ASC_API_KEY_ID']):
        fail('ASC_API_KEY_ID must be a 10-character Key ID')
    if not re.fullmatch(r'[0-9a-fA-F-]{36}', os.environ['ASC_API_ISSUER_ID']):
        fail('ASC_API_ISSUER_ID must be a UUID')
    if not re.fullmatch(r'-----BEGIN PRIVATE KEY-----\s+.+\s+-----END PRIVATE KEY-----\s*',
                        os.environ['ASC_API_PRIVATE_KEY_P8'], re.S):
        fail('ASC_API_PRIVATE_KEY_P8 must contain the complete PEM private key')


def api_get(url, token):
    request = urllib.request.Request(url, headers={
        'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28'})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def gate_ci(repository, sha, token):
    if not re.fullmatch(r'[\w.-]+/[\w.-]+', repository) or not token:
        fail('GITHUB_REPOSITORY and a token with actions:read are required')
    main_ref = api_get('https://api.github.com/repos/' + repository + '/git/ref/heads/main', token)
    if main_ref.get('object', {}).get('sha') != sha:
        fail('TestFlight commit must equal the current main SHA')
    # Query the actual unsigned workflow, never a check from another workflow or ref.
    url = ('https://api.github.com/repos/' + repository + '/actions/workflows/ios.yml/runs?'
           + urllib.parse.urlencode({'head_sha': sha, 'status': 'success', 'per_page': 100}))
    data = api_get(url, token)
    runs = data.get('workflow_runs', [])
    if not any(r.get('head_sha') == sha and r.get('conclusion') == 'success'
               and r.get('head_branch') == 'main'
               and r.get('event') in ('push', 'workflow_dispatch') for r in runs):
        fail('No successful unsigned iOS CI push/dispatch run for exact SHA ' + sha)


def command(*args):
    return subprocess.check_output(args, stderr=subprocess.PIPE)


def profile_info(path):
    data = plistlib.loads(command('security', 'cms', '-D', '-i', str(path)))
    ent = data['Entitlements']
    if TEAM not in data.get('TeamIdentifier', []) or ent.get('application-identifier') != TEAM + '.' + BUNDLE:
        fail('Provisioning profile does not match Yanuseu bundle ID and team')
    if ent.get('com.apple.developer.team-identifier') != TEAM or ent.get('get-task-allow') is not False:
        fail('Provisioning profile must be an App Store distribution profile for the team')
    if data['ExpirationDate'].replace(tzinfo=dt.timezone.utc) <= dt.datetime.now(dt.timezone.utc):
        fail('Provisioning profile is expired')
    if 'ProvisionedDevices' in data or 'ProvisionsAllDevices' in data:
        fail('Development/Ad Hoc/Enterprise profile cannot export to TestFlight')
    certs = {hashlib.sha1(cert).hexdigest().upper() for cert in data['DeveloperCertificates']}
    if not certs:
        fail('Provisioning profile has no distribution certificate')
    return data, certs


def check_identity(profile, keychain):
    _, certs = profile_info(profile)
    identities = command('security', 'find-identity', '-v', '-p', 'codesigning', str(keychain)).decode()
    if not any(re.search(r'\b' + cert + r'\b.*Apple Distribution', identities) for cert in certs):
        fail('Imported Apple Distribution identity does not match the provisioning profile')


def export_options(path, profile):
    data, _ = profile_info(profile)
    options = {'method': 'app-store-connect', 'destination': 'export',
               'signingStyle': 'manual', 'teamID': TEAM,
               'provisioningProfiles': {BUNDLE: data['UUID']},
               'stripSwiftSymbols': True}
    Path(path).write_bytes(plistlib.dumps(options))


def verify_app(app, version, build, intended_profile):
    app = Path(app)
    if not app.is_dir() or list((app / 'PlugIns').glob('*.appex')):
        fail('Expected exactly one Yanuseu app with no unprovisioned extensions')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if (info.get('CFBundleIdentifier'), info.get('CFBundleShortVersionString'),
            str(info.get('CFBundleVersion'))) != (BUNDLE, version, build):
        fail('Signed app bundle ID/version/build does not match dispatch inputs')
    profile, certs = profile_info(app / 'embedded.mobileprovision')
    original, _ = profile_info(intended_profile)
    if profile['UUID'] != original['UUID']:
        fail('Signed app embeds a different provisioning profile than the supplied Yanuseu profile')
    command('codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app))
    with tempfile.TemporaryDirectory() as cert_dir:
        subprocess.run(['codesign', '-d', '--extract-certificates', str(app)],
                       cwd=cert_dir, capture_output=True, check=True)
        leaf = Path(cert_dir) / 'codesign0'
        if not leaf.is_file() or hashlib.sha1(leaf.read_bytes()).hexdigest().upper() not in certs:
            fail('Signed app leaf certificate does not match embedded distribution profile')
    detail = subprocess.run(['codesign', '-dv', '--verbose=4', str(app)],
                            capture_output=True, text=True, check=True)
    if 'TeamIdentifier=' + TEAM not in detail.stderr:
        fail('Signed app TeamIdentifier does not match intended team')
    ent = plistlib.loads(command('codesign', '-d', '--entitlements', ':-', str(app)))
    expected = profile['Entitlements']
    for key in ('application-identifier', 'com.apple.developer.team-identifier', 'get-task-allow'):
        if ent.get(key) != expected.get(key):
            fail('Signed entitlement does not match embedded distribution profile: ' + key)
    if ent.get('get-task-allow') is not False:
        fail('Signed app is debuggable')


def verify_ipa(path, version, build, intended_profile):
    with tempfile.TemporaryDirectory() as temp:
        with zipfile.ZipFile(path) as archive:
            for name in archive.namelist():
                parts = Path(name).parts
                if name.startswith('/') or '..' in parts:
                    fail('Unsafe IPA archive entry')
            archive.extractall(temp)
        apps = list((Path(temp) / 'Payload').glob('*.app'))
        if len(apps) != 1 or apps[0].name != 'Yanuseu.app':
            fail('IPA must contain exactly Payload/Yanuseu.app')
        verify_app(apps[0], version, build, intended_profile)


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='action', required=True)
    p = sub.add_parser('inputs')
    p.add_argument('sha'); p.add_argument('version'); p.add_argument('build')
    p = sub.add_parser('gate-ci')
    p.add_argument('repository'); p.add_argument('sha')
    sub.add_parser('preflight')
    for action, args in [('check-identity', ('profile', 'keychain')),
                         ('export-options', ('output', 'profile')),
                         ('verify-archive', ('app', 'version', 'build', 'profile')),
                         ('verify-ipa', ('ipa', 'version', 'build', 'profile'))]:
        p = sub.add_parser(action)
        for arg in args: p.add_argument(arg)
    args = parser.parse_args()
    try:
        if args.action == 'inputs': validate_inputs(args.sha, args.version, args.build)
        elif args.action == 'gate-ci': gate_ci(args.repository, args.sha, os.environ.get('GH_TOKEN', ''))
        elif args.action == 'preflight': preflight()
        elif args.action == 'check-identity': check_identity(args.profile, args.keychain)
        elif args.action == 'export-options': export_options(args.output, args.profile)
        elif args.action == 'verify-archive': verify_app(args.app, args.version, args.build, args.profile)
        elif args.action == 'verify-ipa': verify_ipa(args.ipa, args.version, args.build, args.profile)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as exc:
        print('TestFlight preflight/verification failed: ' + str(exc), file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
