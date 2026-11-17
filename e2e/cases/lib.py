"""Shared helpers for case generators (cases/<lang>.py -> cases/<lang>.json). Run: python3 cases/<lang>.py

Expectation presets describe what each observer listener should see:
  hybrid :8443 TLS1.2-1.3, PQ preferred   pqonly :8444 TLS1.3 + X25519MLKEM768 only
  mtls   :8445 client cert required       eccert :8446 ECDSA P-256 server cert     tls12 :8447 TLS1.2 only
"""
import json
import os

ALL = ["hybrid", "pqonly", "mtls", "eccert", "tls12"]
# ML-DSA certificate targets (pq-mldsa fixture): dual ML-DSA+ECDSA server, ML-DSA-only server, ML-DSA client cert.
# Added to every client case that originates TLS itself (not the pq-egress extension, which is Go and would be
# measured instead of the language). Expectations: MLDSA_* presets below, set per case in mldsa_expect().
MLDSA = ["mldsa-dual", "mldsa-only", "mldsa-mtls"]
# TLS stack signs and verifies ML-DSA (OpenSSL 3.5+ with ML-DSA in its signature_algorithms): gets the ML-DSA
# certificate from a dual server, connects to an ML-DSA-only server, presents an ML-DSA client certificate.
MLDSA_FULL = {"mldsa-dual": {"ok": True, "server_cert": "mldsa"}, "mldsa-only": {"ok": True, "server_cert": "mldsa"},
              "mldsa-mtls": {"ok": True, "client_cert": "mldsa"}}
# TLS stack without ML-DSA in TLS: still connects to the dual server (gets ECDSA), fails ML-DSA-only and ML-DSA mTLS.
MLDSA_NONE = {"mldsa-dual": {"ok": True, "server_cert": "ecdsa"}, "mldsa-only": {"ok": False}, "mldsa-mtls": {"ok": False}}

# Client negotiates classical everywhere; PQ-only server rejects it; TLS 1.2 legacy server still works.
CLASSICAL = {"hybrid": {"ok": True, "pq": False, "tls_version": "TLSv1.3", "offered_pq": False},
             "pqonly": {"ok": False},
             "mtls": {"ok": True, "pq": False},
             "eccert": {"ok": True, "pq": False},
             "tls12": {"ok": True, "pq": False, "tls_version": "TLSv1.2"}}
# Client offers and negotiates X25519MLKEM768; existing certs/keystores/CA trust keep working; TLS 1.2 fallback intact.
PQ = {"hybrid": {"ok": True, "pq": True, "group": "X25519MLKEM768", "tls_version": "TLSv1.3", "offered_pq": True},
      "pqonly": {"ok": True, "pq": True, "group": "X25519MLKEM768"},
      "mtls": {"ok": True, "pq": True},
      "eccert": {"ok": True, "pq": True},
      "tls12": {"ok": True, "pq": False, "tls_version": "TLSv1.2"}}
# No TLS 1.3 at all (OpenSSL 1.0.2 etc.): everything lands on TLS 1.2.
TLS12_ONLY = {"hybrid": {"ok": True, "pq": False, "tls_version": "TLSv1.2"},
              "pqonly": {"ok": False},
              "mtls": {"ok": True, "pq": False, "tls_version": "TLSv1.2"},
              "eccert": {"ok": True, "pq": False, "tls_version": "TLSv1.2"},
              "tls12": {"ok": True, "pq": False, "tls_version": "TLSv1.2"}}


def only(preset, targets):
    return {t: preset[t] for t in targets}


def override(preset, **per_target):
    out = {k: dict(v) for k, v in preset.items()}
    for t, v in per_target.items():
        out[t] = v
    return out


def _env(c):
    for k in ("lambda", "ecs", "ec2"):
        if isinstance(c.get(k), dict):
            return c[k].get("env") or {}
    return c.get("env") or {}


def write(lang, cases, default_targets=ALL):
    here = os.path.dirname(os.path.abspath(__file__))
    for c in cases:
        c.setdefault("targets", default_targets)
        if c.get("role") != "server" and "PQC_EGRESS_PORT" not in _env(c) and c.get("mldsa", True):
            c["targets"] = [t for t in c["targets"] if t not in MLDSA] + MLDSA
            if "mldsa_expect" not in c:
                from mldsa_rules import expect as _mldsa
                c["mldsa_expect"] = _mldsa(lang, c)
            for t, v in (c.get("mldsa_expect") or {}).items():
                c["expect"][t] = v
        c["expect"] = {t: c["expect"][t] for t in c["targets"] if t in c["expect"]}
    path = os.path.join(here, lang + ".json")
    json.dump({"lang": lang, "generated_by": "cases/%s.py" % lang, "default_targets": default_targets, "cases": cases},
              open(path, "w"), indent=1)
    print("%s: %d cases -> %s" % (lang, len(cases), path))
