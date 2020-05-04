
/////////////////////////////////////////////////////////////////////////////////
// ACKNOWLEDGEMENTS:  Credit to yogstation (Monster860) for the movement code. //
// I had no part in writing the movement engine, that's his work               //
/////////////////////////////////////////////////////////////////////////////////

/mob
	var/obj/structure/overmap/overmap_ship //Used for relaying movement, hotkeys etc.

/obj/structure/overmap
	name = "overmap ship"
	desc = "A space faring vessel."
	icon = 'nsv13/icons/overmap/default.dmi'
	icon_state = "default"
	density = TRUE
	dir = NORTH
	layer = ABOVE_MOB_LAYER
	animate_movement = NO_STEPS // Override the inbuilt movement engine to avoid bouncing
	req_one_access = list(ACCESS_HEADS, ACCESS_MUNITIONS, ACCESS_SEC_DOORS, ACCESS_ENGINE) //Bridge officers/heads, munitions techs / fighter pilots, security officers, engineering personnel all have access.

	anchored = FALSE
	resistance_flags = LAVA_PROOF | FIRE_PROOF | UNACIDABLE | ACID_PROOF // Overmap ships represent massive craft that don't burn

	var/sprite_size = 64 //Pixels. This represents 64x64 and allows for the bullets that you fire to align properly.
	var/area_type = null //Set the type of the desired area you want a ship to link to, assuming it's not the main player ship.
	var/impact_sound_cooldown = FALSE //Avoids infinite spamming of the ship taking damage.
	var/datum/starsystem/current_system //What starsystem are we currently in? Used for parallax.
	var/resize = 0 //Factor by which we should shrink a ship down. 0 means don't shrink it.
	var/list/docking_points = list() //Where we can land on this ship. Usually right at the edge of a z-level.
	var/last_slowprocess = 0

	var/list/linked_areas = list() //List of all areas that we control
	var/datum/gas_mixture/cabin_air //Cabin air mix used for small ships like fighters (see overmap/fighters/fighters.dm)
	var/obj/machinery/portable_atmospherics/canister/internal_tank //Internal air tank reference. Used mostly in small ships. If you want to sabotage a fighter, load a plasma tank into its cockpit :)

	// Health, armor, and damage
	max_integrity = 300 //Max health
	integrity_failure = 0
	var/armour_plates = 0 //You lose max integrity when you lose armour plates.
	var/max_armour_plates = 0
	var/list/dent_decals = list() //Ships get visibly damaged as they get shot
	var/damage_states = FALSE //Did you sprite damage states for this ship? If yes, set this to true

	//Movement Variables
	var/offset_x = 0 // like pixel_x/y but in tiles
	var/offset_y = 0
	var/angle = 0 // degrees, clockwise
	var/desired_angle = null // set by pilot moving his mouse
	var/angular_velocity = 0 // degrees per second
	var/max_angular_acceleration = 180 // in degrees per second per second
	var/speed_limit = 5 //Stops ships from going too damn fast. This can be overridden by things like fighters launching from tubes, so it's not a const.
	var/last_thrust_forward = 0
	var/last_thrust_right = 0
	var/last_rotate = 0
	var/should_open_doors = FALSE //Should we open airlocks? This is off by default because it was HORRIBLE.
	var/inertial_dampeners = TRUE

	var/user_thrust_dir = 0

	//Movement speed variables
	var/forward_maxthrust = 6
	var/backward_maxthrust = 3
	var/side_maxthrust = 1
	var/mass = MASS_SMALL //The "mass" variable will scale the movespeed according to how large the ship is.
	var/landing_gear = FALSE //Allows you to move in atmos without scraping the hell outta your ship

	var/bump_impulse = 0.6
	var/bounce_factor = 0.2 // how much of our velocity to keep on collision
	var/lateral_bounce_factor = 0.95 // mostly there to slow you down when you drive (pilot?) down a 2x2 corridor

	var/brakes = FALSE //Helps you stop the ship
	var/rcs_mode = FALSE //stops you from swivelling on mouse move
	var/move_by_mouse = TRUE //It's way easier this way, but people can choose.

	//Logging
	var/list/weapon_log = list() //Shows who did the firing thing

	// Mobs
	var/mob/living/pilot //Physical mob that's piloting us. Cameras come later
	var/mob/living/gunner //The person who fires the guns.
	var/list/gauss_gunners = list() //Anyone sitting in a gauss turret who should be able to commit pew pew against syndies.
	var/list/operators = list() //Everyone who needs their client updating when we move.
	var/list/mobs_in_ship = list() //A list of mobs which is inside the ship. This is generated by our areas.dm file as they enter / exit areas

	// Controlling equipment
	var/obj/machinery/computer/ship/helm //Relay beeping noises when we act
	var/obj/machinery/computer/ship/tactical
	var/obj/machinery/computer/ship/dradis/dradis //So that pilots can check the radar easily

	// Ship weapons
	var/list/weapons[MAX_POSSIBLE_FIREMODE][] //All of the weapons linked to us
	var/list/weapon_types[MAX_POSSIBLE_FIREMODE]

	var/fire_mode = FIRE_MODE_PDC //What gun do we want to fire? Defaults to railgun, with PDCs there for flak
	var/weapon_safety = FALSE //Like a gun safety. Entirely un-used except for fighters to stop brainlets from shooting people on the ship unintentionally :)
	var/faction = null //Used for target acquisition by AIs

	var/weapon_range = 10 //Range changes based on what weapon youre using.
	var/fire_delay = 5
	var/next_firetime = 0

	var/list/weapon_overlays = list()
	var/obj/weapon_overlay/last_fired //Last weapon overlay that fired, so we can rotate guns independently
	var/atom/last_target //Last thing we shot at, used to point the railgun at an enemy.

	var/torpedoes = 15 //Prevent infinite torp spam

	var/pdc_miss_chance = 20 //In %, how often do PDCs fire inaccurately when aiming at missiles. This is ignored for ships as theyre bigger targets.
	var/list/torpedoes_to_target = list() //Torpedoes that have been fired explicitly at us, and that the PDCs need to worry about.
	var/atom/target_lock = null
	var/can_lock = TRUE //Can we lock on to people or not
	var/lockon_time = 2 SECONDS

	// Railgun aim helper
	var/last_tracer_process = 0
	var/aiming = FALSE
	var/aiming_lastangle = 0
	var/lastangle = 0
	var/list/obj/effect/projectile/tracer/current_tracers
	var/mob/listeningTo

	var/role = NORMAL_OVERMAP

/obj/weapon_overlay
	name = "Weapon overlay"
	layer = 4
	mouse_opacity = FALSE
	layer = WALL_OBJ_LAYER
	var/angle = 0 //Debug

/obj/weapon_overlay/proc/do_animation()
	return

/obj/weapon_overlay/railgun //Railgun sits on top of the ship and swivels to face its target
	name = "Railgun"
	icon_state = "railgun"

/obj/weapon_overlay/railgun_overlay/do_animation()
	flick("railgun_charge",src)

/obj/weapon_overlay/laser
	name = "Laser cannon"
	icon = 'icons/obj/hand_of_god_structures.dmi'
	icon_state = "conduit-red"

/obj/structure/overmap/proc/add_weapon_overlay(type)
	var/path = text2path(type)
	var/obj/weapon_overlay/OL = new path
	OL.icon = icon
	OL.appearance_flags |= KEEP_APART
	OL.appearance_flags |= RESET_TRANSFORM
	vis_contents += OL
	weapon_overlays += OL
	return OL

/obj/weapon_overlay/laser/do_animation()
	flick("laser",src)

/obj/structure/overmap/Initialize()
	. = ..()
	current_tracers = list()
	GLOB.overmap_objects += src
	START_PROCESSING(SSovermap, src)

	vector_overlay = new()
	vector_overlay.appearance_flags |= KEEP_APART
	vector_overlay.appearance_flags |= RESET_TRANSFORM
	vector_overlay.icon = icon
	vis_contents += vector_overlay
	update_icon()
	max_range = initial(weapon_range)+20 //Range of the maximum possible attack (torpedo)
	find_area()
	switch(mass) //Scale speed with mass (tonnage)
		if(MASS_TINY) //Tiny ships are manned by people, so they need air.
			forward_maxthrust = 4
			backward_maxthrust = 4
			side_maxthrust = 3
			max_angular_acceleration = 180
			cabin_air = new
			cabin_air.temperature = T20C
			cabin_air.volume = 200
			cabin_air.add_gases(/datum/gas/oxygen, /datum/gas/nitrogen)
			cabin_air.gases[/datum/gas/oxygen][MOLES] = O2STANDARD*cabin_air.volume/(R_IDEAL_GAS_EQUATION*cabin_air.temperature)
			cabin_air.gases[/datum/gas/nitrogen][MOLES] = N2STANDARD*cabin_air.volume/(R_IDEAL_GAS_EQUATION*cabin_air.temperature)
			move_by_mouse = TRUE //You'll want this. Trust.

		if(MASS_SMALL)
			forward_maxthrust = 3
			backward_maxthrust = 3
			side_maxthrust = 3
			max_angular_acceleration = 110

		if(MASS_MEDIUM)
			forward_maxthrust = 2
			backward_maxthrust = 2
			side_maxthrust = 2
			max_angular_acceleration = 15

		if(MASS_LARGE)
			forward_maxthrust = 0.3
			backward_maxthrust = 0.3
			side_maxthrust = 0.75
			max_angular_acceleration = 1

		if(MASS_TITAN)
			forward_maxthrust = 0.1
			backward_maxthrust = 0.1
			side_maxthrust = 0.3
			max_angular_acceleration = 0.5

	if(role == MAIN_OVERMAP)
		name = "[station_name()]"
	current_system = SSstarsystem.find_system(src)
	addtimer(CALLBACK(src, .proc/check_armour), 20 SECONDS)

	weapon_types[FIRE_MODE_PDC] = new/datum/ship_weapon/pdc_mount
	weapon_types[FIRE_MODE_TORPEDO] = new/datum/ship_weapon/torpedo_launcher
	weapon_types[FIRE_MODE_RAILGUN] = new/datum/ship_weapon/railgun

/obj/structure/overmap/proc/add_weapon(obj/machinery/ship_weapon/weapon)
	if(!weapons[weapon.fire_mode])
		weapons[weapon.fire_mode] = list(weapon)
	else
		weapons[weapon.fire_mode] += weapon

/obj/structure/overmap/Destroy()
	QDEL_LIST(current_tracers)
	if(cabin_air)
		QDEL_NULL(cabin_air)
	. = ..()

/obj/structure/overmap/proc/find_area()
	if(role == MAIN_OVERMAP) //We're the hero ship, link us to every ss13 area.
		for(var/X in GLOB.teleportlocs) //Teleportlocs = ss13 areas that aren't special / centcom
			var/area/area = GLOB.teleportlocs[X] //Pick a station area and yeet it.
			area.linked_overmap = src


/obj/structure/overmap/proc/InterceptClickOn(mob/user, params, atom/target)
	var/list/params_list = params2list(params)
	if(user.incapacitated() || !isliving(user))
		return FALSE
	if(target == src || istype(target, /obj/screen) || (target && (target in user.GetAllContents())) || params_list["alt"] || params_list["ctrl"])
		return FALSE
	if(locate(user) in gauss_gunners) //Special case for gauss gunners here. Takes priority over them being the regular gunner.
		var/obj/machinery/ship_weapon/gauss_gun/user_gun = user.loc
		if(!istype(user_gun))
			return FALSE
		if(user_gun.safety)
			to_chat(user, "<span class='warning'>Gun safeties are engaged.</span>")
			return FALSE
		user_gun.onClick(target)
		return TRUE
	if(user != gunner)
		return FALSE
	if(tactical && prob(80))
		var/sound = pick(GLOB.computer_beeps)
		playsound(tactical, sound, 100, 1)
	if(params_list["shift"]) //Shift click to lock on to people
		start_lockon(target)
		return TRUE
	if(target_lock && mass <= MASS_TINY)
		fire(target_lock) //Fighters get an aimbot to help them out.
		return TRUE
	fire(target)
	return TRUE

/obj/structure/overmap/proc/start_lockon(atom/target)
	if(!istype(target, /obj/structure/overmap))
		return FALSE
	if(target == target_lock)
		relinquish_target_lock()
		return
	if(!can_lock)
		to_chat(gunner, "<span class='warning'>Target acquisition already in progress. Please wait.</span>")
		return
	if(target_lock)
		target_lock = null
		stop_relay(CHANNEL_IMPORTANT_SHIP_ALERT)
		if(mass > MASS_TINY)
			update_gunner_cam(src)
	can_lock = FALSE
	relay('nsv13/sound/effects/fighters/locking.ogg', message=null, loop=TRUE, channel=CHANNEL_IMPORTANT_SHIP_ALERT)
	addtimer(CALLBACK(src, .proc/finish_lockon, target), lockon_time)

/obj/structure/overmap/proc/relinquish_target_lock()
	if(!target_lock)
		return
	to_chat(gunner, "<span class='warning'>Target lock on [target_lock] cancelled. Returning manual fire control.</span>")
	update_gunner_cam(src)
	target_lock = null
	return

/obj/structure/overmap/proc/finish_lockon(atom/target)
	if(!gunner)
		return
	can_lock = TRUE
	target_lock = target
	if(mass > MASS_TINY)
		update_gunner_cam(target)
	else
		to_chat(gunner, "<span class='notice'>Target lock established. All weapons will now automatically lock on to your chosen target instead of where you specifically aim them. </span>")
	stop_relay(CHANNEL_IMPORTANT_SHIP_ALERT)
	relay('nsv13/sound/effects/fighters/locked.ogg', message=null, loop=FALSE, channel=CHANNEL_IMPORTANT_SHIP_ALERT)

/obj/structure/overmap/proc/update_gunner_cam(atom/target)
	var/mob/camera/aiEye/remote/overmap_observer/cam = gunner.remote_control
	cam.track_target(target)

/obj/structure/overmap/onMouseMove(object,location,control,params)
	if(!pilot || !pilot.client || pilot.incapacitated() || !move_by_mouse || control !="mapwindow.map" ||!can_move()) //Check pilot status, if we're meant to follow the mouse, and if theyre actually moving over a tile rather than in a menu
		return // I don't know what's going on.
	desired_angle = getMouseAngle(params, pilot)
	update_icon()

/obj/structure/overmap/proc/getMouseAngle(params, mob/M)
	var/list/params_list = params2list(params)
	var/list/sl_list = splittext(params_list["screen-loc"],",")
	if(!sl_list.len)
		return
	var/list/sl_x_list = splittext(sl_list[1], ":")
	var/list/sl_y_list = splittext(sl_list[2], ":")
	var/view_list = isnum(M.client.view) ? list("[M.client.view*2+1]","[M.client.view*2+1]") : splittext(M.client.view, "x")
	var/dx = text2num(sl_x_list[1]) + (text2num(sl_x_list[2]) / world.icon_size) - 1 - text2num(view_list[1]) / 2
	var/dy = text2num(sl_y_list[1]) + (text2num(sl_y_list[2]) / world.icon_size) - 1 - text2num(view_list[2]) / 2
	if(sqrt(dx*dx+dy*dy) > 1)
		return 90 - ATAN2(dx, dy)
	else
		return null

/obj/structure/overmap/take_damage(damage_amount, damage_type = BRUTE, damage_flag = 0, sound_effect = 1, attack_dir, armour_penetration = 0)
	..()
	if(!impact_sound_cooldown)
		var/sound = pick(GLOB.overmap_impact_sounds)
		relay(sound)
		if(damage_amount >= 15) //Flak begone
			shake_everyone(5)
		impact_sound_cooldown = TRUE
		addtimer(VARSET_CALLBACK(src, impact_sound_cooldown, FALSE), 1 SECONDS)
	update_icon()

/obj/structure/overmap/relaymove(mob/user, direction)
	if(user != pilot || pilot.incapacitated())
		return
	user_thrust_dir = direction

//relay('nsv13/sound/effects/ship/rcs.ogg')

/obj/structure/overmap/update_icon() //Adds an rcs overlay
	cut_overlays()
	apply_damage_states()
	if(last_fired) //Swivel the most recently fired gun's overlay to aim at the last thing we hit
		last_fired.icon = icon
		last_fired.setDir(get_dir(src, last_target))

	if(angle == desired_angle)
		return //No RCS needed if we're already facing where we want to go
	if(prob(20) && desired_angle)
		playsound(src, 'nsv13/sound/effects/ship/rcs.ogg', 30, 1)
	var/list/left_thrusts = list()
	left_thrusts.len = 8
	var/list/right_thrusts = list()
	right_thrusts.len = 8
	var/back_thrust = 0
	for(var/cdir in GLOB.cardinals)
		left_thrusts[cdir] = 0
		right_thrusts[cdir] = 0
	if(last_thrust_right != 0)
		var/tdir = last_thrust_right > 0 ? WEST : EAST
		left_thrusts[tdir] = abs(last_thrust_right) / side_maxthrust
		right_thrusts[tdir] = abs(last_thrust_right) / side_maxthrust
	if(last_thrust_forward > 0)
		back_thrust = last_thrust_forward / forward_maxthrust
	if(last_thrust_forward < 0)
		left_thrusts[NORTH] = -last_thrust_forward / backward_maxthrust
		right_thrusts[NORTH] = -last_thrust_forward / backward_maxthrust
	if(last_rotate != 0)
		var/frac = abs(last_rotate) / max_angular_acceleration
		for(var/cdir in GLOB.cardinals)
			if(last_rotate > 0)
				right_thrusts[cdir] += frac
			else
				left_thrusts[cdir] += frac
	for(var/cdir in GLOB.cardinals)
		var/left_thrust = left_thrusts[cdir]
		var/right_thrust = right_thrusts[cdir]
		if(left_thrust)
			add_overlay(image(icon = icon, icon_state = "rcs_left", dir = cdir))
		if(right_thrust)
			add_overlay(image(icon = icon, icon_state = "rcs_right", dir = cdir))
	if(back_thrust)
		var/image/I = image(icon = icon, icon_state = "thrust")
		add_overlay(I)

/obj/structure/overmap/proc/apply_damage_states()
	if(!damage_states)
		return
	var/progress = obj_integrity //How damaged is this shield? We examine the position of index "I" in the for loop to check which directional we want to check
	var/goal = max_integrity //How much is the max hp of the shield? This is constant through all of them
	progress = CLAMP(progress, 0, goal)
	progress = round(((progress / goal) * 100), 25)//Round it down to 20%. We now apply visual damage
	icon_state = "[initial(icon_state)]-[progress]"

/obj/structure/overmap/proc/relay(var/sound, var/message=null, loop = FALSE, channel = null) //Sends a sound + text message to the crew of a ship
	for(var/X in mobs_in_ship)
		if(ismob(X))
			var/mob/mob = X
			if(sound)
				if(channel) //Doing this forbids overlapping of sounds
					SEND_SOUND(mob, sound(sound, repeat = loop, wait = 0, volume = 100, channel = channel))
				else
					SEND_SOUND(mob, sound(sound, repeat = loop, wait = 0, volume = 100))
			if(message)
				to_chat(mob, message)

/obj/structure/overmap/proc/stop_relay(channel) //Stops all playing sounds for crewmen on N channel.
	for(var/X in mobs_in_ship)
		if(ismob(X))
			var/mob/mob = X
			mob.stop_sound_channel(channel)

/obj/structure/overmap/proc/relay_to_nearby(sound, message, ignore_self=FALSE) //Sends a sound + text message to nearby ships
	for(var/obj/structure/overmap/ship in GLOB.overmap_objects)
		if(ignore_self)
			if(ship == src)
				continue
		if(get_dist(src, ship) <= 20) //Sound doesnt really travel in space, but space combat with no kaboom is LAME
			ship.relay(sound,message)
	for(var/Y in GLOB.dead_mob_list)
		var/mob/dead/M = Y
		if(M.z == z || is_station_level(M.z)) //Ghosts get to hear explosions too for clout.
			SEND_SOUND(M,sound)

/obj/structure/overmap/proc/verb_check(require_pilot = TRUE, mob/user = null)
	if(!user)
		user = usr
	if(user != pilot)
		to_chat(user, "<span class='notice'>You can't reach the controls from here</span>")
		return FALSE
	return !user.incapacitated() && isliving(user)

/obj/structure/overmap/key_down(key, client/user)
	var/mob/themob = user.mob
	switch(key)
		if("Space")
			if(themob == pilot)
				toggle_move_mode()
			if(helm && prob(80))
				var/sound = pick(GLOB.computer_beeps)
				playsound(helm, sound, 100, 1)
			return TRUE
		if("Shift")
			if(themob == pilot)
				toggle_inertia()
			if(helm && prob(80))
				var/sound = pick(GLOB.computer_beeps)
				playsound(helm, sound, 100, 1)
			return TRUE
		if("Alt")
			if(themob == pilot)
				toggle_brakes()
			if(helm && prob(80))
				var/sound = pick(GLOB.computer_beeps)
				playsound(helm, sound, 100, 1)
			return TRUE
		if("Ctrl")
			if(themob == gunner)
				cycle_firemode()
			if(tactical && prob(80))
				var/sound = pick(GLOB.computer_beeps)
				playsound(tactical, sound, 100, 1)
			return TRUE
		if("Q" || "q")
			if(!move_by_mouse)
				desired_angle -= 15
		if("E" || "e")
			if(!move_by_mouse)
				desired_angle += 15

/obj/structure/overmap/verb/toggle_brakes()
	set name = "Toggle Handbrake"
	set category = "Ship"
	set src = usr.loc

	if(!verb_check() || !can_brake())
		return
	brakes = !brakes
	to_chat(usr, "<span class='notice'>You toggle the brakes [brakes ? "on" : "off"].</span>")

/obj/structure/overmap/verb/toggle_inertia()
	set name = "Toggle IAS"
	set category = "Ship"
	set src = usr.loc

	if(!verb_check() || !can_brake())
		return
	inertial_dampeners = !inertial_dampeners
	to_chat(usr, "<span class='notice'>Inertial assistance system [inertial_dampeners ? "ONLINE" : "OFFLINE"].</span>")

/obj/structure/overmap/proc/can_change_safeties()
	return (obj_flags & EMAGGED || !is_station_level(loc.z))

/obj/structure/overmap/verb/toggle_safety()
	set name = "Toggle Gun Safeties"
	set category = "Ship"
	set src = usr.loc

	if(!verb_check() || !can_change_safeties())
		return
	weapon_safety = !weapon_safety
	to_chat(usr, "<span class='notice'>You toggle [src]'s weapon safeties [weapon_safety ? "on" : "off"].</span>")

/obj/structure/overmap/verb/show_dradis()
	set name = "Show DRADIS"
	set category = "Ship"
	set src = usr.loc

	if(!verb_check() || !dradis)
		return
	dradis.attack_hand(usr)

/obj/structure/overmap/proc/can_brake()
	return TRUE //See fighters.dm

/obj/structure/overmap/verb/overmap_help()
	set name = "Help"
	set category = "Ship"
	set src = usr.loc

	if(!verb_check())
		return
	to_chat(usr, "<span class='warning'>=Hotkeys=</span>")
	to_chat(usr, "<span class='notice'>Use the <b>scroll wheel</b> to zoom in / out.</span>")
	to_chat(usr, "<span class='notice'>Use tab to activate hotkey mode, then:</span>")
	to_chat(usr, "<span class='notice'>Press <b>space</b> to make the ship follow your mouse (or stop following your mouse).</span>")
	to_chat(usr, "<span class='notice'>Press <b>Alt<b> to engage handbrake</span>")
	to_chat(usr, "<span class='notice'>Press <b>Ctrl<b> to cycle fire modes</span>")

/obj/structure/overmap/verb/toggle_move_mode()
	set name = "Change movement mode"
	set category = "Ship"
	set src = usr.loc

	if(!verb_check())
		return
	move_by_mouse = !move_by_mouse
	to_chat(usr, "<span class='notice'>You [move_by_mouse ? "activate" : "deactivate"] [src]'s laser guided movement system.</span>")
