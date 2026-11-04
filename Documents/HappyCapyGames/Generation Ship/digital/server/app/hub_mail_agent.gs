/**
 * Happy Capy Games: this Gmail and the outreach funnel on the HCG dashboards.
 *
 * Every 5 minutes this script passes the mail you exchange with our contacts to the dashboards: who, when and the
 * subject, never the text, and nothing that doesn't involve a contact or a thread you labelled "Outreach". It also
 * keeps the Outreach/<stage> labels on those threads in step with the board: change a thread's label here and the
 * contact moves there, move the contact there and the label changes here.
 *
 * Set up, once: open script.google.com signed in to THIS Gmail, click New project, replace everything in Code.gs
 * with this script, choose "setup" in the function list in the toolbar and click Run, then allow the access.
 * To stop it: run "stop" (or Disconnect this Gmail on the dashboards' Outreach page).
 *
 * This file holds this mailbox's own key: don't share it. A new script from the dashboards replaces it.
 */
const HUB = "__HUB__";
const TOKEN = "__TOKEN__";
const VERSION = 1;
const EVERY_MINUTES = 5;
const EMAIL = /[A-Za-z0-9._%+'-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,24}/g;

function setup() {
  stop_();
  const props = PropertiesService.getScriptProperties();
  if (!props.getProperty("since")) props.setProperty("since", String(Math.floor(Date.now() / 1000) - 86400));
  ScriptApp.newTrigger("sync").timeBased().everyMinutes(EVERY_MINUTES).create();
  console.log("Connected. First run: " + sync());
  console.log("From now on this runs by itself every " + EVERY_MINUTES + " minutes. Older mail with our contacts comes in over the next runs.");
}

function stop() {
  stop_();
  console.log("Stopped: this Gmail no longer reports to the dashboards.");
}

function stop_() {
  ScriptApp.getProjectTriggers().forEach((t) => { if (t.getHandlerFunction() === "sync") ScriptApp.deleteTrigger(t); });
}

function sync() {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(2000)) return "The last run is still going.";
  try {
    return run_();
  } finally {
    lock.releaseLock();
  }
}

function call_(path, body) {
  const res = UrlFetchApp.fetch(HUB + "/" + path, {
    method: "post", contentType: "application/json", payload: JSON.stringify(body),
    headers: { "X-Mailbox-Token": TOKEN }, muteHttpExceptions: true,
  });
  const text = res.getContentText();
  if (res.getResponseCode() !== 200) {
    let msg = text;
    try { msg = JSON.parse(text).detail || text; } catch (e) {}
    throw new Error("The dashboards answered " + res.getResponseCode() + ": " + String(msg).slice(0, 300));
  }
  return JSON.parse(text);
}

function run_() {
  const t0 = Date.now();
  const started = Math.floor(t0 / 1000);
  const props = PropertiesService.getScriptProperties();
  const since = Number(props.getProperty("since") || started - 86400);
  const me = Session.getEffectiveUser().getEmail();
  const plan = call_("plan", { version: VERSION, me: me, aliases: GmailApp.getAliases() });
  const errors = [];
  const watch = new Set(plan.watch);

  // the labels: Outreach, and Outreach/<stage> for every stage
  const have = {};
  GmailApp.getUserLabels().forEach((l) => { have[l.getName()] = l; });
  const label = (name) => have[name] || (have[name] = GmailApp.createLabel(name));
  const prefix = plan.label + "/";
  const root = label(plan.label);
  const stageLabel = {};
  plan.stages.forEach((s) => { stageLabel[s] = label(prefix + s); });

  // 1. stage labels the dashboards want on threads (a contact moved there)
  const applied = [], gone = [];
  plan.apply.forEach((a) => {
    try {
      const t = GmailApp.getThreadById(a.thread);
      if (!t) { gone.push(a.thread); return; }
      t.getLabels().forEach((l) => { if (l.getName().indexOf(prefix) === 0 && l.getName() !== prefix + a.stage) t.removeLabel(l); });
      if (stageLabel[a.stage]) t.addLabel(stageLabel[a.stage]);
      applied.push(a.thread);
    } catch (e) { errors.push("label: " + e.message); }
  });

  // 2. drafts the dashboards want here (contacts of this mailbox's owner with Draft status Ready)
  const drafts = [];
  plan.drafts.forEach((d) => {
    try { drafts.push({ contact: d.contact, draft: GmailApp.createDraft(d.to, d.subject, d.body).getId() }); }
    catch (e) { errors.push("draft: " + e.message); }
  });

  // 3. the mail: since the last run, older mail of new contacts, labelled threads the dashboards don't know yet
  const messages = [], taken = new Set();
  const involves = (m) => (String([m.getFrom(), m.getTo(), m.getCc()].join(",")).toLowerCase().match(EMAIL) || []).some((a) => watch.has(a));
  const labelled = (t) => t.getLabels().some((l) => l.getName() === plan.label || l.getName().indexOf(prefix) === 0);
  // mode "new": since the last run, with a contact or in a labelled thread; "history": any time, with a contact;
  // "all": every message of the thread
  const take = (thread, mode) => {
    const tid = thread.getId();
    let lab = null;
    thread.getMessages().forEach((m) => {
      if (m.isDraft() || m.isInTrash()) return;
      const at = Math.floor(m.getDate().getTime() / 1000);
      if (mode === "new" && at < since - 600) return;
      if (mode !== "all" && !involves(m)) {
        if (mode !== "new") return;
        if (lab === null) lab = labelled(thread);
        if (!lab) return;
      }
      const id = m.getId();
      if (taken.has(id)) return;
      taken.add(id);
      messages.push({ id: id, rfc: m.getHeader("Message-ID"), thread: tid, at: at, from: m.getFrom(), to: m.getTo(),
        cc: m.getCc(), subject: m.getSubject() });
    });
  };
  let newOk = true;
  try {
    for (let start = 0; start < 500; start += 100) {
      const found = GmailApp.search("after:" + (since - 600), start, 100);
      found.forEach((t) => take(t, "new"));
      if (found.length < 100) break;
    }
  } catch (e) { newOk = false; errors.push("new mail: " + e.message); }
  const backfilled = [];
  for (let i = 0; i < plan.backfill.length && Date.now() - t0 < 200000; i += 10) {
    const group = plan.backfill.slice(i, i + 10);
    const q = "{" + group.map((a) => "from:" + a + " to:" + a + " cc:" + a).join(" ") + "} newer_than:" + plan.backfill_days + "d";
    try {
      GmailApp.search(q, 0, 100).forEach((t) => take(t, "history"));
      backfilled.push(...group);
    } catch (e) { errors.push("older mail: " + e.message); }
  }
  const needed = [];
  plan.need.forEach((id) => {
    try {
      const t = GmailApp.getThreadById(id);
      if (t) take(t, "all");
      needed.push(id);
    } catch (e) { errors.push("thread: " + e.message); }
  });

  // 4. which threads carry which Outreach labels right now (a label changed here moves the contact there)
  let snap = {};
  const truncated = [];
  try {
    const mark = (l, stage) => {
      const ts = l.getThreads(0, 500);
      if (ts.length === 500) truncated.push(stage);
      ts.forEach((t) => { (snap[t.getId()] = snap[t.getId()] || []).push(stage); });
    };
    mark(root, "");
    plan.stages.forEach((s) => mark(stageLabel[s], s));
  } catch (e) { snap = null; errors.push("labels: " + e.message); }

  const r = call_("report", { version: VERSION, messages: messages, labels: snap, truncated: truncated, applied: applied,
    gone: gone, drafts: drafts, backfilled: backfilled, needed: needed, errors: errors, took: Math.round((Date.now() - t0) / 1000) });
  if (newOk) props.setProperty("since", String(started));
  return r.summary + (errors.length ? " Problems: " + errors.join("; ") : "");
}
