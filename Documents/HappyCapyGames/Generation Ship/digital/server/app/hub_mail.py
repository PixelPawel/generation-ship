"""Gmail is the source of truth for outreach. Everyone on the team who writes to contacts connects their own Gmail
once: a small Google Apps Script in that account (hub_mail_agent.gs, filled in with the mailbox's own token) runs
every 5 minutes. It only ever passes on mail that involves a contact (by the contact's Email) or sits in a thread
labelled Outreach; nothing else leaves the mailbox, and never a mail's text: who, when and the subject.

What the mail does (only the newest mail with a contact changes anything, so old mail found later can't undo news):
  - we wrote to them: Last contact; Lead / To contact / No reply -> Contacted; now we wait for them, so the next
    follow-up is that day + Settings > Follow-up days (or the stage's own, longer rule: Copy sent 14, Partner 90...);
    Draft status In drafts -> Sent
  - they wrote to us: Last reply; Lead / To contact / Contacted / No reply -> Replied; the next follow-up is that
    day + 2 (answer within 2 days). Declined contacts don't move.
  - every mail is a line in the Outreach Log (Email / Email received, the subject, a link to the thread in Gmail).
    Mail that is in several team mailboxes (cc) is logged once.
Labels: every thread with a contact carries the contact's stage as a Gmail label (Outreach/Contacted, ...). Change
the label in Gmail and the contact moves; move the contact on the dashboard and the labels follow. Taking the stage
label off a thread stops the labelling of that thread (putting one back starts it again). A thread labelled
"Outreach" (or any Outreach/<stage>) with someone who isn't a contact yet makes them one, Owner = the mailbox's owner.
A contact without a Stage (a manufacturer, a platform) is not in the funnel: its mail is logged, but it gets no
stage label and mail doesn't move it. A deleted contact's threads lose their stage labels.
Drafts: a contact whose Draft status is Ready goes into its Owner's Gmail as a draft (Draft status -> In drafts).

    GET    /v1/hub/mailboxes                the connected mailboxes (hub token)
    POST   /v1/hub/mailboxes  {owner}       connect one: its script with a new token in it, shown once (hub token)
    POST   /v1/hub/mailboxes/{id}/script    the script again with a new token; the old one stops (hub token)
    DELETE /v1/hub/mailboxes/{id}           disconnect: its token stops working (hub token)
    POST   /v1/hub/contacts/merge {from, into}   the same person twice (met under another address): one row (hub token)
    POST   /v1/hub/mail/plan                the script, step 1: what to watch and what to do (X-Mailbox-Token)
    POST   /v1/hub/mail/report              the script, step 2: what it found and did (X-Mailbox-Token)
"""
import hashlib
import hmac
import json
import os
import re
import secrets
import time
import urllib.parse
from collections import Counter
from datetime import datetime, timedelta
from email.utils import getaddresses
from pathlib import Path

from fastapi import APIRouter, Body, Header, HTTPException

from .hub import (FOLLOW_UP_RULE, FUNNEL, FUNNEL_EXITS, TAB_BY_NAME, TZ, _auth, _num, _stage_moved, clean_row, hdb,
                  kv_get, kv_put, setting)

router = APIRouter()   # mounted into the hub router (/v1/hub) at the end of hub.py
AGENT = Path(__file__).with_name("hub_mail_agent.gs")
AGENT_VERSION = 1      # the script's VERSION; an older script is shown as "needs the new script"
PUBLIC_URL = os.environ.get("HUB_PUBLIC_URL", "https://api.happycapygames.com").rstrip("/")
LABEL = "Outreach"
STALE_AFTER = 3600     # no run for an hour: the dashboard says the Gmail stopped syncing
BACKFILL_PER_RUN = 30  # contacts whose older mail a run looks up (new contacts, new mailboxes)
BACKFILL_DAYS = 730
APPLY_PER_RUN = 100
NEED_PER_RUN = 30
MAX_MESSAGES = 2000
REPLY_WITHIN = 2       # days to answer a mail from a contact
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+'-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,24}")
CONTACTED_FROM = {"Lead", "To contact", "No reply"}
REPLIED_FROM = {"Lead", "To contact", "Contacted", "No reply"}
NO_LABEL = "-"         # label_want: take the stage labels off (the contact is gone or not in the funnel)
FREEMAIL = {"gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "live.com", "yahoo.com", "icloud.com", "me.com",
            "gmx.de", "gmx.net", "web.de", "proton.me", "protonmail.com"}


def init_mail() -> None:
    with hdb() as c:
        c.execute("""CREATE TABLE IF NOT EXISTS mail_msgs (
            key TEXT PRIMARY KEY,
            mailbox TEXT NOT NULL,
            at INTEGER NOT NULL
        )""")
        # the threads with a contact in each mailbox, and the stage label each one had when we last looked
        c.execute("""CREATE TABLE IF NOT EXISTS mail_threads (
            mailbox TEXT NOT NULL,
            thread TEXT NOT NULL,
            contact INTEGER NOT NULL,
            label_seen TEXT NOT NULL DEFAULT '',
            label_want TEXT NOT NULL DEFAULT '',
            muted INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (mailbox, thread)
        )""")


init_mail()


# ---------------------------------------------------------------- mailboxes

def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _boxes(c) -> dict:
    return kv_get(c, "mailboxes", {}) or {}


def _box_for(boxes: dict, token: str | None) -> dict:
    if not token:
        raise HTTPException(403, "No mailbox token.")
    h = _hash(token)
    for b in boxes.values():
        if hmac.compare_digest(b.get("token_hash", ""), h):
            return b
    raise HTTPException(403, "This Gmail was disconnected from the dashboards. Connect it again on the Outreach page.")


def _script(token: str) -> str:
    return AGENT.read_text(encoding="utf-8").replace("__HUB__", f"{PUBLIC_URL}/v1/hub/mail").replace("__TOKEN__", token)


def _public(b: dict) -> dict:
    now = int(time.time())
    last = b.get("last_report") or 0
    return {"id": b["id"], "owner": b.get("owner", ""), "email": b.get("email", ""), "aliases": b.get("aliases") or [],
            "created": b.get("created"), "last_sync": last or None, "last_error": b.get("last_error", ""),
            "stale": bool(b.get("email")) and now - last > STALE_AFTER, "waiting": not b.get("email"),
            "outdated": bool(b.get("version")) and b["version"] < AGENT_VERSION,
            "logged": b.get("logged", 0), "moved": b.get("moved", 0), "added": b.get("added", 0),
            "backfill_left": b.get("backfill_left", 0), "took": b.get("took")}


def status(c) -> list[dict]:
    """The connected mailboxes for the dashboards (Outreach page, the overview's attention list)."""
    return sorted((_public(b) for b in _boxes(c).values()), key=lambda b: b["owner"].lower())


def _add_to_team(c, owner: str) -> None:
    lists = kv_get(c, "lists", {}) or {}
    team = lists.get("Team") or []
    if owner.lower() not in {t.lower() for t in team}:
        lists["Team"] = team + [owner]
        kv_put(c, "lists", lists)


@router.get("/mailboxes")
def get_mailboxes(x_hub_token: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    with hdb() as c:
        return {"mailboxes": status(c), "version": AGENT_VERSION, "label": LABEL}


@router.post("/mailboxes")
def add_mailbox(body: dict = Body(...), x_hub_token: str | None = Header(None)) -> dict:
    """Connect a Gmail: whose it is (their name as in the Owner column). Answers with the script to paste."""
    _auth(x_hub_token)
    owner = str(body.get("owner") or "").strip()[:40]
    if not owner:
        raise HTTPException(400, "Whose Gmail is it? Give the person's name.")
    token = "hcgm_" + secrets.token_urlsafe(32)
    with hdb() as c:
        boxes = _boxes(c)
        bid = secrets.token_hex(4)
        boxes[bid] = {"id": bid, "owner": owner, "token_hash": _hash(token), "created": int(time.time())}
        kv_put(c, "mailboxes", boxes)
        _add_to_team(c, owner)
        return {"mailbox": _public(boxes[bid]), "script": _script(token)}


@router.post("/mailboxes/{bid}/script")
def new_script(bid: str, x_hub_token: str | None = Header(None)) -> dict:
    """The script again (to update it, or because the old one got out): a new token, the old one stops working."""
    _auth(x_hub_token)
    token = "hcgm_" + secrets.token_urlsafe(32)
    with hdb() as c:
        boxes = _boxes(c)
        if bid not in boxes:
            raise HTTPException(404, "That mailbox isn't connected.")
        boxes[bid]["token_hash"] = _hash(token)
        kv_put(c, "mailboxes", boxes)
        return {"mailbox": _public(boxes[bid]), "script": _script(token)}


@router.delete("/mailboxes/{bid}")
def remove_mailbox(bid: str, x_hub_token: str | None = Header(None)) -> dict:
    _auth(x_hub_token)
    with hdb() as c:
        boxes = _boxes(c)
        if boxes.pop(bid, None) is None:
            raise HTTPException(404, "That mailbox isn't connected.")
        kv_put(c, "mailboxes", boxes)
        c.execute("DELETE FROM mail_threads WHERE mailbox = ?", (bid,))
    return {"ok": True}


# ---------------------------------------------------------------- addresses and contacts

def _addrs(text) -> list[str]:
    return [a.lower() for a in EMAIL_RE.findall(str(text or ""))]


def _people(header) -> list[tuple[str, str]]:
    """'Tina <tina@x.com>, bob@y.org' -> [("Tina", "tina@x.com"), ("", "bob@y.org")]."""
    out = []
    for name, addr in getaddresses([str(header or "")]):
        addr = addr.strip().lower()
        if EMAIL_RE.fullmatch(addr):
            out.append((name.strip().strip('"').strip(), addr))
    return out


class _Own(set):
    """Our own addresses, and anything at the company's own domain (kate@happycapygames.com)."""

    def __init__(self, addrs, domains):
        super().__init__(addrs)
        self.domains = domains

    def __contains__(self, addr) -> bool:
        return set.__contains__(self, addr) or str(addr).rsplit("@", 1)[-1] in self.domains


def _team(c, boxes: dict) -> _Own:
    """Our own addresses: a mail from one of them is ours, and they are never taken for contacts."""
    own = set()
    for k in ("Team emails", "Company email", "Support email"):
        own.update(_addrs(setting(c, k)))
    for b in boxes.values():
        own.update(_addrs(b.get("email")))
        own.update(a.lower() for a in b.get("aliases") or [])
    domains = {a.rsplit("@", 1)[1] for a in _addrs(setting(c, "Company email"))} - FREEMAIL
    return _Own(own, domains)


class _Contacts:
    """The Contacts table, loaded once per call; changes are written back at the end (save)."""

    def __init__(self, c):
        self.c = c
        self.slug = TAB_BY_NAME["Contacts"]["slug"]
        self.rows, self.stamp, self.by_addr, self.dirty = {}, {}, {}, set()
        for r in c.execute("SELECT id, data, updated_at FROM rows WHERE tab = ?", (self.slug,)):
            self.rows[r["id"]] = json.loads(r["data"])
            self.stamp[r["id"]] = r["updated_at"]
            for a in _addrs(self.rows[r["id"]].get("Email")):
                self.by_addr.setdefault(a, r["id"])

    def add(self, data: dict, user: str) -> int:
        from .hub import _fill_auto
        _fill_auto(self.c, TAB_BY_NAME["Contacts"], data, creating=True)
        now = int(time.time())
        cur = self.c.execute("INSERT INTO rows (tab, data, created_at, updated_at, updated_by) VALUES (?, ?, ?, ?, ?)",
                             (self.slug, json.dumps(data, ensure_ascii=False), now, now, user))
        rid = cur.lastrowid
        self.rows[rid], self.stamp[rid] = data, now
        for a in _addrs(data.get("Email")):
            self.by_addr.setdefault(a, rid)
        return rid

    def save(self, user: str) -> None:
        now = int(time.time())
        for rid in self.dirty:
            self.c.execute("UPDATE rows SET data = ?, updated_at = ?, updated_by = ? WHERE id = ?",
                           (json.dumps(self.rows[rid], ensure_ascii=False), max(now, self.stamp[rid] + 1), user, rid))


# ---------------------------------------------------------------- what a mail does

def _day(ts: int):
    return datetime.fromtimestamp(ts, TZ).date()


def _wait_days(c, stage: str) -> int:
    """Days until we nudge them again after we wrote: Settings > Follow-up days, or the stage's own longer rule."""
    base = int(_num(setting(c, "Follow-up days")) or 7)
    rule = FOLLOW_UP_RULE.get(stage)
    return max(base, rule) if isinstance(rule, int) and stage not in ("Replied", "Negotiating") else base


def _log(c, data: dict, kind: str, summary: str, link: str, owner: str, day) -> None:
    tab = TAB_BY_NAME["Outreach Log"]
    entry = clean_row(tab, {"Date": day.isoformat(), "Contact ID": data.get("ID", ""), "Kind": kind, "Game": data.get("Game", ""),
                            "Summary": summary, "Mail": link, "Owner": owner}, allow_auto=True)
    now = int(time.time())
    c.execute("INSERT INTO rows (tab, data, created_at, updated_at, updated_by) VALUES (?, ?, ?, ?, ?)",
              (tab["slug"], json.dumps(entry, ensure_ascii=False), now, now, owner))


def _mail_effect(c, data: dict, out: bool, ts: int, owner: str) -> str:
    """One mail with a contact: their dates, stage and next follow-up. Returns a note for the log line."""
    day = _day(ts)
    stage = data.get("Stage") or ""
    newest = ts >= max(int(data.get("_mail_out") or 0), int(data.get("_mail_in") or 0))
    note = ""
    if out:
        before = data.get("Last contact") or ""              # (moving to Contacted would stamp today on it)
        data["_mail_out"] = max(ts, int(data.get("_mail_out") or 0))
        if data.get("Draft status") == "In drafts" and ts >= int(data.get("_draft_at") or 0) - 60:
            data["Draft status"] = "Sent"
        if newest and stage in CONTACTED_FROM:
            data["Stage"] = "Contacted"
            _stage_moved(c, data, stage, {"Next follow-up": True}, owner, log=False)
            note = f" (stage: {stage or 'new'} → Contacted)"
        if newest and data.get("Stage") != "Declined":
            data["Next follow-up"] = (day + timedelta(days=_wait_days(c, data.get("Stage") or ""))).isoformat()
        data["Last contact"] = max(before, day.isoformat())
    else:
        data["_mail_in"] = max(ts, int(data.get("_mail_in") or 0))
        if newest and stage in REPLIED_FROM:
            data["Stage"] = "Replied"
            _stage_moved(c, data, stage, {"Next follow-up": True}, owner, log=False)
            note = f" (stage: {stage or 'new'} → Replied)"
        if newest and data.get("Stage") != "Declined":
            data["Next follow-up"] = (day + timedelta(days=REPLY_WITHIN)).isoformat()
        if not data.get("Last reply") or day.isoformat() > data["Last reply"]:
            data["Last reply"] = day.isoformat()
    return note


def _gmail_link(box: dict, thread: str) -> str:
    who = urllib.parse.quote(box.get("email") or "0", safe="@.+-_")
    return f"https://mail.google.com/mail/u/{who}/#all/{urllib.parse.quote(thread, safe='')}"


def _stage_order(stages: list[str]) -> dict:
    return {s: i for i, s in enumerate(stages)}


@router.post("/contacts/merge")
def merge_contacts(body: dict = Body(...), x_hub_token: str | None = Header(None), x_hub_user: str | None = Header(None)) -> dict:
    """{from, into}: row ids. `from` goes into `into`: its addresses, mail dates, Outreach Log lines and Gmail threads
    (their labels change to `into`'s stage); then `from` is deleted. `into` keeps its own stage and fields."""
    from .hub import _changed, _row_out, _user, today
    _auth(x_hub_token)
    src, dst = int(_num(body.get("from")) or 0), int(_num(body.get("into")) or 0)
    user = _user(x_hub_user)
    with hdb() as c:
        con = _Contacts(c)
        a, b = con.rows.get(src), con.rows.get(dst)
        if a is None or b is None or src == dst:
            raise HTTPException(404, "Give two different contacts that both exist.")
        b["Email"] = ", ".join(dict.fromkeys(_addrs(b.get("Email")) + _addrs(a.get("Email"))))
        for k in ("Last contact", "Last reply"):
            if a.get(k) and a[k] > (b.get(k) or ""):
                b[k] = a[k]
        for k in ("_mail_in", "_mail_out"):
            if int(a.get(k) or 0) > int(b.get(k) or 0):
                b[k] = a[k]
        b["Notes"] = ((b.get("Notes") or "") + f"\nMerged in {a.get('Name')} ({a.get('Email') or a.get('ID')}) on {today().isoformat()}.").strip()
        con.dirty.add(dst)
        con.save(user)
        log_slug = TAB_BY_NAME["Outreach Log"]["slug"]
        moved = 0
        if a.get("ID"):
            for r in c.execute("SELECT id, data FROM rows WHERE tab = ?", (log_slug,)).fetchall():
                d = json.loads(r["data"])
                if d.get("Contact ID") == a["ID"]:
                    d["Contact ID"] = b.get("ID", "")
                    c.execute("UPDATE rows SET data = ? WHERE id = ?", (json.dumps(d, ensure_ascii=False), r["id"]))
                    moved += 1
        c.execute("UPDATE mail_threads SET contact = ? WHERE contact = ?", (dst, src))
        c.execute("DELETE FROM rows WHERE id = ?", (src,))
        out = {"row": _row_out(c, TAB_BY_NAME["Contacts"], dst), "log_lines": moved}
    _changed()
    return out


# ---------------------------------------------------------------- the script's two calls

def _ts(v) -> int:
    try:
        t = int(float(v or 0))
    except (TypeError, ValueError):
        return 0
    return t // 1000 if t > 10**11 else t     # milliseconds from JavaScript


@router.post("/mail/plan")
def mail_plan(body: dict = Body(default={}), x_mailbox_token: str | None = Header(None)) -> dict:
    """Step 1 of a run: the script says who it is; the answer says which addresses to watch, whose older mail to look
    up, which labelled threads to send in full, which stage labels to put on, which drafts to make."""
    now = int(time.time())
    with hdb() as c:
        boxes = _boxes(c)
        box = _box_for(boxes, x_mailbox_token)
        me = _addrs(body.get("me"))
        if me:
            box["email"] = me[0]
        box["aliases"] = sorted({a for x in (body.get("aliases") or [])[:30] for a in _addrs(x)} - set(me))
        box["version"] = int(_num(body.get("version")) or 0)
        box["last_plan"] = now
        stages = (kv_get(c, "lists", {}) or {}).get("Stages") or FUNNEL + FUNNEL_EXITS
        own = _team(c, boxes)
        con = _Contacts(c)
        watch = sorted(a for a in con.by_addr if a not in own)
        known = set(box.get("known") or [])
        todo = [a for a in watch if a not in known]
        box["backfill_left"] = len(todo)
        apply = []
        for r in c.execute("SELECT thread, contact, label_seen FROM mail_threads WHERE mailbox = ? AND muted = 0", (box["id"],)):
            data = con.rows.get(r["contact"])
            want = (data or {}).get("Stage") or NO_LABEL
            if want == r["label_seen"] or (want == NO_LABEL and not r["label_seen"]) or (want != NO_LABEL and want not in stages):
                continue
            if len(apply) < APPLY_PER_RUN:
                apply.append({"thread": r["thread"], "stage": want})
                c.execute("UPDATE mail_threads SET label_want = ? WHERE mailbox = ? AND thread = ?", (want, box["id"], r["thread"]))
        issued = {k: v for k, v in (box.get("drafts_issued") or {}).items() if now - v < 1800}
        drafts = []
        for rid, data in con.rows.items():
            to = [a for a in _addrs(data.get("Email")) if a not in own]
            if (data.get("Draft status") == "Ready" and to and str(rid) not in issued
                    and (data.get("Owner") or "").strip().lower() == box["owner"].lower()
                    and (data.get("Draft subject") or data.get("Draft body"))):
                drafts.append({"contact": rid, "to": to[0], "subject": data.get("Draft subject") or "",
                               "body": data.get("Draft body") or ""})
                issued[str(rid)] = now
        box["drafts_issued"] = issued
        kv_put(c, "mailboxes", boxes)
        return {"label": LABEL, "stages": stages, "watch": watch, "backfill": todo[:BACKFILL_PER_RUN],
                "backfill_days": BACKFILL_DAYS, "need": (box.get("need") or [])[:NEED_PER_RUN], "apply": apply,
                "drafts": drafts[:20], "version": AGENT_VERSION}


@router.post("/mail/report")
def mail_report(body: dict = Body(...), x_mailbox_token: str | None = Header(None)) -> dict:
    """Step 2: the mail the script found, the stage labels on its threads right now, what it did of the plan."""
    with hdb() as c:
        boxes = _boxes(c)
        box = _box_for(boxes, x_mailbox_token)
        owner = box["owner"]
        stats = Counter()
        stages = (kv_get(c, "lists", {}) or {}).get("Stages") or FUNNEL + FUNNEL_EXITS
        order = _stage_order(stages)
        own = _team(c, boxes)
        con = _Contacts(c)
        raw_labels = body.get("labels")
        labelled = ({str(t)[:64]: [str(s) for s in (v or [])] for t, v in raw_labels.items()}
                    if isinstance(raw_labels, dict) else None)       # None: the script couldn't read the labels
        truncated = {str(s) for s in body.get("truncated") or []}
        threads = {r["thread"]: dict(r) for r in c.execute("SELECT * FROM mail_threads WHERE mailbox = ?", (box["id"],))}
        changed = set()

        # 1. the stage labels the script put on (asked for in the plan); threads deleted in Gmail are forgotten
        for th in {str(t) for t in body.get("gone") or []} & set(threads):
            c.execute("DELETE FROM mail_threads WHERE mailbox = ? AND thread = ?", (box["id"], th))
            del threads[th]
        applied = {str(t) for t in body.get("applied") or []}
        for th, r in threads.items():
            if r["label_want"]:
                if th in applied:
                    r["label_seen"] = "" if r["label_want"] == NO_LABEL else r["label_want"]
                r["label_want"] = ""
                changed.add(th)

        # 2. the mail, oldest first
        remapped = set()       # threads whose contact was deleted or merged, now someone else's: their labels were ours
        msgs = [m for m in body.get("messages") or [] if isinstance(m, dict)]
        msgs.sort(key=lambda m: _ts(m.get("at")))
        for m in msgs[:MAX_MESSAGES]:
            th = str(m.get("thread") or "")[:64]
            ts = _ts(m.get("at"))
            sender = _people(m.get("from"))
            if not sender or ts <= 0:
                continue
            others = [p for p in _people(m.get("to")) + _people(m.get("cc")) if p[1] not in own]
            out = sender[0][1] in own or sender[0][1] == box.get("email")
            people = others if out else ([sender[0]] if sender[0][1] not in own else [])
            matched = list(dict.fromkeys(con.by_addr[a] for _, a in people if a in con.by_addr))
            if not matched and people and labelled is not None and th in labelled:
                name, addr = people[0]
                rid = con.add(clean_row(TAB_BY_NAME["Contacts"], {
                    "Name": name or addr.split("@")[0], "Email": addr, "Stage": "Lead", "Owner": owner,
                    "Source": f"Gmail ({owner}): labelled {LABEL}"}), owner)
                matched = [rid]
                stats["added"] += 1
            if not matched:
                continue
            if th and th in threads and threads[th]["contact"] not in con.rows:
                threads[th].update(contact=matched[0], muted=0)
                remapped.add(th)
                changed.add(th)
            elif th and th not in threads:
                threads[th] = {"mailbox": box["id"], "thread": th, "contact": matched[0], "label_seen": "", "label_want": "", "muted": 0}
                changed.add(th)
            key = str(m.get("rfc") or "").strip().strip("<>").lower()[:300] or f"gm:{str(m.get('id'))[:64]}"
            if c.execute("INSERT OR IGNORE INTO mail_msgs (key, mailbox, at) VALUES (?, ?, ?)", (key, box["id"], ts)).rowcount == 0:
                continue                                  # already logged (cc'd to another team mailbox, or sent twice)
            subject = str(m.get("subject") or "").strip()[:300] or "(no subject)"
            for rid in matched:
                data = con.rows[rid]
                note = _mail_effect(c, data, out, ts, owner)
                con.dirty.add(rid)
                _log(c, data, "Email" if out else "Email received", subject + note, _gmail_link(box, th) if th else "",
                     owner, _day(ts))
                stats["logged"] += 1

        # 3. stage labels changed in Gmail move the contact
        if labelled is not None:
            for th, r in threads.items():
                data = con.rows.get(r["contact"])
                if data is None or th in remapped:
                    continue
                cur = sorted({s for s in labelled.get(th, []) if s in order}, key=order.get)
                seen = r["label_seen"]
                if not cur:
                    if seen and seen != "*" and seen not in truncated and not r["muted"]:
                        r["muted"], r["label_seen"] = 1, ""   # the stage label was taken off: leave this thread alone
                        changed.add(th)
                    continue
                if r["muted"]:
                    r["muted"] = 0
                    changed.add(th)
                if cur == [seen]:
                    continue
                pick = ([s for s in cur if s != seen] or cur)[-1]   # the furthest new one
                old = data.get("Stage") or ""
                if pick != old:
                    data["Stage"] = pick
                    _stage_moved(c, data, old, {}, owner, note=" (Gmail label)")
                    con.dirty.add(r["contact"])
                    stats["moved"] += 1
                r["label_seen"] = pick if len(cur) == 1 else "*"    # "*": tidy the extra labels next time
                changed.add(th)

        # 4. labelled threads nobody here knows yet: the next run sends them in full
        fetched = {str(t) for t in body.get("needed") or []}
        ignored = set(box.get("ignored") or [])
        ignored |= {t for t in fetched if t not in threads}    # nothing with an outside person in it
        need = [t for t in (box.get("need") or []) if t not in fetched and t not in threads]
        for th in (labelled or {}):
            if th not in threads and th not in ignored and th not in need and th not in fetched:
                need.append(th)
        box["need"], box["ignored"] = need[:300], sorted(ignored)[-1000:]

        # 5. drafts made, contacts looked up
        for d in body.get("drafts") or []:
            data = con.rows.get(int(_num(d.get("contact")) or 0)) if isinstance(d, dict) else None
            if data is not None and data.get("Draft status") == "Ready":
                data["Draft status"], data["_draft_at"] = "In drafts", int(time.time())
                con.dirty.add(int(_num(d.get("contact"))))
                stats["drafts"] += 1
        box["known"] = sorted(set(box.get("known") or []) | {a for x in body.get("backfilled") or [] for a in _addrs(x)})
        box["backfill_left"] = sum(1 for a in con.by_addr if a not in own and a not in set(box["known"]))

        con.save(owner)
        for th in changed:
            r = threads[th]
            c.execute("""INSERT INTO mail_threads (mailbox, thread, contact, label_seen, label_want, muted) VALUES (?, ?, ?, ?, ?, ?)
                         ON CONFLICT(mailbox, thread) DO UPDATE SET contact = excluded.contact, label_seen = excluded.label_seen,
                         label_want = excluded.label_want, muted = excluded.muted""",
                      (box["id"], th, r["contact"], r["label_seen"], r["label_want"], r["muted"]))
        errors = [str(e)[:200] for e in body.get("errors") or []][:5]
        box["last_report"] = int(time.time())
        box["last_error"] = "; ".join(errors)
        box["took"] = _ts(body.get("took")) or None
        for k in ("logged", "moved", "added"):
            box[k] = box.get(k, 0) + stats[k]
        kv_put(c, "mailboxes", boxes)
    if stats["logged"] or stats["moved"] or stats["added"] or stats["drafts"]:
        from .hub import _changed
        _changed()
    summary = (f"{stats['logged']} mails logged, {stats['moved']} contacts moved by a label, {stats['added']} new contacts, "
               f"{stats['drafts']} drafts made.")
    return {"ok": True, "summary": summary, **{k: stats[k] for k in ("logged", "moved", "added", "drafts")}}
