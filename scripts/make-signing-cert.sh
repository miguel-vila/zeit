#!/bin/bash
# Creates the local code-signing identity that keeps Zeit's privacy grants
# across reinstalls. Run once per machine; running it again is a no-op.
#
# macOS stores a privacy grant as the designated requirement of the binary that
# was granted. An ad-hoc signature has no certificate to name, so the
# requirement is a hash of the binary, and every build invalidates it: the row
# stays in the privacy list, matches nothing, and System Settings ignores a
# drop of an app it already lists, so the dead row blocks every further grant.
# With a certificate the requirement names the certificate instead, and the
# next build still satisfies it.
#
# Self-signed is enough. The check is against the stored requirement, not
# against Apple's roots, so the certificate does not have to be trusted.
#
# Deleting this identity and making a new one invalidates the grants, because
# the requirement names this certificate.
set -e

IDENTITY="${1:-Zeit Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -qF "$IDENTITY"; then
    echo "Identity already present: $IDENTITY"
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
O  = Zeit
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null

# -legacy: the Security framework rejects the encryption OpenSSL 3 uses by default.
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -name "$IDENTITY" -passout pass:zeit

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P zeit -T /usr/bin/codesign

echo "Created identity: $IDENTITY"
echo "Certificate SHA-1: $(openssl x509 -in "$WORK/cert.pem" -outform der | shasum | awk '{print $1}')"
echo
echo "The first build may ask to use the key. Choose Always Allow."
