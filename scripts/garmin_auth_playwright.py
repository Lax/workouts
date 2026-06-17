#!/usr/bin/env python3
"""
Garmin DI OAuth2 auth via Playwright browser automation.

Strategy B: Real browser TLS fingerprint (cannot be blocked by Cloudflare).
Used as fallback when Strategy A (curl_cffi) is exhausted.

Flow:
  1. Attempt to restore saved session cookies (cache file)
  2. If cookies are valid (no SSO redirect), skip login
  3. If cookies expired: open headless browser, fill form, handle MFA
  4. After success: extract DI OAuth2 token, save session cookies
  5. Replay DI token via a browser fetch call

Session cookies persist ~1 year. Browser binary cached via GH Cache.

Input:  SYNC__GARMIN__EMAIL, SYNC__GARMIN__PASSWORD, SYNC__GARMIN__DOMAIN (default garmin.com)
        SYNC__GARMIN__MFA_CODE (optional, for MFA challenge)
        SYNC__GARMIN__PLAYWRIGHT_SESSION (path to session cookies file)
Output: JSON DI OAuth2 token to stdout, exit 0. Exit 1 on failure.
"""

import json
import os
import re
import sys
import time
import urllib.parse

from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout

MOBILE_UA = (
    "Mozilla/5.0 (Linux; Android 13; sdk_gphone64_arm64 Build/TE1A.220922.025; wv) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/132.0.0.0 "
    "Mobile Safari/537.36"
)
DI_TOKEN_URL = "https://diauth.garmin.com/di-oauth2-service/oauth/token"
DI_GRANT_TYPE = "https://connectapi.garmin.com/di-oauth2-service/oauth/grant/service_ticket"
DI_CLIENT_IDS = [
    "GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2",
    "GARMIN_CONNECT_MOBILE_ANDROID_DI_2024Q4",
    "GARMIN_CONNECT_MOBILE_ANDROID_DI",
]


def _di_exchange(domain, ticket):
    import requests

    url = DI_TOKEN_URL.replace("garmin.com", domain)
    for cid in DI_CLIENT_IDS:
        try:
            resp = requests.post(
                url,
                data={"grant_type": DI_GRANT_TYPE, "ticket": ticket, "client_id": cid},
                headers={"Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"},
                timeout=30,
            )
            if resp.status_code == 200:
                return resp.json()
            print(f"[garmin_auth_pw] DI exchange {cid}: HTTP {resp.status_code}", file=sys.stderr)
        except Exception as e:
            print(f"[garmin_auth_pw] DI exchange {cid}: {e}", file=sys.stderr)
    raise RuntimeError("All DI client IDs failed for ticket exchange")


def _extract_di_token_from_browser(page):
    token = page.evaluate("""
        async () => {
            try {
                const resp = await fetch(
                    '/gc-api/activitylist-service/activities/search/activities?start=0&limit=1',
                    { headers: { 'Accept': 'application/json' } }
                );
                if (resp.status === 200) {
                    return { status: 'ok' };
                }
                return { status: resp.status };
            } catch(e) {
                return { status: 0, error: e.message };
            }
        }
    """)
    return token.get("status") == "ok"


def _get_di_token_via_browser(page, domain):
    """Extract DI OAuth2 token by replaying a fetch inside the browser context."""
    token_json = page.evaluate("""
        async () => {
            try {
                const data = new URLSearchParams();
                data.append('grant_type', '""" + DI_GRANT_TYPE + """');
                data.append('ticket', 'BROWSER_SESSION');
                data.append('client_id', '""" + DI_CLIENT_IDS[0] + """');
                const resp = await fetch('""" + DI_TOKEN_URL.replace("garmin.com", domain) + """', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                    body: data.toString()
                });
                if (resp.ok) return await resp.json();
            } catch(e) {}
            return null;
        }
    """)
    return token_json


def _login_widget(domain, email, password, mfa_code, page):
    sso_base = f"https://sso.{domain}"
    sso_embed = f"{sso_base}/embed"
    embed_params = {
        "id": "gauth-widget",
        "embedWidget": "true",
        "gauthHost": sso_base,
    }
    signin_params = {
        **embed_params,
        "gauthHost": sso_embed,
        "service": sso_embed,
        "source": sso_embed,
        "redirectAfterAccountLoginUrl": sso_embed,
        "redirectAfterAccountCreationUrl": sso_embed,
    }

    signin_url = f"{sso_base}/signin?{urllib.parse.urlencode(signin_params)}"
    page.goto(signin_url, wait_until="domcontentloaded", timeout=30000)

    # Fill credentials
    page.fill('input[name="username"]', email, timeout=10000)
    page.fill('input[name="password"]', password, timeout=10000)
    page.click("#login-btn-signin", timeout=10000)

    # Wait for redirect (success = ticket redirect)
    try:
        page.wait_for_url("**/embed?ticket=**", timeout=60000)
    except PlaywrightTimeout:
        # Check for MFA
        url = page.url
        if "mfa" in url.lower() or "verify" in url.lower():
            if not mfa_code:
                raise RuntimeError("MFA required but SYNC__GARMIN__MFA_CODE not set")
            page.fill('input[id*="mfa"], input[name*="mfa"], input[type*="text"]', mfa_code, timeout=10000)
            # Try clicking submit button
            buttons = page.locator('button[type="submit"], input[type="submit"]').all()
            for btn in buttons:
                try:
                    btn.click(timeout=5000)
                    break
                except Exception:
                    continue
            try:
                page.wait_for_url("**/embed?ticket=**", timeout=30000)
            except PlaywrightTimeout:
                current_url = page.url
                if "ticket=" in current_url:
                    pass  # Already at ticket URL
                else:
                    raise RuntimeError(f"MFA verification did not produce ticket redirect. URL: {current_url}")
        elif "ticket=" in url:
            pass  # Already at ticket URL
        else:
            raise RuntimeError(f"Login did not redirect to ticket URL. URL: {url}")

    ticket_match = re.search(r'[?&]ticket=(ST-[^&\s]+)', page.url)
    if not ticket_match:
        raise RuntimeError(f"No CAS ticket found in URL: {page.url}")
    return ticket_match.group(1)


def _try_portal_login_widget(domain, email, password, mfa_code, page):
    sso = f"https://sso.{domain}"

    signin_url = f"{sso}/portal/sso/en-US/sign-in?clientId=GarminConnect&service=https://connect.garmin.com/app"
    page.goto(signin_url, wait_until="domcontentloaded", timeout=30000)

    page.fill('input[name="username"], input[type="email"], input[id*="username"]', email, timeout=10000)
    page.fill('input[name="password"], input[type="password"], input[id*="password"]', password, timeout=10000)

    buttons = page.locator('button[type="submit"]').all()
    for btn in buttons:
        try:
            btn.click(timeout=5000)
            break
        except Exception:
            continue

    try:
        page.wait_for_url("**/embed?ticket=**", timeout=60000)
    except PlaywrightTimeout:
        url = page.url
        if "ticket=" in url:
            pass
        else:
            raise RuntimeError(f"Portal login did not produce ticket redirect. URL: {url}")

    ticket_match = re.search(r'[?&]ticket=(ST-[^&\s]+)', page.url)
    if ticket_match:
        return ticket_match.group(1)
    raise RuntimeError("No ticket in portal login redirect URL")


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

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)

        # Restore session cookies
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
        page = context.new_page()

        try:
            # Check if session is still valid
            connect_url = f"https://connect.{domain}/modern/"
            page.goto(connect_url, wait_until="domcontentloaded", timeout=30000)
            time.sleep(2)
            needs_login = "sso" in page.url.lower() or "signin" in page.url.lower()

            ticket = None
            if needs_login:
                print("[garmin_auth_pw] session expired, performing login...", file=sys.stderr)

                # Try portal login first
                try:
                    ticket = _try_portal_login_widget(domain, email, password, mfa_code, page)
                except Exception as e:
                    print(f"[garmin_auth_pw] portal login failed: {e}", file=sys.stderr)

                # Fall back to widget flow
                if not ticket:
                    try:
                        ticket = _login_widget(domain, email, password, mfa_code, page)
                    except Exception as e:
                        print(f"[garmin_auth_pw] widget login failed: {e}", file=sys.stderr)
                        raise

                # Save session cookies for reuse
                os.makedirs(os.path.dirname(session_path), exist_ok=True)
                state = context.storage_state()
                state["saved_at"] = time.time()
                with open(session_path, "w") as f:
                    json.dump(state, f)
                print(f"[garmin_auth_pw] session cookies saved to {session_path}", file=sys.stderr)
            else:
                print("[garmin_auth_pw] session cookies valid, skipping login", file=sys.stderr)

            if ticket:
                # Exchange ticket for DI token (HTTP, same as Strategy A)
                token = _di_exchange(domain, ticket)
            else:
                # Session valid but no fresh ticket: trigger token exchange via browser fetch
                # First call connectapi to verify
                page.goto(f"https://connect.{domain}/modern/", wait_until="domcontentloaded", timeout=30000)
                time.sleep(2)

                # Extract a fresh access token by intercepting an API call
                # We need a fresh DI token. The most reliable way is to replay the ticket exchange.
                # But without a ticket, we call the API directly and let the browser handle auth.
                token_raw = page.evaluate("""
                    async () => {
                        const resp = await fetch(
                            '/gc-api/activitylist-service/activities/search/activities?start=0&limit=1',
                            { headers: { 'Accept': 'application/json' } }
                        );
                        if (resp.ok) {
                            const data = await resp.json();
                            return { verified: true };
                        }
                        return { verified: false, status: resp.status };
                    }
                """)
                if not token_raw.get("verified"):
                    raise RuntimeError(f"Session appears valid but API call failed")

                # Try to re-authenticate to get a fresh DI token
                ticket = _try_portal_login_widget(domain, email, password, mfa_code, page)
                token = _di_exchange(domain, ticket)

            # Add computed timestamps
            token["expires_at"] = int(time.time()) + token.get("expires_in", 64800)
            if "refresh_token_expires_in" in token:
                token["refresh_token_expires_at"] = int(time.time()) + token["refresh_token_expires_in"]

            json.dump(token, sys.stdout)
            return 0
        finally:
            context.close()
            browser.close()


if __name__ == "__main__":
    sys.exit(main())
