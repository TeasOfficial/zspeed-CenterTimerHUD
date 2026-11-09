# CenterTimer

CenterTimer is a SourceMod HUD plugin for [Shavit Timer](https://github.com/shavitush/bhoptimer) bhop servers. It is a modified/reworked version of the [zSpeed - Center Speed HUD](https://github.com/TeasOfficial/zSpeed---Center-Speed-HUD) plugin, adapted into a standalone timer and finish-diff HUD.

It provides a configurable on-screen timer, an optional finish time display, and a finish diff HUD that compares a run against the world record, server record, or personal best.

## Features

- Time HUD with configurable position, decimal places, and context-aware colors for normal play, practice mode, start zone, and finish.
- Finish Diff HUD with three comparison modes: WR (SourceJump), Server Record, and Personal Best.
- Optional Faster/Slower colors and an optional WR/SR/PB prefix for the finish diff.
- Optional Finish Time HUD with its own delay; the Finish Time and Finish Diff delays are independent.
- Spectator support: shows the watched player's timer, and their finish time/diff when they finish.
- The live timer also works while spectating Shavit replay bots.
- Menu-driven position editor with a live preview and a Target toggle for switching between the Time HUD and Finish Diff.
- Per-player settings stored through clientprefs; no configuration file is required.

## Commands

| Command | Chat alias | Description |
|---|---|---|
| `sm_th` / `sm_thud` | `!th` / `!thud` | Open Time HUD settings |
| `sm_fd` / `sm_finishdiff` | `!fd` / `!finishdiff` | Open Finish Diff settings |

Both `/` and `!` work as chat triggers.

## Requirements

- SourceMod 1.11 or newer
- [Shavit Timer](https://github.com/shavitush/bhoptimer) (core, zones, WR, replay-playback)
- [DynamicChannels](https://github.com/Vauff/DynamicChannels)
- [morecolors](https://forums.alliedmods.net/showthread.php?t=185016)
- Optional: [WRSJ](https://github.com/rtldg/wrsj) for SourceJump world records. Without it, WR mode displays `N/A`.

## Installation

1. Install the requirements above.
2. Copy `CenterTimer.smx` to `addons/sourcemod/plugins/`.
3. Restart the server or run `sm plugins load CenterTimer`.

No configuration file is needed. Settings are saved per player using clientprefs cookies prefixed with `centertimer_`.

## Customizing Defaults

Server owners can edit the macros near the top of `CenterTimer.sp` and recompile the plugin to change the initial settings used for **new players** (players who do not already have saved cookies). Examples include `DEFAULT_SHOW_TIME`, `DEFAULT_FINISH_TIME`, `FINISH_DIFF_DELAY`, `FINISH_TIME_DELAY`, default colors, and default HUD positions.

Existing players keep their saved settings until their cookies are cleared.

## A Note on Time HUD Refresh Rate

`TIME_HUD_CMD_INTERVAL` is intentionally hardcoded to `7`; I did not add a command or convar for free adjustment of the Time HUD refresh rate.

The reason is that higher refresh rates noticeably break the display of JumpStats HUDs such as JHUD, Offsets, and StrafeTrainer, even though they use different engine HUD channels. In my testing, one update every 7 usercmds (7 ticks under normal conditions, roughly 14.2 Hz on a 100-tick server) was the best value, so it is fixed.

To be honest, I couldn't solve this issue. If you have a better approach, please let me know or open a pull request.

## Links

- [SourceMod](https://www.sourcemod.net/)
- [Shavit Timer (bhoptimer)](https://github.com/shavitush/bhoptimer)
- [morecolors](https://forums.alliedmods.net/showthread.php?t=185016)
- [DynamicChannels](https://github.com/Vauff/DynamicChannels)
- [WRSJ](https://github.com/rtldg/wrsj)
- [Original zSpeed - Center Speed HUD](https://github.com/TeasOfficial/zSpeed---Center-Speed-HUD)
