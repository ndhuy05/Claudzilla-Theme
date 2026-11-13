# Claudzilla Theme

A personal look for [claudzilla](https://github.com/HT0710/claudzilla) on top of Claude Code. It uses the opencode color palette everywhere: the Claude Code theme, the status line and the margin panel.

## What it changes

| Part | Change |
| --- | --- |
| Claude Code theme | A custom theme named `opencode`, based on `dark`, with opencode's colors. |
| Status line | A compact layout with solid line bars, full labels (`context`, `cache`, `weekly`) and bars of equal length. Each bar is teal, turns amber at 50% and red above 80%. Only the git changes stand out on the top row: the path is plain text, the branch is purple and the version is grey. The email, time, date, session ID, session name and session time are hidden, and the animations are off. |
| Margin panel | Its fixed colors (labels, faint text, rewind and done marks) use the opencode palette. It needs claudzilla v1.8.0 or later. |

## Files

| File | Purpose |
| --- | --- |
| `apply.sh` | Applies everything on this machine. It is also how you update claudzilla. |
| `hud-filter.pl` | My copy of claudzilla's status line script, `claude/hud/hud-filter.pl`, with the changes above. |
| `theme.json` | The Claude Code theme. |
| `settings.overrides.json` | Selects the theme and points the status line at `hud-filter.pl`. |
| `claudzilla.json` | Turns on the compact status line and sets the margin panel colors through claudzilla's `palette` key. |

## Install on a new machine

1. Install claudzilla with the `hud` part, so that it lives at `~/claudzilla`.
2. Clone this repository. Any location works.

   ```bash
   git clone https://github.com/ndhuy05/Claudzilla-Theme.git ~/Claudzilla-Theme
   ```

3. Run the apply script.

   ```bash
   ~/Claudzilla-Theme/apply.sh --yes
   ```

4. Restart Claude Code.

`apply.sh` does the following, in order:

1. It stops before changing anything if claudzilla or its `hud` part is missing.
2. It undoes the margin panel edit that older versions of this script made, then updates claudzilla to its newest release.
3. It links this folder to `~/.claude/claudzilla-theme`, which is where the status line finds `hud-filter.pl`. If you move the folder, run `apply.sh` again.
4. It links `settings.overrides.json` and `theme.json` into `~/.claude`. A real file already at either place is renamed to a `.bak` file first, so nothing is lost.
5. It merges `claudzilla.json` into `~/.claude/claudzilla.json`, keeping the keys that are already there.
6. It runs claudzilla's installer, which merges the settings.

## Update claudzilla

claudzilla updates itself. To update right away, run the apply script again from this folder:

```bash
./apply.sh --yes
```

## Change something

- **Status line colors or layout:** edit `hud-filter.pl`. The change shows within a second, with no need to run `apply.sh`.
- **Theme colors:** edit `theme.json`, then restart Claude Code.
- **Margin panel colors:** edit the `palette` key in `claudzilla.json`, run `apply.sh`, then run `/reload-plugins` in Claude Code. claudzilla's `GUIDE.md` lists every key.
- **Settings:** edit `settings.overrides.json` or `claudzilla.json`, then run `apply.sh`.

## Undo

1. Delete `~/.claude/settings.overrides.json`, `~/.claude/themes/opencode.json` and the `~/.claude/claudzilla-theme` link.
2. Remove the `palette` key from `~/.claude/claudzilla.json`.
3. Run `~/claudzilla/install.sh`, then restart Claude Code.

## Known limits

- `hud-filter.pl` is a frozen copy, so it does not get later claudzilla fixes to the status line. If a claudzilla update changes what `hud-data.mjs` outputs, the status line may break. Deleting the `statusLine` entry from `settings.overrides.json` and running `apply.sh` brings back claudzilla's own status line.
- The slash command menu can only color the text of the selected row. Claude Code has no theme setting for a row background.

## License

`hud-filter.pl` is derived from claudzilla, which is under the MIT License. Its license is in `LICENSE.claudzilla`.
