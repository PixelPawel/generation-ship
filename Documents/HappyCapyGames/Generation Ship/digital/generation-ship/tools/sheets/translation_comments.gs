/**
 * Google Apps Script for the "GS Translation Comments" sheet (Extensions -> Apps Script, paste, save).
 * Once a day it fetches the players' translation comments from the game's API server and rewrites the
 * "Comments" tab: one row per comment, newest first, next to the card's English and current translated
 * text. The "Notes" column is yours: it is kept per comment ID across updates.
 *
 * Setup (once): reload the sheet, menu "Translation comments" -> "Setup", paste the admin token
 * (same value as ADMIN_TOKEN in /opt/hcg-api/.env on the server, locally ~/.hcg_admin_token).
 * That stores the token in the script's properties (not in the sheet), installs the daily trigger
 * (about 6:00 Berlin time) and runs the first update. "Update now" runs it any time.
 *
 * Server side: GET /v1/comments/report?status=  (all comments, grouped per card part, with votes)
 *              GET /v1/comments/cards           (card texts, uploaded by tools/upload_card_texts.py)
 * Source of truth for this script: digital/generation-ship/tools/sheets/translation_comments.gs
 */
var API = 'https://api.happycapygames.com';
var SHEET = 'Comments';
var HEADER = ['ID', 'Sent', 'Language', 'Card', 'Part', 'English', 'Current translation', 'Comment',
              'Player', 'Players on this part', 'Votes up', 'Votes down', 'Version', 'Status', 'Key', 'Notes'];
var WIDTHS = [50, 120, 70, 160, 60, 280, 280, 320, 80, 80, 70, 80, 70, 70, 220, 260];
var NOTES_COL = HEADER.indexOf('Notes');

function onOpen() {
  SpreadsheetApp.getUi().createMenu('Translation comments')
    .addItem('Update now', 'updateComments')
    .addItem('Setup (token + daily update)', 'setup')
    .addToUi();
}

function setup() {
  var ui = SpreadsheetApp.getUi();
  var res = ui.prompt('Translation comments', 'Admin token of the API server (ADMIN_TOKEN):', ui.ButtonSet.OK_CANCEL);
  if (res.getSelectedButton() !== ui.Button.OK || !res.getResponseText().trim()) return;
  PropertiesService.getScriptProperties().setProperty('ADMIN_TOKEN', res.getResponseText().trim());
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'updateComments') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('updateComments').timeBased().everyDays(1).atHour(6).inTimezone('Europe/Berlin').create();
  updateComments();
  ui.alert('Done: the comments update daily at about 6:00 (Berlin time).');
}

function fetchJson_(path, token) {
  var resp = UrlFetchApp.fetch(API + path, { headers: { 'X-Admin-Token': token }, muteHttpExceptions: true });
  if (resp.getResponseCode() !== 200) {
    throw new Error('Server said ' + resp.getResponseCode() + ' for ' + path + ': ' + resp.getContentText().slice(0, 200));
  }
  return JSON.parse(resp.getContentText());
}

function updateComments() {
  var token = PropertiesService.getScriptProperties().getProperty('ADMIN_TOKEN');
  if (!token) throw new Error('No admin token yet: menu "Translation comments" -> "Setup".');
  var report = fetchJson_('/v1/comments/report?status=', token);
  var cards = fetchJson_('/v1/comments/cards', token).cards || {};

  var ss = SpreadsheetApp.getActive();
  var sh = ss.getSheetByName(SHEET) || ss.insertSheet(SHEET);
  var tz = ss.getSpreadsheetTimeZone();

  // keep the hand-written notes, per comment ID
  var notes = {};
  var last = sh.getLastRow();
  if (last >= 3) {
    sh.getRange(3, 1, last - 2, HEADER.length).getValues().forEach(function (r) {
      if (r[0] !== '' && r[NOTES_COL] !== '') notes[r[0]] = r[NOTES_COL];
    });
  }

  var rows = [];
  var open = 0;
  (report.groups || []).forEach(function (g) {
    var m = /^tv_([A-Z]{2})_([A-Za-z]+)_(.+)$/.exec(g.key) || [];
    var card = cards[m[3]] || {};
    var en = card.EN || {};
    var tr = card[g.lang] || {};
    g.comments.forEach(function (c) {
      if (c.status === 'open') open++;
      rows.push([
        c.id,
        Utilities.formatDate(new Date(c.created_at * 1000), tz, 'yyyy-MM-dd HH:mm'),
        g.lang,
        en.name || m[3] || g.key,
        g.field,
        en[g.field] || '',
        tr[g.field] || '',
        c.text,
        c.player,
        g.players,
        g.votes_up,
        g.votes_down,
        c.version,
        c.status,
        g.key,
        notes[c.id] || ''
      ]);
    });
  });
  rows.sort(function (a, b) { return b[0] - a[0]; });   // newest (highest ID) first

  sh.clearContents();
  var stamp = Utilities.formatDate(new Date(), tz, 'yyyy-MM-dd HH:mm');
  sh.getRange(1, 1).setValue('Last updated ' + stamp + ' · ' + rows.length + ' comment(s), ' + open + ' open');
  sh.getRange(2, 1, 1, HEADER.length).setValues([HEADER]).setFontWeight('bold').setBackground('#e8eaf6');
  if (rows.length) {
    sh.getRange(3, 1, rows.length, HEADER.length).setValues(rows)
      .setVerticalAlignment('top').setWrap(true);
  }
  sh.setFrozenRows(2);
  WIDTHS.forEach(function (w, i) { sh.setColumnWidth(i + 1, w); });
}
