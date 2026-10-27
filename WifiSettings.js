// Pure helpers for WifiSettings.qml, Node-testable like Model.js.

// `wifi-settings list`: uuid \t autoconnect \t active \t timestamp \t priority \t ssid.
// The SSID is last so it may hold tabs.
function parseList(raw) {
  var rows = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var fields = lines[i].split("\t")
    if (fields.length < 6 || fields[0] === "") continue
    rows.push({
      uuid: fields[0],
      autoconnect: fields[1] !== "no",
      active: fields[2] === "yes",
      timestamp: parseInt(fields[3], 10) || 0,
      priority: parseInt(fields[4], 10) || 0,
      ssid: fields.slice(5).join("\t")
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
    autoconnect: next.autoconnect !== "no",
    priority: parseInt(next.priority, 10) || 0,
    active: next.active === "yes",
    timestamp: parseInt(next.timestamp, 10) || 0,
    keyMgmt: next.keymgmt || "",
    hidden: next.hidden === "yes"
  }
}

// Picks the profile for a scanned SSID. Several profiles can share one SSID;
// the active one wins, then the most recently used (parseList's order).
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
    securityLabel: securityLabel,
    hasPassword: hasPassword,
    lastUsedLabel: lastUsedLabel,
    statusLine: statusLine,
    listCaption: listCaption,
    detailActions: detailActions,
    clampPriority: clampPriority,
    pathFromUrl: pathFromUrl
  }
}
