Self-signed certificates for `localhost`, made only for the certificate
trust tests (`core/tests/certificates.rs`, `core/src/cert.rs`). Their
private keys are test fixtures, not secrets: nothing outside the tests
trusts them. Made with:

    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
      -days 36500 -subj "/CN=localhost/O=Piuma Test" \
      -addext "subjectAltName=DNS:localhost" \
      -addext "basicConstraints=critical,CA:FALSE" -keyout k.pem -out c.pem
    openssl x509 -in c.pem -outform DER -out first.der
    openssl pkcs8 -topk8 -nocrypt -in k.pem -outform DER -out first.key.der
