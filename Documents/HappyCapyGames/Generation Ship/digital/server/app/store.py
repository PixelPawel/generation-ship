"""The Happy Capy Games store (Settings > Store URL, e.g. https://happycapygames.com/store/). It sells our games
everywhere except the EU and the UK: there the store sends buyers to Gamefound, so we never owe EU or UK VAT. That
rule is built in (EU_UK below) and doesn't depend on the Shipping table.

Payment is Stripe Checkout: Stripe's own page, card data never touches us. A paid checkout becomes an order in the
hub's Orders table, Sales rows (in EUR, at the ECB rate of the day) and a reservation in Stock at the warehouse that
ships the buyer's region.

What sells where comes from the hub's tables:
  Products  In store, MSRP USD / MSRP CAD / MSRP AUD, Tagline, Description, Players, Age, Play time, Store image
  Shipping  per region: Countries (empty = the rest of the world), Store (Sell / Gamefound / Off), Currency,
            Rate (the first game) and Extra item (each further game) in that currency, Fulfilled by (= a Stock
            Location: the warehouse that ships the region)
A product can be bought in a region when it's In store, has a price in the region's currency and the region's
warehouse has it (Stock: On hand - Reserved).

    GET  /v1/hub/store/catalog?country=US        what the store shows a visitor from there (public)
    POST /v1/hub/store/checkout {country, items: [{sku, qty}]}  -> {url}: the Stripe Checkout page (public)
    GET  /v1/hub/store/order?session=cs_...      the thank-you page's summary of the order (public)
    POST /v1/hub/store/stripe                    Stripe's webhook (signed with STRIPE_WEBHOOK_SECRET)

Orders' Status: Paid -> Packed -> Shipped (Stock: On hand and Reserved go down) -> Delivered. Cancelled or Refunded
frees the reservation (if it hadn't shipped) and takes the order's Sales rows out. A refund made in Stripe's dashboard
sets Refunded by itself. .env: STRIPE_SECRET_KEY (sk_test_... while testing), STRIPE_WEBHOOK_SECRET (whsec_...).
"""
import hashlib
import hmac
import json
import os
import re
import threading
import time
import xml.etree.ElementTree as ET
from datetime import datetime

import requests
from fastapi import APIRouter, Body, HTTPException, Query, Request

from .hub import TAB_BY_NAME, TZ, _f, _next_id, clean_row, hdb, kv_get, kv_put, load_rows, put_metric, setting, today

router = APIRouter(prefix="/store")   # mounted into the hub router (/v1/hub) at the end of hub.py
STRIPE_API = os.environ.get("STRIPE_API_BASE", "https://api.stripe.com").rstrip("/")
CURRENCIES = ("USD", "CAD", "AUD")
MAX_QTY, MAX_LINES = 10, 20
# never sold here, whatever the Shipping table says: EU VAT and UK VAT start with the first sale
EU_UK = set("AT BE BG HR CY CZ DK EE FI FR DE GR HU IE IT LV LT LU MT NL PL PT RO SK SI ES SE GB IM JE GG".split())
# every ISO country Stripe Checkout can ship to (its list leaves out a few: sanctions, US territories it handles as US)
ALL_COUNTRIES = """AC AD AE AF AG AI AL AM AO AQ AR AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW
BY BZ CA CD CF CG CH CI CK CL CM CN CO CR CV CW CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FO FR GA GB GD GE GF
GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HN HR HT HU ID IE IL IM IN IO IQ IS IT JE JM JO JP KE KG KH KI KM KN KR KW KY
KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MK ML MM MN MO MQ MR MS MT MU MV MW MX MY MZ NA NC NE NG NI NL NO
NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PY QA RE RO RS RU RW SA SB SC SE SG SH SI SJ SK SL SM SN SO SR SS ST SV
SX SZ TA TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG US UY UZ VA VC VE VG VN VU WF WS XK YE YT ZA ZM ZW""".split()
_checkouts: list[float] = []      # recent checkout sessions, for a simple brake on abuse
_lock = threading.Lock()


# ---------------------------------------------------------------- regions, products, stock

def _regions(c) -> list[dict]:
    out = []
    for r in load_rows(c, "Shipping"):
        countries = sorted({x.upper() for x in re.findall(r"\b[A-Za-z]{2}\b", r.get("Countries") or "")})
        out.append({"name": r.get("Region") or "", "countries": countries, "mode": (r.get("Store") or "Off").strip().lower(),
                    "currency": (r.get("Currency") or "USD").strip().upper(), "rate": _f(r.get("Rate")),
                    "extra": _f(r.get("Extra item")), "warehouse": (r.get("Fulfilled by") or "").strip()})
    return out


def _region_for(regions: list[dict], country: str) -> dict | None:
    named = [r for r in regions if country in r["countries"]]
    rest = [r for r in regions if not r["countries"]]
    return (named or rest or [None])[0]


def _ship_to(regions: list[dict], region: dict) -> list[str]:
    """The countries Stripe may take as the shipping address for this region (never the EU or the UK)."""
    if region["countries"]:
        return [x for x in region["countries"] if x not in EU_UK and x in ALL_COUNTRIES]
    taken = {x for r in regions for x in r["countries"]}
    return [x for x in ALL_COUNTRIES if x not in taken and x not in EU_UK]


def _gamefound(c) -> dict:
    """Game -> its Gamefound page (Settings > Gamefound campaigns: "Name | link" per line)."""
    out = {}
    for line in setting(c, "Gamefound campaigns").splitlines():
        name, _, url = line.partition("|")
        if url.strip().startswith("http"):
            out[name.strip()] = url.strip()
    return out


def _available(c, warehouse: str) -> dict:
    """SKU -> how many the warehouse can sell (On hand - Reserved)."""
    out = {}
    if not warehouse:
        return out
    for r in load_rows(c, "Stock"):
        if (r.get("Location") or "").strip() == warehouse:
            sku = (r.get("SKU") or "").strip()
            out[sku] = out.get(sku, 0) + int(_f(r.get("On hand")) - _f(r.get("Reserved")))
    return out


def _price(p: dict, currency: str) -> float | None:
    v = p.get(f"MSRP {currency}")
    return round(float(v), 2) if v not in (None, "") and _f(v) > 0 else None


def catalog_for(c, country: str) -> dict:
    country = (country or "").upper()[:2]
    regions = _regions(c)
    region = _region_for(regions, country) if country else None
    gf = _gamefound(c)
    if country in EU_UK:
        mode = "gamefound"
    elif region is None or region["mode"] not in ("sell", "gamefound"):
        mode = "off"
    else:
        mode = region["mode"]
    currency = region["currency"] if region and region["currency"] in CURRENCIES else "USD"
    stock = _available(c, region["warehouse"]) if mode == "sell" else {}
    products = []
    for p in load_rows(c, "Products"):
        if not p.get("In store") or not p.get("SKU"):
            continue
        price = _price(p, currency) if mode == "sell" else None
        products.append({
            "sku": p["SKU"], "game": p.get("Game") or "", "name": p.get("Product") or p["SKU"], "edition": p.get("Edition") or "",
            "language": p.get("Language") or "", "tagline": p.get("Tagline") or "", "description": p.get("Description") or "",
            "players": p.get("Players") or "", "age": p.get("Age") or "", "time": p.get("Play time") or "",
            "image": p.get("Store image") or "", "gtin": p.get("GTIN") or "", "price": price,
            "available": min(MAX_QTY, max(0, stock.get(p["SKU"], 0))) if price else 0,
            "gamefound": p.get("Store URL") or gf.get(p.get("Game") or "", ""),
        })
    return {"country": country, "region": region["name"] if region else "", "mode": mode, "currency": currency,
            "open": bool(os.environ.get("STRIPE_SECRET_KEY")),     # no Stripe yet: a preview, nothing can be bought
            "shipping": {"rate": region["rate"], "extra": region["extra"]} if region and mode == "sell" else None,
            "products": products, "gamefound": gf}


# ---------------------------------------------------------------- Stripe

def _form(prefix: str, value, out: list) -> list:
    """Stripe's form encoding: {"a": {"b": [1]}} -> [("a[b][0]", "1")]."""
    if isinstance(value, dict):
        for k, v in value.items():
            _form(f"{prefix}[{k}]" if prefix else k, v, out)
    elif isinstance(value, list):
        for i, v in enumerate(value):
            _form(f"{prefix}[{i}]", v, out)
    elif isinstance(value, bool):
        out.append((prefix, "true" if value else "false"))
    elif value is not None:
        out.append((prefix, str(value)))
    return out


def _stripe(method: str, path: str, params: dict | None = None) -> dict:
    key = os.environ.get("STRIPE_SECRET_KEY", "")
    if not key:
        raise HTTPException(503, "The store isn't connected to Stripe yet.")
    r = requests.request(method, STRIPE_API + path, data=_form("", params or {}, []) if method == "POST" else None,
                         params=_form("", params or {}, []) if method == "GET" else None, auth=(key, ""), timeout=25)
    data = r.json()
    if r.status_code >= 400:
        raise HTTPException(502, "Stripe: " + str((data.get("error") or {}).get("message") or r.status_code)[:300])
    return data


def _verify(payload: bytes, header: str, secret: str, tolerance: int = 300) -> None:
    parts = dict(p.split("=", 1) for p in (header or "").split(",") if "=" in p)
    sigs = [v for k, v in (p.split("=", 1) for p in (header or "").split(",") if "=" in p) if k == "v1"]
    ts = parts.get("t", "")
    if not ts.isdigit() or abs(time.time() - int(ts)) > tolerance:
        raise HTTPException(400, "Stale or missing signature.")
    want = hmac.new(secret.encode(), f"{ts}.".encode() + payload, hashlib.sha256).hexdigest()
    if not any(hmac.compare_digest(want, s) for s in sigs):
        raise HTTPException(400, "Bad signature.")


def _cents(v: float) -> int:
    return int(round(v * 100))


@router.get("/catalog")
def get_catalog(country: str = Query("", max_length=2)) -> dict:
    with hdb() as c:
        out = catalog_for(c, country)
        out["store_url"] = setting(c, "Store URL")
        return out


@router.post("/checkout")
def checkout(body: dict = Body(...)) -> dict:
    country = str(body.get("country") or "").upper()[:2]
    items = body.get("items") if isinstance(body.get("items"), list) else []
    want: dict[str, int] = {}
    for it in items[:MAX_LINES]:
        if isinstance(it, dict) and str(it.get("sku") or "").strip():
            want[str(it["sku"]).strip()] = want.get(str(it["sku"]).strip(), 0) + max(0, int(_f(it.get("qty"))))
    want = {k: v for k, v in want.items() if v > 0}
    if not want:
        raise HTTPException(400, "The cart is empty.")
    with hdb() as c:
        cat = catalog_for(c, country)
        store_url = setting(c, "Store URL").rstrip("/") + "/"
        tax = setting(c, "Stripe Tax").lower() in ("on", "yes", "true", "1")
        regions = _regions(c)
        region = _region_for(regions, country)
    if cat["mode"] != "sell":
        raise HTTPException(409, "We don't ship there from this store." + (" Our games are on Gamefound." if cat["mode"] == "gamefound" else ""))
    if not store_url.startswith("https://"):
        raise HTTPException(503, "The store isn't set up yet (Settings > Store URL).")
    by_sku = {p["sku"]: p for p in cat["products"]}
    lines, n = [], 0
    for sku, qty in want.items():
        p = by_sku.get(sku)
        if not p or not p["price"]:
            raise HTTPException(409, f"{sku} can't be ordered here.")
        if qty > p["available"]:
            raise HTTPException(409, f"Only {p['available']} of {p['name']} left." if p["available"] else f"{p['name']} is sold out.")
        lines.append((p, qty))
        n += qty
    with _lock:
        now = time.time()
        _checkouts[:] = [t for t in _checkouts if now - t < 600]
        if len(_checkouts) >= 120:
            raise HTTPException(429, "Too many checkouts right now. Try again in a few minutes.")
        _checkouts.append(now)
    cur = cat["currency"].lower()
    ship = cat["shipping"]["rate"] + cat["shipping"]["extra"] * (n - 1)
    params = {
        "mode": "payment", "locale": "auto", "billing_address_collection": "auto",
        "success_url": store_url + "?thanks={CHECKOUT_SESSION_ID}", "cancel_url": store_url + "#cart",
        "line_items": [{"quantity": q, "price_data": {"currency": cur, "unit_amount": _cents(p["price"]), "product_data": {
            "name": p["name"], "metadata": {"sku": p["sku"]}, **({"images": [store_url + "img.php?f=" + p["image"]]} if p["image"] else {})}}}
            for p, q in lines],
        "shipping_address_collection": {"allowed_countries": _ship_to(regions, region)},
        "shipping_options": [{"shipping_rate_data": {"type": "fixed_amount", "display_name": "Standard shipping",
                                                     "fixed_amount": {"amount": _cents(ship), "currency": cur}}}],
        "phone_number_collection": {"enabled": True},
        "metadata": {"items": ",".join(f"{p['sku']}:{q}:{_cents(p['price'])}" for p, q in lines),
                     "region": region["name"], "warehouse": region["warehouse"], "country": country},
        "payment_intent_data": {"metadata": {"store": "happycapygames"}},
    }
    if tax:
        params["automatic_tax"] = {"enabled": True}
    s = _stripe("POST", "/v1/checkout/sessions", params)
    return {"url": s["url"]}


# ---------------------------------------------------------------- orders

def _fx(c, currency: str) -> float | None:
    """Units of `currency` per euro: the ECB's reference rate, at most two days old (fetched when needed)."""
    key = f"fx.{currency.lower()}"
    r = c.execute("SELECT day, value FROM metrics WHERE key = ? ORDER BY day DESC LIMIT 1", (key,)).fetchone()
    if r and (today() - datetime.fromisoformat(r["day"]).date()).days <= 2:
        return r["value"]
    try:
        xml = requests.get("https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml", timeout=15).text
        rates = {e.get("currency"): float(e.get("rate")) for e in ET.fromstring(xml).iter() if e.get("currency")}
        for cur, v in rates.items():
            if cur in CURRENCIES:
                put_metric(c, today().isoformat(), f"fx.{cur.lower()}", v, "ecb")
        return rates.get(currency) or (r["value"] if r else None)
    except Exception:
        return r["value"] if r else None


def _orders(c) -> list[dict]:
    return load_rows(c, "Orders")


def _save(c, tab: str, data: dict, row_id: int | None = None, user: str = "Stripe") -> int:
    now = int(time.time())
    slug = TAB_BY_NAME[tab]["slug"]
    if row_id is None:
        return c.execute("INSERT INTO rows (tab, data, created_at, updated_at, updated_by) VALUES (?, ?, ?, ?, ?)",
                         (slug, json.dumps(data, ensure_ascii=False), now, now, user)).lastrowid
    old = c.execute("SELECT updated_at FROM rows WHERE id = ?", (row_id,)).fetchone()
    c.execute("UPDATE rows SET data = ?, updated_at = ?, updated_by = ? WHERE id = ?",
              (json.dumps(data, ensure_ascii=False), max(now, (old["updated_at"] if old else 0) + 1), user, row_id))
    return row_id


def _stock(c, warehouse: str, lines: list[dict], reserved: int = 0, on_hand: int = 0) -> None:
    """Moves Stock at the warehouse: reserved / on_hand are -1, 0 or +1 times each line's quantity."""
    rows = [r for r in load_rows(c, "Stock") if (r.get("Location") or "").strip() == warehouse]
    for ln in lines:
        r = next((x for x in rows if (x.get("SKU") or "").strip() == ln["sku"]), None)
        if r is None:
            continue
        rid = r.pop("_id")
        for k in ("_created", "_updated", "_by"):
            r.pop(k, None)
        r["Reserved"] = max(0, _f(r.get("Reserved")) + reserved * ln["qty"])
        r["On hand"] = max(0, _f(r.get("On hand")) + on_hand * ln["qty"])
        r["Updated"] = today().isoformat()
        _save(c, "Stock", r, rid)


def _address(a: dict | None) -> str:
    a = a or {}
    city = " ".join(x for x in (a.get("postal_code"), a.get("city")) if x)
    return "\n".join(x for x in (a.get("line1"), a.get("line2"), city, a.get("state"), a.get("country")) if x)


def record_order(c, s: dict, livemode: bool) -> str | None:
    """A paid Checkout Session -> an order (once per session), its Sales rows, its Stock reservation."""
    if any(o.get("_session") == s["id"] for o in _orders(c)):
        return None
    meta = s.get("metadata") or {}
    lines = []
    for part in (meta.get("items") or "").split(","):
        sku, _, rest = part.partition(":")
        qty, _, unit = rest.partition(":")
        if sku and qty.isdigit():
            lines.append({"sku": sku, "qty": int(qty), "unit": int(unit or 0) / 100})
    names = {p.get("SKU"): p.get("Product") or p.get("SKU") for p in load_rows(c, "Products")}
    cur = (s.get("currency") or "usd").upper()
    tot = s.get("total_details") or {}
    cust = s.get("customer_details") or {}
    ship = s.get("shipping_details") or (s.get("collected_information") or {}).get("shipping_details") or {}
    rate = _fx(c, cur) if cur != "EUR" else 1.0
    total = (s.get("amount_total") or 0) / 100
    pi = s.get("payment_intent") or ""
    order_id = _next_id(c, TAB_BY_NAME["Orders"]["slug"], "Order", "HCG-")
    day = datetime.fromtimestamp(s.get("created") or time.time(), TZ).date().isoformat()
    data = clean_row(TAB_BY_NAME["Orders"], {
        "Order": order_id, "Date": day, "Status": "Paid", "Name": ship.get("name") or cust.get("name") or "",
        "Email": cust.get("email") or "", "Phone": cust.get("phone") or "", "Country": (ship.get("address") or cust.get("address") or {}).get("country") or meta.get("country") or "",
        "Address": "\n".join(x for x in (ship.get("name"), _address(ship.get("address") or cust.get("address"))) if x),
        "Items": "\n".join(f"{ln['qty']} × {names.get(ln['sku'], ln['sku'])} [{ln['sku']}]" for ln in lines),
        "Currency": cur, "Subtotal": (s.get("amount_subtotal") or 0) / 100, "Shipping": (tot.get("amount_shipping") or 0) / 100,
        "Tax": (tot.get("amount_tax") or 0) / 100, "Total": total, "Total EUR": round(total / rate, 2) if rate else None,
        "Fulfilled by": meta.get("warehouse") or "",
        "Stripe": f"https://dashboard.stripe.com/{'' if livemode else 'test/'}payments/{pi}" if pi else "",
    }, allow_auto=True)
    data.update({"_session": s["id"], "_payment_intent": pi, "_lines": lines, "_reserved": True, "_live": livemode})
    _save(c, "Orders", data)
    for ln in lines:
        _save(c, "Sales", clean_row(TAB_BY_NAME["Sales"], {
            "Date": day, "Channel": "Webshop", "Event / customer": data["Name"], "Country": data["Country"], "SKU": ln["sku"],
            "Units": ln["qty"], "Gross EUR": round(ln["unit"] * ln["qty"] / rate, 2) if rate else None, "Order ref": order_id,
            "Notes": f"{cur} {ln['unit'] * ln['qty']:.2f}" + ("" if livemode else " (Stripe test mode)")}))
    _stock(c, data["Fulfilled by"], lines, reserved=+1)
    return order_id


def order_status_changed(c, data: dict, old: str) -> None:
    """Called by hub.change_row when someone changes an order: Shipped takes it out of Stock, Cancelled / Refunded
    frees the reservation and takes the Sales rows out."""
    new = data.get("Status") or ""
    lines = data.get("_lines") or []
    wh = data.get("Fulfilled by") or ""
    if new == old:
        return
    if new in ("Shipped", "Delivered") and not data.get("_shipped"):
        _stock(c, wh, lines, reserved=-1 if data.get("_reserved") else 0, on_hand=-1)
        data["_shipped"], data["_reserved"] = True, False
    elif new in ("Cancelled", "Refunded"):
        if data.get("_reserved") and not data.get("_shipped"):
            _stock(c, wh, lines, reserved=-1)
            data["_reserved"] = False
        slug = TAB_BY_NAME["Sales"]["slug"]
        for r in c.execute("SELECT id, data FROM rows WHERE tab = ?", (slug,)).fetchall():
            if json.loads(r["data"]).get("Order ref") == data.get("Order"):
                c.execute("DELETE FROM rows WHERE id = ?", (r["id"],))


@router.post("/stripe")
async def stripe_webhook(request: Request) -> dict:
    secret = os.environ.get("STRIPE_WEBHOOK_SECRET", "")
    if not secret:
        raise HTTPException(503, "No webhook secret on the server.")
    payload = await request.body()
    _verify(payload, request.headers.get("stripe-signature", ""), secret)
    event = json.loads(payload)
    obj = (event.get("data") or {}).get("object") or {}
    kind = event.get("type")
    from .hub import _changed
    if kind in ("checkout.session.completed", "checkout.session.async_payment_succeeded") and obj.get("payment_status") == "paid":
        with hdb() as c:
            record_order(c, obj, bool(event.get("livemode")))
        _changed()
    elif kind == "charge.refunded" and obj.get("refunded"):
        with hdb() as c:
            for o in _orders(c):
                if o.get("_payment_intent") and o["_payment_intent"] == obj.get("payment_intent") and o.get("Status") != "Refunded":
                    rid = o.pop("_id")
                    for k in ("_created", "_updated", "_by"):
                        o.pop(k, None)
                    old, o["Status"] = o.get("Status") or "", "Refunded"
                    order_status_changed(c, o, old)
                    _save(c, "Orders", o, rid)
        _changed()
    return {"ok": True}


@router.get("/order")
def order_summary(session: str = Query(..., min_length=10, max_length=200)) -> dict:
    """The thank-you page: the order number and what's in it (no address, no email: the session id is in the URL)."""
    with hdb() as c:
        for o in _orders(c):
            if o.get("_session") == session:
                return {"order": o.get("Order"), "items": o.get("Items"), "total": o.get("Total"), "currency": o.get("Currency"),
                        "status": o.get("Status")}
    return {"order": None}    # Stripe's confirmation can take a few seconds: the page asks again
