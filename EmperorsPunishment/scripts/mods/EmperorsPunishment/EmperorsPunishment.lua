local mod = get_mod("EmperorsPunishment")
local ScriptUnit = mod:original_require("scripts/foundation/utilities/script_unit")

function mod:clock()
	local tm = Managers.time
	if tm then
		if tm:has_timer("main") then
			return tm:time("main")
		end
		if tm:has_timer("gameplay") then
			return tm:time("gameplay")
		end
	end
	return 0
end

local function local_player_unit()
	local player = Managers.player and Managers.player:local_player_safe(1)
	return player and player.player_unit
end

local function is_local_player(unit)
	local player = Managers.player and Managers.player:local_player_safe(1)
	return player and unit == player.player_unit
end

local function local_health_fraction()
	local unit = local_player_unit()
	if not unit then
		return nil
	end
	local ok, frac = pcall(function()
		local ext = ScriptUnit.has_extension(unit, "health_system")
		return ext and ext:current_health_percent()
	end)
	if ok and frac then
		return frac
	end
	return nil
end

local function local_stamina_fraction()
	local unit = local_player_unit()
	if not unit then
		return nil
	end
	local ok, frac = pcall(function()
		local unit_data_ext = ScriptUnit.has_extension(unit, "unit_data_system")
		if unit_data_ext then
			local stamina_comp = unit_data_ext:read_component("stamina")
			if stamina_comp then
				return stamina_comp.current_fraction
			end
		end
	end)
	if ok and frac then
		return frac
	end
	return nil
end

local function local_toughness_fraction()
	local unit = local_player_unit()
	if not unit then
		return nil
	end
	local ok, frac = pcall(function()
		local ext = ScriptUnit.has_extension(unit, "toughness_system")
		return ext and ext:current_toughness_percent()
	end)
	if ok and frac then
		return frac
	end
	return nil
end

local function local_corruption_fraction()
	local unit = local_player_unit()
	if not unit then
		return nil
	end
	local ok, frac = pcall(function()
		local ext = ScriptUnit.has_extension(unit, "health_system")
		return ext and ext:permanent_damage_taken_percent()
	end)
	if ok and frac then
		return frac
	end
	return nil
end

local function local_is_suppressed()
	local unit = local_player_unit()
	if not unit then
		return false
	end
	local ok, suppressed = pcall(function()
		local supp_ext = ScriptUnit.has_extension(unit, "suppression_system")
		if supp_ext then
			return supp_ext:has_high_suppression()
		end
	end)
	return ok and suppressed or false
end

local function get_player_disabled_state(unit)
	if not unit then
		return nil
	end
	local ok, state = pcall(function()
		local unit_data_ext = ScriptUnit.has_extension(unit, "unit_data_system")
		if unit_data_ext then
			local character_state_component = unit_data_ext:read_component("character_state")
			if character_state_component then
				return character_state_component.state_name
			end
		end
	end)
	if ok and state then
		return state
	end
	return nil
end

local function is_player_downed_or_disabled(unit)
	local state = get_player_disabled_state(unit)
	if state then
		local disabled_states = {
			knocked_down = true,
			dead = true,
			pounced = true,
			netted = true,
			mutant_charged = true,
			consumed = true,
			grabbed = true,
		}
		return disabled_states[state] == true
	end
	return false
end

local pishock_command_queue = {}
local last_event_time = 0

local send_pishock_command

local native = mod:io_dofile("EmperorsPunishment/scripts/mods/EmperorsPunishment/services/pishock")

mod.native = native
local openshock = mod:io_dofile("EmperorsPunishment/scripts/mods/EmperorsPunishment/services/openshock")

local service = "off"

local function configure_native()
	service = mod:get("service") or "off"
	if service == "pishock" then
		openshock.reset()
		native.configure(mod:get("pishock_username") or "", mod:get("pishock_apikey") or "")
	elseif service == "openshock" then
		native.configure("", "")
		openshock.configure(mod:get("openshock_token") or "", mod:get("openshock_server") or "")
	else
		native.configure("", "")
		openshock.reset()
	end
end

mod.on_setting_changed = function(setting_id)
	if setting_id == "service" then
		if mod:is_enabled() then
			configure_native()
		end
		return
	end

	local target_match = setting_id:match("^editor_(%w+)_target$")
	if target_match then
		local prefix = target_match
		local target = mod:get(setting_id)
		if not target then
			return
		end

		mod:set("editor_" .. prefix .. "_op", mod:get("trigger_" .. target .. "_op") or "disabled", false)
		mod:set("editor_" .. prefix .. "_duration", mod:get("trigger_" .. target .. "_duration") or 1, false)
		mod:set("editor_" .. prefix .. "_intensity", mod:get("trigger_" .. target .. "_intensity") or 10, false)
		mod:set(
			"editor_" .. prefix .. "_enable_random_duration",
			mod:get("trigger_" .. target .. "_enable_random_duration") or false,
			false
		)
		mod:set("editor_" .. prefix .. "_duration_min", mod:get("trigger_" .. target .. "_duration_min") or 1, false)
		mod:set("editor_" .. prefix .. "_duration_max", mod:get("trigger_" .. target .. "_duration_max") or 1, false)
		mod:set(
			"editor_" .. prefix .. "_enable_random_intensity",
			mod:get("trigger_" .. target .. "_enable_random_intensity") or false,
			false
		)
		mod:set("editor_" .. prefix .. "_intensity_min", mod:get("trigger_" .. target .. "_intensity_min") or 10, false)
		mod:set("editor_" .. prefix .. "_intensity_max", mod:get("trigger_" .. target .. "_intensity_max") or 10, false)
		return
	end

	local prefix, property = setting_id:match("^editor_(%w+)_(.+)$")
	if prefix and property and property ~= "target" and property ~= "group" then
		local target = mod:get("editor_" .. prefix .. "_target")
		if target then
			local value = mod:get(setting_id)
			mod:set("trigger_" .. target .. "_" .. property, value, false)
		end
	end
end

mod.on_all_mods_loaded = function()
	local old_mod = get_mod("PiShock")
	if old_mod and old_mod:is_enabled() then
		mod:echo(mod:localize("msg_old_mod_installed"))
	end

	mod.on_setting_changed("editor_vitals_target")
	mod.on_setting_changed("editor_mechanics_target")
	mod.on_setting_changed("editor_enemies_target")
	if mod:is_enabled() then
		configure_native()
	end
end

mod.on_settings_reset = function()
	local ALL_HOOKS = {
		"on_damage_taken",
		"on_grimoire_damage",
		"on_corruption_damage",
		"on_health_threshold",
		"on_toughness_broken",
		"on_stamina_depleted",
		"on_guard_broken",
		"on_tired_dodge",
		"on_suppressed",
		"on_knocked_down",
		"on_death",
		"on_minigame_fail",
		"on_explode",
		"on_cheer",
		"on_friendly_fire_taken",
		"on_friendly_fire_dealt",
		"on_boss_spawn",
		"on_pounced",
		"on_netted",
		"on_grabbed_mutant",
		"on_consumed",
		"on_grabbed_spawn",
	}

	for _, hook_id in ipairs(ALL_HOOKS) do
		mod:set("trigger_" .. hook_id .. "_op", nil, false)
		mod:set("trigger_" .. hook_id .. "_duration", nil, false)
		mod:set("trigger_" .. hook_id .. "_intensity", nil, false)
		mod:set("trigger_" .. hook_id .. "_enable_random_duration", nil, false)
		mod:set("trigger_" .. hook_id .. "_duration_min", nil, false)
		mod:set("trigger_" .. hook_id .. "_duration_max", nil, false)
		mod:set("trigger_" .. hook_id .. "_enable_random_intensity", nil, false)
		mod:set("trigger_" .. hook_id .. "_intensity_min", nil, false)
		mod:set("trigger_" .. hook_id .. "_intensity_max", nil, false)
	end

	mod.on_all_mods_loaded()
end

local continuous_trigger_timer = 0
local is_currently_continuous_disabled = false
local has_printed_continuous_start = false

local last_health_frac = nil
local last_damage_frac = 0
local last_corr_frac = nil
local last_stamina_frac = nil
local last_toughness_frac = nil
local was_suppressed = false

mod.on_enabled = function()
	configure_native()
end

mod.on_disabled = function()
	native.disconnect()
	openshock.reset()
	table.clear(pishock_command_queue)
	last_health_frac = nil
	last_corr_frac = nil
	last_stamina_frac = nil
	last_toughness_frac = nil
	was_suppressed = false
end

function mod.update(dt)
	if not mod:is_enabled() then
		return
	end

	if service == "pishock" then
		native.update()
	elseif service == "openshock" then
		openshock.update()
	end

	local tm = mod:clock()

	local unit = local_player_unit()
	local state = get_player_disabled_state(unit)
	local hook_id_for_state = nil
	if state then
		local state_to_hook = {
			pounced = "on_pounced",
			netted = "on_netted",
			mutant_charged = "on_grabbed_mutant",
			consumed = "on_consumed",
			grabbed = "on_grabbed_spawn",
		}
		hook_id_for_state = state_to_hook[state]
	end

	local is_disabled_now = (hook_id_for_state ~= nil)

	if is_disabled_now and mod:get("pulse_while_disabled") then
		is_currently_continuous_disabled = true
	else
		if is_currently_continuous_disabled then
			is_currently_continuous_disabled = false
			has_printed_continuous_start = false
			if mod:get("chat_feedback") then
				mod:echo(mod:localize("msg_done"))
			end
		end
	end

	if tm >= continuous_trigger_timer then
		if is_disabled_now and mod:get("pulse_while_disabled") then
			send_pishock_command(hook_id_for_state)
		end
		local cooldown = tonumber(mod:get("command_cooldown")) or 0
		continuous_trigger_timer = tm + math.max(1.0, cooldown)
	end

	if unit then
		local is_disabled = is_player_downed_or_disabled(unit)

		local health_frac = local_health_fraction()
		if health_frac then
			if last_health_frac then
				if health_frac < last_health_frac - 0.001 then
					if not is_disabled then
						last_damage_frac = last_health_frac - health_frac
						send_pishock_command("on_damage_taken")
					end
				end

				local threshold = (mod:get("trigger_on_health_threshold_value") or 30) / 100.0
				if health_frac <= threshold and last_health_frac > threshold then
					if not is_disabled then
						send_pishock_command("on_health_threshold")
					end
				end
			end
			last_health_frac = health_frac
		else
			last_health_frac = nil
		end

		local corr_frac = local_corruption_fraction()
		if corr_frac then
			if last_corr_frac then
				if corr_frac > last_corr_frac + 0.001 then
					if not is_disabled then
						send_pishock_command("on_corruption_damage")
					end
				end
			end
			last_corr_frac = corr_frac
		else
			last_corr_frac = nil
		end

		local toughness_frac = local_toughness_fraction()
		if toughness_frac then
			if last_toughness_frac then
				if last_toughness_frac > 0 and toughness_frac <= 0 then
					if not is_disabled then
						send_pishock_command("on_toughness_broken")
					end
				end
			end
			last_toughness_frac = toughness_frac
		else
			last_toughness_frac = nil
		end

		local stamina_frac = local_stamina_fraction()
		if stamina_frac then
			if last_stamina_frac then
				if last_stamina_frac > 0 and stamina_frac <= 0 then
					if not is_disabled then
						send_pishock_command("on_stamina_depleted")
					end
				end
			end
			last_stamina_frac = stamina_frac
		else
			last_stamina_frac = nil
		end

		local is_suppressed = local_is_suppressed()
		if is_suppressed and not was_suppressed then
			if not is_disabled then
				send_pishock_command("on_suppressed")
			end
		end
		was_suppressed = is_suppressed
	else
		last_health_frac = nil
		last_corr_frac = nil
		last_toughness_frac = nil
		last_stamina_frac = nil
		was_suppressed = false
	end

	if #pishock_command_queue == 0 then
		return
	end

	local hook_id = table.remove(pishock_command_queue, 1)

	local op = mod:get("trigger_" .. hook_id .. "_op")
	if not op or op == "disabled" then
		return
	end

	if op == "random" then
		local ops = { "0", "1", "2" }
		if mod:get("disable_random_beeps") then
			ops = { "0", "1" }
		end
		op = ops[math.random(1, #ops)]
	end

	local duration = tonumber(mod:get("trigger_" .. hook_id .. "_duration")) or 1
	if mod:get("trigger_" .. hook_id .. "_enable_random_duration") then
		local dur_min = tonumber(mod:get("trigger_" .. hook_id .. "_duration_min")) or 1
		local dur_max = tonumber(mod:get("trigger_" .. hook_id .. "_duration_max")) or 1
		duration = (dur_max > dur_min) and math.random(dur_min, dur_max) or dur_min
	end

	local intensity = tonumber(mod:get("trigger_" .. hook_id .. "_intensity")) or 10
	if mod:get("trigger_" .. hook_id .. "_enable_random_intensity") then
		local int_min = tonumber(mod:get("trigger_" .. hook_id .. "_intensity_min")) or 10
		local int_max = tonumber(mod:get("trigger_" .. hook_id .. "_intensity_max")) or 10
		intensity = (int_max > int_min) and math.random(int_min, int_max) or int_min
	end

	if hook_id == "on_damage_taken" and mod:get("scale_intensity_with_damage") then
		local full_frac = (tonumber(mod:get("scale_full_damage_percent")) or 50) / 100
		local max_intensity = tonumber(mod:get("scale_max_intensity")) or 10
		local min_intensity = math.min(tonumber(mod:get("scale_min_intensity")) or 1, max_intensity)
		intensity =
			math.ceil(min_intensity + (max_intensity - min_intensity) * math.min(1, last_damage_frac / full_frac))
	end

	local continuous_disablers = {
		on_pounced = true,
		on_netted = true,
		on_grabbed_mutant = true,
		on_consumed = true,
		on_grabbed_spawn = true,
	}
	if continuous_disablers[hook_id] and mod:get("pulse_while_disabled") then
		duration = 1
	end

	if service == "pishock" then
		local username = mod:get("pishock_username") or ""
		local apikey = mod:get("pishock_apikey") or ""

		if username == "" or apikey == "" then
			mod:echo(mod:localize("msg_pishock_not_set"))
			mod:echo("/ep_pishock_username <username>")
			mod:echo("/ep_pishock_apikey <apikey>")
			return
		end

		if not native.send(username, apikey, op, intensity, duration, mod:get("target_shockers") or "") then
			return
		end
	elseif service == "openshock" then
		local token = mod:get("openshock_token") or ""

		if token == "" then
			mod:echo(mod:localize("msg_openshock_not_set"))
			mod:echo("/ep_openshock_token <token>")
			return
		end

		if
			not openshock.send(
				token,
				mod:get("openshock_server") or "",
				op,
				intensity,
				duration,
				mod:get("target_shockers") or ""
			)
		then
			return
		end
	else
		return
	end

	if mod:get("chat_feedback") then
		local trigger_name = mod:localize("target_" .. hook_id)

		local is_continuous = continuous_disablers[hook_id] and mod:get("pulse_while_disabled")

		if is_continuous then
			if not has_printed_continuous_start then
				has_printed_continuous_start = true
				if op == "0" then
					mod:echo(mod:localize("msg_shocking", trigger_name))
				elseif op == "1" then
					mod:echo(mod:localize("msg_vibrating", trigger_name))
				elseif op == "2" then
					mod:echo(mod:localize("msg_beeping", trigger_name))
				end
			end
		else
			if op == "0" then
				mod:echo(mod:localize("msg_shock", tostring(duration), tostring(intensity), trigger_name))
			elseif op == "1" then
				mod:echo(mod:localize("msg_vibrate", tostring(duration), tostring(intensity), trigger_name))
			elseif op == "2" then
				mod:echo(mod:localize("msg_beep", trigger_name))
			end
		end
	end
end

local last_grimoire_time = 0

function send_pishock_command(hook_id)
	local tm = mod:clock()

	if hook_id == "on_grimoire_damage" then
		if tm < last_grimoire_time + 10 then
			return
		end
		last_grimoire_time = tm
	end

	local cooldown = tonumber(mod:get("command_cooldown")) or 0

	local bypass_cooldown = false
	if hook_id == "on_death" or hook_id == "on_knocked_down" or hook_id == "on_explode" then
		bypass_cooldown = true
	end

	if hook_id ~= "on_grimoire_damage" then
		if not bypass_cooldown and tm < last_event_time + cooldown then
			return
		end
		last_event_time = tm
	end

	table.insert(pishock_command_queue, hook_id)
end

local function state_event(state_class, my_hook_id)
	mod:hook_safe(state_class, "on_enter", function(self, unit, ...)
		local ok, is_me = pcall(is_local_player, unit)
		if ok and is_me then
			send_pishock_command(my_hook_id)
		end
	end)
end

state_event(CLASS.PlayerCharacterStateKnockedDown, "on_knocked_down")
state_event(CLASS.PlayerCharacterStateDead, "on_death")
state_event(CLASS.PlayerCharacterStateMutantCharged, "on_grabbed_mutant")
state_event(CLASS.PlayerCharacterStateNetted, "on_netted")
state_event(CLASS.PlayerCharacterStatePounced, "on_pounced")
state_event(CLASS.PlayerCharacterStateConsumed, "on_consumed")
state_event(CLASS.PlayerCharacterStateGrabbed, "on_grabbed_spawn")
state_event(CLASS.PlayerCharacterStateExploding, "on_explode")

mod:hook_safe(CLASS.PlayerCharacterStateDodging, "on_enter", function(self, unit, ...)
	local ok_me, is_me = pcall(is_local_player, unit)
	if not ok_me or not is_me then
		return
	end

	local ok_tired, is_tired = pcall(function()
		local dodge_state = self._dodge_character_state_component
		local weapon_ext = self._weapon_extension
		local buff_ext = self._buff_extension
		if not dodge_state or not weapon_ext or not buff_ext then
			return false
		end

		local weapon_dodge_template = weapon_ext:dodge_template()
		local stat_buffs = buff_ext:stat_buffs()
		local extra_consecutive_dodges = math.round(stat_buffs.extra_consecutive_dodges or 0)
		local dr_start = (weapon_dodge_template and weapon_dodge_template.diminishing_return_start or 2)
			+ extra_consecutive_dodges

		return dodge_state.consecutive_dodges > dr_start
	end)

	if ok_tired and is_tired then
		send_pishock_command("on_tired_dodge")
	end
end)

mod:hook_safe(
	CLASS.PlayerUnitWeaponExtension,
	"blocked_attack",
	function(
		self,
		attacking_unit,
		hit_world_position,
		block_broken,
		weapon_template,
		attack_type,
		block_cost,
		is_perfect_block
	)
		if not self._unit or not is_local_player(self._unit) then
			return
		end

		if block_broken then
			send_pishock_command("on_guard_broken")
		end
	end
)

mod:hook_safe(CLASS.BossExtension, "extensions_ready", function(self)
	local breed = self._breed
	if breed and breed.tags and breed.tags.monster then
		send_pishock_command("on_boss_spawn")
	end
end)

mod:hook_safe(
	CLASS.AttackReportManager,
	"add_attack_result",
	function(
		self,
		damage_profile,
		attacked_unit,
		attacking_unit,
		attack_direction,
		hit_world_position,
		hit_weakspot,
		damage,
		attack_result,
		attack_type,
		damage_efficiency,
		is_critical_strike,
		...
	)
		local target_is_me = false
		local attacker_is_me = false

		local ok1, is_me1 = pcall(is_local_player, attacked_unit)
		if ok1 and is_me1 then
			target_is_me = true
		end

		local ok2, is_me2 = pcall(is_local_player, attacking_unit)
		if ok2 and is_me2 then
			attacker_is_me = true
		end

		if target_is_me and damage_profile and damage_profile.name == "grimoire_tick" then
			send_pishock_command("on_grimoire_damage")
		end

		if attack_result == "friendly_fire" then
			if target_is_me then
				send_pishock_command("on_friendly_fire_taken")
			elseif attacker_is_me then
				send_pishock_command("on_friendly_fire_dealt")
			end
		end
	end
)

mod:hook_safe(CLASS.MinigameBase, "play_sound", function(self, alias)
	if alias == "sfx_minigame_fail" or alias == "sfx_minigame_bio_fail" then
		local player = Managers.player and Managers.player:player_from_session_id(self._player_session_id)
		if player and is_local_player(player.player_unit) then
			send_pishock_command("on_minigame_fail")
		end
	end
end)

local MINIGAME_FAIL_EVENTS = {
	["wwise/events/player/play_device_auspex_scanner_minigame_fail"] = true,
	["wwise/events/player/play_device_auspex_bio_minigame_fail"] = true,
}

mod:hook_safe(CLASS.PlayerUnitFxExtension, "rpc_play_player_sound", function(self, channel_id, game_object_id, event_id)
	if MINIGAME_FAIL_EVENTS[NetworkLookup.player_character_sounds[event_id]] and is_local_player(self._unit) then
		send_pishock_command("on_minigame_fail")
	end
end)

mod:hook_safe(
	CLASS.DialogueSystem,
	"_play_dialogue_event_implementation",
	function(self, go_id, is_level_unit, level_name_hash, dialogue_id, ...)
		local ok, is_cheer = pcall(function()
			return NetworkLookup.dialogue_names[dialogue_id] == "com_wheel_vo_for_the_emperor"
		end)
		if not ok or not is_cheer then
			return
		end

		local ok_unit, unit = pcall(function()
			return Managers.state.unit_spawner:unit(go_id, is_level_unit, level_name_hash)
		end)
		if not ok_unit or not unit then
			return
		end

		local ok_me, is_me = pcall(is_local_player, unit)
		if ok_me and is_me then
			send_pishock_command("on_cheer")
		end
	end
)

local function mask(secret)
	if secret == "" then
		return mod:localize("msg_not_set")
	end
	if string.len(secret) > 4 then
		return string.sub(secret, 1, 4) .. string.rep("*", string.len(secret) - 4)
	end
	return string.rep("*", string.len(secret))
end

mod:command("ep_pishock_username", mod:localize("cmd_pishock_username"), function(...)
	local args = { ... }
	if #args > 0 then
		local username = table.concat(args, " ")
		mod:set("pishock_username", username)
		mod:echo(mod:localize("msg_username_set", username))
		if service == "pishock" then
			configure_native()
		else
			mod:echo(mod:localize("msg_pick_pishock"))
		end
	else
		mod:echo(mod:localize("msg_usage", "/ep_pishock_username <username>"))
	end
end)

mod:command("ep_pishock_apikey", mod:localize("cmd_pishock_apikey"), function(...)
	local args = { ... }
	if #args > 0 then
		local apikey = table.concat(args, " ")
		mod:set("pishock_apikey", apikey)
		mod:echo(mod:localize("msg_apikey_set", mask(apikey)))
		if service == "pishock" then
			configure_native()
		else
			mod:echo(mod:localize("msg_pick_pishock"))
		end
	else
		mod:echo(mod:localize("msg_usage", "/ep_pishock_apikey <apikey>"))
	end
end)

mod:command("ep_openshock_token", mod:localize("cmd_openshock_token"), function(...)
	local args = { ... }
	if #args > 0 then
		local token = table.concat(args, " ")
		mod:set("openshock_token", token)
		mod:echo(mod:localize("msg_token_set", mask(token)))
		if service == "openshock" then
			configure_native()
		else
			mod:echo(mod:localize("msg_pick_openshock"))
		end
	else
		mod:echo(mod:localize("msg_usage", "/ep_openshock_token <token>"))
	end
end)

mod:command("ep_openshock_server", mod:localize("cmd_openshock_server"), function(...)
	local server = string.gsub(table.concat({ ... }, " "), "/+$", "")
	if server == "" then
		mod:set("openshock_server", "")
		mod:echo(mod:localize("msg_server_reset"))
	elseif string.find(server, "^https?://[^/%s]+") then
		mod:set("openshock_server", server)
		mod:echo(mod:localize("msg_server_set", server))
	else
		mod:echo(mod:localize("msg_usage", "/ep_openshock_server <https://api.your-server.com>"))
		return
	end
	if service == "openshock" then
		configure_native()
	end
end)

mod:command("ep_target", mod:localize("cmd_target"), function(...)
	local args = { ... }
	if #args > 0 then
		local shockers = table.concat(args, " ")
		mod:set("target_shockers", shockers)
		mod:echo(mod:localize("msg_target_set", shockers))
	else
		mod:set("target_shockers", "")
		mod:echo(mod:localize("msg_target_cleared"))
	end
end)

mod:command("ep_test", mod:localize("cmd_test"), function(op_name, intensity, duration)
	local ops = { shock = "0", vibrate = "1", beep = "2" }
	op_name = string.lower(op_name or "vibrate")
	local op = ops[op_name]
	intensity = math.clamp(math.floor(tonumber(intensity) or 10), 1, 100)
	duration = math.clamp(math.floor(tonumber(duration) or 1), 1, 15)
	if not op then
		mod:echo(mod:localize("msg_usage", "/ep_test [shock|vibrate|beep] [intensity] [seconds]"))
		return
	end

	local shocker_names = mod:get("target_shockers") or ""
	local sent, reason
	if service == "pishock" then
		local username = mod:get("pishock_username") or ""
		local apikey = mod:get("pishock_apikey") or ""
		if username == "" or apikey == "" then
			mod:echo(mod:localize("msg_test_pishock_not_set"))
			return
		end
		sent, reason = native.send(username, apikey, op, intensity, duration, shocker_names, true)
	elseif service == "openshock" then
		local token = mod:get("openshock_token") or ""
		if token == "" then
			mod:echo(mod:localize("msg_test_openshock_not_set"))
			return
		end
		sent, reason =
			openshock.send(token, mod:get("openshock_server") or "", op, intensity, duration, shocker_names, true)
	else
		mod:echo(mod:localize("msg_service_off"))
		return
	end

	if sent then
		mod:echo(mod:localize("msg_test_sent", op_name, tostring(duration), tostring(intensity)))
	elseif reason == "connecting" then
		mod:echo(mod:localize("msg_test_connecting"))
	else
		mod:echo(mod:localize("msg_test_not_sent"))
	end
end)

mod:command("ep_refresh", mod:localize("cmd_refresh"), function()
	if service ~= "pishock" and service ~= "openshock" then
		mod:echo(mod:localize("msg_service_off"))
		return
	end
	configure_native()
	local started = service == "pishock" and native.refresh() or service == "openshock" and openshock.refresh()
	if started then
		mod:echo(mod:localize("msg_refreshing"))
	else
		mod:echo(mod:localize("msg_refresh_no_login"))
	end
end)

mod:command("ep_info", mod:localize("cmd_info"), function(action)
	if action then
		if string.lower(action) ~= "clear" then
			mod:echo(mod:localize("msg_usage", "/ep_info [clear]"))
			return
		end
		mod:set("pishock_username", "")
		mod:set("pishock_apikey", "")
		mod:set("openshock_token", "")
		mod:set("openshock_server", "")
		mod:set("target_shockers", "")
		configure_native()
		mod:echo(mod:localize("msg_info_cleared"))
		return
	end

	local username = mod:get("pishock_username") or ""
	local apikey = mod:get("pishock_apikey") or ""
	local shocker_names = mod:get("target_shockers") or ""

	local display_username = username ~= "" and username or mod:localize("msg_not_set")
	local display_shockers = shocker_names ~= "" and shocker_names or mod:localize("msg_all_devices")

	local service_names = { pishock = "PiShock", openshock = "OpenShock" }

	local server = mod:get("openshock_server") or ""

	mod:echo(mod:localize("msg_info_header"))
	mod:echo(mod:localize("msg_info_service", service_names[service] or mod:localize("service_off")))
	mod:echo(mod:localize("msg_info_target", display_shockers))
	if service ~= "openshock" then
		mod:echo("--- PiShock ---")
		mod:echo(mod:localize("msg_info_username", display_username))
		mod:echo(mod:localize("msg_info_apikey", mask(apikey)))
	end
	if service ~= "pishock" then
		mod:echo("--- OpenShock ---")
		mod:echo(mod:localize("msg_info_token", mask(mod:get("openshock_token") or "")))
		mod:echo(mod:localize("msg_info_server", server ~= "" and server or mod:localize("msg_official")))
	end
end)
