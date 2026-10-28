#!/usr/bin/env python3
"""Reads the App Store Connect state that blocks a submission, and can add the iOS version to
the open draft review submission. It never submits for review.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (PEM file), APP_ID, ACTION (check | add-version).
Output is plain text on stdout. It prints ids, states and Apple's error messages only, never
contact details or review notes, because the results are published to a public branch.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com"
APP_ID = os.environ.get("APP_ID", "6827877311")
ACTION = os.environ.get("ACTION", "check")


def token():
    key = open(os.environ["ASC_KEY_PATH"]).read()
    now = int(time.time())
    payload = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


TOKEN = token()


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method)
    req.add_header("Authorization", "Bearer " + TOKEN)
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, data, timeout=60) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw.decode(errors="replace")[:2000]}


def errors(resp):
    out = []
    for e in resp.get("errors", []):
        line = f"  {e.get('status')} {e.get('code')}: {e.get('title')} -- {e.get('detail')}"
        src = e.get("source")
        if src:
            line += f" (source {json.dumps(src)})"
        out.append(line)
        assoc = (e.get("meta") or {}).get("associatedErrors")
        if isinstance(assoc, dict):
            for where, subs in assoc.items():
                for sub in subs or []:
                    out.append(f"     - [{where}] {sub.get('code')}: {sub.get('detail') or sub.get('title')}")
    return "\n".join(out)


def get(path, label):
    status, resp = call("GET", path)
    if status >= 400:
        print(f"[{label}] HTTP {status}\n{errors(resp) or json.dumps(resp)[:1500]}")
        return None
    return resp


def section(title):
    print("\n=== " + title + " ===")


section("iOS and macOS versions")
versions = get(f"/v1/apps/{APP_ID}/appStoreVersions?limit=10&include=build", "versions") or {}
builds = {i["id"]: i for i in versions.get("included", []) if i["type"] == "builds"}
ios_version = None
for v in versions.get("data", []):
    a = v["attributes"]
    b = (v["relationships"].get("build", {}).get("data") or {}).get("id")
    battrs = builds.get(b, {}).get("attributes", {})
    print(f"{a['platform']} {a['versionString']} id={v['id']} state={a.get('appStoreState')} / {a.get('appVersionState')}"
          f" build={battrs.get('version')} buildState={battrs.get('processingState')} encryptionKnown={battrs.get('usesNonExemptEncryption')}")
    if a["platform"] == "IOS" and a.get("appStoreState") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"):
        ios_version = v

if ios_version:
    vid = ios_version["id"]
    section("iOS version details")
    det = get(f"/v1/appStoreVersions/{vid}/appStoreReviewDetail", "reviewDetail")
    if det and det.get("data"):
        a = det["data"]["attributes"]
        print("review detail: demoAccountRequired=", a.get("demoAccountRequired"),
              " contact fields filled=", all(a.get(k) for k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail")),
              " notes filled=", bool(a.get("notes")))
    locs = get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations", "localizations") or {}
    for l in locs.get("data", []):
        a = l["attributes"]
        print(f"localization {a['locale']}: description={len(a.get('description') or '')} chars, keywords={len(a.get('keywords') or '')},"
              f" supportUrl={'yes' if a.get('supportUrl') else 'NO'}")
        sets = get(f"/v1/appStoreVersionLocalizations/{l['id']}/appScreenshotSets", "screenshotSets") or {}
        print("   screenshot sets:", ", ".join(s["attributes"]["screenshotDisplayType"] for s in sets.get("data", [])) or "none")

section("App info (age rating, privacy, category)")
infos = get(f"/v1/apps/{APP_ID}/appInfos", "appInfos") or {}
for i in infos.get("data", []):
    a = i["attributes"]
    print(f"appInfo id={i['id']} state={a.get('appStoreState') or a.get('state')} ageRating={a.get('appStoreAgeRating')}")

section("Subscription groups and subscriptions")
groups = get(f"/v1/apps/{APP_ID}/subscriptionGroups?include=subscriptions,subscriptionGroupLocalizations", "groups") or {}
for g in groups.get("data", []):
    print(f"group {g['attributes']['referenceName']} id={g['id']}")
for inc in groups.get("included", []):
    a = inc["attributes"]
    if inc["type"] == "subscriptions":
        print(f"  subscription {a.get('productId')} id={inc['id']} state={a.get('state')}")
    elif inc["type"] == "subscriptionGroupLocalizations":
        print(f"  group localization {a.get('locale')} state={a.get('state')}")

section("In-app purchases")
iaps = get(f"/v1/apps/{APP_ID}/inAppPurchasesV2?limit=20", "iaps") or {}
for p in iaps.get("data", []):
    a = p["attributes"]
    print(f"  {a.get('productId')} id={p['id']} type={a.get('inAppPurchaseType')} state={a.get('state')}")

section("Review submissions")
subs = get(f"/v1/reviewSubmissions?filter[app]={APP_ID}&limit=10&include=items", "reviewSubmissions") or {}
draft = None
for s in subs.get("data", []):
    a = s["attributes"]
    items = [i["id"] for i in (s["relationships"].get("items", {}).get("data") or [])]
    print(f"submission id={s['id']} platform={a.get('platform')} state={a.get('state')} items={len(items)}")
    if a.get("platform") == "IOS" and a.get("state") == "READY_FOR_REVIEW":
        draft = s
for inc in subs.get("included", []):
    if inc["type"] == "reviewSubmissionItems":
        rel = {k: (v.get("data") or {}).get("type") for k, v in inc.get("relationships", {}).items() if isinstance(v, dict) and v.get("data")}
        print(f"  item id={inc['id']} state={inc['attributes'].get('state')} -> {rel}")

if ACTION == "add-purchases":
    section("Add the subscription group, subscriptions and Lifetime for review (no app submit)")
    for g in groups.get("data", []):
        status, resp = call("POST", "/v1/subscriptionGroupSubmissions", {"data": {"type": "subscriptionGroupSubmissions",
                            "relationships": {"subscriptionGroup": {"data": {"type": "subscriptionGroups", "id": g["id"]}}}}})
        print(f"group {g['attributes']['referenceName']}: HTTP {status}")
        print(errors(resp) or "  added")
    for inc in groups.get("included", []):
        if inc["type"] != "subscriptions":
            continue
        status, resp = call("POST", "/v1/subscriptionSubmissions", {"data": {"type": "subscriptionSubmissions",
                            "relationships": {"subscription": {"data": {"type": "subscriptions", "id": inc["id"]}}}}})
        print(f"subscription {inc['attributes'].get('productId')}: HTTP {status}")
        print(errors(resp) or "  added")
    for p in iaps.get("data", []):
        status, resp = call("POST", "/v1/inAppPurchaseSubmissions", {"data": {"type": "inAppPurchaseSubmissions",
                            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": p["id"]}}}}})
        print(f"in-app purchase {p['attributes'].get('productId')}: HTTP {status}")
        print(errors(resp) or "  added")
    section("State afterwards")
    for inc in (get(f"/v1/apps/{APP_ID}/subscriptionGroups?include=subscriptions", "groups") or {}).get("included", []):
        if inc["type"] == "subscriptions":
            print(f"  {inc['attributes'].get('productId')} state={inc['attributes'].get('state')}")
    for p in (get(f"/v1/apps/{APP_ID}/inAppPurchasesV2", "iaps") or {}).get("data", []):
        print(f"  {p['attributes'].get('productId')} state={p['attributes'].get('state')}")
    subs2 = get(f"/v1/reviewSubmissions?filter[app]={APP_ID}&limit=10&include=items", "reviewSubmissions") or {}
    for s in subs2.get("data", []):
        a = s["attributes"]
        print(f"  submission {s['id']} platform={a.get('platform')} state={a.get('state')} items={len((s['relationships'].get('items', {}).get('data') or []))}")

if ACTION == "submit":
    section("Submit the iOS draft for review")
    if not draft:
        print("No iOS draft submission (READY_FOR_REVIEW) found.")
        sys.exit(0)
    sid = draft["id"]
    items = get(f"/v1/reviewSubmissions/{sid}/items?include=appStoreVersion", "items") or {}
    has_version = False
    for it in items.get("data", []):
        rel = {k: (v.get("data") or {}).get("id") for k, v in it.get("relationships", {}).items() if isinstance(v, dict) and v.get("data")}
        print(f"  item state={it['attributes'].get('state')} rel={rel}")
        if rel.get("appStoreVersion"):
            has_version = True
    print(f"draft {sid}: {len(items.get('data', []))} item(s) visible through the API; version included={has_version}")
    if not has_version and ios_version:
        status, resp = call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": ios_version["id"]}}}}})
        print(f"add version: HTTP {status}")
        print(errors(resp) or "  added")
    status, resp = call("PATCH", f"/v1/reviewSubmissions/{sid}", {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})
    print(f"submit: HTTP {status}")
    print(errors(resp) or f"  submitted, state={resp.get('data', {}).get('attributes', {}).get('state')}")
    section("State afterwards")
    for v in (get(f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS&limit=3", "versions") or {}).get("data", []):
        print(f"  iOS {v['attributes']['versionString']} state={v['attributes'].get('appStoreState')}")
    for inc in (get(f"/v1/apps/{APP_ID}/subscriptionGroups?include=subscriptions", "groups") or {}).get("included", []):
        if inc["type"] == "subscriptions":
            print(f"  {inc['attributes'].get('productId')} state={inc['attributes'].get('state')}")
    for p in (get(f"/v1/apps/{APP_ID}/inAppPurchasesV2", "iaps") or {}).get("data", []):
        print(f"  {p['attributes'].get('productId')} state={p['attributes'].get('state')}")

if ACTION == "add-version":
    section("Add the iOS version to the draft submission (no submit)")
    if not ios_version:
        print("No editable iOS version found.")
        sys.exit(0)
    if not draft:
        status, resp = call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                            "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
        print(f"create draft: HTTP {status}")
        print(errors(resp))
        if status >= 400:
            sys.exit(0)
        draft = resp["data"]
    status, resp = call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": draft["id"]}},
        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": ios_version["id"]}}}}})
    print(f"add version {ios_version['attributes']['versionString']} to submission {draft['id']}: HTTP {status}")
    print(errors(resp) or "  added")
