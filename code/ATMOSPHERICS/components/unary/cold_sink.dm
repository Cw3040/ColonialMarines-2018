//TODO: Put this under a common parent type with heaters to cut down on the copypasta
#define FREEZER_PERF_MULT 2.5

/obj/machinery/atmospherics/unary/freezer
	name = "gas cooling system"
	desc = "Cools gas when connected to pipe network"
	icon = 'icons/obj/machines/cryogenics.dmi'
	icon_state = "freezer_0"
	density = 1

	anchored = TRUE

	var/heatsink_temperature = T20C	//the constant temperature resevoir into which the freezer pumps heat. Probably the hull of the station or something.

	var/on = 0
	use_power = 0
	idle_power_usage = 5			//5 Watts for thermostat related circuitry
	active_power_usage			//50 kW. The power rating of the freezer

	var/max_power_usage = 20000 //power rating when the usage is turned up to 100
	var/power_setting = 100

	var/set_temperature = T20C	//thermostat
	var/cooling = 0
	var/opened = 0	//for deconstruction

/obj/machinery/atmospherics/unary/freezer/New()
	..()
	initialize_directions = dir

	component_parts = list()
	component_parts += new /obj/item/circuitboard/machine/unary_atmos/cooler(src)
	component_parts += new /obj/item/stock_parts/matter_bin(src)
	component_parts += new /obj/item/stock_parts/capacitor(src)
	component_parts += new /obj/item/stock_parts/capacitor(src)
	component_parts += new /obj/item/stock_parts/manipulator(src)

	active_power_usage = max_power_usage * (power_setting/100)
	start_processing()

/obj/machinery/atmospherics/unary/freezer/initialize()
	if(node) return

	var/node_connect = dir

	for(var/obj/machinery/atmospherics/target in get_step(src,node_connect))
		if(target.initialize_directions & get_dir(target,src))
			node = target
			break

	update_icon()


/obj/machinery/atmospherics/unary/freezer/update_icon()
	if(src.node)
		if(src.on && cooling)
			icon_state = "freezer_1"
		else
			icon_state = "freezer"
	else
		icon_state = "freezer_0"
	return

/obj/machinery/atmospherics/unary/freezer/attack_ai(mob/user as mob)
	src.ui_interact(user)

/obj/machinery/atmospherics/unary/freezer/attack_paw(mob/user as mob)
	src.ui_interact(user)

/obj/machinery/atmospherics/unary/freezer/attack_hand(mob/user as mob)
	src.ui_interact(user)

/obj/machinery/atmospherics/unary/freezer/ui_interact(mob/user, ui_key = "main", var/datum/nanoui/ui = null, var/force_open = 1)
	// this is the data which will be sent to the ui
	var/data[0]
	data["on"] = on ? 1 : 0
	data["gasPressure"] = round(pressure)
	data["gasTemperature"] = round(temperature)
	data["minGasTemperature"] = 1
	data["maxGasTemperature"] = round(T20C+500)
	data["targetGasTemperature"] = round(set_temperature)
	data["powerSetting"] = power_setting

	var/temp_class = "good"
	if (temperature > (T0C - 20))
		temp_class = "bad"
	else if (temperature < (T0C - 20) && temperature > (T0C - 100))
		temp_class = "average"
	data["gasTemperatureClass"] = temp_class

	// update the ui if it exists, returns null if no ui is passed/found
	ui = nanomanager.try_update_ui(user, src, ui_key, ui, data, force_open)
	if (!ui)
		// the ui does not exist, so we'll create a new() one
        // for a list of parameters and their descriptions see the code docs in \code\modules\nano\nanoui.dm
		ui = new(user, src, ui_key, "freezer.tmpl", "Gas Cooling System", 440, 300)
		// when the ui is first opened this is the data it will use
		ui.set_initial_data(data)
		// open the new ui window
		ui.open()
		// auto update every Master Controller tick
		ui.set_auto_update(1)

/obj/machinery/atmospherics/unary/freezer/Topic(href, href_list)
	if (href_list["toggleStatus"])
		src.on = !src.on
		update_icon()
		update_use_power(on)
	if(href_list["temp"])
		var/amount = text2num(href_list["temp"])
		if(amount > 0)
			src.set_temperature = min(src.set_temperature+amount, 1000)
		else
			src.set_temperature = max(src.set_temperature+amount, 1)
		temperature = set_temperature
	if(href_list["setPower"]) //setting power to 0 is redundant anyways
		var/new_setting = between(0, text2num(href_list["setPower"]), 100)
		set_power_level(new_setting)

	src.add_fingerprint(usr)
	return 1

/obj/machinery/atmospherics/unary/freezer/process()
	..()
	if(stat & (NOPOWER|BROKEN) || !on)
		cooling = 0
		update_use_power(0)
		update_icon()
		return

	cooling = 1
	update_use_power(1)

	update_icon()

//upgrading parts
/obj/machinery/atmospherics/unary/freezer/RefreshParts()
	..()
	var/cap_rating = 0
	var/cap_count = 0
	var/manip_rating = 0
	var/manip_count = 0
	var/bin_rating = 0
	var/bin_count = 0

	for(var/obj/item/stock_parts/P in component_parts)
		if(istype(P, /obj/item/stock_parts/capacitor))
			cap_rating += P.rating
			cap_count++
		if(istype(P, /obj/item/stock_parts/manipulator))
			manip_rating += P.rating
			manip_count++
		if(istype(P, /obj/item/stock_parts/matter_bin))
			bin_rating += P.rating
			bin_count++
	cap_rating /= cap_count
	bin_rating /= bin_count
	manip_rating /= manip_count

	active_power_usage = initial(active_power_usage)*cap_rating			//more powerful
	heatsink_temperature = initial(heatsink_temperature)/((manip_rating+bin_rating)/2)	//more efficient
	set_power_level(power_setting)

/obj/machinery/atmospherics/unary/freezer/proc/set_power_level(var/new_power_setting)
	power_setting = new_power_setting

	var/old_power_usage = active_power_usage
	active_power_usage = max_power_usage * (power_setting/100)

	if (use_power >= 2 && old_power_usage != active_power_usage)
		force_power_update()

//dismantling code. copied from autolathe
/obj/machinery/atmospherics/unary/freezer/attackby(var/obj/item/O as obj, var/mob/user as mob)
	if(istype(O, /obj/item/tool/screwdriver))
		opened = !opened
		user << "You [opened ? "open" : "close"] the maintenance hatch of [src]."
		return

	if (opened && istype(O, /obj/item/tool/crowbar))
		dismantle()
		return

	..()

/obj/machinery/atmospherics/unary/freezer/examine(mob/user)
	..()
	if(opened)
		user << "The maintenance hatch is open."