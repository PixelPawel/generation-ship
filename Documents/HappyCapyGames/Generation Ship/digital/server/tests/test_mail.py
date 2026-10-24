"""Run with:  pip install -r requirements.txt httpx pytest  &&  pytest tests"""
import os
import smtplib
import tempfile

os.environ["DB_PATH"] = os.path.join(tempfile.mkdtemp(), "votes.db")
os.environ["ADMIN_TOKEN"] = "test-admin-token"
os.environ["MAIL_TOKEN"] = "test-mail-token"

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402  (first: main registers the routers)
from app import mail as mailmod  # noqa: E402

client = TestClient(app)
TOKEN = {"X-Mail-Token": "test-mail-token"}
SENT = []


class FakeSMTP:
    fail = False

    def __init__(self, host, port, timeout=None):
        self.host, self.port = host, port

    def starttls(self):
        pass

    def login(self, user, password):
        assert user == "info@pixelpawel.de" and password == "secret"

    def send_message(self, msg):
        if FakeSMTP.fail:
            raise smtplib.SMTPRecipientsRefused({"x@y.de": (550, b"no")})
        SENT.append(msg)

    def quit(self):
        pass


def configure(monkeypatch):
    for k, v in {"SMTP_HOST": "smtp.hostinger.com", "SMTP_PORT": "465", "SMTP_USER": "info@pixelpawel.de",
                 "SMTP_PASSWORD": "secret"}.items():
        monkeypatch.setenv(k, v)
    monkeypatch.setattr(smtplib, "SMTP_SSL", FakeSMTP)
    monkeypatch.setattr(smtplib, "SMTP", FakeSMTP)


def send(body, headers=TOKEN):
    return client.post("/v1/mail/send", json=body, headers=headers)


def test_needs_token(monkeypatch):
    configure(monkeypatch)
    assert send({"to": "a@b.de", "subject": "s", "text": "t"}, headers={}).status_code == 403
    assert send({"to": "a@b.de", "subject": "s", "text": "t"}, headers={"X-Mail-Token": "wrong"}).status_code == 403
    # the admin token is not enough
    assert send({"to": "a@b.de", "subject": "s", "text": "t"}, headers={"X-Mail-Token": "test-admin-token"}).status_code == 403


def test_not_configured(monkeypatch):
    for k in ("SMTP_HOST", "SMTP_USER", "SMTP_PASSWORD"):
        monkeypatch.delenv(k, raising=False)
    assert send({"to": "a@b.de", "subject": "s", "text": "t"}).status_code == 503
    assert client.get("/v1/mail/status", headers=TOKEN).json()["configured"] is False


def test_send_text_and_html(monkeypatch):
    configure(monkeypatch)
    SENT.clear()
    r = send({"to": ["anna@example.com", "bob@example.org"], "subject": "Bitte bestätigen", "text": "Hallo",
              "html": "<p>Hallo</p>", "reply_to": "info@pixelpawel.de", "from_name": "Happy Capy Games"})
    assert r.status_code == 200, r.text
    msg = SENT[-1]
    assert msg["From"] == "Happy Capy Games <info@pixelpawel.de>"
    assert msg["To"] == "anna@example.com, bob@example.org"
    assert msg["Reply-To"] == "info@pixelpawel.de"
    assert msg["Message-ID"].endswith("@pixelpawel.de>")
    assert msg.get_body(("html",)).get_content().strip() == "<p>Hallo</p>"
    status = client.get("/v1/mail/status", headers=TOKEN).json()
    assert status["configured"] and status["sender"] == "info@pixelpawel.de" and status["sent_24h"] >= 1


def test_validation(monkeypatch):
    configure(monkeypatch)
    assert send({"to": "not-an-address", "subject": "s", "text": "t"}).status_code == 400
    assert send({"to": [f"a{i}@b.de" for i in range(11)], "subject": "s", "text": "t"}).status_code == 400
    assert send({"to": "a@b.de", "subject": "s\r\nBcc: evil@x.de", "text": "t"}).status_code == 400
    assert send({"to": "a@b.de", "subject": "s", "text": "t", "from_name": "x\nBcc: y@z.de"}).status_code == 400
    assert send({"to": "a@b.de", "subject": "s", "text": "t", "reply_to": "nope"}).status_code == 400
    assert send({"to": "a@b.de", "subject": "", "text": "t"}).status_code == 422


def test_smtp_failure_is_logged(monkeypatch):
    configure(monkeypatch)
    FakeSMTP.fail = True
    try:
        r = send({"to": "x@y.de", "subject": "s", "text": "t"})
    finally:
        FakeSMTP.fail = False
    assert r.status_code == 502
    status = client.get("/v1/mail/status", headers=TOKEN).json()
    assert status["failed_24h"] >= 1 and "SMTPRecipientsRefused" in status["last_error"]["error"]


def test_hourly_limit(monkeypatch):
    configure(monkeypatch)
    monkeypatch.setattr(mailmod, "MAILS_PER_HOUR", 1)
    send({"to": "a@b.de", "subject": "s", "text": "t"})
    assert send({"to": "a@b.de", "subject": "s", "text": "t"}).status_code == 429
