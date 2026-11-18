#!/bin/sh
# Test fixtures for PEC receipt signatures (core/src/pec.rs, smime.rs): a
# throwaway test CA, certificates it issues (a provider's, a person's, one
# not allowed to sign), a certificate of another CA, and receipts signed
# with them. Nothing here is a real provider's; the keys are thrown away.
# Run from the repository root: sh tools/gen_pec_fixtures.sh
set -eu
out=core/tests/fixtures/pec
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

cat > ca.cnf <<'CNF'
[ca]
basicConstraints = critical,CA:true
keyUsage = critical,keyCertSign,cRLSign
[leaf]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature,nonRepudiation
extendedKeyUsage = emailProtection
subjectAltName = email:posta-certificata@pec.example.it
[nosign]
basicConstraints = critical,CA:false
keyUsage = critical,nonRepudiation
subjectAltName = email:posta-certificata@pec.example.it
CNF

ca() { # name
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.pem" \
    -days 7300 -subj "/O=Piuma Test/CN=$1" -addext "basicConstraints=critical,CA:true" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
}
leaf() { # name issuer organization extensions
  openssl req -new -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.csr" \
    -subj "/O=$3/CN=$1" 2>/dev/null
  openssl x509 -req -in "$1.csr" -CA "$2.pem" -CAkey "$2.key" -CAcreateserial \
    -out "$1.pem" -days 7300 -extfile ca.cnf -extensions "$4" 2>/dev/null
}
ca test-root
ca other-root
leaf provider test-root "Piuma Test PEC Provider" leaf
leaf person test-root "Mario Rossi" leaf
leaf nosign test-root "Piuma Test PEC Provider" nosign
leaf stranger other-root "Piuma Test PEC Provider" leaf

printf 'Content-Type: multipart/mixed; boundary="inner"\r\n\r\n--inner\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nRicevuta di avvenuta consegna\r\n\r\nIl giorno 19/10/2026 alle ore 09:12:04 (+0200) il messaggio\r\n"Lease renewal 2027" proveniente da "matteo@pec.example.it"\r\ned indirizzato a "studio.rossi@pec.example.it"\r\nè stato consegnato nella casella di destinazione.\r\n--inner--\r\n' > content.eml

sign() { # signer out digest
  {
    printf 'From: posta-certificata@pec.example.it\r\n'
    printf 'To: matteo@pec.example.it\r\n'
    printf 'Subject: CONSEGNA: Lease renewal 2027\r\n'
    printf 'X-Ricevuta: avvenuta-consegna\r\n'
    printf 'X-Riferimento-Message-ID: <opec1.20261019@pec.example.it>\r\n'
    openssl smime -sign -binary -crlfeol -md "$3" -in content.eml \
      -signer "$1.pem" -inkey "$1.key"
  } > "$2"
}
sign provider signed.eml sha256
sign provider sha1.eml sha1
sign person person.eml sha256
sign nosign nosign.eml sha256
sign stranger stranger.eml sha256
# The bare signature, for the parser's hostile-input test.
openssl smime -sign -binary -md sha256 -in content.eml -signer provider.pem \
  -inkey provider.key -outform DER -out signed.p7s

dest="$OLDPWD/$out"
cp test-root.pem signed.eml sha1.eml person.eml nosign.eml stranger.eml signed.p7s "$dest/"
