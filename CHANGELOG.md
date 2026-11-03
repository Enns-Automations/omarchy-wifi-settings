# Changelog

User-facing changes per release, newest first. Written by the release job from `.changes/`.

## 0.1.2 — 2026-11-03

- Publishes the 0.1.1 fixes to GitHub; the 0.1.1 release was tagged but never published.

## 0.1.1 — 2026-11-03

- A saved password ending in a colon is shown and copied in full.
- The row gear opens the saved network with exactly that name, and saved names that only look alike are shown apart.
- Roaming no longer lets a nearby network's name run commands or fake a saved network in range.
- Roaming never switches to an open, OWE or WEP network or to an access point whose security does not match the saved profile, and holds a failed switch for 30 minutes.
- Roaming leaves a hotspot or ad-hoc connection alone and never switches to one.
- Roaming ignores a malformed signal floor or state directory and logs saved network names without control characters.
- A copied Wi-Fi password leaves the clipboard after 45 seconds, and a shown password no longer lingers once the card closes.

## 0.1.0 — 2026-10-27

- First release: Omarchy network widget with a saved Wi-Fi settings card (auto-connect, priority, show or copy the password, forget) and a service that switches to a higher-priority network when one comes into range.
