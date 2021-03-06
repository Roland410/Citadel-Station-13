#define SIPHONING	0
#define SCRUBBING	1

/obj/machinery/atmospherics/components/unary/vent_scrubber
	name = "air scrubber"
	desc = "Has a valve and pump attached to it."
	icon_state = "scrub_map"
	use_power = IDLE_POWER_USE
	idle_power_usage = 10
	active_power_usage = 60
	can_unwrench = TRUE
	welded = FALSE
	level = 1
	layer = GAS_SCRUBBER_LAYER

	var/id_tag = null
	var/on = FALSE
	var/scrubbing = SCRUBBING //0 = siphoning, 1 = scrubbing

	var/scrub_CO2 = TRUE
	var/scrub_Toxins = FALSE
	var/scrub_N2O = FALSE
	var/scrub_BZ = FALSE
	var/scrub_Freon = FALSE
	var/scrub_WaterVapor = FALSE


	var/volume_rate = 200
	var/widenet = 0 //is this scrubber acting on the 3x3 area around it.
	var/list/turf/adjacent_turfs = list()

	var/frequency = 1439
	var/datum/radio_frequency/radio_connection
	var/radio_filter_out
	var/radio_filter_in

/obj/machinery/atmospherics/components/unary/vent_scrubber/New()
	..()
	if(!id_tag)
		assign_uid()
		id_tag = num2text(uid)

/obj/machinery/atmospherics/components/unary/vent_scrubber/on
	on = TRUE
	icon_state = "scrub_map_on"

/obj/machinery/atmospherics/components/unary/vent_scrubber/Destroy()
	var/area/A = get_area(src)
	A.air_scrub_names -= id_tag
	A.air_scrub_info -= id_tag

	SSradio.remove_object(src,frequency)
	radio_connection = null

	for(var/I in adjacent_turfs)
		I = null

	return ..()

/obj/machinery/atmospherics/components/unary/vent_scrubber/auto_use_power()
	if(!on || welded || !is_operational() || !powered(power_channel))
		return FALSE

	var/amount = idle_power_usage

	if(scrubbing & SCRUBBING)
		if(scrub_CO2)
			amount += idle_power_usage
		if(scrub_Toxins)
			amount += idle_power_usage
		if(scrub_N2O)
			amount += idle_power_usage
		if(scrub_BZ)
			amount += idle_power_usage
		if(scrub_Freon)
			amount += idle_power_usage
		if(scrub_WaterVapor)
			amount += idle_power_usage
	else //scrubbing == SIPHONING
		amount = active_power_usage

	if(widenet)
		amount += amount * (adjacent_turfs.len * (adjacent_turfs.len / 2))
	use_power(amount, power_channel)
	return TRUE

/obj/machinery/atmospherics/components/unary/vent_scrubber/update_icon_nopipes()
	cut_overlays()
	if(showpipe)
		add_overlay(getpipeimage(icon, "scrub_cap", initialize_directions))

	if(welded)
		icon_state = "scrub_welded"
		return

	if(!NODE1 || !on || !is_operational())
		icon_state = "scrub_off"
		return

	if(scrubbing & SCRUBBING)
		icon_state = "scrub_on"
	else //scrubbing == SIPHONING
		icon_state = "scrub_purge"

/obj/machinery/atmospherics/components/unary/vent_scrubber/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	radio_connection = SSradio.add_object(src, frequency, radio_filter_in)

/obj/machinery/atmospherics/components/unary/vent_scrubber/proc/broadcast_status()
	if(!radio_connection)
		return FALSE

	var/datum/signal/signal = new
	signal.transmission_method = 1 //radio signal
	signal.source = src
	signal.data = list(
		"tag" = id_tag,
		"frequency" = frequency,
		"device" = "VS",
		"timestamp" = world.time,
		"power" = on,
		"scrubbing" = scrubbing,
		"widenet" = widenet,
		"filter_co2" = scrub_CO2,
		"filter_toxins" = scrub_Toxins,
		"filter_n2o" = scrub_N2O,
		"filter_bz" = scrub_BZ,
		"filter_freon" = scrub_Freon,
		"filter_water_vapor" = scrub_WaterVapor,
		"sigtype" = "status"
	)

	var/area/A = get_area(src)
	if(!A.air_scrub_names[id_tag])
		name = "\improper [A.name] air scrubber #[A.air_scrub_names.len + 1]"
		A.air_scrub_names[id_tag] = name
	A.air_scrub_info[id_tag] = signal.data

	radio_connection.post_signal(src, signal, radio_filter_out)

	return TRUE

/obj/machinery/atmospherics/components/unary/vent_scrubber/atmosinit()
	radio_filter_in = frequency==initial(frequency)?(GLOB.RADIO_FROM_AIRALARM):null
	radio_filter_out = frequency==initial(frequency)?(GLOB.RADIO_TO_AIRALARM):null
	if(frequency)
		set_frequency(frequency)
	broadcast_status()
	check_turfs()
	..()

/obj/machinery/atmospherics/components/unary/vent_scrubber/process_atmos()
	..()
	if(welded || !is_operational())
		return FALSE
	if(!NODE1 || !on)
		on = FALSE
		return FALSE
	scrub(loc)
	if(widenet)
		for(var/turf/tile in adjacent_turfs)
			scrub(tile)
	return TRUE

/obj/machinery/atmospherics/components/unary/vent_scrubber/proc/scrub(var/turf/tile)
	if(!istype(tile))
		return FALSE

	var/datum/gas_mixture/environment = tile.return_air()
	var/datum/gas_mixture/air_contents = AIR1
	var/list/env_gases = environment.gases

	if(air_contents.return_pressure() >= 50*ONE_ATMOSPHERE)
		return FALSE

	if(scrubbing & SCRUBBING)
		var/should_we_scrub = FALSE
		for(var/id in env_gases)
			if(id == /datum/gas/nitrogen || id == /datum/gas/oxygen)
				continue
			if(env_gases[id][MOLES])
				should_we_scrub = TRUE
				break
		if(should_we_scrub)
			var/transfer_moles = min(1, volume_rate/environment.volume)*environment.total_moles()

			//Take a gas sample
			var/datum/gas_mixture/removed = tile.remove_air(transfer_moles)
			//Nothing left to remove from the tile
			if(isnull(removed))
				return FALSE
			var/list/removed_gases = removed.gases

			//Filter it
			var/datum/gas_mixture/filtered_out = new
			var/list/filtered_gases = filtered_out.gases
			filtered_out.temperature = removed.temperature

			if(scrub_Toxins && removed_gases[/datum/gas/plasma])
				ADD_GAS(/datum/gas/plasma, filtered_out.gases)
				filtered_gases[/datum/gas/plasma][MOLES] = removed_gases[/datum/gas/plasma][MOLES]
				removed_gases[/datum/gas/plasma][MOLES] = 0

			if(scrub_CO2 && removed_gases[/datum/gas/carbon_dioxide])
				ADD_GAS(/datum/gas/carbon_dioxide, filtered_out.gases)
				filtered_gases[/datum/gas/carbon_dioxide][MOLES] = removed_gases[/datum/gas/carbon_dioxide][MOLES]
				removed_gases[/datum/gas/carbon_dioxide][MOLES] = 0

			if(removed_gases[/datum/gas/oxygen_agent_b])
				ADD_GAS(/datum/gas/oxygen_agent_b, filtered_out.gases)
				filtered_gases[/datum/gas/oxygen_agent_b][MOLES] = removed_gases[/datum/gas/oxygen_agent_b][MOLES]
				removed_gases[/datum/gas/oxygen_agent_b][MOLES] = 0

			if(scrub_N2O && removed_gases[/datum/gas/nitrous_oxide])
				ADD_GAS(/datum/gas/nitrous_oxide, filtered_out.gases)
				filtered_gases[/datum/gas/nitrous_oxide][MOLES] = removed_gases[/datum/gas/nitrous_oxide][MOLES]
				removed_gases[/datum/gas/nitrous_oxide][MOLES] = 0

			if(scrub_BZ && removed_gases[/datum/gas/bz])
				ADD_GAS(/datum/gas/bz, filtered_out.gases)
				filtered_gases[/datum/gas/bz][MOLES] = removed_gases[/datum/gas/bz][MOLES]
				removed_gases[/datum/gas/bz][MOLES] = 0

			if(scrub_Freon && removed_gases[/datum/gas/freon])
				ADD_GAS(/datum/gas/freon, filtered_out.gases)
				filtered_gases[/datum/gas/freon][MOLES] = removed_gases[/datum/gas/freon][MOLES]
				removed_gases[/datum/gas/freon][MOLES] = 0

			if(scrub_WaterVapor && removed_gases[/datum/gas/water_vapor])
				ADD_GAS(/datum/gas/water_vapor, filtered_out.gases)
				filtered_gases[/datum/gas/water_vapor][MOLES] = removed_gases[/datum/gas/water_vapor][MOLES]
				removed_gases[/datum/gas/water_vapor][MOLES] = 0

			removed.garbage_collect()

			//Remix the resulting gases
			air_contents.merge(filtered_out)

			tile.assume_air(removed)
			tile.air_update_turf()

	else //Just siphoning all air

		var/transfer_moles = environment.total_moles()*(volume_rate/environment.volume)

		var/datum/gas_mixture/removed = tile.remove_air(transfer_moles)

		air_contents.merge(removed)
		tile.air_update_turf()

	update_parents()

	return TRUE


//There is no easy way for an object to be notified of changes to atmos can pass flags_1
//	So we check every machinery process (2 seconds)
/obj/machinery/atmospherics/components/unary/vent_scrubber/process()
	if(widenet)
		check_turfs()

//we populate a list of turfs with nonatmos-blocked cardinal turfs AND
//	diagonal turfs that can share atmos with *both* of the cardinal turfs
/obj/machinery/atmospherics/components/unary/vent_scrubber/proc/check_turfs()
	adjacent_turfs.Cut()
	var/turf/T = get_turf(src)
	if(istype(T))
		adjacent_turfs = T.GetAtmosAdjacentTurfs(alldir = 1)


/obj/machinery/atmospherics/components/unary/vent_scrubber/receive_signal(datum/signal/signal)
	if(!is_operational() || !signal.data["tag"] || (signal.data["tag"] != id_tag) || (signal.data["sigtype"]!="command"))
		return 0

	if("power" in signal.data)
		on = text2num(signal.data["power"])
	if("power_toggle" in signal.data)
		on = !on

	if("widenet" in signal.data)
		widenet = text2num(signal.data["widenet"])
	if("toggle_widenet" in signal.data)
		widenet = !widenet

	if("scrubbing" in signal.data)
		scrubbing = text2num(signal.data["scrubbing"])
	if("toggle_scrubbing" in signal.data)
		scrubbing = !scrubbing

	if("co2_scrub" in signal.data)
		scrub_CO2 = text2num(signal.data["co2_scrub"])
	if("toggle_co2_scrub" in signal.data)
		scrub_CO2 = !scrub_CO2

	if("tox_scrub" in signal.data)
		scrub_Toxins = text2num(signal.data["tox_scrub"])
	if("toggle_tox_scrub" in signal.data)
		scrub_Toxins = !scrub_Toxins

	if("n2o_scrub" in signal.data)
		scrub_N2O = text2num(signal.data["n2o_scrub"])
	if("toggle_n2o_scrub" in signal.data)
		scrub_N2O = !scrub_N2O

	if("bz_scrub" in signal.data)
		scrub_BZ = text2num(signal.data["bz_scrub"])
	if("toggle_bz_scrub" in signal.data)
		scrub_BZ = !scrub_BZ

	if("freon_scrub" in signal.data)
		scrub_Freon = text2num(signal.data["freon_scrub"])
	if("toggle_freon_scrub" in signal.data)
		scrub_Freon = !scrub_Freon

	if("water_vapor_scrub" in signal.data)
		scrub_WaterVapor = text2num(signal.data["water_vapor_scrub"])
	if("toggle_water_vapor_scrub" in signal.data)
		scrub_WaterVapor = !scrub_WaterVapor

	if("init" in signal.data)
		name = signal.data["init"]
		return

	if("status" in signal.data)
		broadcast_status()
		return //do not update_icon

	broadcast_status()
	update_icon()
	return

/obj/machinery/atmospherics/components/unary/vent_scrubber/power_change()
	..()
	update_icon_nopipes()

/obj/machinery/atmospherics/components/unary/vent_scrubber/attackby(obj/item/W, mob/user, params)
	if(istype(W, /obj/item/weldingtool))
		var/obj/item/weldingtool/WT = W
		if(WT.remove_fuel(0,user))
			playsound(loc, WT.usesound, 40, 1)
			to_chat(user, "<span class='notice'>Now welding the scrubber.</span>")
			if(do_after(user, 20*W.toolspeed, target = src))
				if(!src || !WT.isOn())
					return
				playsound(src.loc, 'sound/items/welder2.ogg', 50, 1)
				if(!welded)
					user.visible_message("[user] welds the scrubber shut.","You weld the scrubber shut.", "You hear welding.")
					welded = TRUE
				else
					user.visible_message("[user] unwelds the scrubber.", "You unweld the scrubber.", "You hear welding.")
					welded = FALSE
				update_icon()
				pipe_vision_img = image(src, loc, layer = ABOVE_HUD_LAYER, dir = dir)
				pipe_vision_img.plane = ABOVE_HUD_PLANE
			return 0
	else
		return ..()

/obj/machinery/atmospherics/components/unary/vent_scrubber/can_unwrench(mob/user)
	. = ..()
	if(. && on && is_operational())
		to_chat(user, "<span class='warning'>You cannot unwrench [src], turn it off first!</span>")
		return FALSE

/obj/machinery/atmospherics/components/unary/vent_scrubber/can_crawl_through()
	return !welded

/obj/machinery/atmospherics/components/unary/vent_scrubber/attack_alien(mob/user)
	if(!welded || !(do_after(user, 20, target = src)))
		return
	user.visible_message("[user] furiously claws at [src]!", "You manage to clear away the stuff blocking the scrubber.", "You hear loud scraping noises.")
	welded = FALSE
	update_icon()
	pipe_vision_img = image(src, loc, layer = ABOVE_HUD_LAYER, dir = dir)
	pipe_vision_img.plane = ABOVE_HUD_PLANE
	playsound(loc, 'sound/weapons/bladeslice.ogg', 100, 1)



#undef SIPHONING
#undef SCRUBBING
