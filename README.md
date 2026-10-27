# Wi-Fi Settings for Omarchy

A drop-in replacement for Omarchy's network bar widget that adds settings for saved Wi-Fi networks, plus a small service that moves you to a higher-priority network when one comes into range.

- **Saved networks**: every saved Wi-Fi profile, in range or not, with when it was last used.
- **Auto-connect**: turn joining a network on its own on or off.
- **Priority**: rank networks. NetworkManager picks the highest one in range, and the plugin switches to it from a lower one (home Wi-Fi over a phone hotspot, for example).
- **Password**: show it, or copy it to the clipboard.
- **Forget**: delete the saved network, with a confirmation click.

Everything else in the panel (connection details, band, DNS, network list, QR share, speed test) is Omarchy's own `omarchy.network` panel, unchanged.

## Requirements

- Omarchy with the Quattro shell (`omarchy plugin` commands available)
- NetworkManager as the network backend, with `nmcli`
- `wl-copy` (wl-clipboard) for copying passwords, as Omarchy ships it

Changing a saved network uses `nmcli connection modify` and `delete`. On Omarchy, NetworkManager's polkit rule lets members of the `wheel` group do that from a local session without a password prompt; on other setups NetworkManager may ask for authentication or refuse.

## Install

```sh
omarchy plugin add https://github.com/Enns-Automations/omarchy-wifi-settings.git --enable
```

Enabling puts the widget in the network widget's place in the bar and turns the built-in `omarchy.network` off. The Super+Ctrl+W keybinding and anything else that opens `omarchy.network` open this panel instead.

Update with `omarchy plugin update com.ennsautomations.wifi-settings`.

## Use

Open the network panel from its bar icon or Super+Ctrl+W.

| Action | Opens |
| --- | --- |
| Gear in the panel header | The list of saved networks and the roaming switch |
| Gear on a saved network's row | That network's settings |
| `s` | The highlighted saved network, or the list when none is highlighted |

Inside the settings card: `j`/`k` or the arrow keys move, Enter or `l` activates, Esc or `h` goes back one level. A click outside the card goes back too.

### Priority and switching

NetworkManager uses a network's priority only when it is choosing one to join. It never leaves a connected network for a better one. The plugin's service fills that gap. Once a minute, while you are on a lower-priority network, it rescans. If a saved network with a higher priority and auto-connect on is in range at 40% signal or more, it connects to it.

A deliberate choice sticks. If you join a lower network while a higher one is already in range, the service leaves it alone until the higher network drops out of range and comes back. A switch that fails, for example on a wrong saved password, is held the same way, so your current connection is not dropped every minute.

Turn the switching off with **Switch to higher priority** at the bottom of the saved-network list. Priorities still apply when NetworkManager picks a network itself.

## Privacy and files

- Passwords are read only when you click show or copy. A copy goes straight from `nmcli` to `wl-copy --sensitive`, never through an argument list. A shown password is dropped from memory when the card closes.
- State lives in `~/.local/state/omarchy-wifi-settings/`: `roam` (the current connection and any held networks) and `roaming-off` (present when switching is off).
- Nothing is sent anywhere. The plugin only runs `nmcli` and `wl-copy`.

## Remove

```sh
omarchy plugin remove com.ennsautomations.wifi-settings
rm -rf ~/.local/state/omarchy-wifi-settings
```

Removing restores Omarchy's built-in network widget in the same bar position. Your saved networks and the priorities and auto-connect settings you changed stay in NetworkManager.

## Notes

`Panel.qml` and `Model.js` are a copy of Omarchy's `omarchy.network` plugin with the settings hooks added, so Omarchy updates to that panel reach this plugin only when a new release of this plugin takes them in.

## License

MIT, see [LICENSE](LICENSE). The derived panel files keep Omarchy's MIT copyright notice.
