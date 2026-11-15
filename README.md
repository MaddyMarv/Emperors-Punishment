### [Emperor's Punishment](https://www.nexusmods.com/warhammer40kdarktide/mods/1043)
<img width="1407" height="663" alt="image" src="https://github.com/user-attachments/assets/a48964e6-14f6-4410-bfc6-e84d2aa16327" />

Connects Darktide to a PiShock or OpenShock device to trigger shocks, vibrations, or beeps on specific game events. Each trigger has its own operation, intensity and duration, with optional randomization, chat feedback and a cooldown.

**Version 3.0 and newer no longer need a separate server file running. The mod connects to PiShock or OpenShock on its own.**

**Setup:**
1. Install the mod like any other Darktide mod.
2. In the mod options, set **Service** to PiShock or OpenShock. It is Off by default, and nothing is sent while it is Off.
3. Enter your account details in game chat (see below).
4. Optional: run `/ep_target <names>` to target specific shockers. Without it, all active shockers are triggered.
5. Run `/ep_test` to check it works. It sends a short vibration.
6. Pick what each trigger does in the mod options.

**PiShock:** type `/ep_pishock_username <username>` and `/ep_pishock_apikey <apikey>` in chat. Your API key must have been generated after 15 October 2024. If the mod reports that the key was rejected, generate a new one on the PiShock website.

**OpenShock:** type `/ep_openshock_token <token>` in chat. Create the token on [openshock.app](https://openshock.app) under API Tokens, and tick **Use** under **Shockers** (the `shockers.use` permission). The mod uses your own shockers and any shared with you, within the limits the owner set.

Self-hosting? Run `/ep_openshock_server <address>` with your API address (for example `https://api.example.com`). Run it with nothing after it to go back to the official server.

**Building the DLL yourself (optional):**
Players do not need to do this. If you would rather not trust the included DLL, you can build it from the source in `EmperorsPunishment/native/`:
1. Install [zig](https://ziglang.org/download/).
2. Run `EmperorsPunishment/native/build.sh` on Linux or macOS. On Windows, run this from the `EmperorsPunishment/native` folder instead: `zig cc -target x86_64-windows-gnu -shared -O2 -s -o ../bin/ep_native.dll ep_native.c -lwinhttp`
3. The new `ep_native.dll` replaces the one in `EmperorsPunishment/bin/`.

<details>
<summary><b>Mod Settings / Commands</b></summary>

**General**
- Service (Off, PiShock, OpenShock)
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
- `/ep_pishock_username <username>` - Sets your PiShock account username.
- `/ep_pishock_apikey <apikey>` - Sets your PiShock API key.
- `/ep_openshock_token <token>` - Sets your OpenShock API token.
- `/ep_openshock_server <address>` - Sets a self-hosted OpenShock API address. Leave blank to use the official server.
- `/ep_target <shocker_names>` - Sets specific shockers to target (works for both services) (comma-separated). Leave blank to clear targeted shockers and trigger all active ones.
- `/ep_test [shock|vibrate|beep] [intensity] [seconds]` - Sends a test to the active service. Defaults to vibrate at intensity 10 for 1 second.
- `/ep_refresh` - Re-reads your shocker list. Use it after adding, pausing or sharing a shocker while the game is running.
- `/ep_info` - Shows the active service and your configured account information (with masked keys for safety).
- `/ep_info clear` - Clears your saved username, API key, OpenShock token, server address and targeted shockers. Trigger settings are kept.
</details>

Commissioned by Angels

**Credits:** The FFI and native DLL approach is based on [Emperor's Touch](https://www.nexusmods.com/warhammer40kdarktide/mods/1003) by [augentism](https://www.nexusmods.com/profile/augentism?gameId=4943).

🔗 **Links:** [Source Code](https://github.com/MaddyMarv/Emperors-Punishment) | [Nexus Mods Profile](https://www.nexusmods.com/profile/indicabunny) | [Support Me on Ko-fi](https://ko-fi.com/indicabunny)
