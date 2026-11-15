return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`EmperorsPunishment` encountered an error loading the Darktide Mod Framework.")

		new_mod("EmperorsPunishment", {
			mod_script       = "EmperorsPunishment/scripts/mods/EmperorsPunishment/EmperorsPunishment",
			mod_data         = "EmperorsPunishment/scripts/mods/EmperorsPunishment/EmperorsPunishment_data",
			mod_localization = "EmperorsPunishment/scripts/mods/EmperorsPunishment/EmperorsPunishment_localization",
		})
	end,
	packages = {},
}
