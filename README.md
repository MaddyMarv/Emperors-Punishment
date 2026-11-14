### [Emperor's Punishment (PiShock for Darktide)](https://www.nexusmods.com/warhammer40kdarktide/mods/1043)
<img width="1407" height="663" alt="image" src="https://github.com/user-attachments/assets/a48964e6-14f6-4410-bfc6-e84d2aa16327" />

Connects Darktide to a PiShock device to trigger shocks, vibrations, or beeps on specific game events. Each trigger has its own operation, intensity and duration, with optional randomization, chat feedback and a cooldown.

**No companion server needed.** From version 3.0 the mod talks to PiShock directly through a small DLL included in the mod folder (`bin/ps_native.dll`). You no longer need Python, `server.exe` or `start_server.bat`. The DLL's source is included in `native/ps_native.c`.

**Setup:**
1. Install the mod like any other Darktide mod.
2. In game chat, run `/pishock_username <username>` and `/pishock_apikey <apikey>`.
3. Optional: run `/pishock_shocker <names>` to target specific shockers. Without it, all active shockers are triggered.
4. Pick what each trigger does in the mod options.

Your API key must have been generated after 15 October 2024. If the mod reports that the key was rejected, generate a new one on the PiShock website.

**Building the DLL yourself (optional):**
Players do not need to do this. If you would rather not trust the included DLL, you can build it from the source in `PiShock/native/`:
1. Install [zig](https://ziglang.org/download/).
2. Run `PiShock/native/build.sh` on Linux or macOS. On Windows, run this from the `PiShock/native` folder instead: `zig cc -target x86_64-windows-gnu -shared -O2 -s -o ../bin/ps_native.dll ps_native.c -lwinhttp`
3. The new `ps_native.dll` replaces the one in `PiShock/bin/`.

<details>
<summary><b>Mod Settings / Commands</b></summary>

**General**
- Chat Feedback
- Disable Beeps in Randomization
- Continuous Pulse While Disabled
- Command Cooldown (Seconds)
- Health Threshold Percent
- Scale Intensity With Hit Size
- Minimum Intensity
- Maximum Intensity
- Hit Size For Maximum (% of Max Health)

**Vitals**
- Health Damage Taken
- Grimoire Corruption Tick
- Corruption Taken
- Health Drops Below Percent
- Toughness Broken
- Stamina Depleted
- Guard Broken
- Tired Dodge
- High Suppression
- Knocked Down
- Player Death

**Mechanics**
- Minigame Failure
- Plasma / Psyker Explosion
- For the Emperor
- Friendly Fire (Taken)
- Friendly Fire (Dealt)

**Enemies**
- Boss Spawned
- Pounced by Hound
- Trapped by Trapper
- Grabbed by Mutant
- Eaten by Beast of Nurgle
- Grabbed by Chaos Spawn

**Per-trigger settings** (Vitals, Mechanics and Enemies tabs)
- Select Trigger to Edit
- Operation Type (Disabled, Shock, Vibrate, Beep, Random)
- Duration (Seconds)
- Intensity
- Randomize Duration (min and max)
- Randomize Intensity (min and max)

**Commands:**
- `/pishock_username <username>` - Sets your PiShock account username.
- `/pishock_apikey <apikey>` - Sets your PiShock API key.
- `/pishock_shocker <shocker_names>` - Sets specific PiShock shockers to target (comma-separated). Leave blank to clear targeted shockers and trigger all active ones.
- `/pishock_info` - Shows your currently configured PiShock account information (with a masked API key for safety).
</details>

Commissioned by Angels

**Credits:** The FFI and native DLL approach is based on [Emperor's Touch](https://www.nexusmods.com/warhammer40kdarktide/mods/1003) by [augentism](https://www.nexusmods.com/profile/augentism?gameId=4943).

🔗 **Links:** [Source Code](https://github.com/MaddyMarv/Emperor-s-Punishment-Pishock-for-Darktide-) | [Nexus Mods Profile](https://www.nexusmods.com/profile/indicabunny) | [Support Me on Ko-fi](https://ko-fi.com/indicabunny)
