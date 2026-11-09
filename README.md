# CenterTimer

CenterTimer is a SourceMod HUD plugin for [Shavit Timer](https://github.com/shavitush/bhoptimer) bhop servers. It is a modified version of the [zSpeed - Center Speed HUD](https://github.com/TeasOfficial/zSpeed---Center-Speed-HUD) plugin, adapted into a standalone timer and finish-diff HUD.

It is designed to make it easier for players to see their current run time and their finish time. This is especially useful for players who repeatedly grind map records(like strafe maps): the finish time/difference is displayed right in the center of the screen, rather than having to read it from the shavit timer's chat message.

<img width="287" height="284" alt="image" src="https://github.com/user-attachments/assets/8347a193-13e1-43a9-badf-06a24564f754" /> 
<img width="276" height="261" alt="image" src="https://github.com/user-attachments/assets/c6f67156-8323-4074-a9c2-38aded2035df" />
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/14a17833-6c9d-42ce-8da2-443f74fcd92f" />


## Features

- Time HUD with configurable position, decimal places, and context-aware colors for normal play, practice mode, start zone, and finish.
- Finish Diff HUD with three comparison modes: WR (SourceJump), Server Record, and Personal Best.
- Optional Faster/Slower colors and an optional WR/SR/PB prefix for the finish diff.
- Spectator support: shows the watched player's timer, and their finish time/diff when they finish.
- The live timer also works while spectating Shavit replay bots.
- Menu-driven position editor with a live preview and a Target toggle for switching between the Time HUD and Finish Diff.
- Every player's settings stored in cookies through clientprefs; 

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
- [WRSJ](https://github.com/rtldg/wrsj) for SourceJump world records. Without it, WR mode displays `N/A`.

## Installation

1. Install the requirements above.
2. Copy `zspeed-center-timer.smx` to `addons/sourcemod/plugins/`.
3. Restart the server or run `sm plugins load zspeed-center-timer`.


## Customizing Defaults

Server owners can edit the macros near the top of `CenterTimer.sp` and recompile the plugin to change the initial settings used for **new players** (players who do not already have saved cookies). Examples include `DEFAULT_SHOW_TIME`, `DEFAULT_FINISH_TIME`, `FINISH_DIFF_DELAY`, `FINISH_TIME_DELAY`, default colors, and default HUD positions.

Existing players keep their saved settings until their cookies are cleared.

## Known Problems
Due to HUD refresh limitations, the Finish Diff HUD can sometimes conflict with StrafeTrainer and fail to display properly. If you want to use it, please disable StrafeTrainer if possible.

## A Note on Time HUD Refresh Rate

`TIME_HUD_CMD_INTERVAL` is intentionally hardcoded to `7`; I did not add a command or convar for free adjustment of the Time HUD refresh rate.

The reason is that higher refresh rates noticeably break the display of JumpStats HUDs (like JHUD, Offsets, StrafeTrainer), even though they use different engine HUD channels. In my testing, one update every 7 usercmds (14.2 Hz on a 100-tick server) was the best value, so it is fixed.

tbh, I couldn't solve this issue. If you have a better approach, please let me know or open a pull request.

