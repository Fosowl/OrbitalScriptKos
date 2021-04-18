
// general purpose orbital script

clearscreen.

set KSC to latlng(-0.0972092543643722, -74.557706433623).
set deorbitBurnLNG to 170.
set flight_msg to "standbye".
set old_msg to flight_msg.
set flight_step to 0.

set radarOffset to 5.    // "alt:radar" of the vehicle when landed

set target_pitch to 90.
set target_direction to 50.
set target_apoapsis to 210000.
set target_periapsis to 160000.

lock forwardSpeed to ship:velocity:surface * ship:facing:forevector.
lock max_acc to ship:maxthrust/ship:mass.
// Physics landing
lock trueRadar to alt:radar - radarOffset.                  // Distance from the bottom of vehicle to the ground
lock g to constant:g * body:mass / body:radius^2.           // Gravitational acceleration
lock impactTime to trueRadar / abs(ship:verticalspeed).     // Time to impact with the current velocity opDist / trueRadar.                 // Hoverslam throttling setting

set M to body:mass.
set e to 2.71828.
set PR to 6371000.        //planetary radius
set Ppsl to 1.           //Planet's pressure at sea level
set CoD to .2.          // fill in for your rocket
set AtmoSH to 5000.    //Atmo scale height

// Atmospheric physics
lock Fgrav to (-1 * g * M) / (PR + altitude ) ^ 2.
lock Fdrag to .5 * CoD * velocity:surface:mag ^ 2 * mass / 125 * 1.223 * e ^ ( -1 * altitude / AtmoSH ).
lock vterm to ( ( 204.4 * g * M) / ( ( PR + altitude ) ^ 2 * CoD * Ppsl ) * e ^ ( altitude / AtmoSH ) ) ^ .5.
lock Fneed to -1 * Fgrav + ( mass  * ( vterm - velocity:surface:mag ) ) / 1 + Fdrag.
// Fneed is the force needed to close the gap (term vel - current vel) in 1 sec.
lock idealAtmThrottle to 1 - (1 - ( Fneed / maxthrust ) ).

// Burn time from rocket equation
declare function getBurnTime {
    parameter deltaV.
    parameter isp to 0.
    
    if deltaV:typename() = "Vector" {
        set deltaV to deltaV:mag.
    }
    if isp = 0 {
        set isp to _avg_isp().
    }
    
    local burnTime is -1.
    if ship:availablethrust <> 0 {
        set burnTime to ship:mass * (1 - CONSTANT:E ^ (-deltaV / isp)) / (ship:availablethrust / isp).
    }
    return burnTime.
}

// Instantaneous azimuth
declare function azimuth {
    parameter inclination.
    parameter orbit_alt.
    parameter auto_switch is false.

    local shipLat to ship:latitude.
    if abs(inclination) < abs(shipLat) {
        set inclination to shipLat.
    }

    local head is arcsin(cos(inclination) / cos(shipLat)).
    if auto_switch {
        if angleToBodyDescendingNode(ship) < angleToBodyAscendingNode(ship) {
            set head to 180 - head.
        }
    }
    else if inclination < 0 {
        set head to 180 - head.
    }
    local vOrbit is sqrt(body:mu / (orbit_alt + body:radius)).
    local vRotX is vOrbit * sin(head) - vdot(ship:velocity:orbit, heading(90, 0):vector).
    local vRotY is vOrbit * cos(head) - vdot(ship:velocity:orbit, heading(0, 0):vector).
    set head to 90 - arctan2(vRotY, vRotX).
    return mod(head + 360, 360).
}

// Average Isp calculation
declare function getAvgIsp {
    local burnEngines is list().
    list engines in burnEngines.
    local massBurnRate is 0.
    for e in burnEngines {
        if e:ignition {
            set massBurnRate to massBurnRate + e:availableThrust/(e:ISP * constant:g0).
        }
    }
    local isp is -1.
    if massBurnRate <> 0 {
        set isp to ship:availablethrust / massBurnRate.
    }
    return isp.
}

// impact coordinate, taking atmospheric drag into account
declare function getImpactCoord {
    if ADDONS:TR:AVAILABLE {
        return ADDONS:TR:IMPACTPOS.
    }
    alert("Trajectories module not available", 10).
}

// return true if trajectorie lead to ground impact
declare function willImpact {
    if ADDONS:TR:AVAILABLE {
        return ADDONS:TR:HASIMPACT.
    }
    alert("Trajectories module not available", 10).
    return false.
}

// return time till impact with ground
declare function timeTillImpact {
    if ADDONS:TR:AVAILABLE {
        return ADDONS:TR:TIMETILLIMPACT.
    }
    alert("Trajectories module not available", 10).
    return -1.
}

// check that all parameters are coherent for flight.

declare function preFlightChecklist {
    print "pre-flight checklist...".
    if target_periapsis > target_apoapsis {
        abortPhase("Incoherent periapsis").
    }
    if target_periapsis < 120000 {
        abortPhase("Target altitude too low").
    }
    wait 1.
    print "checklist complete !".
}

// countdown to 0.
declare function count_down {
    parameter start.
    print "Counting down:".
    from {local countdown is start.} until countdown = 0 step {set countdown to countdown - 1.} do {
        print "T minus : " + countdown.
        playSound().
        wait 1.
    }
}

// show some ship info to the screen
declare function showFlightData {
    parameter msg.
    clearscreen.
    print "+------------------------------------------------+".
    print "                    FLIGHT INFO                  ".
    print "                                                 ".
    print "          Apoapsis : " + round(ship:apoapsis) + " in " + round(ETA:Apoapsis).
    print "          Periapsis : " + round(ship:periapsis).
    print "          Status : " + ship:status.
    print "          Thrust : " + round(ship:maxthrust) + " kN".
    print "          Pitch : " + target_pitch.
    print "          Liquid fuel : " + round(ship:liquidfuel).
    print "          True radar : " + trueRadar.
    print "          possible impact in : " + round(impactTime).
    print "          Last message : [ " + msg + " ]".
    print "+------------------------------------------------+".
}

// show alert to screen for a few seconds.
declare function alert {
    parameter msg.
    parameter delay.
    clearscreen.
    print "+------------------------------------------------+".
    print "                    FLIGHT INFO                  ".
    print "                                                 ".
    print "     Alert : " + msg.
    print "+------------------------------------------------+".
    set V0 to GetVoice(0).
    V0:PLAY(
        NOTE("C", 0.4,  0.9)
    ).
    wait delay.
}

// play sound
declare function playSound {
    set V0 to GetVoice(0).
    V0:PLAY(
        LIST(
            NOTE("C", 0.2,  0.35), // quarter note, of which the last 0.05s is 'release'.
            NOTE("Am",  0.2,  0.35), // quarter note, of which the last 0.05s is 'release'.
            SLIDENOTE("E", "A", 0.45, 0.4) // half note that slides from C5 to F5 as it goes.
        )
    ).
}

// abort program, showing message to the screen
declare function abortPhase {
    parameter cause.
    lock throttle to 0.
    setFlightMsg("Aborted !").
    clearscreen.
    print "Aborting...".
    print "Reason : " + cause.
    playSound().
    wait 0.7.
    playSound().
    wait 30.
    shutdown.
}

// calculate DeltaV needed to make it to orbit
declare function toOrbitDeltaV {
    // https://fr.wikipedia.org/wiki/%C3%89quation_de_la_force_vive
    local v_old to sqrt(body:mu * (2/(target_apoapsis + body:radius) - 2/(ship:periapsis + target_apoapsis + 2*body:radius))).
    local v_new to sqrt(body:mu * (2/(trueRadar + body:radius) - 2/(2*trueRadar + 2*body:radius))).
// completly false value, idk why
    if v_new - v_old > 15000 {
        alert("DeltaV calculation error : " + (v_new - v_old), 7).
        return 15000.
    }
    return v_new - v_old.
}

declare function checkSeparation {
    parameter core_name.
    set PartsL to SHIP:PARTSDUBBED(core_name).
    if PartsL:length = 0 {
        return true.
    }
    return false.
}

// change current flight message, showed by "showFlightData"
declare function setFlightMsg {
    parameter msg.
    if msg = old_msg {
        return.
    }
    set old_msg to flight_msg.
    set flight_msg to msg.
    playSound().
}

// ##########################start################################

lock steering to up.
preFlightChecklist().
count_down(5).
SAS off.
takeOff().
showFlightData(flight_msg).
wait 1.
suborbitalCourse().
circularizeCourse().
orbitalAction().

// ###############################################################

// execute take off
declare function takeOff {
    setFlightMsg("lift off !").
    lock steering to up.
    lock throttle to 1.
    RCS ON.
    until ship:maxthrust > 0 {
        stage.
    }
}

// execute staging
declare function staging {
    stage.
    setFlightMsg("Staging !").
    wait 0.5.
    setFlightMsg(old_msg).
}

// check for engine flameout or lost of thrust, return true if so. 
declare function needStage {
	local need to false.
	if STAGE:READY {
		if MAXTHRUST = 0 {
			set need to true.
		} else {
			local engineList is list().
			list engines in engineList.
			for engine in engineList {
				if engine:IGNITION and engine:FLAMEOUT {
					set need to true.
					break.
				}
			}
		}
	}
	return need.
}

// set flight path to a suborbital course
declare function suborbitalCourse {
    until ship:apoapsis > target_apoapsis {
        showFlightData(flight_msg).
        if ship:apoapsis > 80000 {
            setFlightMsg("Vehicle suborbital").
        } else if forwardSpeed > 330 {
            setFlightMsg("Vehicule supersonic").
        }
        when needStage() = true then {
            staging().
            preserve.
        }
        set target_pitch to (target_apoapsis / 1000) - (ship:apoapsis / 1000).
        set target_pitch to min(target_pitch + 10, 90).
        lock steering to heading(target_direction, target_pitch).
        lock throttle to idealAtmThrottle.
        wait 0.1.
    }
}

// return the angle between desired orientation vector, and actual orientation
declare function checkPitchDeviation {
    return (vectorangle(ship:up:forevector, ship:facing:forevector) - target_pitch - 90) * -1.
}

// circularize trajectory to make an orbit
declare function circularizeCourse {
    local MdeltaV to toOrbitDeltaV.
    local reachSpace to false.
    local orbitNode to node(ETA:Apoapsis, 0, 0, MdeltaV).
    // add orbitNode to flight plan
    add orbitNode.
    local nd to nextnode.
    local burn_duration to nd:deltav:mag/max(max_acc, 1).
    lock steering to heading(target_direction, 0).
    lock throttle to 1.
    if burn_duration > ETA:Apoapsis * 1.5 {
        alert("burn time too long to make it to orbit", 10).
        alert("burn duration needed : " + round(burn_duration), 20).
    }
    setFlightMsg("Circularize orbit !").
    until ship:periapsis + 1500 > target_periapsis {
        showFlightData(flight_msg).
        if trueRadar > 95000 {
            set reachSpace to true.
        }
        if trueRadar < 95000 and reachSpace = true {
            abortPhase("failed to get into orbit").
        }
        when needStage() = true then {
            staging().
            preserve.
        }
        wait 0.1.
    }
    setFlightMsg("In orbit").
    remove orbitNode.
    lock throttle to 0.
}

// execute orbital action depending on mission
declare function orbitalAction {
    setFlightMsg("Payload Release").
    BAYS ON.
    RADIATORS ON.
    AG5 on.
    wait 5.
    clearscreen.
    print "Mission ended".
}