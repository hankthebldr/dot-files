# Logitech config — MX Vertical (Ubuntu)

The MX Vertical works as a plain mouse via the kernel HID driver with no extra
software. These tools add configuration:

- **Solaar** — battery %, pointer/scroll speed, basic settings (GUI + tray + CLI).
- **logiops** (`logid`) — advanced button remap, gestures, DPI via `/etc/logid.cfg`.

Both are in the Ubuntu repos (24.04). They coexist; if a setting fights, prefer
one tool for that setting.

## Install

```bash
sudo apt update
sudo apt install -y solaar logiops
```

## Deploy this repo's logid config

```bash
# symlink so edits in the repo take effect (back up any existing file first)
sudo ln -sfn "$HOME/.dotfiles/config/logitech/logid.cfg" /etc/logid.cfg
sudo systemctl enable --now logid
sudo systemctl restart logid        # after any config edit
```

## Customizing

1. Find button CIDs / confirm the device name: `sudo logid -v`, then press buttons.
2. Edit `config/logitech/logid.cfg`, uncomment/adjust the `buttons` examples.
3. `sudo systemctl restart logid`.

Solaar needs no config — launch `solaar` (or it auto-starts to the tray).
Battery: `solaar show` (CLI).
