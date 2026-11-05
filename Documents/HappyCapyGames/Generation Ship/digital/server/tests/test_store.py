"""The store: catalog per country, Stripe Checkout, the webhook, orders and stock. Stripe itself is faked."""
import hashlib
import hmac
import json
import time

from test_hub import H, add, client, hub  # noqa: F401  (same app, same temporary databases)
from app import store

SECRET = "whsec_test"


def setup_function():
    with hub.hdb() as c:
        c.execute("DELETE FROM rows")
        c.execute("DELETE FROM metrics")
    client.put("/v1/hub/settings", json={"Store URL": "https://happycapygames.com/store/", "Stripe Tax": "off",
                                         "Gamefound campaigns": "Generation Ship | https://gamefound.com/en/projects/happy-capy-games/generation-ship"}, headers=H)
    add("products", SKU="GS-EN", Game="Generation Ship", Product="Generation Ship (EN)", **{"In store": True, "MSRP USD": 59, "MSRP CAD": 79, "Store image": "abc.webp"})
    add("products", SKU="GF-EN", Game="Generation Ship", Product="Generation Fleet (EN)", **{"In store": True, "MSRP USD": 29})
    add("products", SKU="GS-DE", Game="Generation Ship", Product="Generation Ship (DE)", **{"MSRP USD": 59})   # not in store
    add("shipping", Region="US", Countries="US", Store="Sell", Currency="USD", Rate=12, **{"Extra item": 4, "Fulfilled by": "US warehouse"})
    add("shipping", Region="Canada", Countries="CA", Store="Sell", Currency="CAD", Rate=18, **{"Extra item": 6, "Fulfilled by": "CA warehouse"})
    add("shipping", Region="EU", Countries="DE, FR, IT", Store="Gamefound")
    add("shipping", Region="UK", Countries="GB", Store="Sell", Currency="USD", Rate=10, **{"Fulfilled by": "US warehouse"})   # a mistake: still Gamefound
    add("shipping", Region="Rest of world", Store="Sell", Currency="USD", Rate=25, **{"Extra item": 10, "Fulfilled by": "US warehouse"})
    add("stock", Location="US warehouse", SKU="GS-EN", **{"On hand": 5, "Reserved": 1})
    add("stock", Location="US warehouse", SKU="GF-EN", **{"On hand": 2})


def cat(country):
    return client.get(f"/v1/hub/store/catalog?country={country}").json()


def test_catalog_per_country(monkeypatch):
    monkeypatch.delenv("STRIPE_SECRET_KEY", raising=False)
    assert cat("US")["open"] is False                  # no Stripe key: the store is a preview
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_x")
    us = cat("US")
    assert us["open"] is True
    assert us["mode"] == "sell" and us["currency"] == "USD" and us["shipping"] == {"rate": 12.0, "extra": 4.0}
    p = {x["sku"]: x for x in us["products"]}
    assert set(p) == {"GS-EN", "GF-EN"} and p["GS-EN"]["price"] == 59 and p["GS-EN"]["available"] == 4 and p["GF-EN"]["available"] == 2
    ca = {x["sku"]: x for x in cat("CA")["products"]}
    assert ca["GS-EN"]["price"] == 79 and ca["GS-EN"]["available"] == 0 and ca["GF-EN"]["price"] is None   # no CAD price, no CA stock
    for country in ("DE", "GB", "IE"):                 # the EU and the UK go to Gamefound, whatever the table says
        x = cat(country)
        assert x["mode"] == "gamefound" and all(q["price"] is None for q in x["products"])
        assert x["products"][0]["gamefound"].startswith("https://gamefound.com/")
    assert cat("JP")["region"] == "Rest of world" and cat("JP")["mode"] == "sell"


def test_checkout_builds_the_stripe_session(monkeypatch):
    seen = {}
    monkeypatch.setattr(store, "_stripe", lambda method, path, params: seen.update(params) or {"url": "https://checkout.stripe.com/c/pay/x"})
    r = client.post("/v1/hub/store/checkout", json={"country": "US", "items": [{"sku": "GS-EN", "qty": 2}, {"sku": "GF-EN", "qty": 1}]})
    assert r.status_code == 200 and r.json()["url"].startswith("https://checkout.stripe.com/")
    assert seen["line_items"][0]["price_data"] == {"currency": "usd", "unit_amount": 5900, "product_data": {
        "name": "Generation Ship (EN)", "metadata": {"sku": "GS-EN"}, "images": ["https://happycapygames.com/store/img.php?f=abc.webp"]}}
    assert seen["shipping_options"][0]["shipping_rate_data"]["fixed_amount"] == {"amount": 2000, "currency": "usd"}   # 12 + 2 x 4
    assert seen["shipping_address_collection"]["allowed_countries"] == ["US"]
    assert seen["metadata"]["items"] == "GS-EN:2:5900,GF-EN:1:2900" and seen["metadata"]["warehouse"] == "US warehouse"
    assert "automatic_tax" not in seen
    world = client.post("/v1/hub/store/checkout", json={"country": "JP", "items": [{"sku": "GS-EN", "qty": 1}]})
    allowed = seen["shipping_address_collection"]["allowed_countries"]
    assert world.status_code == 200 and "JP" in allowed and not {"US", "CA", "GB", "DE", "FR", "IE"} & set(allowed)
    assert client.post("/v1/hub/store/checkout", json={"country": "DE", "items": [{"sku": "GS-EN", "qty": 1}]}).status_code == 409
    assert client.post("/v1/hub/store/checkout", json={"country": "US", "items": [{"sku": "GF-EN", "qty": 3}]}).json()["detail"] == "Only 2 of Generation Fleet (EN) left."
    assert client.post("/v1/hub/store/checkout", json={"country": "CA", "items": [{"sku": "GS-EN", "qty": 1}]}).json()["detail"] == "Generation Ship (EN) is sold out."
    assert client.post("/v1/hub/store/checkout", json={"country": "US", "items": []}).status_code == 400


def _event(kind, obj, live=False):
    body = json.dumps({"type": kind, "livemode": live, "data": {"object": obj}}).encode()
    ts = str(int(time.time()))
    sig = hmac.new(SECRET.encode(), f"{ts}.".encode() + body, hashlib.sha256).hexdigest()
    return client.post("/v1/hub/store/stripe", content=body, headers={"stripe-signature": f"t={ts},v1={sig}"})


def _session(sid, items, total, pi):
    return {"id": sid, "payment_status": "paid", "currency": "usd", "created": int(time.time()), "payment_intent": pi,
            "amount_subtotal": total - 2000, "amount_total": total, "total_details": {"amount_shipping": 2000, "amount_tax": 0},
            "customer_details": {"email": "ann@example.com", "name": "Ann Buyer", "phone": "+1 555 0100"},
            "collected_information": {"shipping_details": {"name": "Ann Buyer", "address": {
                "line1": "1 Main St", "city": "Austin", "state": "TX", "postal_code": "78701", "country": "US"}}},
            "metadata": {"items": items, "warehouse": "US warehouse", "region": "US", "country": "US"}}


def test_webhook_orders_stock_and_refunds(monkeypatch):
    monkeypatch.setenv("STRIPE_WEBHOOK_SECRET", SECRET)
    monkeypatch.setattr(store, "_fx", lambda c, cur: 1.25)          # 1 EUR = 1.25 USD
    bad = client.post("/v1/hub/store/stripe", content=b"{}", headers={"stripe-signature": "t=1,v1=00"})
    assert bad.status_code == 400
    s1 = _session("cs_test_one", "GS-EN:2:5900,GF-EN:1:2900", 16700, "pi_1")
    assert _event("checkout.session.completed", s1).status_code == 200
    assert _event("checkout.session.completed", s1).status_code == 200      # Stripe sends again: still one order
    orders = client.get("/v1/hub/rows/orders", headers=H).json()["rows"]
    assert len(orders) == 1
    o = orders[0]
    assert o["Order"] == "HCG-0001" and o["Status"] == "Paid" and o["Total"] == 167 and o["Total EUR"] == 133.6
    assert o["Address"] == "Ann Buyer\n1 Main St\n78701 Austin\nTX\nUS" and o["Stripe"].endswith("/test/payments/pi_1")
    assert o["Items"] == "2 × Generation Ship (EN) [GS-EN]\n1 × Generation Fleet (EN) [GF-EN]"
    sales = client.get("/v1/hub/rows/sales", headers=H).json()["rows"]
    assert [(s["SKU"], s["Units"], s["Gross EUR"], s["Order ref"], s["Channel"]) for s in sales] == [
        ("GS-EN", 2, 94.4, "HCG-0001", "Webshop"), ("GF-EN", 1, 23.2, "HCG-0001", "Webshop")]
    stock = lambda: {s["SKU"]: (s["On hand"], s["Reserved"]) for s in client.get("/v1/hub/rows/stock", headers=H).json()["rows"]}
    assert stock() == {"GS-EN": (5, 3), "GF-EN": (2, 1)}
    assert client.get("/v1/hub/store/order?session=cs_test_one").json()["order"] == "HCG-0001"
    # shipped: out of stock for good
    client.put(f"/v1/hub/rows/orders/{o['_id']}", json={"data": {"Status": "Shipped", "Tracking": "USPS 9400"}}, headers=H)
    assert stock() == {"GS-EN": (3, 1), "GF-EN": (1, 0)}
    client.put(f"/v1/hub/rows/orders/{o['_id']}", json={"data": {"Status": "Delivered"}}, headers=H)
    assert stock() == {"GS-EN": (3, 1), "GF-EN": (1, 0)}                     # no second time
    # a second order, refunded in Stripe before it shipped: stock back, out of Sales
    _event("checkout.session.completed", _session("cs_test_two", "GS-EN:1:5900", 7900, "pi_2"))
    assert stock()["GS-EN"] == (3, 2)
    _event("charge.refunded", {"payment_intent": "pi_2", "refunded": True})
    o2 = next(x for x in client.get("/v1/hub/rows/orders", headers=H).json()["rows"] if x["Order"] == "HCG-0002")
    assert o2["Status"] == "Refunded" and stock()["GS-EN"] == (3, 1)
    assert {s["Order ref"] for s in client.get("/v1/hub/rows/sales", headers=H).json()["rows"]} == {"HCG-0001"}
