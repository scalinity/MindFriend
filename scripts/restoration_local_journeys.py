#!/usr/bin/env python3
"""Synthetic HTTP journeys against the isolated restoration stack only.

Reads local CLI status privately. Reports assertions, never credentials or content.
No production requests, AI inference, external email, notifications or microphone use.
"""
import argparse
import html
import json
import re
import secrets
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

p = argparse.ArgumentParser()
p.add_argument("--local-status", type=Path, required=True)
p.add_argument("--output", type=Path, required=True)
args = p.parse_args()
cfg = json.loads(args.local_status.read_text())
base, mailbox = cfg["API_URL"], cfg["MAILPIT_URL"]
assert base == "http://127.0.0.1:55321" and mailbox == "http://127.0.0.1:55324", "Local stack required"
report = {"started_eastern": datetime.now(ZoneInfo("America/New_York")).isoformat(), "environment": "synthetic local stack", "checks": []}


def request(path, body=None, token=None, method=None, raw=None, content_type=None):
    url = path if path.startswith(mailbox + "/") else base + path
    assert url.startswith(base + "/") or url.startswith(mailbox + "/")
    headers = {"apikey": cfg["ANON_KEY"], "Authorization": "Bearer " + (token or cfg["ANON_KEY"])}
    if body is not None:
        raw, content_type = json.dumps(body).encode(), "application/json"
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=raw, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            data = r.read()
            return r.status, json.loads(data) if "json" in r.headers.get("Content-Type", "") else data
    except urllib.error.HTTPError as e:
        data = e.read()
        try:
            return e.code, json.loads(data)
        except ValueError:
            return e.code, b""


def check(name, condition):
    report["checks"].append({"name": name, "status": "PASS" if condition else "FAIL"})
    args.output.write_text(json.dumps(report, indent=2))
    if not condition:
        raise AssertionError(name)


def verify_mail(email, kind):
    status, messages = request(mailbox + "/api/v1/messages")
    assert status == 200
    msg = next(m for m in messages["messages"] if any(t["Address"] == email for t in m["To"]))
    status, mail = request(mailbox + "/api/v1/message/" + msg["ID"])
    assert status == 200
    link = html.unescape(re.search(r'https?://[^\s"<>]+/auth/v1/verify\?[^\s"<>]+', mail["HTML"])[0])
    assert link.startswith(base + "/auth/v1/verify?")
    q = urllib.parse.parse_qs(urllib.parse.urlparse(link).query)
    status, result = request("/auth/v1/verify", {"token_hash": q["token"][0], "type": kind})
    assert status == 200
    return result


password = secrets.token_urlsafe(24)
users = []
for index in range(2):
    email = "restoration-" + secrets.token_hex(6) + "@example.invalid"
    status, signup = request("/auth/v1/signup?redirect_to=mindfriend%3A%2F%2Fauth%2Fcallback", {"email": email, "password": password})
    check(f"signup {index + 1} requires verification", status == 200 and not signup.get("access_token"))
    status, _ = request("/auth/v1/token?grant_type=password", {"email": email, "password": password})
    check(f"unverified login {index + 1} denied", status == 400)
    verified = verify_mail(email, "signup")
    check(f"email verification {index + 1}", bool(verified.get("access_token")))
    status, session = request("/auth/v1/token?grant_type=password", {"email": email, "password": password})
    check(f"verified login {index + 1}", status == 200 and bool(session.get("refresh_token")))
    users.append({"id": session["user"]["id"], "email": email, "session": session})

a, b = users
ta, tb = a["session"]["access_token"], b["session"]["access_token"]
for table, field in [("profiles", "id"), ("user_settings", "user_id"), ("user_stats", "user_id")]:
    status, rows = request(f"/rest/v1/{table}?{field}=eq.{a['id']}&select=*", token=ta)
    check(f"profile bootstrap {table}", status == 200 and len(rows) == 1)
status, rows = request(f"/rest/v1/profiles?id=eq.{b['id']}&select=id", token=ta)
check("cross-user profile denied", status == 200 and rows == [])
status, _ = request(f"/rest/v1/profiles?id=eq.{a['id']}", {"subscription_tier": "premium"}, ta, "PATCH")
check("client entitlement escalation denied", status == 403)
status, _ = request(f"/rest/v1/profiles?id=eq.{a['id']}", {"display_name": "Synthetic profile"}, ta, "PATCH")
check("owner profile edit", status == 204)
status, _ = request("/rest/v1/conversations", {"user_id": a["id"], "title": "Synthetic HTTP journey"}, ta)
check("conversation creation", status == 201)
status, rows = request("/rest/v1/conversations?select=id&order=created_at.desc&limit=1", token=ta)
assert status == 200 and rows
conversation = rows[0]["id"]
status, _ = request("/rest/v1/messages", {"conversation_id": conversation, "role": "user", "content": "Synthetic history fixture"}, ta)
check("message persistence", status == 201)
status, rows = request(f"/rest/v1/messages?conversation_id=eq.{conversation}&select=id", token=tb)
check("cross-user chat history denied", status == 200 and rows == [])
status, refreshed = request("/auth/v1/token?grant_type=refresh_token", {"refresh_token": a["session"]["refresh_token"]})
check("refresh session", status == 200 and refreshed["user"]["id"] == a["id"])
ta = refreshed["access_token"]
status, rows = request(f"/rest/v1/messages?conversation_id=eq.{conversation}&select=id", token=ta)
check("history after session restoration", status == 200 and len(rows) == 1)

# Reproduce private bucket limits; service creates configuration, accounts upload bytes.
status, _ = request("/storage/v1/bucket", {"id": "mood-photos", "name": "mood-photos", "public": False, "file_size_limit": 5242880, "allowed_mime_types": ["image/png", "image/jpeg", "image/heic"]}, cfg["SERVICE_ROLE_KEY"])
check("private bucket fixture", status in (200, 201, 400))
object_path = "/storage/v1/object/mood-photos/" + a["id"] + "/fixture.png"
payload = bytes.fromhex("89504e470d0a1a0a") + b"synthetic-fixture"
status, _ = request(object_path, token=ta, method="POST", raw=payload, content_type="image/png")
check("owner private upload", status == 200)
status, _ = request(object_path, token=tb)
check("cross-user private download denied", status in (400, 403, 404))
status, _ = request(object_path)
check("anonymous private download denied", status in (400, 403, 404))
status, signed = request(object_path.replace("/object/", "/object/sign/"), {"expiresIn": 60}, ta)
check("owner signed URL", status == 200 and bool(signed.get("signedURL")))
status, data = request("/storage/v1" + signed["signedURL"])
check("signed download matches uploaded bytes", status == 200 and data == payload)
status, _ = request(object_path, token=tb, method="PUT", raw=payload, content_type="image/png")
check("cross-user overwrite denied", status in (400, 403, 404))
status, _ = request("/storage/v1/object/mood-photos/" + a["id"] + "/bad.txt", token=ta, method="POST", raw=b"fixture", content_type="text/plain")
check("upload MIME validation", status in (400, 415, 422))

status, _ = request("/auth/v1/recover?redirect_to=mindfriend%3A%2F%2Fauth%2Fcallback", {"email": a["email"]})
check("reset email to local mailbox", status == 200)
recovery = verify_mail(a["email"], "recovery")
new_password = secrets.token_urlsafe(24)
status, _ = request("/auth/v1/user", {"password": new_password}, recovery["access_token"], "PUT")
check("password recovery update", status == 200)
status, _ = request("/auth/v1/token?grant_type=password", {"email": a["email"], "password": password})
check("old password denied", status == 400)
status, restored = request("/auth/v1/token?grant_type=password", {"email": a["email"], "password": new_password})
check("recovered account login", status == 200)
status, _ = request("/auth/v1/logout?scope=global", {}, restored["access_token"])
check("logout", status == 204)
status, _ = request("/auth/v1/token?grant_type=refresh_token", {"refresh_token": restored["refresh_token"]})
check("logged-out refresh denied", status == 400)
report["finished_eastern"] = datetime.now(ZoneInfo("America/New_York")).isoformat()
args.output.write_text(json.dumps(report, indent=2))
print(f"PASS: {len(report['checks'])} synthetic local HTTP assertions; no provider calls")
