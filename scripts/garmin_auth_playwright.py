#!/usr/bin/env python3
"""
Garmin DI OAuth2 auth via Playwright browser automation.

Strategy B: Real browser TLS fingerprint via Playwright APIRequestContext.
Used as fallback when Strategy A (curl_cffi) is exhausted or unavailable.

Garmin SSO web pages are behind Cloudflare WAF which blocks headless browsers
(HTTP 429 / "Access denied"). This script bypasses CF by calling the mobile
API login endpoints directly through Playwright's browser-context HTTP stack,
which carries Chrome's real TLS fingerprint.

Flow:
  1. Restore saved session cookies (optional, may help CF bypass)
  2. GET mobile sign-in page (establishes CF cookies)
  3. 30-45s random delay (critical for CF WAF bypass)
  4. POST /mobile/api/login (credentials)
  5. If MFA required: prompt or read SYNC__GARMIN__MFA_CODE env var
  6. POST /mobile/api/mfa/verifyCode
  7. DI ticket exchange via diauth.garmin.com
  8. Output DI OAuth2 token JSON to stdout

Session cookies benefit: stored cookies reduce CF scrutiny on subsequent runs,
but SSO login is always required since we cannot verify session validity
without navigating to CF-blocked web pages.

Input:  SYNC__GARMIN__EMAIL, SYNC__GARMIN__PASSWORD, SYNC__GARMIN__DOMAIN (default garmin.com)
        SYNC__GARMIN__MFA_CODE (optional, for MFA challenge)
        SYNC__GARMIN__PLAYWRIGHT_SESSION (path to session cookies file)
Output: JSON DI OAuth2 token to stdout, exit 0. Exit 1 on failure.
"""

import json
import os
import random
import sys
import time

from playwright.sync_api import sync_playwright

MOBILE_UA = (
    "Mozilla/5.0 (Linux; Android 13; sdk_gphone64_arm64 Build/TE1A.220922.025; wv) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/132.0.0.0 "
    "Mobile Safari/537.36"
)
MOBILE_CLIENT_ID = "GCM_ANDROID_DARK"
MOBILE_SERVICE = "https://mobile.integration.garmin.com/gcm/android"
DI_TOKEN_URL = "https://diauth.garmin.com/di-oauth2-service/oauth/token"
DI_GRANT_TYPE = "https://connectapi.garmin.com/di-oauth2-service/oauth/grant/service_ticket"
DI_CLIENT_IDS = [
    "GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2",
    "GARMIN_CONNECT_MOBILE_ANDROID_DI_2024Q4",
    "GARMIN_CONNECT_MOBILE_ANDROID_DI",
]
LOGIN_DELAY_MIN = 30.0
LOGIN_DELAY_MAX = 45.0


def _random_delay(label):
    delay = random.uniform(LOGIN_DELAY_MIN, LOGIN_DELAY_MAX)
    print(f"[garmin_auth_pw] {label}: waiting {delay:.0f}s for Cloudflare...", file=sys.stderr)
    time.sleep(delay)


def _di_exchange(domain, ticket):
    import requests

    url = DI_TOKEN_URL.replace("garmin.com", domain)
    for cid in DI_CLIENT_IDS:
        try:
            resp = requests.post(
                url,
                data={
                    "grant_type": DI_GRANT_TYPE,
                    "service_ticket": ticket,
                    "client_id": cid,
                    "service_url": MOBILE_SERVICE,
                },
                headers={
                    "Authorization": "Basic " + __import__("base64").b64encode(f"{cid}:".encode()).decode(),
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
            print(f"[garmin_auth_pw] DI exchange {cid}: HTTP {resp.status_code}", file=sys.stderr)
        except Exception as e:
            print(f"[garmin_auth_pw] DI exchange {cid}: {e}", file=sys.stderr)
    raise RuntimeError("All DI client IDs failed for ticket exchange")


def _extract_ticket_from_url(url):
    import re
    m = re.search(r'[?&]ticket=(ST-[^&\s]+)', url)
    return m.group(1) if m else None


def _mobile_api_login(domain, email, password, mfa_code, api, sso):
    headers = {
        "User-Agent": MOBILE_UA,
        "Accept": "application/json, text/plain, */*",
        "Content-Type": "application/json",
        "Origin": sso,
        "Accept-Language": "en-US,en;q=0.9",
    }
    params = {"clientId": MOBILE_CLIENT_ID, "locale": "en-US", "service": MOBILE_SERVICE}
    referer = f"{sso}/mobile/sso/en_US/sign-in?clientId={MOBILE_CLIENT_ID}&service={MOBILE_SERVICE}"

    # Step 1: GET sign-in page. If valid session cookies exist, Garmin returns
    # 302 redirect with a CAS ticket — skip login + MFA entirely.
    print(f"[garmin_auth_pw] checking session (GET mobile sign-in)...", file=sys.stderr)
    signin_resp = api.get(
        f"{sso}/mobile/sso/en_US/sign-in",
        params={"clientId": MOBILE_CLIENT_ID, "service": MOBILE_SERVICE},
        headers={"User-Agent": MOBILE_UA, "Accept": "text/html,...", "Accept-Language": "en-US,en;q=0.9"},
        max_redirects=0,
    )

    if signin_resp.status in (301, 302, 303, 307, 308):
        location = signin_resp.headers.get("location", "")
        ticket = _extract_ticket_from_url(location)
        if ticket:
            print(f"[garmin_auth_pw] session valid — ticket from redirect: {ticket[:20]}...", file=sys.stderr)
            return ticket, MOBILE_SERVICE
        print(f"[garmin_auth_pw] 302 redirect but no ticket in: {location[:80]}...", file=sys.stderr)

    # Step 2: No valid session — POST login credentials
    _random_delay("mobile")
    print(f"[garmin_auth_pw] posting login credentials...", file=sys.stderr)
    resp = api.post(
        f"{sso}/mobile/api/login",
        params=params,
        headers={**headers, "Referer": referer},
        data=json.dumps({
            "username": email,
            "password": password,
            "rememberMe": True,
            "captchaToken": "",
        }),
    )

    if resp.status == 429:
        raise RuntimeError("mobile API login 429 (rate limited by Cloudflare)")

    data = resp.json()
    resp_type = data.get("responseStatus", {}).get("type")

    if resp_type == "INVALID_USERNAME_PASSWORD":
        raise RuntimeError("Invalid username or password")

    if resp_type == "SUCCESSFUL":
        return data["serviceTicketId"], MOBILE_SERVICE

    if resp_type != "MFA_REQUIRED":
        raise RuntimeError(f"Unexpected login response: {resp_type}")

    # --- MFA required ---
    mfa_method = data.get("customerMfaInfo", {}).get("mfaLastMethodUsed", "email")
    print(f"[garmin_auth_pw] MFA required (method: {mfa_method})", file=sys.stderr)

    code = (mfa_code or "").strip()
    if not code and sys.stdin.isatty():
        print("Enter MFA code: ", file=sys.stderr, end="", flush=True)
        code = sys.stdin.readline().strip()
    if not code:
        raise RuntimeError("MFA required but no code provided (set SYNC__GARMIN__MFA_CODE or use stdin)")

    # Step 3: Verify MFA
    print(f"[garmin_auth_pw] verifying MFA code...", file=sys.stderr)
    mfa_data = {
        "mfaMethod": mfa_method,
        "mfaVerificationCode": code,
        "rememberMyBrowser": True,
        "reconsentList": [],
        "mfaSetup": False,
    }

    resp = api.post(
        f"{sso}/mobile/api/mfa/verifyCode",
        params=params,
        headers={**headers, "Referer": referer},
        data=json.dumps(mfa_data),
    )

    data = resp.json()
    resp_type = data.get("responseStatus", {}).get("type")

    if resp_type == "SUCCESSFUL":
        return data["serviceTicketId"], MOBILE_SERVICE

    if resp_type == "MFA_CODE_INVALID":
        raise RuntimeError(f"MFA code invalid — {data.get('responseStatus', {}).get('message', 'unknown')}")

    raise RuntimeError(f"Unexpected MFA response: {resp_type}")


def main():
    email = os.environ["SYNC__GARMIN__EMAIL"]
    password = os.environ["SYNC__GARMIN__PASSWORD"]
    domain = os.environ.get("SYNC__GARMIN__DOMAIN", "garmin.com")
    mfa_code = os.environ.get("SYNC__GARMIN__MFA_CODE", "").strip() or None
    session_path = os.environ.get(
        "SYNC__GARMIN__PLAYWRIGHT_SESSION",
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "cache", f"garmin_playwright_session_{domain.replace('.', '_')}.json"),
    )
    session_path = os.path.abspath(session_path)
    sso = f"https://sso.{domain}"

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)

        # Restore session cookies (optional — helps reduce CF scrutiny)
        session_state = None
        if os.path.exists(session_path):
            try:
                session_state = json.load(open(session_path))
                age_days = (time.time() - session_state.get("saved_at", 0)) / 86400
                print(f"[garmin_auth_pw] loaded session cookies ({age_days:.0f} days old)", file=sys.stderr)
            except Exception as e:
                print(f"[garmin_auth_pw] failed to load session cookies: {e}", file=sys.stderr)
                os.remove(session_path)

        context = browser.new_context(
            user_agent=MOBILE_UA,
            storage_state=session_path if session_state else None,
            viewport={"width": 375, "height": 812},
        )

        try:
            # API-based mobile login (no web page navigation — CF blocks SSO pages)
            ticket, service_url = _mobile_api_login(domain, email, password, mfa_code, context.request, sso)
            print(f"[garmin_auth_pw] login successful, ticket: {ticket[:20]}...", file=sys.stderr)

            # Exchange CAS ticket for DI OAuth2 token
            token = _di_exchange(domain, ticket)
            token["expires_at"] = int(time.time()) + token.get("expires_in", 64800)
            if "refresh_token_expires_in" in token:
                token["refresh_token_expires_at"] = int(time.time()) + token["refresh_token_expires_in"]

            # Save session cookies for next run
            os.makedirs(os.path.dirname(session_path), exist_ok=True)
            state = context.storage_state()
            state["saved_at"] = time.time()
            with open(session_path, "w") as f:
                json.dump(state, f)
            print(f"[garmin_auth_pw] session cookies saved to {session_path}", file=sys.stderr)

            json.dump(token, sys.stdout)
            return 0
        finally:
            context.close()
            browser.close()


if __name__ == "__main__":
    sys.exit(main())
