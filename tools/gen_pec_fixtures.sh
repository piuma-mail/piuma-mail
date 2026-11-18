#!/bin/sh
# Test fixtures for PEC receipt signatures (core/src/pec.rs, smime.rs): a
# throwaway test CA standing in for a qualified CA of TSL-IT, certificates
# it issues (a provider's, a person's, one not allowed to sign), a
# certificate of another CA, a stand-in for AgID's PEC network CA under a
# stand-in Actalis root (and one issued by that root directly), and
# receipts signed with them. Also two chains with more than one candidate
# issuer: a CA certified twice, first by a CA under another root (a dead
# end), then by the test CA; and two CAs certifying each other (a loop).
# Nothing here is a real provider's; the keys are thrown away.
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
[subca]
basicConstraints = critical,CA:true,pathlen:0
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
subca() { # name issuer
  openssl req -new -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.csr" \
    -subj "/O=Piuma Test/CN=$1" 2>/dev/null
  openssl x509 -req -in "$1.csr" -CA "$2.pem" -CAkey "$2.key" -CAcreateserial \
    -out "$1.pem" -days 7300 -extfile ca.cnf -extensions subca 2>/dev/null
}
ca test-root
ca other-root
ca actalis-root
subca agid-pec-ca actalis-root
leaf pecnet agid-pec-ca "Piuma Test PEC Provider" leaf
# A CA renewed with the same name and key: the old copy expires in a day.
openssl req -new -newkey rsa:2048 -nodes -keyout renewed-ca.key -out renewed-ca.csr \
  -subj "/O=Piuma Test/CN=renewed-ca" 2>/dev/null
openssl x509 -req -in renewed-ca.csr -CA test-root.pem -CAkey test-root.key -CAcreateserial \
  -out renewed-ca-old.pem -days 1 -extfile ca.cnf -extensions subca 2>/dev/null
openssl x509 -req -in renewed-ca.csr -CA test-root.pem -CAkey test-root.key -CAcreateserial \
  -out renewed-ca.pem -days 7300 -extfile ca.cnf -extensions subca 2>/dev/null
cat renewed-ca-old.pem renewed-ca.pem > renewed-chain.pem
leaf renewed renewed-ca "Piuma Test PEC Provider" leaf
# A CA certified twice with the same name and key: by a CA under another
# root (tried first, leads nowhere) and by the test CA.
openssl req -new -newkey rsa:2048 -nodes -keyout other-sub.key -out other-sub.csr \
  -subj "/O=Piuma Test/CN=other-sub" 2>/dev/null
openssl x509 -req -in other-sub.csr -CA other-root.pem -CAkey other-root.key -CAcreateserial \
  -out other-sub.pem -days 7300 -extfile ca.cnf -extensions ca 2>/dev/null
openssl req -new -newkey rsa:2048 -nodes -keyout cross-ca.key -out cross-ca.csr \
  -subj "/O=Piuma Test/CN=cross-ca" 2>/dev/null
openssl x509 -req -in cross-ca.csr -CA other-sub.pem -CAkey other-sub.key -CAcreateserial \
  -out cross-ca-stray.pem -days 7300 -extfile ca.cnf -extensions ca 2>/dev/null
openssl x509 -req -in cross-ca.csr -CA test-root.pem -CAkey test-root.key -CAcreateserial \
  -out cross-ca.pem -days 7300 -extfile ca.cnf -extensions ca 2>/dev/null
leaf cross cross-ca "Piuma Test PEC Provider" leaf
cat cross-ca-stray.pem other-sub.pem cross-ca.pem > cross-carried.pem
cat cross.pem cross-carried.pem > cross-chain.pem
# Two CAs certifying each other, and nothing else: a loop.
for n in loop-a loop-b; do
  openssl req -new -newkey rsa:2048 -nodes -keyout "$n.key" -out "$n.csr" \
    -subj "/O=Piuma Test/CN=$n" 2>/dev/null
  openssl x509 -req -in "$n.csr" -signkey "$n.key" -out "$n.pem" -days 7300 \
    -extfile ca.cnf -extensions ca 2>/dev/null
done
openssl x509 -req -in loop-a.csr -CA loop-b.pem -CAkey loop-b.key -CAcreateserial \
  -out loop-a-by-b.pem -days 7300 -extfile ca.cnf -extensions ca 2>/dev/null
openssl x509 -req -in loop-b.csr -CA loop-a.pem -CAkey loop-a.key -CAcreateserial \
  -out loop-b-by-a.pem -days 7300 -extfile ca.cnf -extensions ca 2>/dev/null
leaf looped loop-a "Piuma Test PEC Provider" leaf
cat looped.pem loop-a-by-b.pem loop-b-by-a.pem > loop-chain.pem
leaf rootonly actalis-root "Piuma Test PEC Provider" leaf
leaf provider test-root "Piuma Test PEC Provider" leaf
leaf person test-root "Mario Rossi" leaf
leaf nosign test-root "Piuma Test PEC Provider" nosign
leaf stranger other-root "Piuma Test PEC Provider" leaf

printf 'Content-Type: multipart/mixed; boundary="inner"\r\n\r\n--inner\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nRicevuta di avvenuta consegna\r\n\r\nIl giorno 19/10/2026 alle ore 09:12:04 (+0200) il messaggio\r\n"Lease renewal 2027" proveniente da "matteo@pec.example.it"\r\ned indirizzato a "studio.rossi@pec.example.it"\r\nè stato consegnato nella casella di destinazione.\r\n--inner--\r\n' > content.eml

sign() { # signer out digest [extra certificates]
  {
    printf 'From: posta-certificata@pec.example.it\r\n'
    printf 'To: matteo@pec.example.it\r\n'
    printf 'Subject: CONSEGNA: Lease renewal 2027\r\n'
    printf 'X-Ricevuta: avvenuta-consegna\r\n'
    printf 'X-Riferimento-Message-ID: <opec1.20261019@pec.example.it>\r\n'
    openssl smime -sign -binary -crlfeol -md "$3" -in content.eml \
      -signer "$1.pem" -inkey "$1.key" ${4:+-certfile "$4"}
  } > "$2"
}
sign provider signed.eml sha256
sign provider sha1.eml sha1
sign person person.eml sha256
sign nosign nosign.eml sha256
sign stranger stranger.eml sha256
sign pecnet pecnet.eml sha256 agid-pec-ca.pem
sign rootonly rootonly.eml sha256
sign renewed renewed.eml sha256 renewed-chain.pem
sign cross cross.eml sha256 cross-carried.pem
# The bare signature, for the parser's hostile-input test.
openssl smime -sign -binary -md sha256 -in content.eml -signer provider.pem \
  -inkey provider.key -outform DER -out signed.p7s

dest="$OLDPWD/$out"
cp test-root.pem agid-pec-ca.pem signed.eml sha1.eml person.eml nosign.eml stranger.eml \
  pecnet.eml rootonly.eml renewed.eml cross.eml cross-chain.pem loop-chain.pem signed.p7s \
  "$dest/"
