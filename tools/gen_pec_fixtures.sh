#!/bin/sh
# Test fixtures for PEC receipt signatures (core/src/pec.rs): a throwaway
# test CA, a provider certificate it issues, a certificate of another CA,
# and receipts signed with them. Nothing here is a real provider's; the
# keys are thrown away. Run from the repository root: sh tools/gen_pec_fixtures.sh
set -eu
out=core/tests/fixtures/pec
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

cat > ca.cnf <<'CNF'
[req]
distinguished_name = dn
prompt = no
[dn]
O = Piuma Test PEC CA
CN = Piuma Test PEC Root
[ca]
basicConstraints = critical,CA:true
keyUsage = critical,keyCertSign,cRLSign
[leaf]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature,nonRepudiation
subjectAltName = email:posta-certificata@pec.example.it
CNF

ca() { # name
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.pem" \
    -days 7300 -config ca.cnf -extensions ca -subj "/O=Piuma Test/CN=$1" 2>/dev/null
}
leaf() { # name issuer
  openssl req -new -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.csr" \
    -subj "/O=Piuma Test PEC Provider/CN=$1" 2>/dev/null
  openssl x509 -req -in "$1.csr" -CA "$2.pem" -CAkey "$2.key" -CAcreateserial \
    -out "$1.pem" -days 7300 -extfile ca.cnf -extensions leaf 2>/dev/null
}
ca test-root
ca other-root
leaf provider test-root
leaf stranger other-root

printf 'Content-Type: multipart/mixed; boundary="inner"\r\n\r\n--inner\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nRicevuta di avvenuta consegna\r\n\r\nIl giorno 19/10/2026 alle ore 09:12:04 (+0200) il messaggio\r\n"Lease renewal 2027" proveniente da "matteo@pec.example.it"\r\ned indirizzato a "studio.rossi@pec.example.it"\r\nè stato consegnato nella casella di destinazione.\r\n--inner--\r\n' > content.eml

sign() { # signer out
  {
    printf 'From: posta-certificata@pec.example.it\r\n'
    printf 'To: matteo@pec.example.it\r\n'
    printf 'Subject: CONSEGNA: Lease renewal 2027\r\n'
    printf 'X-Ricevuta: avvenuta-consegna\r\n'
    printf 'X-Riferimento-Message-ID: <opec1.20261019@pec.example.it>\r\n'
    openssl smime -sign -binary -crlfeol -md sha256 -in content.eml \
      -signer "$1.pem" -inkey "$1.key"
  } > "$2"
}
sign provider signed.eml
sign stranger stranger.eml

cp test-root.pem "$OLDPWD/$out/test-root.pem"
cp signed.eml "$OLDPWD/$out/signed.eml"
cp stranger.eml "$OLDPWD/$out/stranger.eml"
