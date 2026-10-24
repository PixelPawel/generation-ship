"""Outgoing mail for the HCG Hub sheet. The company mailbox (info@pixelpawel.de) is Hostinger Mail, and the hub's
Apps Script can't speak SMTP, so it posts here and this sends through the mailbox: double opt-in mails, support
confirmations and notices, the weekly digest. The sender is always SMTP_USER, so the mails pass the domain's
SPF/DKIM.

Send:   POST /v1/mail/send   (header X-Mail-Token)
        {"to": "a@b.de" | ["a@b.de", ...], "subject", "text", "html"?, "reply_to"?, "from_name"?}
Status: GET  /v1/mail/status (header X-Mail-Token) -> configured?, sent/failed in the last 24 h, last error

Settings in /opt/hcg-api/.env: SMTP_HOST (smtp.hostinger.com), SMTP_PORT (465 = SSL, 587 = STARTTLS), SMTP_USER,
SMTP_PASSWORD, MAIL_TOKEN. MAIL_TOKEN is separate from ADMIN_TOKEN: the sheet only gets the right to send mail.
Every send is logged in mail_log (recipient domains and a hash, subject, result), never the body.
"""
import hashlib
import hmac
import os
import re
import smtplib
import time
from email.message import EmailMessage
from email.utils import formataddr, formatdate, make_msgid

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

from .main import db

router = APIRouter()
MAX_RECIPIENTS = 10
MAILS_PER_HOUR = 300
EMAIL_RE = re.compile(r"^[^@\s<>,;\"]{1,64}@[A-Za-z0-9.-]{1,253}\.[A-Za-z]{2,24}$")


def init_mail() -> None:
    with db() as c:
        c.execute(
            """CREATE TABLE IF NOT EXISTS mail_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at INTEGER NOT NULL,
                recipients TEXT NOT NULL,
                subject TEXT NOT NULL,
                ok INTEGER NOT NULL,
                error TEXT NOT NULL
            )"""
        )
        c.execute("CREATE INDEX IF NOT EXISTS mail_log_time ON mail_log(created_at)")


init_mail()


def _require_mail_token(token: str | None) -> None:
    expected = os.environ.get("MAIL_TOKEN", "")
    if not expected or not token or not hmac.compare_digest(token, expected):
        raise HTTPException(403, "Mail token required")


def _smtp_settings() -> dict | None:
    s = {k: os.environ.get(k, "") for k in ("SMTP_HOST", "SMTP_PORT", "SMTP_USER", "SMTP_PASSWORD")}
    if not (s["SMTP_HOST"] and s["SMTP_USER"] and s["SMTP_PASSWORD"]):
        return None
    s["SMTP_PORT"] = int(s["SMTP_PORT"] or 465)
    return s


def _log_entry(recipients: list[str]) -> str:
    """Domains stay readable for debugging; the full addresses only as a short hash."""
    return ", ".join(f"{a.split('@')[1]}#{hashlib.sha256(a.lower().encode()).hexdigest()[:8]}" for a in recipients)


def _log(recipients: list[str], subject: str, ok: bool, error: str = "") -> None:
    with db() as c:
        c.execute("INSERT INTO mail_log (created_at, recipients, subject, ok, error) VALUES (?, ?, ?, ?, ?)",
                  (int(time.time()), _log_entry(recipients), subject[:200], int(ok), error[:300]))


def _sent_last_hour() -> int:
    with db() as c:
        return c.execute("SELECT COUNT(*) FROM mail_log WHERE ok = 1 AND created_at > ?",
                         (int(time.time()) - 3600,)).fetchone()[0]


class MailIn(BaseModel):
    to: str | list[str]
    subject: str = Field(min_length=1, max_length=300)
    text: str = Field(min_length=1, max_length=200_000)
    html: str = Field(default="", max_length=500_000)
    reply_to: str = ""
    from_name: str = Field(default="Happy Capy Games", max_length=80)


def _clean_header(value: str) -> str:
    if "\r" in value or "\n" in value:
        raise HTTPException(400, "Line breaks are not allowed in headers")
    return value.strip()


def _build(mail: MailIn, recipients: list[str], sender: str) -> EmailMessage:
    msg = EmailMessage()
    msg["From"] = formataddr((_clean_header(mail.from_name), sender))
    msg["To"] = ", ".join(recipients)
    msg["Subject"] = _clean_header(mail.subject)
    msg["Date"] = formatdate(localtime=True)
    msg["Message-ID"] = make_msgid(domain=sender.split("@")[1])
    if mail.reply_to:
        reply_to = _clean_header(mail.reply_to)
        if not EMAIL_RE.match(reply_to):
            raise HTTPException(400, "Invalid reply_to")
        msg["Reply-To"] = reply_to
    msg.set_content(mail.text)
    if mail.html:
        msg.add_alternative(mail.html, subtype="html")
    return msg


def _send(settings: dict, msg: EmailMessage) -> None:
    host, port = settings["SMTP_HOST"], settings["SMTP_PORT"]
    if port == 465:
        server = smtplib.SMTP_SSL(host, port, timeout=30)
    else:
        server = smtplib.SMTP(host, port, timeout=30)
        server.starttls()
    try:
        server.login(settings["SMTP_USER"], settings["SMTP_PASSWORD"])
        server.send_message(msg)
    finally:
        try:
            server.quit()
        except smtplib.SMTPException:
            pass


@router.post("/v1/mail/send")
def send_mail(mail: MailIn, x_mail_token: str | None = Header(default=None)) -> dict:
    _require_mail_token(x_mail_token)
    settings = _smtp_settings()
    if settings is None:
        raise HTTPException(503, "Mail is not configured on the server (SMTP_* in .env)")
    recipients = [mail.to] if isinstance(mail.to, str) else list(mail.to)
    recipients = [_clean_header(r) for r in recipients if r and r.strip()]
    if not recipients or len(recipients) > MAX_RECIPIENTS:
        raise HTTPException(400, f"Give 1-{MAX_RECIPIENTS} recipients")
    bad = [r for r in recipients if not EMAIL_RE.match(r)]
    if bad:
        raise HTTPException(400, f"Invalid recipient: {bad[0]}")
    if _sent_last_hour() >= MAILS_PER_HOUR:
        raise HTTPException(429, f"More than {MAILS_PER_HOUR} mails in the last hour")
    msg = _build(mail, recipients, settings["SMTP_USER"])
    try:
        _send(settings, msg)
    except (smtplib.SMTPException, OSError) as e:
        _log(recipients, mail.subject, False, f"{type(e).__name__}: {e}")
        raise HTTPException(502, f"SMTP error: {type(e).__name__}")
    _log(recipients, mail.subject, True)
    return {"ok": True, "id": msg["Message-ID"]}


@router.get("/v1/mail/status")
def mail_status(x_mail_token: str | None = Header(default=None)) -> dict:
    _require_mail_token(x_mail_token)
    since = int(time.time()) - 86400
    with db() as c:
        sent, failed = c.execute("SELECT COALESCE(SUM(ok = 1), 0), COALESCE(SUM(ok = 0), 0) FROM mail_log WHERE created_at > ?",
                                 (since,)).fetchone()
        last = c.execute("SELECT created_at, error FROM mail_log WHERE ok = 0 ORDER BY id DESC LIMIT 1").fetchone()
    settings = _smtp_settings()
    return {"configured": settings is not None, "sender": settings["SMTP_USER"] if settings else "",
            "sent_24h": sent, "failed_24h": failed,
            "last_error": {"at": last[0], "error": last[1]} if last else None}
