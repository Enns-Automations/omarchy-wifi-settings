// Pure helpers for WifiSettings.qml, Node-testable like Model.js.

// `wifi-settings list`: uuid \t autoconnect \t active \t timestamp \t priority \t
// ssid-hex \t ssid. The SSID is last (a tab in it would still parse); the helper
// prints its control bytes as ?, so ssid-hex (the raw bytes) tells profiles apart.
function parseList(raw) {
  var rows = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var fields = lines[i].split("\t")
    if (fields.length < 7 || fields[0] === "") continue
    rows.push({
      uuid: fields[0],
      autoconnect: fields[1] !== "no",
      active: fields[2] === "yes",
      timestamp: parseInt(fields[3], 10) || 0,
      priority: parseInt(fields[4], 10) || 0,
      ssidHex: fields[5],
      ssid: fields.slice(6).join("\t")
    })
  }
  return sortList(rows)
}

// Connected first, then highest priority, then most recently used.
function sortList(rows) {
  var list = rows.slice()
  list.sort(function(a, b) {
    if (a.active !== b.active) return a.active ? -1 : 1
    if (a.priority !== b.priority) return b.priority - a.priority
    return b.timestamp - a.timestamp
  })
  return list
}

// `wifi-settings show`: key \t value lines.
function parseShow(raw) {
  var lines = String(raw || "").split("\n")
  var next = {}
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx === -1) continue
    next[lines[i].substring(0, idx)] = lines[i].substring(idx + 1)
  }
  if (!next.uuid) return null
  return {
    uuid: next.uuid,
    ssid: next.ssid || "",
    ssidHex: next.ssidhex || "",
    autoconnect: next.autoconnect !== "no",
    priority: parseInt(next.priority, 10) || 0,
    active: next.active === "yes",
    timestamp: parseInt(next.timestamp, 10) || 0,
    keyMgmt: next.keymgmt || "",
    hidden: next.hidden === "yes"
  }
}

function byteHex(b) {
  return (b < 16 ? "0" : "") + b.toString(16).toUpperCase()
}

// Upper-case hex of a string's UTF-8 bytes, the form of the helper's
// SSID-HEX. "" for "" and for a string UTF-8 cannot encode (a lone surrogate).
function utf8Hex(text) {
  var s = String(text || "")
  var out = ""
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i)
    if (c >= 0xDC00 && c <= 0xDFFF) return ""
    if (c >= 0xD800 && c <= 0xDBFF) {
      var low = i + 1 < s.length ? s.charCodeAt(i + 1) : 0
      if (low < 0xDC00 || low > 0xDFFF) return ""
      c = 0x10000 + ((c - 0xD800) << 10) + (low - 0xDC00)
      i++
    }
    if (c < 0x80) out += byteHex(c)
    else if (c < 0x800) out += byteHex(0xC0 | (c >> 6)) + byteHex(0x80 | (c & 63))
    else if (c < 0x10000) out += byteHex(0xE0 | (c >> 12)) + byteHex(0x80 | ((c >> 6) & 63)) + byteHex(0x80 | (c & 63))
    else out += byteHex(0xF0 | (c >> 18)) + byteHex(0x80 | ((c >> 12) & 63)) + byteHex(0x80 | ((c >> 6) & 63)) + byteHex(0x80 | (c & 63))
  }
  return out
}

function fromCodePoint(c) {
  if (c < 0x10000) return String.fromCharCode(c)
  c -= 0x10000
  return String.fromCharCode(0xD800 + (c >> 10), 0xDC00 + (c & 0x3FF))
}

// The SSID behind a SSID-HEX, decoded as UTF-8. Bytes that are not UTF-8 come
// out as U+FFFD, one per maximal invalid subpart (the WHATWG decoder, as Qt
// decodes them). "" for "" or a string that is not hex byte pairs.
function ssidFromHex(hex) {
  var h = String(hex || "")
  if (!/^(?:[0-9A-Fa-f]{2})*$/.test(h)) return ""
  var bytes = []
  for (var p = 0; p < h.length; p += 2) bytes.push(parseInt(h.substring(p, p + 2), 16))
  var out = ""
  var i = 0
  while (i < bytes.length) {
    var b = bytes[i]
    var len = 0, cp = 0, lower = 0x80, upper = 0xBF
    if (b < 0x80) { out += String.fromCharCode(b); i++; continue }
    if (b >= 0xC2 && b <= 0xDF) { len = 2; cp = b & 0x1F }
    else if (b >= 0xE0 && b <= 0xEF) { len = 3; cp = b & 0x0F; if (b === 0xE0) lower = 0xA0; if (b === 0xED) upper = 0x9F }
    else if (b >= 0xF0 && b <= 0xF4) { len = 4; cp = b & 0x07; if (b === 0xF0) lower = 0x90; if (b === 0xF4) upper = 0x8F }
    else { out += "\uFFFD"; i++; continue }
    var k = 1
    while (k < len) {
      var c = bytes[i + k]
      if (c === undefined || c < lower || c > upper) break
      cp = (cp << 6) | (c & 0x3F)
      lower = 0x80
      upper = 0xBF
      k++
    }
    out += k < len ? "\uFFFD" : fromCodePoint(cp)
    i += k
  }
  return out
}

// Unicode format characters (category Cf, Unicode 15.1): zero-width, bidi
// overrides and isolates, soft hyphen, tags. Explicit ranges: the QML engine
// is not known to support Unicode property escapes in regular expressions.
var FORMAT_RANGES = [
  [0x00AD, 0x00AD], [0x0600, 0x0605], [0x061C, 0x061C], [0x06DD, 0x06DD], [0x070F, 0x070F],
  [0x0890, 0x0891], [0x08E2, 0x08E2], [0x180E, 0x180E], [0x200B, 0x200F], [0x202A, 0x202E],
  [0x2060, 0x2064], [0x2066, 0x206F], [0xFEFF, 0xFEFF], [0xFFF9, 0xFFFB], [0x110BD, 0x110BD],
  [0x110CD, 0x110CD], [0x13430, 0x1343F], [0x1BCA0, 0x1BCA3], [0x1D173, 0x1D17A], [0xE0001, 0xE0001],
  [0xE0020, 0xE007F]
]

function isFormat(c) {
  for (var i = 0; i < FORMAT_RANGES.length; i++) {
    if (c >= FORMAT_RANGES[i][0] && c <= FORMAT_RANGES[i][1]) return true
  }
  return false
}

// An SSID as the card shows it: control characters (Cc) become \n, \r, \t
// or \xHH, format characters (Cf) \uHHHH, so names that differ only in them
// do not look alike. Everything else is unchanged.
function visibleSsid(text) {
  var s = String(text || "")
  var out = ""
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i)
    var ch = s.charAt(i)
    var next = i + 1 < s.length ? s.charCodeAt(i + 1) : 0
    if (c >= 0xD800 && c <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF) {
      c = 0x10000 + ((c - 0xD800) << 10) + (next - 0xDC00)
      ch = s.substring(i, i + 2)
      i++
    }
    if (c === 0x0A) out += "\\n"
    else if (c === 0x0D) out += "\\r"
    else if (c === 0x09) out += "\\t"
    else if (c < 0x20 || (c >= 0x7F && c <= 0x9F)) out += "\\x" + byteHex(c)
    else if (isFormat(c)) {
      var hex = c.toString(16).toUpperCase()
      while (hex.length < 4) hex = "0" + hex
      out += "\\u" + hex
    } else out += ch
  }
  return out
}

// Picks the profile for a scanned network's SSID (Quickshell's decoded name)
// from parseList rows: { uuid, ambiguous }. The SSID's UTF-8 bytes must equal
// a row's SSID-HEX; several profiles of one network are legitimate, the first
// in list order wins. Only an SSID that is not valid UTF-8 (both sides then
// hold U+FFFD) falls back to the decoded string, and only among such rows:
// more than one match is ambiguous and opens nothing. A row whose bytes are
// valid UTF-8 never matches by string, so a saved "Cafe\nWifi", printed as
// "Cafe?Wifi" by the helper, is never opened for a scanned "Cafe?Wifi".
function profileForScanned(rows, ssid) {
  var want = utf8Hex(ssid)
  var i
  if (want !== "") {
    for (i = 0; i < rows.length; i++) {
      if (rows[i].ssidHex !== "" && rows[i].ssidHex === want) return { uuid: rows[i].uuid, ambiguous: false }
    }
  }
  var found = []
  for (i = 0; i < rows.length; i++) {
    var hex = rows[i].ssidHex
    if (utf8Hex(ssidFromHex(hex)) !== hex && rows[i].ssid === ssid) found.push(rows[i].uuid)
  }
  if (found.length === 1) return { uuid: found[0], ambiguous: false }
  return { uuid: "", ambiguous: found.length > 1 }
}

// The first profile whose (flattened) SSID string is ssid. Several profiles
// can share one SSID; the active one wins, then the highest priority, then
// the most recently used (sortList's order). The row gear no longer uses it:
// it goes through profileForScanned.
function uuidForSsid(rows, ssid) {
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].ssid === ssid) return rows[i].uuid
  }
  return ""
}

function securityLabel(keyMgmt) {
  if (keyMgmt === "") return "Open"
  if (keyMgmt === "none") return "WEP"
  if (keyMgmt === "wpa-psk") return "WPA2 Personal"
  if (keyMgmt === "sae") return "WPA3 Personal"
  if (keyMgmt === "owe") return "Enhanced Open"
  if (keyMgmt.indexOf("eap") !== -1 || keyMgmt === "ieee8021x") return "Enterprise"
  return keyMgmt
}

// Only personal (PSK/SAE) and WEP profiles carry a password worth showing.
function hasPassword(keyMgmt) {
  return keyMgmt === "wpa-psk" || keyMgmt === "sae" || keyMgmt === "none"
}

function lastUsedLabel(timestamp, nowSeconds) {
  var ts = parseInt(timestamp, 10) || 0
  if (ts <= 0) return "Never connected"
  var diff = Math.max(0, nowSeconds - ts)
  if (diff < 60) return "Used just now"
  if (diff < 3600) return "Used " + Math.floor(diff / 60) + " min ago"
  if (diff < 86400) return "Used " + Math.floor(diff / 3600) + " h ago"
  var days = Math.floor(diff / 86400)
  if (days === 1) return "Used yesterday"
  if (days < 30) return "Used " + days + " days ago"
  var months = Math.floor(days / 30)
  if (months < 12) return "Used " + months + (months === 1 ? " month ago" : " months ago")
  var years = Math.floor(days / 365)
  return "Used " + years + (years === 1 ? " year ago" : " years ago")
}

function statusLine(profile, nowSeconds) {
  if (!profile) return ""
  if (profile.active) return "Connected"
  return lastUsedLabel(profile.timestamp, nowSeconds)
}

function listCaption(row, nowSeconds) {
  var parts = [row.active ? "Connected" : lastUsedLabel(row.timestamp, nowSeconds)]
  if (row.priority !== 0) parts.push("Priority " + row.priority)
  if (!row.autoconnect) parts.push("Auto-connect off")
  return parts.join(" · ")
}

// The saved list as the card shows it, in the rows' order: { uuid, title,
// caption }. The title is the real SSID (from its hex) made visible; rows whose
// titles are still equal get the first 8 characters of their UUID in the
// caption, so two lookalike profiles can be told apart.
function renderRows(rows, nowSeconds) {
  var titles = []
  var counts = {}
  var i
  for (i = 0; i < rows.length; i++) {
    var title = visibleSsid(ssidFromHex(rows[i].ssidHex))
    if (title === "") title = "Hidden network"
    titles.push(title)
    counts["=" + title] = (counts["=" + title] || 0) + 1
  }
  var out = []
  for (i = 0; i < rows.length; i++) {
    var caption = listCaption(rows[i], nowSeconds)
    if (counts["=" + titles[i]] > 1) caption += " · " + rows[i].uuid.substring(0, 8)
    out.push({ uuid: rows[i].uuid, title: titles[i], caption: caption })
  }
  return out
}

// Cursor stops in the detail view, top to bottom.
function detailActions(profile) {
  if (!profile) return []
  var actions = ["autoconnect", "lower", "raise"]
  if (hasPassword(profile.keyMgmt)) actions.push("reveal", "copy")
  actions.push("forget")
  return actions
}

// NetworkManager accepts -999..999; the card steps by one.
function clampPriority(value) {
  return Math.max(-999, Math.min(999, parseInt(value, 10) || 0))
}

// Whether a `wifi-settings password` response may enter the card: the card is
// open, a request is pending (back and reset clear it) and the card still
// shows the network the request was for.
function acceptPassword(requestUuid, uuid, opened) {
  return opened === true && requestUuid !== "" && requestUuid === uuid
}

// Plain path from a file:// URL, as Qt.resolvedUrl returns it.
function pathFromUrl(url) {
  var value = String(url || "").replace(/^file:\/\//, "").replace(/[?#].*$/, "")
  try { return decodeURIComponent(value) } catch (e) { return value }
}

if (typeof module !== "undefined") {
  module.exports = {
    parseList: parseList,
    sortList: sortList,
    parseShow: parseShow,
    uuidForSsid: uuidForSsid,
    utf8Hex: utf8Hex,
    ssidFromHex: ssidFromHex,
    visibleSsid: visibleSsid,
    profileForScanned: profileForScanned,
    securityLabel: securityLabel,
    hasPassword: hasPassword,
    lastUsedLabel: lastUsedLabel,
    statusLine: statusLine,
    listCaption: listCaption,
    renderRows: renderRows,
    detailActions: detailActions,
    clampPriority: clampPriority,
    acceptPassword: acceptPassword,
    pathFromUrl: pathFromUrl
  }
}
