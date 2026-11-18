#!/usr/bin/env python3
"""Writes what PEC receipt signatures are checked against (core/src/pec.rs).

- core/src/pec_anchors.pem: the CAs AgID runs for the PEC network itself
  (AgID CA1, AgID CA SMIME RSA 2026: they certify only PEC providers'
  nodes and signing keys), from AgID_CA_URL; and the qualified CAs
  (service type CA/QC, status "granted") of the Italian trusted list,
  TSL-IT, the ETSI TS 119 612 list AgID publishes at TSL_URL.
- core/src/pec_providers.txt: the PEC providers in AgID's public list
  ("elenco pubblico dei gestori di posta elettronica certificata"), at
  PROVIDERS_URL. A receipt counts only when its signer's certificate is
  issued to one of them: qualified CAs also certify people.

AgID's PEC CAs are anchors themselves: the Actalis roots above them are
fetched too, only to check (with `openssl verify`) that each AgID CA
really is issued by them, and are not anchors, since Actalis certifies far
more than PEC providers.

TSL-IT is signed (XMLDSig). The certificate it is signed with must be one
the EU's list of trusted lists (LOTL_URL) publishes for Italy, and the
signature itself is checked with xmlsec1 when it is installed
(`apt install xmlsec1`); without it the script stops, unless
--no-signature-check is given, and then the file says it wasn't checked.

Refresh with every release (CI warns when the files are over 90 days old):

    python3 tools/gen_pec_trust.py
    python3 tools/gen_pec_trust.py --check   # only: are they older than 90 days?
"""

import argparse
import base64
import datetime
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

TSL_URL = "https://eidas.agid.gov.it/TL/TSL-IT.xml"
LOTL_URL = "https://ec.europa.eu/tools/lotl/eu-lotl.xml"
AGID_CA_URL = (
    "https://www.agid.gov.it/it/piattaforme/posta-elettronica-certificata/"
    "certificati-gestori-pec-siti-web"
)
# The archives on that page: the PEC network's CAs, and the roots and
# cross-certificates they hang from (checked, not trusted).
AGID_PEC_CAS = ("Certificato_SubCA_AGID_CA1", "Sub_AgID CA SMIME RSA 2026")
AGID_CHAIN = (
    "Certificato_CA_Actalis_Authentication_Root_CA",
    "Root_Actalis SMIME RSA Root CA 2025",
    "Cross_Actalis SMIME RSA RootCA 2025",
)
PROVIDERS_URL = (
    "https://www.agid.gov.it/it/piattaforme/posta-elettronica-certificata/elenco-gestori-pec"
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANCHORS = os.path.join(ROOT, "core", "src", "pec_anchors.pem")
PROVIDERS = os.path.join(ROOT, "core", "src", "pec_providers.txt")

TSL_NS = "http://uri.etsi.org/02231/v2#"
DS_NS = "http://www.w3.org/2000/09/xmldsig#"
CA_QC = "http://uri.etsi.org/TrstSvc/Svctype/CA/QC"
GRANTED = "http://uri.etsi.org/TrstSvc/TrustedList/Svcstatus/granted"
MAX_AGE_DAYS = 90


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "piuma-mail-tools"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def t(name):
    return "{%s}%s" % (TSL_NS, name)


def english(node, path):
    """The English name under `path`, else the first one."""
    names = node.findall(path)
    for n in names:
        if n.get("{http://www.w3.org/XML/1998/namespace}lang") == "en":
            return (n.text or "").strip()
    return (names[0].text or "").strip() if names else ""


def italian_signers(lotl):
    """The certificates the LOTL says TSL-IT is signed with, base64."""
    root = ET.fromstring(lotl)
    certs = set()
    for pointer in root.iter(t("OtherTSLPointer")):
        territory = pointer.find(".//" + t("SchemeTerritory"))
        if territory is None or (territory.text or "").strip() != "IT":
            continue
        for c in pointer.iter(t("X509Certificate")):
            certs.add("".join((c.text or "").split()))
    return certs


def check_signature(tsl, signers, skip):
    root = ET.fromstring(tsl)
    key = root.find(".//{%s}Signature/{%s}KeyInfo//{%s}X509Certificate" % (DS_NS, DS_NS, DS_NS))
    if key is None:
        sys.exit("TSL-IT carries no signing certificate")
    cert = "".join((key.text or "").split())
    if cert not in signers:
        sys.exit("TSL-IT is signed with a certificate the EU list doesn't publish for Italy")
    xmlsec = shutil.which("xmlsec1")
    if xmlsec is None:
        if skip:
            return "signer certificate matches the EU list; signature NOT checked (no xmlsec1)"
        sys.exit("xmlsec1 is not installed: install it, or pass --no-signature-check")
    with tempfile.TemporaryDirectory() as tmp:
        pem = os.path.join(tmp, "signer.pem")
        doc = os.path.join(tmp, "tsl.xml")
        with open(pem, "w") as f:
            f.write("-----BEGIN CERTIFICATE-----\n")
            for i in range(0, len(cert), 64):
                f.write(cert[i : i + 64] + "\n")
            f.write("-----END CERTIFICATE-----\n")
        with open(doc, "wb") as f:
            f.write(tsl)
        done = subprocess.run(
            [xmlsec, "--verify", "--pubkey-cert-pem", pem,
             "--id-attr:Id", "TrustServiceStatusList", doc],
            capture_output=True,
            text=True,
        )
        if done.returncode != 0:
            sys.exit("TSL-IT signature does not verify:\n" + done.stderr)
    return "signature checked with xmlsec1 against the certificate the EU list publishes for Italy"


def anchors(tsl):
    """(provider, service, base64 certificate) of each granted qualified CA."""
    root = ET.fromstring(tsl)
    issued = root.find(".//" + t("ListIssueDateTime")).text.strip()
    found = []
    seen = set()
    for tsp in root.iter(t("TrustServiceProvider")):
        provider = english(tsp, "./%s/%s/%s" % (t("TSPInformation"), t("TSPName"), t("Name")))
        for service in tsp.iter(t("ServiceInformation")):
            kind = (service.findtext(t("ServiceTypeIdentifier")) or "").strip()
            status = (service.findtext(t("ServiceStatus")) or "").strip()
            if kind != CA_QC or status != GRANTED:
                continue
            name = english(service, "./%s/%s" % (t("ServiceName"), t("Name")))
            for c in service.iter(t("X509Certificate")):
                b64 = "".join((c.text or "").split())
                base64.b64decode(b64, validate=True)
                if b64 not in seen:
                    seen.add(b64)
                    found.append((provider, name, b64))
    return issued, found


def providers():
    """The providers in AgID's current list (not the ceased ones), from
    every page of it, following the page links each page gives."""
    import urllib.parse

    names = []
    queue = [PROVIDERS_URL]
    visited = set()
    while queue and len(visited) < 20:
        url = queue.pop(0)
        if url in visited:
            continue
        visited.add(url)
        text = fetch(url).decode("utf-8", "replace")
        current = text.split("Gestori PEC cessati")[0]
        cells = re.findall(
            r'<td headers="view-field-acc-subj-website-table-column"[^>]*>(.*?)</td>',
            current,
            flags=re.S,
        )
        for c in cells:
            n = html.unescape(re.sub(r"<[^>]+>", "", c)).strip()
            if n and n not in names:
                names.append(n)
        for href in re.findall(r'href="([^"]*elenco-gestori-pec[^"]*\?page=\d+)"', text):
            link = urllib.parse.urljoin(url, html.unescape(href))
            if link not in visited:
                queue.append(link)
    if len(names) < 5:
        sys.exit("AgID's list of PEC providers came back with %d names" % len(names))
    return names


def pem_blocks(data):
    """The base64 of each certificate in a PEM text."""
    text = data.decode("ascii", "replace")
    return [
        "".join(b.split())
        for b in re.findall(
            r"-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----", text, flags=re.S
        )
    ]


def write_pem(f, b64):
    f.write("-----BEGIN CERTIFICATE-----\n")
    for i in range(0, len(b64), 64):
        f.write(b64[i : i + 64] + "\n")
    f.write("-----END CERTIFICATE-----\n")


def agid_cas(skip):
    """The PEC network's CAs from AgID's page, each checked against the
    Actalis roots the same page publishes: [(name, base64)], and how."""
    import io
    import urllib.parse
    import zipfile

    page = fetch(AGID_CA_URL).decode("utf-8", "replace")
    links = {}
    for href in re.findall(r'href="([^"]+\.zip)"', page):
        url = urllib.parse.urljoin(AGID_CA_URL, html.unescape(href))
        name = urllib.parse.unquote(url.rsplit("/", 1)[-1])[: -len(".zip")]
        links[name] = url

    def certs(name):
        if name not in links:
            sys.exit("AgID's page no longer links %r" % name)
        archive = zipfile.ZipFile(io.BytesIO(fetch(links[name])))
        found = []
        for member in archive.namelist():
            found.extend(pem_blocks(archive.read(member)))
        if not found:
            sys.exit("%r holds no certificate" % name)
        return found

    cas = [(n, b) for n in AGID_PEC_CAS for b in certs(n)]
    chain = [b for n in AGID_CHAIN for b in certs(n)]
    openssl = shutil.which("openssl")
    if openssl is None:
        if skip:
            return cas, "chain to the Actalis roots NOT checked (no openssl)"
        sys.exit("openssl is not installed: install it, or pass --no-signature-check")
    with tempfile.TemporaryDirectory() as tmp:
        bundle = os.path.join(tmp, "chain.pem")
        with open(bundle, "w") as f:
            for b in chain:
                write_pem(f, b)
        for name, b64 in cas:
            leaf = os.path.join(tmp, "ca.pem")
            with open(leaf, "w") as f:
                write_pem(f, b64)
            done = subprocess.run(
                [openssl, "verify", "-partial_chain", "-CAfile", bundle, leaf],
                capture_output=True,
                text=True,
            )
            if done.returncode != 0:
                sys.exit("%s doesn't chain to the Actalis roots:\n%s" % (name, done.stderr))
    return cas, "each checked with openssl to chain to the Actalis roots on the same page"


def generated(path):
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"# Generated: (\d{4}-\d{2}-\d{2})", line)
            if m:
                return datetime.date.fromisoformat(m.group(1))
    return None


def check():
    old = False
    for path in (ANCHORS, PROVIDERS):
        day = generated(path)
        age = (datetime.date.today() - day).days if day else None
        if age is None or age > MAX_AGE_DAYS:
            old = True
            rel = os.path.relpath(path, ROOT)
            print("::warning file=%s::%s is %s days old: run tools/gen_pec_trust.py"
                  % (rel, rel, age if age is not None else "an unknown number of"))
    return 1 if old else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="only report files older than 90 days")
    parser.add_argument("--no-signature-check", action="store_true")
    args = parser.parse_args()
    if args.check:
        return check()

    pec_cas, pec_how = agid_cas(args.no_signature_check)
    tsl = fetch(TSL_URL)
    how = check_signature(tsl, italian_signers(fetch(LOTL_URL)), args.no_signature_check)
    issued, cas = anchors(tsl)
    if len(cas) < 20:
        sys.exit("TSL-IT came back with only %d qualified CAs" % len(cas))
    names = providers()
    today = datetime.date.today().isoformat()

    with open(ANCHORS, "w", encoding="utf-8", newline="\n") as f:
        f.write("# The CAs a PEC receipt's S/MIME signature must lead to (pec.rs):\n")
        f.write("# AgID's CAs for the PEC network, then the qualified CAs (CA/QC,\n")
        f.write("# granted) of the Italian trusted list.\n")
        f.write("# Written by tools/gen_pec_trust.py; don't edit by hand.\n")
        f.write("# Generated: %s\n" % today)
        f.write("# Source: %s (%s)\n" % (AGID_CA_URL, pec_how))
        f.write("# Source: %s (issued %s; %s)\n" % (TSL_URL, issued, how))
        for name, b64 in pec_cas:
            f.write("\n# AgID, PEC network: %s\n" % name)
            write_pem(f, b64)
        for provider, name, b64 in cas:
            f.write("\n# %s: %s\n" % (provider, name))
            write_pem(f, b64)

    with open(PROVIDERS, "w", encoding="utf-8", newline="\n") as f:
        f.write("# PEC providers, one a line: a receipt's signer must be issued to one\n")
        f.write("# of them (pec.rs). Written by tools/gen_pec_trust.py; don't edit by hand.\n")
        f.write("# Generated: %s\n" % today)
        f.write("# Source: %s (current providers, not the ceased ones)\n" % PROVIDERS_URL)
        for n in names:
            f.write(n + "\n")
    print("%d AgID PEC CAs (%s), %d qualified CAs, %d providers; %s"
          % (len(pec_cas), pec_how, len(cas), len(names), how))
    return 0


if __name__ == "__main__":
    sys.exit(main())
