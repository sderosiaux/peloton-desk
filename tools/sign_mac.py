"""Keep a stable local signing identity across companion rebuilds.

The private keychain is project-local and is never added to the login keychain
or trusted as a system CA. A configured Developer ID can be used instead.
"""
import hashlib
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / '.local/signing'


def run(*args):
    result = subprocess.run([str(arg) for arg in args], capture_output=True)
    if result.returncode:
        # Keychain commands carry credentials. Do not include arguments in errors.
        raise RuntimeError('Local signing failed at ' + Path(str(args[0])).name + ': ' + result.stderr.decode(errors='replace').strip())
    return result.stdout


def sign(app):
    identity = os.environ.get('PELOTON_DESK_SIGN_IDENTITY')
    if identity:
        run('codesign', '--force', '--sign', identity, app)
        return
    DIRECTORY.mkdir(mode=0o700, parents=True, exist_ok=True)
    DIRECTORY.chmod(0o700)
    keychain = DIRECTORY / 'identity.keychain-db'
    password_file = DIRECTORY / 'password'
    if not keychain.exists():
        password = secrets.token_urlsafe(32)
        password_file.write_text(password)
        password_file.chmod(0o600)
        config = DIRECTORY / 'certificate.cnf'
        config.write_text('''[req]
 distinguished_name = subject
 x509_extensions = extensions
 prompt = no
[subject]
 CN = Peloton Desk Local Development
[extensions]
 basicConstraints = critical,CA:false
 keyUsage = critical,digitalSignature
 extendedKeyUsage = critical,codeSigning
 subjectKeyIdentifier = hash
''')
        key, certificate, archive = (DIRECTORY / name for name in ('private.pem', 'certificate.pem', 'identity.p12'))
        old_mask = os.umask(0o077)
        search_list = shlex.split(run('security', 'list-keychains', '-d', 'user').decode())
        try:
            run('openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-days', '3650',
                '-config', config, '-keyout', key, '-out', certificate)
            run('openssl', 'pkcs12', '-export', '-inkey', key, '-in', certificate, '-out', archive,
                '-passout', 'file:' + str(password_file), '-keypbe', 'PBE-SHA1-3DES', '-certpbe', 'PBE-SHA1-3DES', '-macalg', 'sha1')
            run('security', 'create-keychain', '-p', password, keychain)
            run('security', 'unlock-keychain', '-p', password, keychain)
            run('security', 'import', archive, '-k', keychain, '-P', password, '-T', '/usr/bin/codesign')
            run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, keychain)
        finally:
            run('security', 'list-keychains', '-d', 'user', '-s', *search_list)
            for path in (key, archive): path.unlink(missing_ok=True)
            os.umask(old_mask)
    password = password_file.read_text()
    certificate = run('openssl', 'x509', '-in', DIRECTORY / 'certificate.pem', '-outform', 'DER')
    fingerprint = hashlib.sha1(certificate).hexdigest().upper()
    run('security', 'unlock-keychain', '-p', password, keychain)
    search_list = shlex.split(run('security', 'list-keychains', '-d', 'user').decode())
    try:
        # codesign also needs the identity in the search list while signing.
        run('security', 'list-keychains', '-d', 'user', '-s', *search_list, keychain)
        run('codesign', '--force', '--sign', fingerprint, '--keychain', keychain, app)
        run('codesign', '--verify', '--strict', app)
    finally:
        run('security', 'list-keychains', '-d', 'user', '-s', *search_list)
        run('security', 'lock-keychain', keychain)


if __name__ == '__main__':
    try:
        sign(Path(sys.argv[1]))
    except RuntimeError as error:
        raise SystemExit(str(error)) from None
