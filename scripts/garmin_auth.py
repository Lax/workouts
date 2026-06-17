#!/usr/bin/env python3
"""
Garmin DI OAuth2 auth for CI.

Uses curl_cffi TLS impersonation with two strategies:
  1. mobile+cffi: /mobile/api/login (Safari TLS, primary)
  2. portal+cffi: /portal/api/login (5 TLS fingerprints, fallback)

MFA threshold: supply SYNC__GARMIN__MFA_CODE env var if account has MFA enabled.
30-45s random delay between SSO page GET and credential POST critical for
Cloudflare WAF bypass.

Input:  SYNC__GARMIN__EMAIL, SYNC__GARMIN__PASSWORD, SYNC__GARMIN__DOMAIN (garmin.com default)
Output: JSON DI OAuth2 token to stdout, exit 0. Exit 1 on failure.
"""

import json
import os
import random
import sys
import time
import base64

from curl_cffi import requests as cffi_requests

PORTAL_CLIENT_ID = "GarminConnect"
PORTAL_SERVICE = "https://connect.garmin.com/app"
MOBILE_CLIENT_ID = "GCM_ANDROID_DARK"
MOBILE_SERVICE = "https://mobile.integration.garmin.com/gcm/android"
MOBILE_UA = (
    "Mozilla/5.0 (Linux; Android 13; sdk_gphone64_arm64 Build/TE1A.220922.025; wv) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/132.0.0.0 "
    "Mobile Safari/537.36"
)
LOGIN_DELAY_MIN = 30.0
LOGIN_DELAY_MAX = 45.0
TLS_FINGERPRINTS = ["safari", "safari_ios", "chrome120", "edge101", "chrome"]
DI_TOKEN_URL = "https://diauth.garmin.com/di-oauth2-service/oauth/token"
DI_GRANT_TYPE = "https://connectapi.garmin.com/di-oauth2-service/oauth/grant/service_ticket"
DI_CLIENT_IDS = [
    "GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2",
    "GARMIN_CONNECT_MOBILE_ANDROID_DI_2024Q4",
    "GARMIN_CONNECT_MOBILE_ANDROID_DI",
]


def _browser_headers():
    return {
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/131.0.0.0 Safari/537.36"
        ),
        "Accept-Language": "en-US,en;q=0.9",
    }


def _random_delay(label):
    delay = random.uniform(LOGIN_DELAY_MIN, LOGIN_DELAY_MAX)
    print(f"[garmin_auth] {label}: waiting {delay:.0f}s for Cloudflare...", file=sys.stderr)
    time.sleep(delay)


def _di_exchange(domain, ticket, service_url):
    url = DI_TOKEN_URL.replace("garmin.com", domain)
    for cid in DI_CLIENT_IDS:
        try:
            basic = base64.b64encode(f"{cid}:".encode()).decode()
            resp = cffi_requests.post(
                url,
                data={
                    "client_id": cid,
                    "service_ticket": ticket,
                    "grant_type": DI_GRANT_TYPE,
                    "service_url": service_url,
                },
                headers={
                    "Authorization": f"Basic {basic}",
                    "Accept": "application/json,text/html;q=0.9,*/*;q=0.8",
                    "Content-Type": "application/x-www-form-urlencoded",
                    "Cache-Control": "no-cache",
                    "User-Agent": "GCM-Android-5.23",
                },
                timeout=30,
            )
            if resp.status_code == 200:
                token = resp.json()
                token["di_client_id"] = cid
                return token
            print(f"[garmin_auth] DI exchange {cid}: HTTP {resp.status_code}", file=sys.stderr)
        except Exception as e:
            print(f"[garmin_auth] DI exchange {cid}: {e}", file=sys.stderr)
    raise RuntimeError("All DI client IDs failed for ticket exchange")


def _handle_mfa(sess, base_url, method, mfa_params, mfa_headers, mfa_data):
    mfa_code = os.environ.get("SYNC__GARMIN__MFA_CODE")
    if not mfa_code and sys.stdin.isatty():
        print("Enter MFA code: ", file=sys.stderr, end="", flush=True)
        mfa_code = sys.stdin.readline()
    if not mfa_code:
        raise RuntimeError("MFA required but SYNC__GARMIN__MFA_CODE env var not set and stdin unavailable")

    code = mfa_code.strip()
    if not code:
        raise RuntimeError("SYNC__GARMIN__MFA_CODE is empty")

    mfa_data["mfaVerificationCode"] = code

    endpoints = [
        (f"{base_url}/portal/api/mfa/verifyCode", mfa_params, mfa_headers),
        (f"{base_url}/mobile/api/mfa/verifyCode",
         {"clientId": MOBILE_CLIENT_ID, "locale": "en-US", "service": MOBILE_SERVICE},
         mfa_headers),
    ]

    for ep_url, ep_params, ep_headers in endpoints:
        try:
            resp = sess.post(ep_url, params=ep_params, headers=ep_headers, json=mfa_data, timeout=30)
            if resp.status_code == 429:
                continue
            if not resp.ok:
                continue
            res = resp.json()
            if res.get("responseStatus", {}).get("type") == "SUCCESSFUL":
                return res
        except Exception:
            continue

    raise RuntimeError("MFA verification failed on all endpoints")


def portal_login(domain, email, password):
    sso = f"https://sso.{domain}"

    for imp in TLS_FINGERPRINTS:
        sess = cffi_requests.Session(impersonate=imp)
        try:
            _random_delay(f"portal+cffi/{imp}")

            signin_url = f"{sso}/portal/sso/en-US/sign-in"
            hdrs = _browser_headers()
            get_params = {"clientId": PORTAL_CLIENT_ID, "service": PORTAL_SERVICE}

            resp = sess.get(signin_url, params=get_params,
                            headers={"Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", **hdrs},
                            timeout=30)
            if resp.status_code == 429:
                print(f"[garmin_auth] portal+cffi/{imp} GET 429", file=sys.stderr)
                continue
            if not resp.ok:
                print(f"[garmin_auth] portal+cffi/{imp} GET {resp.status_code}", file=sys.stderr)
                continue

            post_hdrs = {
                **hdrs,
                "Accept": "application/json, text/plain, */*",
                "Content-Type": "application/json",
                "Origin": sso,
                "Referer": f"{signin_url}?clientId={PORTAL_CLIENT_ID}&service={PORTAL_SERVICE}",
            }
            login_params = {"clientId": PORTAL_CLIENT_ID, "locale": "en-US", "service": PORTAL_SERVICE}

            resp = sess.post(
                f"{sso}/portal/api/login",
                params=login_params,
                headers=post_hdrs,
                json={"username": email, "password": password, "rememberMe": True, "captchaToken": ""},
                timeout=30,
            )

            if resp.status_code == 429:
                print(f"[garmin_auth] portal+cffi/{imp} POST 429", file=sys.stderr)
                continue
            if not resp.ok:
                print(f"[garmin_auth] portal+cffi/{imp} POST {resp.status_code}", file=sys.stderr)
                continue

            res = resp.json()
            resp_type = res.get("responseStatus", {}).get("type")

            if resp_type == "MFA_REQUIRED":
                method = res.get("customerMfaInfo", {}).get("mfaLastMethodUsed", "email")
                mfa_data = {"mfaMethod": method, "rememberMyBrowser": True, "reconsentList": [], "mfaSetup": False}
                res = _handle_mfa(sess, sso, method, login_params, post_hdrs, mfa_data)
                resp_type = res.get("responseStatus", {}).get("type")

            if resp_type == "SUCCESSFUL":
                return res["serviceTicketId"], PORTAL_SERVICE

            if resp_type == "INVALID_USERNAME_PASSWORD":
                raise RuntimeError("Invalid username or password")

        except RuntimeError:
            raise
        except Exception:
            continue

    raise RuntimeError("portal+cffi: all TLS fingerprints exhausted")


def mobile_login(domain, email, password):
    sso = f"https://sso.{domain}"
    sess = cffi_requests.Session(impersonate="safari")

    _random_delay("mobile+cffi")

    signin_url = f"{sso}/mobile/sso/en_US/sign-in"
    get_hdrs = {"User-Agent": MOBILE_UA, "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", "accept-language": "en-US,en;q=0.9"}

    resp = sess.get(signin_url, params={"clientId": MOBILE_CLIENT_ID, "service": MOBILE_SERVICE}, headers=get_hdrs, timeout=30)
    if resp.status_code == 429:
        raise RuntimeError("mobile+cffi GET 429")
    if not resp.ok:
        raise RuntimeError(f"mobile+cffi GET {resp.status_code}")

    post_hdrs = {**get_hdrs, "accept": "application/json, text/plain, */*", "content-type": "application/json", "origin": sso, "referer": f"{signin_url}?clientId={MOBILE_CLIENT_ID}&service={MOBILE_SERVICE}"}
    login_params = {"clientId": MOBILE_CLIENT_ID, "locale": "en-US", "service": MOBILE_SERVICE}

    resp = sess.post(f"{sso}/mobile/api/login", params=login_params, headers=post_hdrs,
                     json={"username": email, "password": password, "rememberMe": True, "captchaToken": ""}, timeout=30)

    if resp.status_code == 429:
        raise RuntimeError("mobile+cffi POST 429")
    if not resp.ok:
        raise RuntimeError(f"mobile+cffi POST {resp.status_code}")

    res = resp.json()
    resp_type = res.get("responseStatus", {}).get("type")

    if resp_type == "MFA_REQUIRED":
        method = res.get("customerMfaInfo", {}).get("mfaLastMethodUsed", "email")
        mfa_data = {"mfaMethod": method, "rememberMyBrowser": True, "reconsentList": [], "mfaSetup": False}
        res = _handle_mfa(sess, sso, method, login_params, post_hdrs, mfa_data)
        resp_type = res.get("responseStatus", {}).get("type")

    if resp_type == "SUCCESSFUL":
        return res["serviceTicketId"], MOBILE_SERVICE

    if resp_type == "INVALID_USERNAME_PASSWORD":
        raise RuntimeError("Invalid username or password")

    raise RuntimeError(f"mobile+cffi: unexpected response type: {resp_type}")


def main():
    email = os.environ["SYNC__GARMIN__EMAIL"]
    password = os.environ["SYNC__GARMIN__PASSWORD"]
    domain = os.environ.get("SYNC__GARMIN__DOMAIN", "garmin.com")

    if not email.strip() or not password.strip():
        print("[garmin_auth] SYNC__GARMIN__EMAIL or SYNC__GARMIN__PASSWORD not set", file=sys.stderr)
        sys.exit(1)

    errors = []

    # Strategy 1: mobile+cffi (Safari TLS — proven path)
    try:
        ticket, svc_url = mobile_login(domain, email, password)
        token = _di_exchange(domain, ticket, svc_url)
        token["expires_at"] = int(time.time()) + token.get("expires_in", 64800)
        if "refresh_token_expires_in" in token:
            token["refresh_token_expires_at"] = int(time.time()) + token["refresh_token_expires_in"]
        json.dump(token, sys.stdout)
        return 0
    except RuntimeError as e:
        errors.append(f"mobile+cffi: {e}")
        print(f"[garmin_auth] {errors[-1]}", file=sys.stderr)

    # Strategy 2: portal+cffi (5 TLS fingerprints)
    try:
        ticket, svc_url = portal_login(domain, email, password)
        token = _di_exchange(domain, ticket, svc_url)
        token["expires_at"] = int(time.time()) + token.get("expires_in", 64800)
        if "refresh_token_expires_in" in token:
            token["refresh_token_expires_at"] = int(time.time()) + token["refresh_token_expires_in"]
        json.dump(token, sys.stdout)
        return 0
    except RuntimeError as e:
        errors.append(f"portal+cffi: {e}")
        print(f"[garmin_auth] {errors[-1]}", file=sys.stderr)

    print(f"[garmin_auth] All strategies exhausted: {'; '.join(errors)}", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    sys.exit(main())
