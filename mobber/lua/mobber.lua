----------------------------------
-- Mobber
----------------------------------

require("gmcphelper");
require("sqlitedb");
require("checkplugin");
require("stringutils");
require("tprint");
require("serialize");
require("var");

local next = next;

----------------------------------
-- Notes
----------------------------------

-- Find mobs with inconsistent mob_priority or area_mob_priority
--  This may happen when adding a mob to new rooms either 
--  via mobber addmob or mobber consider, having previously established a mob_priority or area_mob_priority.
--  The new entries will have default mob_priority and area_mob_priority of 0.

-- SELECT DISTINCT m1.mob_name, m1.zone_name, m1.mob_priority, m1.area_mob_priority
-- FROM mob m1,
--      mob m2
-- WHERE m1.mob_name = m2.mob_name
--   AND m1.zone_name = m2.zone_name
--   AND (m1.mob_priority <> m2.mob_priority OR m1.area_mob_priority <> m2.area_mob_priority)
-- ORDER BY 2,1,3,4;

-- mob_priority and area_mob_priority define order of mobs in the list.
--  mob_priority always overrides area_mob_priority, it defines that ideally, for higher priority,
--  you should always go for that mob first.
-- area_mob_priority is used in case mob_priority is tied but only for mobs within the same area.

-- note that the sorting algorithm for campaigns is different than the one for global quests,
--  mob_priority is more important for GQs. Check functions campaign.sort and globalQuest.sort.

-- room_priority defines the order of all known rooms for a given mob without changing the order
--  of the mobs in the list. Ideally the room(s) where that mob spawns have higher room_priority.
--  Especially important for GQs when mob dies often so you know exactly what room(s) it will spawn in.

-- My personal convention for room_priority: >= 50: mob spawns there. 48: mob spawns there too but mob
--  spawns in a maze mapper can't get to, so 49 will be the start of the maze and also the highest
--  room_priority for that mob.




-- My convention for room priorities:

-- 50 or higher: the mob spawns there

-- 48: the mob spawns there but for some reason it can't be the first room
--     or I don't want it to be the first room and don't
--     want to mark another as spawn room.
--     Typically in a maze:
--       I will mark 49 for start of maze so mobber takes me to the start
--       then 48 to spawn rooms! (49 is NOT spawn room)



-- My convention for mob priorities:

-- 50 or higher: there is only one of them (exception: tagor, annoying af)

-- 49: only one spawns per repop but there may be several from previous repops

-- 40: special for prosper: there's only one of them but i want to wait for someone else to kill
--        it before i go - in the case of prosper, only for those that spawn in rooms we can speedwalk to


-- 75-80: there is only one of them and it is in a PK room

-- 70-74: only one spawns per repop but there may be several from previous repops and is in a PK room

-- 25: there's lots of this mob but only in PK rooms





-- lower than 100: mobs with no priority. Might set different priorities between them in the future
------ 40 (follower of bhazat, dunoir): can't remember why 40, left as is
------ 75-99: Many spawn, but all in PK rooms (default 75)
 
-- 150-190: Only two mobs spawn 

-- 195: deadlights maze

-- 200-1000: priority mobs, only one spawns per repop
------ 210: special for prosper SH. There's only one of each and it's a PK trap but I want to delay Prosper.
------ 215: special for sohtwo Outer Space mobs. They are single spawn but they wander, all rooms same name.
------ 230-240: Only one spawns per repop but there may be 2 or more from previous repops (default 230)
------ 250-300: Default for only one mob spawns that is not particularly (default 250)
---------- 280-290: Fast to access (no agro mobs on the way) (default 290: further from entrance = 280)
------ 500-700: only one mob spawns and GQ may require to kill more than one (they should accumulate during multiple repops but spawn only once per repop) (default 500)

------ 241-245: Only one spawns per repop IN PK ROOM but there may be 2 or more from previous repops (default 243)
-------- Originally tried 5300-5400 range but better to head for one-only mob in non-PK rooms first

-- 5000-7000: priority mobs IN PK ROOMS, only one spawns per repop (exception: deadlights maze)
------ 5500-5600: Default for only one mob spawns in PK room (default 5500)
------ 6000-6100: Only one spawns and GQ may require to kill more than one (default 6000)

-- 9998: Tagor in Kearvek (This one's spawn is special...)
-- 9999: Mutant spider in Mistridge (usually 3 are required, only spawns 1, killer)

-- nottingham: a dinner guest 270 before, but fits on 500. Might revert to 270..



-- Prosper SH maze rooms able to speedwalk to from outside:
-- 28253
-- 28255
-- 28256
-- 28257

-- rooms closer to 28257: 28259, 28260, 28261, 28262, 28263, 28264, 28267
-- rooms closer to 28255: 28258
-- rooms closer to either 28253 or 28255: 28252, 28266 (picked 28253)
-- rooms closer to either 28253 or 28257: 28254, 28265 (picked 28253)



----------------------------------
-- Campaigns
----------------------------------

campaign = {};

function campaign.initialize()
	AddAlias("alias_campaign_check", "^cp (?:c|ch|che|chec|check)$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"campaign.startTargetCapture"
	);
	
	AddTriggerEx("trigger_campaign_store_target",
		"^You still have to kill \\* (?<mob_name>.+?) \\((?<location>.+?)(?<is_dead> - Dead)?\\)$",
		"", trigger_flag.RegularExpression + trigger_flag.OmitFromOutput + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"campaign.storeTarget", sendto.script
	);
	
	AddTriggerEx("trigger_campaign_inactive",
		"^You are not currently on a campaign\\.$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"campaign.endInactive", sendto.script
	);
	
	AddTriggerEx("trigger_campaign_end",
		"^(?!You)",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary + trigger_flag.OmitFromOutput, custom_colour.NoChange, 0, "",
		"campaign.endTargetCapture", sendto.script
	);
	
	AddTriggerEx("trigger_campaign_update",
		"^Congratulations, that was one of your CAMPAIGN mobs!$",
		"", trigger_flag.Enabled + trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"campaign.update", sendto.script
	);
	
	AddTriggerEx("trigger_campaign_reset",
		"^CONGRATULATIONS! You have completed your campaign\\.$",
		"", trigger_flag.Enabled + trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"campaign.reset", sendto.script
	);
	
	campaign.targets = {};
	campaign.currentTargetIndex = nil;
end

function campaign.getCurrentTargetIndex()
	return campaign.currentTargetIndex
end

function campaign.startTargetCapture()
	campaign.reset();

	EnableTrigger("trigger_campaign_store_target", true);
	EnableTrigger("trigger_campaign_inactive", true);
	
	Send("campaign check");
end

function campaign.storeTarget(name, line, wildcards)
	EnableTrigger("trigger_campaign_end", true);
	EnableTrigger("trigger_campaign_inactive", false);
	
	local target = mobTarget:new{
		name = wildcards.mob_name:lower(),
		location = wildcards.location,
		isDead = wildcards.is_dead ~= "" and true or false,
		amount = 1
	};
	
	target:initialize();
	
	table.insert(campaign.targets, target);
end

function campaign.endTargetCapture()
	EnableTrigger("trigger_campaign_store_target", false);
	EnableTrigger("trigger_campaign_end", false);

    local f = utility.gmcp.getPlayerLevel() < 190 and globalQuest.sort or campaign.sort
	table.sort(campaign.targets, f);
	display.printTargets(campaign.targets, "CP");
end

function campaign.endInactive()
	EnableTrigger("trigger_campaign_store_target", false);
	EnableTrigger("trigger_campaign_inactive", false);
	campaign.reset();
	display.printTargets(nil, "CP");
end

function campaign.update()
	local targets = campaign.targets;
	local index = campaign.currentTargetIndex;

	if (next(targets)) then
		if (index and targets[index]) then
			local target = targets[index];
			
			local playerEnemy = utility.gmcp.getPlayerEnemy();
			local playerZone = utility.gmcp.getPlayerZone();
			
			if (target.name == playerEnemy or target.rooms[1].zone_name == playerZone) then
				table.remove(targets, index);
				
				roomHandler.reset();
				display.printTargets(targets, "CP");
			else
				campaign.startTargetCapture();
			end
		else
			campaign.startTargetCapture();
		end
	end
end

function campaign.sort(mob1, mob2)
	local isMob1Dead = mob1.isDead and 1 or 0;
	local isMob2Dead = mob2.isDead and 1 or 0;
	
	local mob1Zone = mob1.rooms[1].zone_name:lower();
	local mob2Zone = mob2.rooms[1].zone_name:lower();

	local mob1AreaPriority = mob1.rooms[1].area_mob_priority or 0;
	local mob2AreaPriority = mob2.rooms[1].area_mob_priority or 0;

	local mob1Room = mob1.rooms[1].room_id;
	local mob2Room = mob2.rooms[1].room_id;

	if (isMob1Dead == isMob2Dead and mob1Zone == mob2Zone) then
		local mob1Priority = mob1.rooms[1].mob_priority or 0;
		local mob2Priority = mob2.rooms[1].mob_priority or 0;
		if mob1Priority ~= mob2Priority then
			return mob1Priority > mob2Priority;
		end
		if mob1AreaPriority ~= mob2AreaPriority then
		  return mob1AreaPriority > mob2AreaPriority;
		end
		if (mob1Room == mob2Room or mob1Room == -1 or mob2Room == -1) then
		  return mob1.name < mob2.name;
		end
		return mob1Room < mob2Room;
	end
	if (isMob1Dead == isMob2Dead) then
		return mob1Zone < mob2Zone;
	end
	return isMob1Dead < isMob2Dead;
end

function campaign.reset()
	campaign.targets = {};
	campaign.currentTargetIndex = nil;
	roomHandler.reset();
end

----------------------------------
-- Global Quests
----------------------------------

globalQuest = {};

function globalQuest.initialize()
	AddAlias("alias_global_quest_check", "^(?:qq|gq (?:c|ch|che|chec|check))$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"globalQuest.startTargetCapture"
	);

	AddTriggerEx("trigger_global_quest_store_target",
		"^You still have to kill (?<amount>\\d+) \\* (?<mob_name>.+?) \\((?<location>.+?)\\)$",
		"", trigger_flag.RegularExpression + trigger_flag.OmitFromOutput + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"globalQuest.storeTarget", sendto.script
	);

	AddTriggerEx("trigger_global_quest_end",
		"^(?!You)",
		"", trigger_flag.RegularExpression + trigger_flag.OmitFromOutput + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"globalQuest.endTargetCapture", sendto.script
	);
	
	AddTriggerEx("trigger_global_quest_inactive",
		"^(?:" ..
		"You are not (in|on) a global quest\\." ..
		"|" ..
		"The global quest has not yet started\\." ..
		"|" ..
		"No global quest is currently being run\\." ..
		")$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"globalQuest.endInactive", sendto.script
	);
	
	AddTriggerEx("trigger_global_quest_update",
		"^Congratulations, that was one of the GLOBAL QUEST mobs!$",
		"", trigger_flag.Enabled + trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"globalQuest.update", sendto.script
	);
	
	AddTriggerEx("trigger_global_quest_reset1",
		"^Global Quest: Global quest # \\d+? \\(extended\\) is now over\\.$",
		"", trigger_flag.Enabled + trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"globalQuest.reset", sendto.script
	);
	
	AddTriggerEx("trigger_global_quest_reset2",
		"^Global Quest: (?<player_name>.+?) has completed global quest # \\d+?\\.$",
		"", trigger_flag.Enabled + trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"globalQuest.reset", sendto.script
	);
	
	AddTriggerEx("trigger_global_quest_reset3",
		"^Global Quest: Global quest # \\d+? has been won by (?<player_name>.+?) \\- \\d+?(?:nd|st|rd|th) win\\.$",
		"", trigger_flag.Enabled + trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"globalQuest.reset", sendto.script
	);
	
	AddTriggerEx("trigger_global_quest_started",
		"^Global Quest: Global quest # \\d+? for levels \\d+? to \\d+? has now started\\.$",
		"", trigger_flag.Enabled + trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"globalQuest.startTargetCapture", sendto.script
	);
	
	AddTriggerEx("trigger_global_quest_alert",
		"^Global Quest: Global quest # \\d+? has been declared for levels (?<minLvl>\\d+?) to (?<maxLvl>\\d+?)\\.$",
		"", trigger_flag.Enabled + trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"globalQuest.alert", sendto.script
	);
	
	globalQuest.targets = {};
	globalQuest.currentTargetIndex = nil;
end

function globalQuest.startTargetCapture()
	globalQuest.reset();

	EnableTrigger("trigger_global_quest_store_target", true);
	EnableTrigger("trigger_global_quest_inactive", true);
	
	Execute("gquest check");
end

function globalQuest.storeTarget(name, line, wildcards)
	EnableTrigger("trigger_global_quest_end", true);
	EnableTrigger("trigger_global_quest_inactive", false);

	local target = mobTarget:new{
		name = wildcards.mob_name:lower(),
		location = wildcards.location,
		amount = tonumber(wildcards.amount);
	};
	
	target:initialize();

	table.insert(globalQuest.targets, target);
end

function globalQuest.endTargetCapture()
	EnableTrigger("trigger_global_quest_store_target", false);
	EnableTrigger("trigger_global_quest_end", false);
	
	table.sort(globalQuest.targets, globalQuest.sort);
	display.printTargets(globalQuest.targets, "GQ");
end

function globalQuest.endInactive()
	EnableTrigger("trigger_global_quest_store_target", false);
	EnableTrigger("trigger_global_quest_inactive", false);
	globalQuest.reset();
	display.printTargets(nil, "GQ");
end

function globalQuest.update()
	local targets = globalQuest.targets;
	local index = globalQuest.currentTargetIndex;
	
	if (next(globalQuest.targets)) then
		if (index and targets[index]) then
			local target = targets[index];
			
			local playerEnemy = utility.gmcp.getPlayerEnemy();
			local playerZone = utility.gmcp.getPlayerZone();
			
			if (target.name == playerEnemy or target.rooms[1].zone_name == playerZone) then
				if (target.amount > 1) then
					target.amount = target.amount - 1;
				else
					table.remove(targets, index);
				end
				
				roomHandler.reset();
				display.printTargets(targets, "GQ");
			else
				globalQuest.startTargetCapture();
			end
		else
			globalQuest.startTargetCapture();
		end
	end
end

function globalQuest.sort(mob1, mob2)
	local mob1Priority = mob1.rooms[1].mob_priority or 0;
	local mob2Priority = mob2.rooms[1].mob_priority or 0;

	local mob1Zone = mob1.rooms[1].zone_name:lower();
	local mob2Zone = mob2.rooms[1].zone_name:lower();

	local mob1AreaPriority = mob1.rooms[1].area_mob_priority or 0;
	local mob2AreaPriority = mob2.rooms[1].area_mob_priority or 0;

	local mob1Room = mob1.rooms[1].room_id;
	local mob2Room = mob2.rooms[1].room_id;

	if (mob1Priority == mob2Priority) then
		if (mob1Zone ~= mob2Zone) then
			if mob1Priority == 0 then
				return mob1Zone < mob2Zone;
			end
			--return mob1Zone > mob2Zone;
			return mob1Zone < mob2Zone;
		end
		if (mob1AreaPriority ~= mob2AreaPriority) then
		  return mob1AreaPriority > mob2AreaPriority;
		end
		if (mob1Room == mob2Room or mob1Room == -1 or mob2Room == -1) then
		  return mob1.name < mob2.name;
		end
		return mob1Room < mob2Room;
	else
		return mob1Priority > mob2Priority;
	end
end

function globalQuest.reset(name, line, wildcards)
	local playerName = utility.gmcp.getPlayerName();

	if (wildcards and wildcards.player_name and wildcards.player_name ~= playerName) then
		return;
	end
	
	globalQuest.targets = {};
	globalQuest.currentTargetIndex = nil;
	roomHandler.reset();
end

function globalQuest.alert(name, line, wildcards)
	local minLvl = tonumber(wildcards.minLvl);
	local maxLvl = tonumber(wildcards.maxLvl);
	local playerLevel = utility.gmcp.getPlayerLevel();
	
	if (not quest.isMuted and playerLevel >= minLvl and playerLevel <= maxLvl) then
		Sound(GetInfo(66) .. "\\sounds\\global_quest.wav");
	end
end

----------------------------------
-- Room Handler
----------------------------------

roomHandler = {};

function roomHandler.initialize()
	AddAlias("alias_room_handler_run_to_area", "^xrt (?<location>[a-zA-Z\\d ]+?)$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"roomHandler.runToArea"
	);
	
	AddAlias("alias_room_handler_select_cp_target", "^x?cp (?<index>\\d+)$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"roomHandler.selectCampaignTarget"
	);

	AddAlias("alias_room_handler_select_gq_target", "^x?[gq]q (?<index>\\d+)$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"roomHandler.selectGlobalQuestTarget"
	);

	AddAlias("alias_room_handler_select_room", "^x?go(?: (?<index>\\d+?))?$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"roomHandler.selectRoom"
	);
	
	AddAlias("alias_room_handler_select_next_room", "^x?(?:next|nex|nx)$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"roomHandler.selectNextRoom"
	);
	
	AddAlias("alias_room_handler_select_previous_room", "^x?(?:prev|pre|pr|nx-)$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"roomHandler.selectPreviousRoom"
	);
	
	roomHandler.rooms = {};
	roomHandler.index = nil;
end

function roomHandler.runToArea(name, line, wildcards)
	local location = wildcards.location;
	
	local sql = [[
		SELECT room_id
		FROM area
		WHERE zone_name = %s
		LIMIT 1;
	]];
	
	sql = sql:format(fixsql(location));
	
	local room = database.mobber:gettable(sql);
	
	if (not next(room)) then
		sql = [[
			SELECT room_id
			FROM area
			WHERE zone_name LIKE %s
			OR area_name LIKE %s
			LIMIT 1;
		]];
		
		local wildcardLocation = fixsql(location, "both");
		
		sql = sql:format(wildcardLocation, wildcardLocation);
		
		room = database.mobber:gettable(sql);
	end
	
	if (next(room)) then
		Execute(igo.go .. room[1].room_id);
	else
		local AYLOR_ROOM_ID = 32418;
		Execute(igo.go .. AYLOR_ROOM_ID .. ";runto " .. location);
	end
end

function mobberWindowRedraw()
	local windowId = "22c840004727cceeb20f4fee"
	if IsPluginInstalled(windowId) and GetPluginInfo(windowId, 17) then
		CallPlugin(windowId, "mobberMw.drawQuest")
	end
end

function roomHandler.selectCampaignTarget(name, line, wildcards)
	local targets = campaign.targets;
	
	if (next(targets)) then
		local index = tonumber(wildcards.index);
		local target = targets[index];
		
		if (target) then
			campaign.currentTargetIndex = index;
			mobberWindowRedraw()
			roomHandler.processTarget(target)
		else
			utility.print("That campaign target does not exist!");
		end
	else
		utility.print("No campaign targets processed!");
	end
end

function roomHandler.selectGlobalQuestTarget(name, line, wildcards)
	local targets = globalQuest.targets;
	
	if (next(targets)) then
		local index = tonumber(wildcards.index);
		local target = targets[index];
		
		if (target) then
			globalQuest.currentTargetIndex = index;
			
			roomHandler.processTarget(target)
		else
			utility.print("That global quest target does not exist!");
		end
	else
		utility.print("No global quest targets processed!");
	end
end

function roomHandler.showNotes(rooms)
	local sql = [[
		SELECT room_id, room_name, notes
		FROM room
		WHERE room_id = %d AND notes IS NOT NULL;
	]];
		  
	sql = sql:format(rooms[1].room_id);
	
	local notes = database.mobber:gettable(sql);
	
	if (next(notes)) then
		display.printNotes(notes);
		return true;
	end
	return false;
end

function roomHandler.hasPath(room)

    if igo.enabled then
      -- IGO implementation
      local igoId = "c34c487f941b4f483fae2867";
      local dst = tonumber(room) or tonumber(room.room_id);
      local result, path, steps = CallPlugin(igoId, "findpath", dst);
      -- check comment below, same applies for IGO
      return result == error_code.eErrorCallingPluginRoutine
    end

    -- Original implementation
	local gmcpMapper = "b6eae87ccedd84f510b74714"
	local src = utility.gmcp.getPlayerRoomId();
	local dst = tonumber(room) or tonumber(room.room_id);
	local result, path = CallPlugin(gmcpMapper, "findpath", src, dst);

	-- If findpath does find a path it can't return it through CallPlugin because it is a table
	--  the return if path found will actually be: result = errorCode (30040), path = errorDescription
	-- However, if path was not found it will return (0, nil). error_code.eErrorCallingPluginRoutine == 30040
	return result == error_code.eErrorCallingPluginRoutine;
	-- return path ~= nil;
end

function roomHandler.goToRoomOrArea(room)

	if roomHandler.hasPath(room) then
	  utility.runToRoomId(room.room_id);
	  quickScan.scan("", "", {mob_name = ""});
	  return
	end

	if room.zone_name == utility.gmcp.getPlayerZone() then
	  local showed = roomHandler.showNotes({room});
	  if not showed then
	    utility.print(string.format("Can't go to room %s.", room.room_id));
	  end
	  return;
	end

	roomHandler.runToArea(nil, nil, { location = room.zone_name });
end

function roomHandler.processTarget(target)
	utility.setTarget(target.name, target.keyword);
			
	roomHandler.rooms = {};

	if (target.lookupType == "mobMatchInLvlRange" or target.lookupType == "roomMatchInLvlRange" 
		or target.lookupType == "mobMatchOutOfLvlRange" or target.lookupType == "roomMatchOutOfLvlRange") then
		roomHandler.rooms = target.rooms;
		display.printRooms(roomHandler.rooms);
		roomHandler.goToRoomOrArea(target.rooms[1])

	elseif (target.lookupType == "areaMatch") then
		local zoneName = target.rooms[1].zone_name;
		local playerZone = utility.gmcp.getPlayerZone();
		
		if (playerZone ~= zoneName) then
			local roomId = target.rooms[1].room_id;
			
			if (utility.runToRoomId(roomId)) then
				Execute("ht " .. target.keyword);
			end
		else
			Execute("ht " .. target.keyword);
		end
	else
		local AYLOR_RECALL_ROOM_ID = 32418;
		
		if (utility.runToRoomId(AYLOR_RECALL_ROOM_ID)) then
			local zoneName = target.rooms[1].zone_name;
			
			Execute("runto " .. zoneName);
		end
	end
end

function roomHandler.selectRoom(name, line, wildcards)
	local rooms = roomHandler.rooms;

	if (next(rooms)) then
		local index = tonumber(wildcards.index) or 1;
		local room = rooms[index];
		
		if (room) then
			roomHandler.goToRoomOrArea(room);
			roomHandler.index = index;
		else
			utility.print("No more rooms!");
		end
	else
		utility.print("No room list exists.");
	end
end

function roomHandler.selectNextRoom()
	local rooms = roomHandler.rooms;
	
	if (next(rooms)) then
		local index = roomHandler.index or 1;
		local room = rooms[index];
		
		if (room and index < #rooms) then
			if (room.room_id == utility.gmcp.getPlayerRoomId()) then
				index = index + 1;
				roomHandler.index = index;
				room = rooms[index];
			end
			
			utility.runToRoomId(room.room_id);
			quickScan.scan("", "", {mob_name = ""});
		else
			utility.print("No more rooms!");
		end
	else
		utility.print("No room list exists.");
	end
end

function roomHandler.selectPreviousRoom()
	local rooms = roomHandler.rooms;
	
	if (next(rooms)) then
		local index = roomHandler.index or 1;
		local room = rooms[index];
		
		if (room and index > 1 and index <= #rooms) then
			if (room.room_id == utility.gmcp.getPlayerRoomId()) then
				index = index - 1;
				roomHandler.index = index;
				room = rooms[index];
			end
			
			utility.runToRoomId(room.room_id);
			quickScan.scan("", "", {mob_name = ""});
		else
			utility.print("No more rooms!");
		end
	else
		utility.print("No room list exists.");
	end
end

function roomHandler.reset()
	roomHandler.index = nil;
	roomHandler.rooms = {};
end

----------------------------------
-- Mob Search
----------------------------------

mobSearch = {};

function mobSearch.initialize()
	AddAlias("alias_mob_search_find", "^(?:mf|fm)(?: (?<mob_name>.+?)(?: (?:zone|area) (?<zone_name>.+?))?)?$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"mobSearch.findMob"
	);
	
	AddAlias("alias_mob_search_find_all", "^(?:mfa|fma) (?<mob_name>.+?)(?: (?:lvl|level) (?<min_level>\\d+?) (?<max_level>\\d+?))?$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"mobSearch.findAllMob"
	);
	
	mobSearch.MIN_LVL = 1;
	mobSearch.MAX_LVL = 220;
end

function mobSearch.findMob(name, line, wildcards)
	local mobName = wildcards.mob_name ~= "" and wildcards.mob_name or "%";
	local zoneName = wildcards.zone_name ~= "" and wildcards.zone_name or utility.gmcp.getPlayerZone();
	
	roomHandler.reset();
	
	if (zoneName ~= "") then
		local sql;
		
		if (mobName ~= "%") then
			sql = [[
				SELECT *
				FROM mob
				WHERE zone_name = %s
				AND mob_name LIKE %s
				ORDER BY mob_name ASC, room_id ASC;
			]];
		else
			sql = [[
				SELECT DISTINCT mob.mob_name, COUNT(mob_name) AS room_count, mob.mob_priority, mob.zone_name
				FROM mob
				INNER JOIN area ON mob.zone_name = area.zone_name
				WHERE mob.zone_name = %s
				AND mob.mob_name LIKE %s
				GROUP BY mob_name, mob.zone_name
				ORDER BY mob.mob_name;
			]];
			
		end
		
		sql = sql:format(fixsql(zoneName), fixsql(mobName, "both"));
		
		local results = database.mobber:gettable(sql);
		
		utility.setTarget(mobName, mobName);
		
		if (next(results)) then
			if (mobName ~= "%") then
				roomHandler.rooms = results;
				display.printMobRooms(roomHandler.rooms);
			else
				display.printMobs(results);
			end
		else
			utility.print("Found 0 mobs in " .. zoneName .. " with the name: " .. mobName, "yellow");
		end
	else
		utility.print("GMCP error retrieving zone.");
	end
end

function mobSearch.findAllMob(name, line, wildcards)
	local mobName = wildcards.mob_name;
	
	local minLvl = tonumber(wildcards.min_level) or mobSearch.MIN_LVL;
	local maxLvl = tonumber(wildcards.max_level) or mobSearch.MAX_LVL;
	
	roomHandler.reset();
	
	local sql = [[
		SELECT DISTINCT mob.mob_name, COUNT(mob_name) AS room_count, mob.mob_priority, mob.zone_name
		FROM mob
		INNER JOIN area ON mob.zone_name = area.zone_name
		WHERE area.min_lvl >= %d
		AND area.max_lvl <= %d
		AND mob.mob_name LIKE %s
		GROUP BY mob_name, mob.zone_name
		ORDER BY mob.zone_name;
	]];
		  
	sql = sql:format(minLvl, maxLvl, fixsql(mobName, "both"));
	
	local mobs = database.mobber:gettable(sql);
	
	utility.setTarget(mobName, mobName);
	
	if (next(mobs)) then
		display.printMobs(mobs);
	else
		utility.print("Found 0 mobs (L" .. minLvl .. "-" .. maxLvl .. ") with the name: " .. mobName, "yellow");
	end
end

----------------------------------
-- Room Search
----------------------------------

roomSearch = {};

function roomSearch.initialize()
	AddAlias("alias_room_search_zone", "^(?:rf|xm)(?: (?<room_name>.+?)(?: (?:zone|area) (?<zone_name>.+?))?)?$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"roomSearch.searchZone"
	);
	
	AddAlias("alias_room_search_all", "^(?:rfa|xma) (?<room_name>.+?)(?: (?:lvl|level) (?<min_level>\\d+?) (?<max_level>\\d+?))?$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"roomSearch.searchAll"
	);
	
	roomSearch.MIN_LVL = 1;
	roomSearch.MAX_LVL = 220;
end

function roomSearch.searchZone(name, line, wildcards)
	local roomName = wildcards.room_name;
	local zoneName = wildcards.zone_name ~= "" and wildcards.zone_name or utility.gmcp.getPlayerZone();
	
	roomHandler.reset();
	
	if (zoneName ~= "") then
		local sql = [[
			SELECT room_name, room_id, zone_name
			FROM room
			WHERE zone_name = %s
			AND room_name LIKE %s
			ORDER BY room_id ASC;
		]];
		
		sql = sql:format(fixsql(zoneName), fixsql(roomName, "both"));
		
		local rooms = database.mobber:gettable(sql);
		
		if (next(rooms)) then
			roomHandler.rooms = rooms;
			display.printRooms(rooms, 200);
		else
			utility.print("Found 0 rooms in " .. zoneName .. " with the name: " .. roomName, "yellow");
		end
	else
		utility.print("GMCP error retrieving zone.");
	end
end

function roomSearch.searchAll(name, line, wildcards)
	local roomName = wildcards.room_name;
	
	local minLvl = tonumber(wildcards.min_level) or roomSearch.MIN_LVL;
	local maxLvl = tonumber(wildcards.max_level) or roomSearch.MAX_LVL;
	
	roomHandler.reset();
	
	local sql = [[
		SELECT room.room_name, room.room_id, room.zone_name
		FROM room
		INNER JOIN area ON room.zone_name = area.zone_name
		WHERE area.min_lvl >= %d
		AND area.max_lvl <= %d
		AND room.room_name LIKE %s
		ORDER BY room.zone_name ASC, room.room_id ASC;
	]];
	
	sql = sql:format(minLvl, maxLvl, fixsql(roomName, "both"));
	
	local rooms = database.mobber:gettable(sql);
	
	if (next(rooms)) then
		roomHandler.rooms = rooms;
		display.printRooms(rooms, 200);
	else
		utility.print("Found 0 rooms (L" .. minLvl .. "-" .. maxLvl .. ") with the name: " .. roomName, "yellow");
	end
end

----------------------------------
-- Display
----------------------------------

display = {};

function display.printTargets(targets, questType)
	targets = targets or {};

	local msg = questType == "CP" and 420 or 69;
	BroadcastPlugin(msg, serialize.save_simple(targets));

	ColourNote(pluginPalette.border, "", string.format("\r\n+%s+", string.rep("-", 49)));
	
	ColourNote(
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-19s%s%-19s", " ", "Target List", " "),
		pluginPalette.border, "", "|"
	);
	
	ColourNote(pluginPalette.border, "", string.format("+%s+", string.rep("-", 49)));
	
	if (next(targets)) then
		for i = 1, #targets do
			local target = targets[i];

			local mobName = toPascalCase(target.name);
			local zoneName = toPascalCase(target.rooms[1].zone_name);
			local amount = target.amount > 1 and target.amount or " ";
			local lookupType = target.lookupType;
			
			local color;

			if (target.isDead) then
				color = pluginPalette.deadMob;
			elseif (lookupType == "mobMatchInLvlRange" or lookupType == "roomMatchInLvlRange") then
				color = pluginPalette.foundMobRoom;
			elseif (lookupType == "areaMatch") then
				color = pluginPalette.foundArea;
			elseif (lookupType == "mobMatchOutOfLvlRange" or lookupType == "roomMatchOutOfLvlRange") then
				color = pluginPalette.roomOrMobAll;
			else
				color = pluginPalette.missingAreaRoom;
			end
			
			local idxLine = string.format("%3.3s", i .. ".");
			local mobLine;
			local zoneLine;
			
			if (color ~= pluginPalette.missingAreaRoom) then
				mobLine = string.format(" %-29.28s%s ", mobName, amount);
				zoneLine = string.format(" %-13.12s", "("..zoneName..") ");
			else
				mobLine = string.format(" %-31.30s%14s", zoneName, "Missing ");
				zoneLine = "";
			end

			local action = questType == "CP" and "xcp" or "xgq";

			ColourTell(pluginPalette.border, "", "|", pluginPalette.indexNumbering, "", idxLine);
			Hyperlink(action .. " " .. i, mobLine .. zoneLine, mobName .. " (" .. zoneName .. ")", color, "", false, true);
			ColourTell(pluginPalette.border, "", "|\r\n");
-- used this during redo to know which mobs to map
--if target.rooms and target.rooms[1] and target.rooms[1].room_priority == 0 then CallPlugin("b555825a4a5700c35fa80780", "storeFromOutside", "no room priority: @Y" .. target.name) end
		end
	else
		ColourNote(
			pluginPalette.border, "", "|",
			pluginPalette.header, "", string.format("%-17s%s%-17s", " ", "No " .. questType .. " Available", " "),
			pluginPalette.border, "", "|"
		);
	end
	
	ColourNote(pluginPalette.border, "", string.format("+%s+", string.rep("-", 49)));
end

function display.printNotes(rooms)
	-- total noteLength + roomNameLength + 5 <= 84
	local noteLength = 64;
	local roomNameLength = 15

	local hasNotes = false
	for k,v in ipairs(rooms) do
		if v.notes then
			hasNotes = true;
			break;
		end
	end
	if not hasNotes then
		return;
	end

	ColourNote(
		pluginPalette.border, "", 
		string.format(
			"+%s+%s+%s",
			string.rep("-", 5),
			string.rep("-", roomNameLength),
			string.rep("-", noteLength)
		)
	);
	
	ColourNote(
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-5s", "Rm Id"),
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-" .. roomNameLength .. "s", "Room name"),
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-" .. noteLength .. "s", "Notes"),
		pluginPalette.border, "", "|"
	);
	
	ColourNote(
		pluginPalette.border, "", 
		string.format(
			"+%s+%s+%s",
			string.rep("-", 5),
			string.rep("-", roomNameLength),
			string.rep("-", noteLength)
		)
	);
	
	for k,v in ipairs(rooms) do
		-- TODO split note here to print multiline notes
		if v.notes then
			ColourNote(
				pluginPalette.border, "", "|",
				"orange", "", string.format("%-5.5s", v.room_id),
				pluginPalette.border, "", "|",
				"paleturquoise", "", string.format("%-" .. roomNameLength .. "." .. roomNameLength .. "s", v.room_name),
				pluginPalette.border, "", "|",
				"yellow", "", string.format("%-" .. noteLength .. "." .. noteLength .. "s", v.notes),
				pluginPalette.border, "", "|"
			);
		end
	end

	ColourNote(
		pluginPalette.border, "", 
		string.format(
			"+%s+%s+%s+",
			string.rep("-", 5),
			string.rep("-", roomNameLength),
			string.rep("-", noteLength)
		)
	);
end

function display.printRooms(rooms, limit)
	ColourNote(pluginPalette.border, "", string.format("\r\n+%s+", string.rep("-", 48)));
	
	ColourNote(
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-19s%s%-19s", " ", "Rooms List", " "),
		pluginPalette.border, "", "|"
	);
	
	ColourNote(pluginPalette.border, "", string.format("+%s+", string.rep("-", 48)));
	
	local limit = limit or 5;
	local skipped = 0;
	if (next(rooms)) then
		local zone;
		
		for i = 1, #rooms do

			local spawnRoomColor = "lime";
			local rPriority = rooms[i].room_priority or 0; -- On qw, might not have seen mob in that room
			local isSpawnRoom = rPriority >= 50 or rPriority == 48; -- refer to notes section for magic numbers

            -- print at most <limit> rooms unless they are spawn rooms
            if i > limit and not isSpawnRoom then
            	skipped = #rooms - i + 1;
            	break;
            end

			local zoneName = toPascalCase(rooms[i].zone_name);
			local roomName = toPascalCase(rooms[i].room_name);
			local roomId = rooms[i].room_id;
		
			if (zone ~= zoneName) then
				zone = zoneName;
				
				if (i ~= 1) then
					ColourNote(pluginPalette.border, "", string.format("+%s+", string.rep("-", 48)));
				end
				
				ColourNote(
					pluginPalette.border, "", "|",
					"silver", "", ">> ",
					"darkgray", "", string.format("%-45s", zoneName),
					pluginPalette.border, "", "|"
				);
			end

			ColourTell(pluginPalette.border, "", "|", pluginPalette.indexNumbering, "", string.format("%3.3s", i .. "."));
			Hyperlink(igo.go .. roomId, string.format(" %-36.35s", roomName), roomName, (isSpawnRoom and spawnRoomColor or pluginPalette.rooms), "", false, true);
			Hyperlink(igo.go .. roomId, string.format(" %-7.7s", "("..roomId..")"), roomName, (isSpawnRoom and spawnRoomColor or "silver"), "", false, true);
			ColourTell(pluginPalette.border, "", "|\r\n");
		end
	else
		ColourNote(
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-17s%s%-17s", " ", "No Rooms Found", " "),
		pluginPalette.border, "", "|"
		);
	end
	
	ColourNote(pluginPalette.border, "", string.format("+%s+", string.rep("-", 48)));

	-- if skipped > 0 then
	--	utility.print(string.format("Skipped listing %d rooms.", skipped), "silver");
	-- end
end

function display.printMobs(mobs)
	ColourNote(
		pluginPalette.border, "", 
		string.format(
			"+%s+%s+%s+%s+",
			string.rep("-", 10),
			string.rep("-", 26),
			string.rep("-", 2),
			string.rep("-", 2)
		)
	);
	
	ColourNote(
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-10s", "Zone"),
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format(" %-25s", "Mob Name"),
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-2s", "Rm"),
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-2s", "Pr"),
		pluginPalette.border, "", "|"
	);
	
	ColourNote(
		pluginPalette.border, "", 
		string.format(
			"+%s+%s+%s+%s+",
			string.rep("-", 10),
			string.rep("-", 26),
			string.rep("-", 2),
			string.rep("-", 2)
		)
	);
	
	local zone;
	
	for k,v in ipairs(mobs) do
		ColourTell(pluginPalette.border, "", "|");
	
		Hyperlink("xrt " .. v.zone_name, string.format("%-10.10s", v.zone_name), "Goto: " .. v.zone_name, "teal", "", false, true);
		
		ColourTell(pluginPalette.border, "", "|");
		
		Hyperlink("mf " .. v.mob_name .. " zone " .. v.zone_name, string.format(" %-25.24s", v.mob_name), "Show rooms for: " .. v.mob_name, "paleturquoise", "", false, true);
		
		ColourTell(
			pluginPalette.border, "", "|",
			"yellow", "", string.format("%-2.2s", v.room_count),
			pluginPalette.border, "", "|",
			"green", "", string.format("%-2.2s", v.mob_priority),
			pluginPalette.border, "", "|\r\n"
		);
	end
	
	ColourNote(
		pluginPalette.border, "", 
		string.format(
			"+%s+%s+%s+%s+",
			string.rep("-", 10),
			string.rep("-", 26),
			string.rep("-", 2),
			string.rep("-", 2)
		)
	);
	
	utility.print("Click a mob to see its rooms.", "silver");
end

function display.printMobRooms(mobRooms)
	ColourNote(
		pluginPalette.border, "", 
		string.format(
			"+%s+%s+%s+%s+%s+",
			string.rep("-", 24),
			string.rep("-", 29),
			string.rep("-", 2),
			string.rep("-", 5),
			string.rep("-", 10)
		)
	);
	
	ColourNote(
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-24s", "Mob Name"),
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format(" %-28s", "Room Name"),
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-2s", "Pr"),
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-5s", "Room"),
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-10s", "Zone"),
		pluginPalette.border, "", "|"
	);
	
	ColourNote(
		pluginPalette.border, "", 
		string.format(
			"+%s+%s+%s+%s+%s+",
			string.rep("-", 24),
			string.rep("-", 29),
			string.rep("-", 2),
			string.rep("-", 5),
			string.rep("-", 10)
		)
	);
	
	local zone;
	
	for k,v in ipairs(mobRooms) do
		ColourTell(pluginPalette.border, "", "|", pluginPalette.indexNumbering, "", string.format("%-3.3s", k .. "."));
		
		Hyperlink(igo.go .. v.room_id, string.format(" %-20.19s", v.mob_name), "Goto: " .. v.mob_name, "lightblue", "", false, true);
		
		ColourTell(pluginPalette.border, "", "|");
		
		Hyperlink(igo.go .. v.room_id, string.format(" %-28.27s", v.room_name), "Goto: " .. v.room_name, "silver", "", false, true);
	
		ColourTell(
			pluginPalette.border, "", "|",
			"green", "", string.format("%-2.2s", v.mob_priority),
			pluginPalette.border, "", "|"
		);
		
		Hyperlink(igo.go .. v.room_id, string.format("%-5.5s", v.room_id), "Goto: " .. v.room_id, "orange", "", false, true);
		
		ColourTell(pluginPalette.border, "", "|");
		
		Hyperlink("xrt " .. v.zone_name, string.format("%-10.10s", v.zone_name), "Goto: " .. v.zone_name, "teal", "", false, true);
		
		ColourTell(
			pluginPalette.border, "", "|\r\n"
		);
	end
	
	ColourNote(
		pluginPalette.border, "", 
		string.format(
			"+%s+%s+%s+%s+%s+",
			string.rep("-", 24),
			string.rep("-", 29),
			string.rep("-", 2),
			string.rep("-", 5),
			string.rep("-", 10)
		)
	);
	
	utility.print("Click a mob to go to its room.", "silver");
end

function display.printAreas(areas)
	ColourNote(
		pluginPalette.border, "", 
		string.format(
			"+%s+%s+%s+%s+%s+%s+%s+",
			string.rep("-", 10),
			string.rep("-", 34),
			string.rep("-", 3),
			string.rep("-", 3),
			string.rep("-", 5),
			string.rep("-", 4),
			string.rep("-", 3)
		)
	);
	
	ColourNote(
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-10s", "Zone Name"),
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-34s", "Area Name"),
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-3s", "Min"),
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-3s", "Max"),
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-5s", "Rm Id"),
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-4s", "#Rm"),
		pluginPalette.border, "", "|",
		pluginPalette.header, "", string.format("%-3s", "#Mb"),
		pluginPalette.border, "", "|"
	);
	
	ColourNote(
		pluginPalette.border, "", 
		string.format(
			"+%s+%s+%s+%s+%s+%s+%s+",
			string.rep("-", 10),
			string.rep("-", 34),
			string.rep("-", 3),
			string.rep("-", 3),
			string.rep("-", 5),
			string.rep("-", 4),
			string.rep("-", 3)
		)
	);
	
	for k,v in ipairs(areas) do
		ColourNote(
			pluginPalette.border, "", "|",
			"teal", "", string.format("%-10.10s", v.zone_name),
			pluginPalette.border, "", "|",
			"white", "", string.format("%-34.34s", v.area_name),
			pluginPalette.border, "", "|",
			"darkgray", "", string.format("%-3.3s", v.min_lvl),
			pluginPalette.border, "", "|",
			"darkgray", "", string.format("%-3.3s", v.max_lvl),
			pluginPalette.border, "", "|",
			"orange", "", string.format("%-5.5s", v.room_id),
			pluginPalette.border, "", "|",
			"yellow", "", string.format("%-4.4s", v.room_count),
			pluginPalette.border, "", "|",
			"green", "", string.format("%-3.3s", v.mob_count),
			pluginPalette.border, "", "|"
		);
	end

	ColourNote(
		pluginPalette.border, "", 
		string.format(
			"+%s+%s+%s+%s+%s+%s+%s+",
			string.rep("-", 10),
			string.rep("-", 34),
			string.rep("-", 3),
			string.rep("-", 3),
			string.rep("-", 5),
			string.rep("-", 4),
			string.rep("-", 3)
		)
	);
	
	ColourNote("yellow", "", "* Excludes nomap rooms\r\n", "green", "", "* Unique mob names");
end

----------------------------------
-- Quick Scan
----------------------------------

quickScan = {};

function quickScan.initialize()
	AddAlias("alias_quick_scan", "^qs(?: (?<mob_name>.+?))?$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"quickScan.scan"
	);
	
	AddTriggerEx("trigger_quick_scan_tag_start",
		"^\\{scan\\}$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"quickScan.enableCapture", sendto.script, 100
	);

	AddTriggerEx("trigger_quick_scan_capture",
		"^\\s{5}-\\s(?:\\([A-Za-z ]+\\)\\s?)*(?<mob_name>.+?)$",
		"", trigger_flag.RegularExpression + trigger_flag.OmitFromOutput + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"quickScan.highlight", sendto.script, 100
	);
	
	AddTriggerEx("trigger_quick_scan_tag_end",
		"^\\{\\/scan\\}$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"quickScan.disableCapture", sendto.script, 100
	);

	AddTriggerEx("trigger_quick_scan_tag_start_gag",
		"^\\{scan\\}$",
		"", trigger_flag.Enabled + trigger_flag.RegularExpression + trigger_flag.KeepEvaluating + trigger_flag.OmitFromOutput + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"", sendto.script, 99
	);
	
	AddTriggerEx("trigger_quick_scan_tag_end_gag",
		"^\\{\\/scan\\}$",
		"", trigger_flag.Enabled + trigger_flag.RegularExpression + trigger_flag.KeepEvaluating + trigger_flag.OmitFromOutput + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"", sendto.script, 99
	);
end

function quickScan.scan(name, line, wildcards)
	if (wildcards.mob_name ~= "") then
		utility.targetName = wildcards.mob_name;
		utility.targetKeyword = utility.getMobKeyword(wildcards.mob_name);
		EnableTrigger("trigger_quick_scan_tag_start", true);
		Execute(igo.scan);
	else
		local target = utility.targetKeyword;
		
		if (target) then
			EnableTrigger("trigger_quick_scan_tag_start", true);
			Execute(igo.scan .. " " .. target);
		else
			Execute(igo.scan);
		end
	end
end

function quickScan.enableCapture()
	EnableTrigger("trigger_quick_scan_tag_start", false);
	EnableTrigger("trigger_quick_scan_capture", true);
	EnableTrigger("trigger_quick_scan_tag_end", true);
end

function quickScan.highlight(name, line, wildcards, styles)
	local mobName = wildcards.mob_name:lower();
	local target = utility.targetName:lower();
	
	if (mobName == target) then
		ColourTell(pluginPalette.highlightTargetParentheses, "", "(");
		ColourTell(pluginPalette.highlightTarget, "", "TARGET");
		ColourTell(pluginPalette.highlightTargetParentheses, "", ") ");
		ColourTell("white", "", toPascalCase(target) .. "\r\n");
		PlaySound (0, "quest_target_found.wav", false, 0, 0)
	else
		for k,v in ipairs(styles) do
			ColourTell(RGBColourToName(v.textcolour), v.backcolour, v.text);
		end
		
		print();
	end
end

function quickScan.disableCapture()
	EnableTrigger("trigger_quick_scan_capture", false);
	EnableTrigger("trigger_quick_scan_tag_end", false);
end

----------------------------------
-- Quick Where
----------------------------------

quickWhere = {};

function quickWhere.initialize()
	AddAlias("alias_quick_where", "^qw(?: ((?<index>\\d+?)\\.)?(?<target_name>.+?))?$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"quickWhere.doWhere"
	);

	AddTriggerEx("trigger_quick_where",
		--"^(?<target_name>.{30}) (?<room_name>.+?)$",
		"^(?<target_name>(?!You entered:).{30}) (?<room_name>.+?)$", -- support echocommands
		"", trigger_flag.RegularExpression + trigger_flag.KeepEvaluating + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"quickWhere.matchTarget", sendto.script, 100
	);

	AddTriggerEx("trigger_quick_where_end",
		"^There is no .+? around here\\.$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"EnableTriggerGroup('trigger_group_quick_where', false)", sendto.script, 99
	);
	
	SetTriggerOption("trigger_quick_where", "group", "trigger_group_quick_where");
	SetTriggerOption("trigger_quick_where_end", "group", "trigger_group_quick_where");
end

function quickWhere.doWhere(name, line, wildcards)
	local index = tonumber(wildcards.index) or 1;
	local targetName = wildcards.target_name:lower();
	
	if (targetName ~= "") then
		utility.setTarget(targetName, targetName);
	else
		if (utility.targetKeyword) then
			targetName = utility.targetKeyword;
		else
			return utility.print("No target mob has been set to quick where.", "red");
		end
	end

	EnableTriggerGroup("trigger_group_quick_where", true);
	
	Execute("where " .. index .. "." .. targetName);
	DoAfterSpecial(10, "EnableTriggerGroup('trigger_group_quick_where', false)", 12);
end

function quickWhere.matchTarget(name, line, wildcards)
	if (utility.targetName) then
		local targetName = Trim(wildcards.target_name):lower();

		for token in utility.targetName:gmatch("[^ ]+") do
			if (string.find(targetName, token, 1, true)) then
				local roomName = wildcards.room_name;
				local zoneName = utility.gmcp.getPlayerZone();
				
				if (zoneName ~= "") then
					local sql = [[
						SELECT room_name, room_id, zone_name, notes
						FROM room
						WHERE room_name = %s
						AND zone_name = %s
						ORDER BY room_id;
					]];

					sql = sql:format(fixsql(roomName), fixsql(zoneName));

					local rooms = database.mobber:gettable(sql);
					
					if (next(rooms)) then
						roomHandler.rooms = rooms;
					end

					display.printRooms(rooms);
					display.printNotes(rooms);
				else
					utility.print("GMCP error retrieving zone.");
				end
				
				EnableTriggerGroup("trigger_group_quick_where", false);
				
				break;
			end
		end
	end
end

----------------------------------
-- Hunt Trick
----------------------------------

huntTrick = {};

function huntTrick.initialize()
	-- Aliases

	AddAlias("alias_hunt_trick_start", "^(?:ht|ht (?:(?<index>\\d+?)\\.)?(?<targetName>.+))$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"huntTrick.startHuntTrick"
	);
	
	AddAlias("alias_hunt_trick_stop", "^ht abort$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"huntTrick.stopHuntTrick"
	);
	SetAliasOption ("alias_hunt_trick_stop", "sequence", "99")
	
	-- Triggers

	AddTriggerEx("trigger_hunt_trick_continue",
		"^(?:" ..
		"You are certain that .+? is .+?\\." ..
		"|" ..
		"You are almost certain that .+? is (?:north|east|south|west|up|down) from here\\." ..
		"|" ..
		"You are confident that .+? passed through here, heading (north|east|south|west|up|down)\\." ..
		"|" ..
		"The trail of .+? is confusing, but you're reasonably sure .+? headed (?:north|east|south|west|up|down)\\." ..
		"|" ..
		"There are traces of .+? having been here\\. Perhaps they lead (?:north|east|south|west|up|down)\\?" ..
		"|" ..
		"You have no idea what you're doing, but maybe .+? left (?:north|east|south|west|up|down)\\?" ..
		"|" ..
		"You couldn't find a path to .+? from here\\." ..
		"|" ..
		".+? is here!" ..
		"|" ..
		"You have no idea what you're doing, but maybe (.+?) is (north|east|south|west|up|down)\\?" ..
		")$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"huntTrick.continueHuntTrick", sendto.script
	);
	
	AddTriggerEx("trigger_hunt_trick_complete",
		"^You seem unable to hunt that target for some reason\\.$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"huntTrick.completeHuntTrick", sendto.script
	);
	
	AddTriggerEx("trigger_hunt_trick_stop",
		"^(?:" ..
		"You couldn't find a path to .+? from here\\." ..
		"|" ..
		"No one in this area by that name\\." ..
		"|" ..
		"No one in this area by the name '.+?'\\." ..
		"|" ..
		"There is no .+? around here\\." ..
		"|" ..
		"Not while you are fighting!" ..
		")$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"huntTrick.stopHuntTrick", sendto.script
	);
	
	SetTriggerOption("trigger_hunt_trick_continue", "group", "trigger_group_hunt_trick");
	SetTriggerOption("trigger_hunt_trick_complete", "group", "trigger_group_hunt_trick");
	SetTriggerOption("trigger_hunt_trick_stop", "group", "trigger_group_hunt_trick");
	
	huntTrick.index = nil;
	huntTrick.targetName = nil;
end

function huntTrick.startHuntTrick(name, line, wildcards)
	local STATE_ACTIVE = 3;

	if (tonumber(gmcp("char.status.state")) == STATE_ACTIVE) then
		EnableTriggerGroup("trigger_group_hunt_trick", true);
		
		huntTrick.index = tonumber(wildcards.index) or 1;
		
		huntTrick.targetName = wildcards.targetName ~= "" and wildcards.targetName or utility.targetKeyword;
		if huntTrick.targetName == nil then
			-- never set target to begin with
			ColourNote("white", "", "(", "maroon", "", "Mobber", "white", "", ") No target to auto-hunt.");
			return
		end
		huntTrick.huntTarget(huntTrick.index, huntTrick.targetName);
	else
		ColourNote("white", "", "(", "maroon", "", "Mobber", "white", "", ") You are too busy to hunt.");
	end
end

function huntTrick.continueHuntTrick()
	if (huntTrick.index and huntTrick.targetName) then
		huntTrick.index = huntTrick.index + 1;
		
		huntTrick.huntTarget(huntTrick.index, huntTrick.targetName);
	else
		huntTrick.stopHuntTrick();
	end
end

function huntTrick.completeHuntTrick()
	huntTrick.stopHuntTrick();
	Execute("qw " .. huntTrick.index .. "." .. huntTrick.targetName);
end

function huntTrick.stopHuntTrick()
	EnableTriggerGroup("trigger_group_hunt_trick", false);
	
	ColourNote("white", "", "(", "maroon", "", "Mobber", "white", "", ") Hunt-tricking stopped.");
end

function huntTrick.huntTarget(index, targetName)
	Execute("hunt " .. index .. "." .. targetName);
end

----------------------------------
-- Auto Hunt
----------------------------------

autoHunt = {};

function autoHunt.initialize()
	-- Aliases

	AddAlias("alias_auto_hunt_start", "^(?:ah|ah (?<targetName>.+))$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"autoHunt.startHunt"
	);
	
	AddAlias("alias_auto_hunt_abort", "^ah abort$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"autoHunt.stopHunt"
	);
	SetAliasOption ("alias_auto_hunt_abort", "sequence", "99")
	
	-- Triggers
	
	AddTriggerEx("trigger_auto_hunt_door",
		"^Magical wards .+? bounce you back\\.$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary + trigger_flag.KeepEvaluating, custom_colour.NoChange, 0, "",
		"autoHunt.hunt", sendto.script, 99
	);
	
	AddTriggerEx("trigger_auto_hunt_continue1",
		"^You are confident that .+? passed through here, heading (north|east|south|west|up|down)\\.$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"autoHunt.hunt", sendto.script
	);
	
	AddTriggerEx("trigger_auto_hunt_continue2",
		"^The trail of .+? is confusing, but you're reasonably sure .+? headed (north|east|south|west|up|down)\\.$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"autoHunt.hunt", sendto.script
	);
	
	AddTriggerEx("trigger_auto_hunt_continue3",
		"^You are certain that .+? is (north|east|south|west|up|down) from here\\.$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"autoHunt.hunt", sendto.script
	);
	
	AddTriggerEx("trigger_auto_hunt_continue4",
		"^There are traces of .+? having been here\\. Perhaps they lead (north|east|south|west|up|down)\\?",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"autoHunt.hunt", sendto.script
	);
	
	AddTriggerEx("trigger_auto_hunt_continue5",
		"^The trail of .+? is confusing, but you're reasonably sure .+? is (north|east|south|west|up|down)\\.",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"autoHunt.hunt", sendto.script
	);
	
	AddTriggerEx("trigger_auto_hunt_continue6",
		"^You are almost certain that .+? is (north|east|south|west|up|down) from here\\.$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"autoHunt.hunt", sendto.script
	);
	
	AddTriggerEx("trigger_auto_hunt_abort",
		"^(?:" ..
		"You seem unable to hunt that target for some reason\\." ..
		"|" ..
		"You couldn't find a path to .+? from here\\." ..
		"|" ..
		".+? is here!" ..
		"|" ..
		"Not while you are fighting!" ..
		"|" ..
		"No one in this area by the name '.+?'\\." ..
		")$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"autoHunt.stopHunt", sendto.script
	);
	
	SetTriggerOption("trigger_auto_hunt_door", "group", "trigger_group_auto_hunt");
	SetTriggerOption("trigger_auto_hunt_abort", "group", "trigger_group_auto_hunt");
	
	for i = 1, 6 do
		SetTriggerOption("trigger_auto_hunt_continue" .. i, "group", "trigger_group_auto_hunt");
	end
	
	autoHunt.targetName = nil;
	autoHunt.lastDirection = nil;
end

function autoHunt.startHunt(name, line, wildcards)
	local STATE_ACTIVE = 3;

	if (tonumber(gmcp("char.status.state")) == STATE_ACTIVE) then
		EnableTriggerGroup("trigger_group_auto_hunt", true);
		
		autoHunt.targetName = wildcards.targetName ~= "" and wildcards.targetName or utility.targetKeyword;
		SendNoEcho("hunt " .. autoHunt.targetName);
	else
		ColourNote("white", "", "(", "maroon", "", "Mobber", "white", "", ") You are too busy to auto-hunt.");
	end
end

function autoHunt.hunt(name, line, wildcards)
	if (name == "trigger_auto_hunt_door") then
		if (autoHunt.lastDirection) then
			Execute("open " .. autoHunt.lastDirection);
		else
			Execute("hunt " .. autoHunt.targetName);
		end
	else
		autoHunt.lastDirection = wildcards[1];
		
		Execute(wildcards[1]);
		SendNoEcho("hunt " .. autoHunt.targetName);
	end
end

function autoHunt.stopHunt()
	EnableTriggerGroup("trigger_group_auto_hunt", false);
	autoHunt.targetName = nil;
	autoHunt.lastDirection = nil;
	ColourNote("white", "", "(", "maroon", "", "Mobber", "white", "", ") Auto-hunt stopped.");
end

----------------------------------
-- Autokill
----------------------------------

autoKill = {};

function autoKill.initialize()
	AddAlias("alias_auto_kill", "^(?:ak|kk)$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"autoKill.kill"
	);
	
	AddAlias("alias_auto_kill_set_skill", "^(?:ak|kk) (?<skill>.+?)$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"autoKill.setSkill"
	);
	
	AddAlias("alias_auto_kill_toggle", "^toggle (?:ak|kk)$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"autoKill.toggle"
	);
	
	autoKill.skill = var.akSkill or "kill";
	autoKill.isTargetting = var.isTargetting == "true" and true or false;
end

function autoKill.kill()
	local target = utility.targetKeyword;
	local skill = autoKill.skill;

	if (autoKill.isTargetting and target) then
		skill = skill:gsub("[^;]+", "%1 '" .. target .. "'");
	end
	
	Execute(skill);
end

function autoKill.setSkill(name, line, wildcards)
	autoKill.skill = wildcards.skill;
	var.akSkill = wildcards.skill;
	utility.print("Autokill skill/spell: " .. wildcards.skill);
end

function autoKill.toggle()
	if (autoKill.isTargetting) then
		utility.print("Target Mode: OFF");
	else
		utility.print("Target Mode: ON");
	end
	
	autoKill.isTargetting = not autoKill.isTargetting;
	var.isTargetting = autoKill.isTargetting;
end

----------------------------------
-- Noexp
----------------------------------

noexp = {};

function noexp.initialize()
	AddAlias("alias_noexp_toggle", "^mobber noexp(?: (?<threshold>\\d+?))?$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"noexp.toggle"
	);
	
	AddTriggerEx("trigger_noexp_1",
		"^(?:You may take a campaign at this level\\.|You raise a level! You are now level \\d+?\\.)$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"noexp.enableCampaignAvailableAndCheckTnl", sendto.script, 100
	);
	
	AddTriggerEx("trigger_noexp_2",
		"^(?:You will have to level before you can go on another campaign\\.|.+?'Good luck in your campaign!')$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"noexp.disableCampaignAvailableAndTurnOffNoExp", sendto.script, 100
	);
	
	AddTriggerEx("trigger_noexp_3",
		"^You receive \\d+? experience points?\\.$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"noexp.checkCampaignTnl", sendto.script, 100
	);
	
	AddTriggerEx("trigger_noexp_4",
		"^You will no longer receive experience\\. Happy questing!$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"noexp.enableIsNoExp", sendto.script, 100
	);
	
	AddTriggerEx("trigger_noexp_5",
		"^You will now receive experience\\. Happy leveling!$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"noexp.disableIsNoExp", sendto.script, 100
	);
	
	for i = 1, 5 do
		SetTriggerOption("trigger_noexp_" .. i, "group", "trigger_group_noexp");
	end
	
	noexp.isNoExpMode = false;
	noexp.isNoExp = false;
	noexp.isCampaignAvailable = false;
	noexp.threshold = tonumber(var.threshold) or 1000;
end

function noexp.showVars()
	print("noexp.isNoExpMode", noexp.isNoExpMode);
	print("noexp.isNoExp", noexp.isNoExp);
	print("noexp.isCampaignAvailable", noexp.isCampaignAvailable);
	print("noexp.threshold", noexp.threshold);
end

function noexp.toggle(name, line, wildcards)
	noexp.threshold = tonumber(wildcards.threshold) or noexp.threshold;
	var.threshold = noexp.threshold;
	
	if (noexp.isNoExpMode) then
		EnableTriggerGroup("trigger_group_noexp", false);
		utility.print("NOEXP AUTOMODE OFF", "red");
	else
		EnableTriggerGroup("trigger_group_noexp", true);
		utility.print("NOEXP AUTOMODE ON (THRESHOLD = " .. noexp.threshold .. "xp)", "lime");
		Execute("cp check");
	end
	
	noexp.setNoExp(false);
	
	noexp.isNoExpMode = not noexp.isNoExpMode;
end

function noexp.setNoExp(state)
	noexp.isNoExp = state;

	state = state and "on" or "off";
	
	Send_GMCP_Packet("config noexp " .. state);
	utility.print("Setting noexp " .. state, "orange");
end

function noexp.checkTnl()
	local tnl = utility.gmcp.getPlayerTnl();
	
	if (noexp.isNoExp and tnl > noexp.threshold) then
		noexp.setNoExp(false);
	elseif (not noexp.isNoExp and tnl < noexp.threshold) then
		noexp.setNoExp(true);
	end
end

function noexp.turnOffNoExp()
	if (noexp.isNoExp) then
		noexp.setNoExp(false);
	end
end

function noexp.enableCampaignAvailableAndCheckTnl()
	noexp.isCampaignAvailable = true;
	DoAfterSpecial(0.2, "noexp.checkTnl()", 12);
end

function noexp.disableCampaignAvailableAndTurnOffNoExp()
	noexp.isCampaignAvailable = false;
	noexp.turnOffNoExp();
end

function noexp.checkCampaignTnl()
	if (noexp.isCampaignAvailable) then
		DoAfterSpecial(0.2, "noexp.checkTnl()", 12);
	else
		noexp.turnOffNoExp();
	end
end

function noexp.enableIsNoExp()
	noexp.isNoExp = true;
end

function noexp.disableIsNoExp()
	noexp.isNoExp = false;
end

----------------------------------
-- Quest
----------------------------------

quest = {};

function quest.initialize()
	AddAlias("alias_quest_mute", "^mobber (?<toggle>mute|unmute) quest$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"quest.toggleMute"
	);
	
	AddAlias("alias_quest_request", "^mobber quest|(?:q|qu|que|ques|quest) (?:i|in|inf|info)$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"quest.request"
	);
	
	quest.commPrefix = "@r(@WQuest@r)@w";
	quest.timer = nil;
	quest.isMuted = false;
end

function quest.start(newQuest)
	if (not quest.isMuted) then
		local commMsg = quest.commPrefix .. " @Y" .. newQuest.targ .. " @win @R" .. newQuest.room .. " @r(@w" .. newQuest.area .. "@r)@w";
		CallPlugin("b555825a4a5700c35fa80780", "storeFromOutside", commMsg);
		
		AddTimer("questReminder", 0, 1, 0, "", timer_flag.Enabled + timer_flag.Temporary, "quest.playSound");
		quest.timer = os.time();
	end
	
	quest.process(newQuest);
end

function quest.showRequest(newQuest)
	local mobName = newQuest.targ;
	local roomName = stripColors(newQuest.room or "");
	local areaName = newQuest.area;

	if (mobName == "missing") then
		ColourNote("maroon", "", "(", "white", "", "Quest", "maroon", "", ") ", "red", "", "Quest mob is missing.");
	elseif (mobName == "killed") then
		ColourNote("maroon", "", "(", "white", "", "Quest", "maroon", "", ") ", "red", "", "Quest mob is killed.");
	elseif (mobName and roomName and areaName) then
		ColourNote("maroon", "", "(", "white", "", "Quest", "maroon", "", ") ", "red", "", "Mob:  " .. mobName);
		ColourNote("maroon", "", "(", "white", "", "Quest", "maroon", "", ") ", "red", "", "Room: " .. roomName);
		ColourNote("maroon", "", "(", "white", "", "Quest", "maroon", "", ") ", "red", "", "Area: " .. areaName);
		quest.process(newQuest);
	else
		ColourNote("maroon", "", "(", "white", "", "Quest", "maroon", "", ") ", "red", "", "Quest mob not found.");
	end
end

function quest.request(name, line, wildcards)
	Send_GMCP_Packet("request quest");
	if (line ~= "mobber quest") then
		Send(line);
	end
end

function quest.fail()
	if (not quest.isMuted) then
		local commMsg = quest.commPrefix .. " @WFailed!@w";
		CallPlugin("b555825a4a5700c35fa80780", "storeFromOutside", commMsg);
	
		quest.timer = nil;
		DeleteTimer("questReminder");
		ColourNote(
			"maroon", "", "(", 
			"white", "", "Quest", 
			"maroon", "", ") ", 
			"red", "", "You failed the quest!\r\n"
		);
	end
end

function quest.complete(newQuest)
	if (not quest.isMuted) then
		local commMsg = quest.commPrefix .. " @WComplete!@w";
		CallPlugin("b555825a4a5700c35fa80780", "storeFromOutside", commMsg);
	
		local duration = 0;
	
		if (quest.timer) then
			duration = os.difftime(os.time(), quest.timer);
			duration = formatSeconds(duration);
			quest.timer = nil;
		end
		
		local numQuestPoints = tonumber(newQuest.totqp);
		local numTriviaPoints = tonumber(newQuest.tp);
		
		ColourTell(
			"maroon", "", "(", 
			"white", "", "Quest", 
			"maroon", "", ") ", 
			"cyan", "", numQuestPoints,
			"red", "", " quest points. Completed in: ",
			"cyan", "", duration
		);
		
		if (numTriviaPoints > 0) then
			ColourTell(
				"red", "", " [",
				"lime", "", numTriviaPoints .. " tp",
				"red", "", "]\r\n\r\n"
			);
		else
			ColourTell("red", "", "\r\n\r\n");
		end
		
		DeleteTimer("questReminder");
	end
end

function quest.process(newQuest)
	local mobName = newQuest.targ:lower();
	local roomName = stripColors(newQuest.room);
	local areaName = newQuest.area;
	
	local mobKeyword = database.lookupMobKeyword(mobName) or utility.getMobKeyword(mobName);

	utility.setTarget(mobName, mobKeyword);

	local sql = [[
		SELECT mob.room_name, mob.room_id, mob.zone_name
		FROM mob
		INNER JOIN area ON mob.zone_name = area.zone_name
		WHERE mob.mob_name = %s
		AND mob.room_name = %s
		AND area.area_name = %s
		ORDER BY mob.room_priority DESC, mob.room_id ASC;
	]];

	sql = sql:format(fixsql(mobName), fixsql(roomName), fixsql(areaName));
	
	local rooms = database.mobber:gettable(sql);
	
	if (not next(rooms)) then
		sql =   [[
			SELECT room.room_name, room.room_id, room.zone_name
			FROM room
			INNER JOIN area ON room.zone_name = area.zone_name
			WHERE room.room_name = %s
			AND area.area_name = %s
			ORDER BY room.room_id ASC;
		]];

		sql = sql:format(fixsql(roomName), fixsql(areaName));

		rooms = database.mobber:gettable(sql);
	end
	
	roomHandler.rooms = rooms;
	
	display.printRooms(rooms);
end

function quest.playSound()
	Sound(GetInfo(66) .. "\\sounds\\quest_warning.wav");
end

function quest.toggleMute(name, line, wildcards)
	if (wildcards.toggle == "unmute") then
		quest.isMuted = false;
		utility.print("Quest messages are now on.", "yellowgreen");
	else
		quest.isMuted = true;
		utility.print("Quest messages are now off.", "indianred");
	end
	
	var.isQuestMuted = quest.isMuted;
end

----------------------------------
-- Database
----------------------------------

database = {};

function database.initialize()
	AddAlias("alias_database_developer", "^mobber dev(?:eloper)?(?: mode)?$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.toggleDeveloperMode"
	);
	
	AddAlias("alias_database_backup", "^mobber backup$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.manualBackup"
	);
	
	AddAlias("alias_database_vacuum", "^mobber vacuum$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.vacuum"
	);
	
	AddAlias("alias_database_consider", "^mobber consider(?: (?<mode>on|off))?$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.toggleConsiderMobLogging"
	);
	
	AddAlias("alias_database_add_area", "^mobber add(?:area|zone) (?<min_lvl>\\d+) (?<max_lvl>\\d+)$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.startAddArea"
	);
	
	AddAlias("alias_database_remove_area", "^mobber (?:remove|delete) (?:area|zone)$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.removeArea"
	);
	
	AddAlias("alias_database_show_areas", "^mobber show (?:areas|zones)(?: sort (?<order>mobs?|rooms?|level))?$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.showAreas"
	);
	
	AddAlias("alias_database_show_area", "^mobber show (?:area|zone)(?: (?<zone_name>.+?))?$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.showArea"
	);
	
	AddAlias("alias_database_update_rooms", "^mobber update rooms$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.updateRooms"
	);

	AddAlias("alias_database_update_notes", "^mobber update notes$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.updateNotes"
	);
	
	AddAlias("alias_database_update_areas", "^mobber update (?:areas|zones)$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.updateAreas"
	);
	
	AddAlias("alias_database_update_area_id", "^(?:mobber xset|xset mark)$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.updateAreaId"
	);

	AddAlias("alias_database_update_remote_area_id", "^(?:mobber xset|xset mark) (?<area>[^ ]+) (?<roomid>\\d+)$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.updateRemoteAreaId"
	);
	
	AddAlias("alias_database_update_area_level_range", "^mobber update (?:level|lvl)range (?<min_lvl>\\d+) (?<max_lvl>\\d+)$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.updateAreaLevelRange"
	);
	
	AddAlias("alias_database_add_mob", "^mobber addmob (?<mob_name>.+?)(?: priority (?<mob_priority>\\d+))?$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.addMob"
	);
	
	AddAlias("alias_database_remove_mob_room", "^mobber (?:remove|delete)mob (?:room|here)$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.removeMobRoom"
	);
	
	AddAlias("alias_database_remove_mob_zone", "^mobber (?:remove|delete)mob (?:zone|area)$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.removeMobZone"
	);
	
	AddAlias("alias_database_remove_mob_single", "^mobber (?:remove|delete)mob single (?<mob_name>.+?)$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.removeMobSingle"
	);
	
	AddAlias("alias_database_update_mob_keyword", "^mobber keyword (?<mobKeyword>.+?) mob (?<mob_name>.+?)$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.updateMobKeyword"
	);
	
	AddAlias("alias_database_update_mob_keywords", "^mobber update keywords?$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.updateMobKeywords"
	);
	
	AddAlias("alias_database_clean_keywords", "^mobber clean keywords?$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.cleanKeywords"
	);
	
	AddAlias("alias_database_set_mob_priority", "^mobber priority (?<priority>-?\\d+) mob (?<mob_name>.+?)$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.setMobPriority"
	);

	AddAlias("alias_database_set_mob_room_priority", "^mobber rprio(?:rity)? (?<priority>-?\\d+)(?: room (?<roomid>-?\\d+))? mob (?<mob_name>.+?)$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.setMobRoomPriority"
	);

	AddAlias("alias_database_set_mob_area_mob_priority", "^mobber aprio(?:rity)? (?<priority>-?\\d+)(?: zone (?<zone_name>-?.+))? mob (?<mob_name>.+?)$", "",
		alias_flag.Enabled + alias_flag.RegularExpression + alias_flag.Temporary,
		"database.setMobAreaMobPriority"
	);
	
	-- Consider Triggers
	
	AddTriggerEx("trigger_database_developer_mob_consider1",
		"^You get .+? gold coins? from the .*?corpse of (?<mob_name>.+?)\\.$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"database.addMob", sendto.script, 100
	);
	
	AddTriggerEx("trigger_database_developer_mob_consider2",
		"^(?:\\([A-Za-z ]+\\)\\s?)*You would be completely annihilated by (?<mob_name>.+?)$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"database.addMob", sendto.script, 100
	);
	
	AddTriggerEx("trigger_database_developer_mob_consider3",
		"^(?:\\([A-Za-z ]+\\)\\s?)*You would stomp (?<mob_name>.+?) into the ground\\.$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"database.addMob", sendto.script, 100
	);
	
	AddTriggerEx("trigger_database_developer_mob_consider4",
		"^(?:\\([A-Za-z ]+\\)\\s?)*No Problem! (?<mob_name>.+?) is weak compared to you\\.$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"database.addMob", sendto.script, 100
	);
	
	AddTriggerEx("trigger_database_developer_mob_consider5",
		"^(?:\\([A-Za-z ]+\\)\\s?)*Best run away from (?<mob_name>.+?) while you can!$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"database.addMob", sendto.script, 100
	);
	
	AddTriggerEx("trigger_database_developer_mob_consider6",
		"^(?:\\([A-Za-z ]+\\)\\s?)*Challenging (?<mob_name>.+?) would be either very brave or very stupid\\.$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"database.addMob", sendto.script, 100
	);
	
	AddTriggerEx("trigger_database_developer_mob_consider7",
		"^(?:\\([A-Za-z ]+\\)\\s?)*(?<mob_name>.+?) " ..
		"(?:" ..
		"would be easy, but is it even worth the work out\\?" ..
		"|" ..
		"looks a little worried about the idea\\." ..
		"|" ..
		"should be a fair fight!" ..
		"|" ..
		"snickers nervously\\." ..
		"|" ..
		"chuckles at the thought of you fighting (?:him|her|it)\\." ..
		"|" ..
		"would crush you like a bug!" ..
		"|" ..
		"would dance on your grave!" ..
		"|" ..
		"says 'BEGONE FROM MY SIGHT unworthy!'" ..
		"|" ..
		"has divine protection\\." ..
		")$",
		"", trigger_flag.RegularExpression + trigger_flag.Temporary, custom_colour.NoChange, 0, "",
		"database.addMob", sendto.script, 100
	);
	
	for i = 1, 7 do
		local triggerName = "trigger_database_developer_mob_consider" .. i;
		SetTriggerOption(triggerName, "group", "trigger_group_add_mob_consider");
	end
	
	database.isDeveloperMode = false;
	database.isConsiderMobLogging = false;
end

function database.openDatabase()
	if (not database.mobber) then
		database.mobber = sqlitedb:new{name = "mobber.db"};
	end
	database.mobber:open();
	database.checkCreateTables();
	database.checkBackup();
end

function database.closeDatabase()
	database.mobber:close();
	database.mobber = nil;
end

function database.checkBackup()
	if (var.dbBackupTimer) then
		local NUM_SECONDS_DAY = 86400;
		local duration = math.abs(GetInfo(232) - var.dbBackupTimer);

		if (duration > NUM_SECONDS_DAY) then
			database.mobber:backup();
			var.dbBackupTimer = GetInfo(232);
		else
			local timeRemaining = formatSeconds(NUM_SECONDS_DAY - duration);
			utility.print("Next database backup will occur in: " .. timeRemaining, "darkgray");
		end
	else
		var.dbBackupTimer = GetInfo(232);
	end
end

function database.manualBackup()
	if (database.isDeveloperModeEnabled()) then
		database.mobber:backup();
	end
end

function database.vacuum()
	if (database.isDeveloperModeEnabled()) then
		database.mobber:vacuum();
	end
end

function database.toggleDeveloperMode()
	if (database.isDeveloperMode) then
		utility.print("Developer mode disabled.");
	else
		utility.print("Developer mode enabled.");
	end

	database.isDeveloperMode = not database.isDeveloperMode;
end

function database.isDeveloperModeEnabled()
	if (not database.isDeveloperMode) then
		utility.print("Developer mode is disabled.", "red");
	end

	return database.isDeveloperMode;
end

function database.toggleConsiderMobLogging(name, line, wildcards)
	local mode = wildcards.mode;
	local enable = mode == "on" or mode == "" and not database.isConsiderMobLogging;
	local desc = enable and "enabled." or "disabled.";
	utility.print("Developer consider mob logging " .. desc);
	EnableTriggerGroup("trigger_group_add_mob_consider", enable);
	database.isConsiderMobLogging = enable;
end

function database.lookupMobKeyword(mobName)
	local mobKeyword;

	local sql = [[
		SELECT mob_keyword
		FROM keyword
		WHERE mob_name = %s
		LIMIT 1;
	]];
	
	sql = sql:format(fixsql(mobName));
	
	local results = database.mobber:gettable(sql);
	
	mobKeyword = next(results) and results[1].mob_keyword or nil;
	
	return mobKeyword;
end

function database.lookupMobRoomOrAreaByLvl(location, mobName)
	local playerLevel = utility.gmcp.getPlayerLevel();

	local sql = [[
		SELECT mob.room_name, mob.room_id, mob.zone_name, mob.mob_priority, mob.room_priority, mob.area_mob_priority
		FROM mob
		INNER JOIN area ON mob.zone_name = area.zone_name
		WHERE mob.mob_name = %s
		AND (mob.room_name = %s OR area.area_name = %s)
		AND area.min_lvl - 10 <= %d
		AND area.max_lvl + 15 >= %d
		ORDER BY mob.room_priority DESC, mob.room_id ASC;
	]];

	sql = sql:format(fixsql(mobName), fixsql(location), fixsql(location), playerLevel, playerLevel);
	
	local results = database.mobber:gettable(sql);
	
	local lookupType = "mobMatchInLvlRange";
	
	return results, lookupType;
end

function database.lookupMobRoomOrArea(location, mobName)
	local playerLevel = utility.gmcp.getPlayerLevel();

	local sql = [[
		SELECT mob.room_name, mob.room_id, mob.zone_name, mob.mob_priority, mob.room_priority, mob.area_mob_priority
		FROM mob
		INNER JOIN area ON mob.zone_name = area.zone_name
		WHERE mob.mob_name = %s
		AND (mob.room_name = %s OR area.area_name = %s)
		ORDER BY mob.room_priority DESC, mob.room_id ASC;
	]];

	sql = sql:format(fixsql(mobName), fixsql(location), fixsql(location), playerLevel, playerLevel);
	
	local results = database.mobber:gettable(sql);
	
	local lookupType = "mobMatchOutOfLvlRange";
	
	return results, lookupType;
end

function database.lookupArea(location)
	local sql = [[
		SELECT zone_name, room_id
		FROM area
		WHERE area_name = %s
		LIMIT 1;
	]];

	sql = sql:format(fixsql(location));
	
	local results = database.mobber:gettable(sql);
	
	local lookupType = "areaMatch";
	
	return results, lookupType;
end

function database.lookupRoomAreaByLvl(location)
	local playerLevel = utility.gmcp.getPlayerLevel();

	local sql = [[
		SELECT room.room_name, room.room_id, room.zone_name
		FROM room
		INNER JOIN area ON room.zone_name = area.zone_name
		WHERE room.room_name = %s
		AND area.min_lvl - 10 <= %d
		AND area.max_lvl + 15 >= %d;
	]];
	
	sql = sql:format(fixsql(location), playerLevel, playerLevel);
	
	local results = database.mobber:gettable(sql);
	
	local lookupType = "roomMatchInLvlRange";
	
	return results, lookupType;
end

function database.lookupRoomArea(location)
	local sql = [[
		SELECT room.room_name, room.room_id, room.zone_name
		FROM room
		INNER JOIN area ON room.zone_name = area.zone_name
		WHERE room.room_name = %s;
	]];
	
	sql = sql:format(fixsql(location));
	
	local results = database.mobber:gettable(sql);
	
	local lookupType = "roomMatchOutOfLvlRange";
	
	return results, lookupType;
end

function database.setMobPriority(name, line, wildcards)
	if (database.isDeveloperModeEnabled()) then
		local mobName = wildcards.mob_name;
		local priority = tonumber(wildcards.priority);
		local zoneName = utility.gmcp.getPlayerZone();
		
		if (zoneName ~= "") then
			local sql = [[
				UPDATE mob
				SET mob_priority = %d
				WHERE zone_name = %s
				AND mob_name = %s;
			]];
			
			sql = sql:format(priority, fixsql(zoneName), fixsql(mobName));
			
			database.mobber:exec(sql);
			
			local numChanges = database.mobber:changes();
			
			if (numChanges > 0) then
				utility.print(numChanges .. " instance(s) of " .. mobName .. " had their GQ priority set to: " .. priority, "lime");
			elseif (numChanges == 0) then
				utility.print("Mob " .. mobName .. " was not found in " .. zoneName .. ".", "yellow");
			end
		else
			utility.print("GMCP error retrieving zone.");
		end
	end
end

function database.setMobRoomPriority(name, line, wildcards)
	if (not database.isDeveloperModeEnabled()) then
		return
	end
	local mobName = wildcards.mob_name;
	local priority = tonumber(wildcards.priority);
	local roomid = tonumber(wildcards.roomid) or tonumber(gmcp("room.info.num"))
	if mobName == "" or roomid == "" then
		utility.print("Couldn't set room priority for room [" .. roomid .. "], mob [" .. mobName .. "]")
		return
	end

	local sql = [[
				UPDATE mob
				SET room_priority = %d
				WHERE room_id = %d
				AND mob_name = %s;
	]];

	sql = sql:format(priority, roomid, fixsql(mobName));
	
	database.mobber:exec(sql);
	
	local numChanges = database.mobber:changes();
	
	if (numChanges > 0) then
		utility.print(numChanges .. " instance(s) of " .. mobName .. " had their room priority set to: " .. priority, "lime");
	elseif (numChanges == 0) then
		utility.print("Mob " .. mobName .. " was not found in " .. roomid .. ".", "yellow");
	end
end

function database.setMobAreaMobPriority(name, line, wildcards)
	if (not database.isDeveloperModeEnabled()) then
		return
	end
	local mobName = wildcards.mob_name;
	local priority = tonumber(wildcards.priority);

	local zone_name = wildcards.zone_name ~= "" and wildcards.zone_name or gmcp("room.info.zone")
	if mobName == "" or zone_name == "" then
		utility.print("Couldn't set area mob priority for area [" .. zone_name .. "], mob [" .. mobName .. "]")
		return
	end

	local sql = [[
				UPDATE mob
				SET area_mob_priority = %d
				WHERE zone_name = %s
				AND mob_name = %s;
	]];

	sql = sql:format(priority, fixsql(zone_name), fixsql(mobName));

	database.mobber:exec(sql);

	local numChanges = database.mobber:changes();

	if (numChanges > 0) then
		utility.print(numChanges .. " instance(s) of " .. mobName .. " had their area mob priority set to: " .. priority, "lime");
	elseif (numChanges == 0) then
		utility.print("Mob " .. mobName .. " was not found in " .. zone_name .. ".", "yellow");
	end
end

function database.updateMobKeyword(name, line, wildcards)
	if (database.isDeveloperModeEnabled()) then
		local mobName = wildcards.mob_name;
		local mobKeyword = wildcards.mobKeyword;
	
		local sql = [[
			UPDATE keyword
			SET mob_keyword = %s
			WHERE mob_name = %s;
		]];
					
		sql = sql:format(fixsql(mobKeyword), fixsql(mobName));
		
		database.mobber:exec(sql, true);
		
		local numChanges = database.mobber:changes();
		
		if (numChanges ~= 0) then
			utility.print("The mob " .. mobName .. " was updated with the keyword " .. mobKeyword .. ".", "lime");
		else
			utility.print("The mob " .. mobName .. " was not found and therefore its keyword could not be updated.", "yellow");
			ColourNote(
				"yellow", "",
				"Possible reasons:\r\n\r\n" ..
				"mob name mispelled\r\n" ..
				"mob not previously added via the 'mob update keywords' command\r\n" ..
				"mob not logged to the database"
			);
		end
	end
end

function database.updateMobKeywords()
	if (database.isDeveloperModeEnabled()) then
		local start = GetInfo(232);
		
		local sql = [[
			SELECT mob_name FROM mob WHERE mob_name NOT IN (SELECT mob_name FROM keyword);
		]];
		
		local mobNames = database.mobber:gettable(sql);
		
		if (next(mobNames)) then
			local sql = [[
				INSERT OR IGNORE INTO keyword(mob_name, mob_keyword) VALUES(%s, %s);
			]];
			
			database.mobber:exec("BEGIN TRANSACTION;", true);
			
			local numChanges = 0;
			
			for i = 1, #mobNames do
				local mobKeyword = utility.getMobKeyword(mobNames[i].mob_name);
				local stmt = sql:format(fixsql(mobNames[i].mob_name), fixsql(mobKeyword));
				
				database.mobber:exec(stmt, true);
				
				numChanges = numChanges + database.mobber:changes();
			end
			
			database.mobber:exec("END TRANSACTION;", true);
			
			local dif = GetInfo(232) - start;
		
			utility.print(numChanges .. " mob keyword(s) created.\r\nKeyword update completed in: " .. formatSeconds(dif), "lime");
		else
			utility.print("All mob keywords are up-to-date.", "greenyellow");
		end
	end
end

function database.cleanKeywords()
	if (database.isDeveloperModeEnabled()) then
		local sql = [[
			DELETE FROM keyword WHERE mob_name NOT IN (SELECT mob_name FROM mob);
		]];
		
		database.mobber:exec(sql, true);
		
		local numChanges = database.mobber:changes();
		
		if (numChanges ~= 0) then
			utility.print(numChanges .. " unmatched keyword(s) deleted from the mobber database.", "lime");
		else
			utility.print("There are no unmatched keywords in the mobber database!", "greenyellow");
		end
	end
end

function database.removeMobRoom()
	if (database.isDeveloperModeEnabled()) then
		local roomId = utility.gmcp.getPlayerRoomId();
		
		if (roomId) then
			local sql = [[
				DELETE FROM mob WHERE room_id = %d;
			]];
			
			sql = sql:format(roomId);
			
			database.mobber:exec(sql, true);
			
			local numChanges = database.mobber:changes();
			
			utility.print(numChanges .. " mob(s) removed from roomid: " .. roomId, "lime");
		else
			utility.print("GMCP error retrieving room id.");
		end
	end
end

function database.removeMobZone()
	if (database.isDeveloperModeEnabled()) then
		local zoneName = utility.gmcp.getPlayerZone();
		
		if (zoneName ~= "") then
			local sql = [[
				DELETE FROM mob WHERE zone_name = %s;
			]];
			
			sql = sql:format(fixsql(zoneName));
			
			database.mobber:exec(sql, true);
			
			local numChanges = database.mobber:changes();
			
			utility.print(numChanges .. " mob(s) removed from zone: " .. zoneName, "lime");
		else
			utility.print("GMCP error retrieving zone.");
		end
	end
end

function database.removeMobSingle(name, line, wildcards)
	if (database.isDeveloperModeEnabled()) then
		local mobName = wildcards.mob_name;
		local zoneName = utility.gmcp.getPlayerZone();
		
		if (zoneName ~= "") then
			local sql = [[
				DELETE FROM mob WHERE mob_name = %s AND zone_name = %s;
			]];
			
			sql = sql:format(fixsql(mobName), fixsql(zoneName));
			
			database.mobber:exec(sql, true);
			
			local numChanges = database.mobber:changes();
			
			utility.print(numChanges .. " instance(s) of " .. mobName .. " removed from zone: " .. zoneName, "lime");
		else
			utility.print("GMCP error retrieving zone.");
		end
	end
end

function database.addMob(name, line, wildcards)
	if (name ~= "alias_database_add_mob" or database.isDeveloperModeEnabled()) then
		local mobName = wildcards.mob_name;
		local mobPriority = tonumber(wildcards.mob_priority) or 0;
		local mobAreaPriority = tonumber(wildcards.mob_area_priority) or 0;

		local roomName = utility.gmcp.getPlayerRoomName();
		local zoneName = utility.gmcp.getPlayerZone();
		local roomId = utility.gmcp.getPlayerRoomId();
		
		if (roomName ~= "" and zoneName ~= "" and roomId) then
			roomName = stripColors(roomName);
			
			local sql = [[
				INSERT OR IGNORE INTO mob (mob_name, room_name, room_id, zone_name, mob_priority, area_mob_priority)
				VALUES(%s, %s, %d, %s,
                  (SELECT COALESCE((SELECT mob_priority FROM mob WHERE mob_name = %s AND zone_name = %s LIMIT 1), %d) AS mob_priority),
                  (SELECT COALESCE((SELECT area_mob_priority FROM mob WHERE mob_name = %s AND zone_name = %s LIMIT 1), %d) AS area_mob_priority)
				  );
			]];
			
			sql = sql:format(fixsql(mobName), fixsql(roomName), roomId, fixsql(zoneName), 
				             fixsql(mobName), fixsql(zoneName), mobPriority,
				             fixsql(mobName), fixsql(zoneName), mobAreaPriority);
			
			local code = database.mobber:exec(sql, false);
			
			if (code == sqlite3.OK) then
				local numChanges = database.mobber:changes();
				
				if (numChanges == 1) then
					if (name == "alias_database_add_mob") then
						utility.print(
							numChanges .. " mob was added to the room.\r\n\r\n" ..
							"Mob: " .. mobName .. "\r\n" ..
							"Room: " .. roomName .. "\r\n" ..
							"RoomId: " .. roomId .. "\r\n" ..
							"Zone: " .. zoneName .. "\r\n" ..
							"Priority: " .. mobPriority ..
							"areaPriority: " .. mobAreaPriority,
							"lime"
						);
					else
						utility.print(mobName .. " was logged to the room." ,"lime");
					end
				else
					-- utility.print(mobName .. " is already logged to room id: " .. roomId, "yellow");
				end
			elseif (code == sqlite3.CONSTRAINT) then
				utility.print("Error: This room and/or zone is missing from the mobber database.", "red");
			else
				local err = database.mobber.db:errmsg();
				database.mobber.db:execute("ROLLBACK;");
				error(err);
			end
		else
			utility.print("GMCP error adding mob.");
		end
	end
end

function database.startAddArea(name, line, wildcards)
	if (database.isDeveloperModeEnabled()) then
		if (tonumber(wildcards.min_lvl) > tonumber(wildcards.max_lvl)) then
			return utility.print("Max level must be greater than or equal to min level.", "yellow");
		end
	
		database.area = {};
		database.area.minLvl = tonumber(wildcards.min_lvl);
		database.area.maxLvl = tonumber(wildcards.max_lvl);
		database.area.roomId = utility.gmcp.getPlayerRoomId();
		database.area.isAddingArea = true;
		
		utility.gmcp.requestPlayerArea();
	end
end

function database.addArea(zoneName, areaName)
	if (database.area and zoneName ~= "" and areaName ~= "") then
		local sql = [[
			INSERT OR IGNORE INTO area VALUES(%s, %s, %d, %d, %d);
		]];
		
		sql = sql:format(fixsql(zoneName), fixsql(areaName), database.area.minLvl, database.area.maxLvl, database.area.roomId);

		database.mobber:exec(sql, true);
		
		local numChanges = database.mobber:changes();
		
		if (numChanges == 1) then
			utility.print("Added to database: " .. areaName .. " (" .. zoneName .. ") " .. database.area.minLvl .. " to " .. database.area.maxLvl, "lime");
		elseif (numChanges == 0) then
			utility.print("This area already exists in the mobber database.", "yellow");
		end
	else
		utility.print("GMCP error adding area.");
	end
	
	database.area = nil;
end

function database.removeArea()
	if (database.isDeveloperModeEnabled()) then
		local zoneName = utility.gmcp.getPlayerZone();
		
		if (zoneName ~= "") then
			local start = GetInfo(232);
		
			local sql = [[
				DELETE FROM area WHERE zone_name = %s;
			]];
			
			sql = sql:format(fixsql(zoneName));
			
			database.mobber:exec(sql, true);
			
			local dif = GetInfo(232) - start;
			
			local numChanges = database.mobber:changes();
			
			if (numChanges == 1) then
				utility.print(zoneName .. " was removed from the mobber database.\r\nDelete operation completed in: " .. formatSeconds(dif), "lime");
			elseif (numChanges == 0) then
				utility.print(zoneName .. " does not exist in the mobber database!", "yellow");
			end
		else
			utility.print("GMCP error retrieving zone.");
		end
	end
end

function database.showAreas(name, line, wildcards)
	local order = wildcards.order;

	if (order == "mob" or order == "mobs") then
		order = "mob_count";
	elseif (order == "room" or order == "rooms") then
		order = "room_count";
	elseif (order == "level") then
		order = "min_lvl ASC, max_lvl";
	else
		order = "zone_name";
	end
		
	local sql = [[
		SELECT * FROM
		(
			SELECT area.zone_name, area.area_name, area.min_lvl, area.max_lvl, area.room_id, COUNT(room.room_id) AS room_count
			FROM area
			LEFT JOIN room USING(zone_name)
			GROUP BY zone_name
		) 
		JOIN
		(
			SELECT area.zone_name, COUNT(DISTINCT mob.mob_name) AS mob_count
			FROM area
			LEFT JOIN mob USING(zone_name)
			GROUP BY zone_name
		)
		USING (zone_name)
		ORDER BY %s ASC;
	]];
	
	sql = sql:format(order);
	
	local areas = database.mobber:gettable(sql);
	
	if (next(areas)) then
		display.printAreas(areas);
	end
	
	utility.print("Found " .. #areas .. " area(s) in the mobber database.", "lime");
end

function database.showArea(name, line, wildcards)
	local zoneName = wildcards.zone_name ~= "" and wildcards.zone_name or utility.gmcp.getPlayerZone();
	
	if (zoneName ~= "") then
		local sql = [[
			SELECT * FROM
			(
				SELECT area.zone_name, area.area_name, area.min_lvl, area.max_lvl, area.room_id, COUNT(room.room_id) AS room_count
				FROM area
				LEFT JOIN room USING(zone_name)
				WHERE zone_name = %s
				GROUP BY zone_name
			) 
			JOIN
			(
				SELECT area.zone_name, COUNT(DISTINCT mob.mob_name) AS mob_count
				FROM area
				LEFT JOIN mob USING(zone_name)
				WHERE zone_name = %s
				GROUP BY zone_name
			)
			USING (zone_name);
		]];
		
		sql = sql:format(fixsql(zoneName), fixsql(zoneName));

		local areas = database.mobber:gettable(sql);
		
		if (next(areas)) then
			display.printAreas(areas);
		end
		
		utility.print("Found " .. #areas .. " area(s) in the mobber database with the name: " .. zoneName, "lime");
	else
		utility.print("GMCP error retrieving zone.");
	end
end

function database.updateAreaId()
	if (database.isDeveloperModeEnabled()) then
		local roomId = utility.gmcp.getPlayerRoomId();
		local zoneName = utility.gmcp.getPlayerZone();
		
		if (roomId and zoneName ~= "") then
			local sql = [[
				UPDATE area
				SET room_id = %d
				WHERE zone_name = %s;
			]];
						
			sql = sql:format(roomId, fixsql(zoneName));
			
			database.mobber:exec(sql, true);
			
			local numChanges = database.mobber:changes();
			
			if (numChanges == 1) then
				utility.print(zoneName .. " roomid set to: " .. roomId, "lime");
			elseif (numChanges == 0) then
				utility.print(
				zoneName .. " was not found in the mobber database.\r\n" ..
				"Possible solutions:\r\n" ..
				"Add area to the database with the 'mobber addarea <minLvl> <maxLvl>' command.",
				"red"
				);
			end
		else
			utility.print("GMCP error updating zone id.");
		end
	end
end

function database.updateRemoteAreaId(name, line, wildcards)
	if (not database.isDeveloperModeEnabled()) then
		return
	end
	local roomId = wildcards.roomid;
	local zoneName = wildcards.area;
	if not roomId or roomId == "" or not zoneName or zoneName == "" then
		utility.print("GMCP error updating zone id. roomId=" .. roomId .. ", area=" .. zoneName);
		return
	end

	local sql = [[
		UPDATE area
		SET room_id = %d
		WHERE zone_name = %s;
	]];
				
	sql = sql:format(roomId, fixsql(zoneName));

	database.mobber:exec(sql, true);
	
	local numChanges = database.mobber:changes();
	
	if (numChanges == 1) then
		utility.print(zoneName .. " roomid set to: " .. roomId, "lime");
	elseif (numChanges == 0) then
		utility.print(
		zoneName .. " was not found in the mobber database.\r\n" ..
		"Possible solutions:\r\n" ..
		"Add area to the database with the 'mobber addarea <minLvl> <maxLvl>' command.",
		"red"
		);
	end
end

function database.updateAreaLevelRange(name, line, wildcards)
	if (database.isDeveloperModeEnabled()) then
		local minLvl = tonumber(wildcards.min_lvl);
		local maxLvl = tonumber(wildcards.max_lvl);
		
		if (minLvl > maxLvl) then
			return utility.print("Max level must be greater than or equal to min level.", "yellow");
		end
		
		local zoneName = utility.gmcp.getPlayerZone();
		
		if (zoneName ~= "") then
			local sql = [[
				UPDATE area
				SET min_lvl = %d, max_lvl = %d
				WHERE zone_name = %s;
			]];
			
			sql = sql:format(minLvl, maxLvl, fixsql(zoneName));
			
			database.mobber:exec(sql, true);
			
			local numChanges = database.mobber:changes();
			
			if (numChanges == 1) then
				utility.print(zoneName .. " level range set to: " .. minLvl .. " - " .. maxLvl .. ".", "lime");
			elseif (numChanges == 0) then
				utility.print("The zone " .. zoneName .. " was not found in the mobber database.", "yellow");
			end
		else
			utility.print("GMCP error retrieving zone.");
		end
	end
end

function database.updateNotes()
	if (not database.isDeveloperModeEnabled()) then
		return
	end
	local start = GetInfo(232);

	local sql = [[
		ATTACH DATABASE %s AS 'aardwolf';
	]];
	
	sql = sql:format(fixsql(GetInfo(68) .. "Aardwolf.db"));
	
	database.mobber:exec(sql, true);
	
	sql = [[
		UPDATE room
		SET notes = (
			SELECT aardwolf.bookmarks.notes 
			FROM aardwolf.bookmarks
			WHERE aardwolf.bookmarks.uid = room.room_id);
	]];
	
	database.mobber:exec(sql, true);
	
	local numChanges = database.mobber:changes();
	
	sql = [[
		DETACH DATABASE 'aardwolf';
	]];
	
	database.mobber:exec(sql, true);

	local dif = GetInfo(232) - start;
	
	utility.print(numChanges .. " notes(s) imported from Aardwolf.db\r\nNote update completed in: " .. formatSeconds(dif), "lime");
end

function database.updateRooms()
	if (database.isDeveloperModeEnabled()) then
		local start = GetInfo(232);

		local sql = [[
			ATTACH DATABASE %s AS 'aardwolf';
		]];
		
		sql = sql:format(fixsql(GetInfo(68) .. "Aardwolf.db"));
		
		database.mobber:exec(sql, true);
		
		sql = [[
			INSERT OR IGNORE INTO room('room_name', 'room_id', 'zone_name')
			SELECT name, CAST(uid AS INTEGER), area
			FROM aardwolf.rooms
			WHERE EXISTS (SELECT * FROM area WHERE aardwolf.rooms.area = area.zone_name);
		]];
		
		database.mobber:exec(sql, true);
		
		local numChanges = database.mobber:changes();
		
		sql = [[
			DETACH DATABASE 'aardwolf';
		]];
		
		database.mobber:exec(sql, true);

		local dif = GetInfo(232) - start;
		
		utility.print(numChanges .. " room(s) imported from Aardwolf.db\r\nRoom update completed in: " .. formatSeconds(dif), "lime");
	end
end

function database.checkCreateTables()
	local sql = [[
		CREATE TABLE IF NOT EXISTS `area` (
			`zone_name`	TEXT NOT NULL UNIQUE,
			`area_name`	TEXT NOT NULL,
			`min_lvl`	INTEGER NOT NULL,
			`max_lvl`	INTEGER NOT NULL,
			`room_id`	INTEGER NOT NULL,
			PRIMARY KEY(`zone_name`)
		);
		
		CREATE TABLE IF NOT EXISTS `room` (
			`room_name`	TEXT NOT NULL,
			`room_id`	INTEGER NOT NULL UNIQUE,
			`zone_name`	TEXT NOT NULL,
			`notes`		TEXT,
			FOREIGN KEY(`zone_name`) REFERENCES `area`(`zone_name`) ON DELETE CASCADE,
			PRIMARY KEY(`room_id`)
		);
		
		CREATE TABLE IF NOT EXISTS `mob` (
			`mob_name`	TEXT NOT NULL COLLATE NOCASE,
			`room_name`	TEXT NOT NULL,
			`room_id`	INTEGER NOT NULL,
			`zone_name`	TEXT NOT NULL,
			`mob_priority`	INTEGER NOT NULL,
			`room_priority`	INTEGER NOT NULL DEFAULT 0,
			`area_mob_priority` INTEGER NOT NULL DEFAULT 0,
			FOREIGN KEY(`room_id`) REFERENCES `room`(`room_id`) ON DELETE CASCADE,
			FOREIGN KEY(`zone_name`) REFERENCES `area`(`zone_name`) ON DELETE CASCADE,
			PRIMARY KEY(`mob_name`,`room_id`)
		);
		
		CREATE TABLE IF NOT EXISTS `keyword` (
			`mob_name`	TEXT NOT NULL UNIQUE COLLATE NOCASE,
			`mob_keyword`	TEXT NOT NULL,
			PRIMARY KEY(`mob_name`)
		);
		
		CREATE INDEX IF NOT EXISTS `idx_area_an_zn_rid` ON `area` (
			`area_name`,
			`zone_name`,
			`room_id`
		);
		
		CREATE INDEX IF NOT EXISTS `idx_room_rn_zn_rid` ON `room` (
			`room_name`,
			`zone_name`,
			`room_id`
		);
	]];
	
	database.mobber:exec(sql);
end

function database.updateAreas()
	if (database.isDeveloperModeEnabled()) then
		local start = GetInfo(232);
	
		local zones = {
			["aardington"] = 	{ area_name = "Aardington Estate", room_id = 47509, min_lvl = 70, max_lvl = 90 },
			["abend"] = 		{ area_name = "The Dark Continent, Abend", room_id = 24909, min_lvl = 1, max_lvl = 201 },
			["academy"] = 		{ area_name = "The Aylorian Academy", room_id = 35233, min_lvl = 1, max_lvl = 15 },
			["adaldar"] = 		{ area_name = "Battlefields of Adaldar", room_id = 34400, min_lvl = 150, max_lvl = 175 },
			["afterglow"] = 	{ area_name = "Afterglow", room_id = 38134, min_lvl = 190, max_lvl = 201 },
			["agroth"] = 		{ area_name = "The Marshlands of Agroth", room_id = 11027, min_lvl = 105, max_lvl = 125 },
			["ahner"] = 		{ area_name = "Kingdom of Ahner", room_id = 30129, min_lvl = 20, max_lvl = 50 },
			["alagh"] = 		{ area_name = "Alagh, the Blood Lands", room_id = 3224, min_lvl = 1, max_lvl = 201 },
			["alehouse"] = 		{ area_name = "Wayward Alehouse", room_id = 885, min_lvl = 75, max_lvl = 90 },
			["amazon"] = 		{ area_name = "The Amazon Nation", room_id = 1409, min_lvl = 120, max_lvl = 201 },
			["amazonclan"] = 	{ area_name = "The Ivory City", room_id = 34212, min_lvl = 210, max_lvl = 210 },
			["amusement"] = 	{ area_name = "The Amusement Park", room_id = 29282, min_lvl = 1, max_lvl = 20 },
			["andarin"] = 		{ area_name = "The Blighted Tundra of Andarin", room_id = 2399, min_lvl = 35, max_lvl = 60 },
			["annwn"] = 		{ area_name = "Annwn", room_id = 28963, min_lvl = 160, max_lvl = 186 },
			["anthrox"] = 		{ area_name = "Anthrox", room_id = 3993, min_lvl = 80, max_lvl = 105 },
			["arboretum"] = 	{ area_name = "Arboretum", room_id = 39100, min_lvl = 110, max_lvl = 130 },
			["arena"] = 		{ area_name = "The Gladiator's Arena", room_id = 25768, min_lvl = 90, max_lvl = 105 },
			["arisian"] = 		{ area_name = "Arisian Realm", room_id = 28144, min_lvl = 150, max_lvl = 170 },
			["ascent"] = 		{ area_name = "The First Ascent", room_id = 43161, min_lvl = 1, max_lvl = 15 },
			["asherodan"] =     { area_name = "The Keep of the Asherodan", room_id = 37400, min_lvl = 80, max_lvl = 90 },
			["astral"] = 		{ area_name = "The Astral Travels", room_id = 27882, min_lvl = 180, max_lvl = 201 },
			["atlantis"] = 		{ area_name = "Atlantis", room_id = 10573, min_lvl = 20, max_lvl = 40 },
			["autumn"] = 		{ area_name = "Eternal Autumn", room_id = 13839, min_lvl = 170, max_lvl = 201 },
			["avian"] = 		{ area_name = "Avian Kingdom", room_id = 4334, min_lvl = 170, max_lvl = 186 },
			["aylor"] = 		{ area_name = "The Grand City of Aylor", room_id = 32418, min_lvl = 1, max_lvl = 201 },
			["badtrip"] = 		{ area_name = "A Bad Trip", room_id = 32877, min_lvl = 210, max_lvl = 210 },
			["bard"] = 			{ area_name = "The Bard Clan", room_id = 30538, min_lvl = 1, max_lvl = 201 },
			["bazaar"] = 		{ area_name = "Onyx Bazaar", room_id = 34454, min_lvl = 30, max_lvl = 85 },
			["beer"] = 			{ area_name = "The Land of the Beer Goblins", room_id = 20062, min_lvl = 1, max_lvl = 20 },
			["believer"] = 		{ area_name = "The Path of the Believer", room_id = 25940, min_lvl = 1, max_lvl = 10 },
			["birthday"] = 		{ area_name = "Aardwolf Birthday Area", room_id = 10920, min_lvl = 210, max_lvl = 210 },
			["blackclaw"] =     { area_name = "Black Claw Crag", room_id = 55009, min_lvl = 201, max_lvl = 201 },
			["blackrose"] = 	{ area_name = "Black Rose", room_id = 1817, min_lvl = 175, max_lvl = 201 },
			["bliss"] = 		{ area_name = "Wedded Bliss", room_id = 29988, min_lvl = 80, max_lvl = 100 },
			["bonds"] = 		{ area_name = "Unearthly Bonds", room_id = 23411, min_lvl = 140, max_lvl = 170 },
			["bootcamp"] = 		{ area_name = "The Boot Camp", room_id = 49256, min_lvl = 1, max_lvl = 201 },
			["cabal"] = 		{ area_name = "Cathedral of the Elements", room_id = 15704, min_lvl = 1, max_lvl = 201 },
			["caldera"] = 		{ area_name = "The Icy Caldera of Mauldoon", room_id = 26341, min_lvl = 190, max_lvl = 201 },
			["callhero"] = 		{ area_name = "The Call of Heroes", room_id = 33031, min_lvl = 1, max_lvl = 15 },
			["camps"] = 		{ area_name = "Tournament Camps", room_id = 4714, min_lvl = 1, max_lvl = 15 },
			["canyon"] = 		{ area_name = "Canyon Memorial Hospital", room_id = 25551, min_lvl = 1, max_lvl = 30 },
			["caravan"] = 		{ area_name = "Wayfarer's Caravan", room_id = 16071, min_lvl = 190, max_lvl = 201 },
			["cards"] = 		{ area_name = "House of Cards", room_id = 6255, min_lvl = 120, max_lvl = 160 },
			["carnivale"] = 	{ area_name = "Olde Worlde Carnivale", room_id = 28635, min_lvl = 1, max_lvl = 35 },
			["cataclysm"] = 	{ area_name = "The Cataclysm", room_id = 19976, min_lvl = 145, max_lvl = 201 },
			["cathedral"] = 	{ area_name = "The Old Cathedral", room_id = 27497, min_lvl = 50, max_lvl = 80 },
			["cats"] = 			{ area_name = "Sheila's Cat Sanctuary", room_id = 40900, min_lvl = 1, max_lvl = 35 },
			["chaos"] = 		{ area_name = "The Realm of Chaos", room_id = 28909, min_lvl = 1, max_lvl = 201 },
			["chasm"] = 		{ area_name = "The Chasm and The Catacombs", room_id = 29446, min_lvl = 1, max_lvl = 25 },
			["chessboard"] = 	{ area_name = "The Chessboard", room_id = 25513, min_lvl = 1, max_lvl = 20 },
			["childsplay"] = 	{ area_name = "Child's Play", room_id = 678, min_lvl = 1, max_lvl = 25 },
			["cineko"] = 		{ area_name = "Aerial City of Cineko", room_id = 1507, min_lvl = 1, max_lvl = 30 },
			["citadel"] = 		{ area_name = "The Flying Citadel", room_id = 14963, min_lvl = 40, max_lvl = 65 },
			["conflict"] = 		{ area_name = "Thandeld's Conflict", room_id = 27711, min_lvl = 1, max_lvl = 50 },
			["coral"] = 		{ area_name = "The Coral Kingdom", room_id = 4565, min_lvl = 1, max_lvl = 50 },
			["cougarian"] = 	{ area_name = "The Cougarian Queendom", room_id = 14311, min_lvl = 140, max_lvl = 170 },
			["cove"] = 			{ area_name = "Kiksaadi Cove", room_id = 49941, min_lvl = 190, max_lvl = 201 },
			["cradle"] = 		{ area_name = "Cradlebrook", room_id = 11267, min_lvl = 30, max_lvl = 50 },
			["crimson"] = 		{ area_name = "The Crimson Horde Clan Hall", room_id = 27989, min_lvl = 1, max_lvl = 201 },
			["crusaders"] = 	{ area_name = "The Crusader Clan", room_id = 31122, min_lvl = 1, max_lvl = 201 },
			["crynn"] = 		{ area_name = "Crynn's Church", room_id = 43800, min_lvl = 190, max_lvl = 201 },
			["damned"] = 		{ area_name = "Halls of the Damned", room_id = 10469, min_lvl = 95, max_lvl = 115 },
			["daoine"] = 		{ area_name = "The Underground Hall", room_id = 30949, min_lvl = 1, max_lvl = 201 },
			["darklight"] = 	{ area_name = "The DarkLight", room_id = 19642, min_lvl = 60, max_lvl = 120 },
			["darkside"] = 		{ area_name = "The Darkside of the Fractured Lands", room_id = 15060, min_lvl = 35, max_lvl = 60 },
			["ddoom"] = 		{ area_name = "Desert Doom", room_id = 4193, min_lvl = 135, max_lvl = 150 },
			["deadlights"] = 	{ area_name = "The Deadlights", room_id = 16856, min_lvl = 175, max_lvl = 201 },
			["deathtrap"] = 	{ area_name = "Deathtrap Dungeon", room_id = 1767, min_lvl = 85, max_lvl = 120 },
			["deneria"] = 		{ area_name = "Realm of Deneria", room_id = 35006, min_lvl = 60, max_lvl = 80 },
			["desert"] = 		{ area_name = "The Desert Prison", room_id = 20186, min_lvl = 130, max_lvl = 201 },
			["desolation"] = 	{ area_name = "The Mountains of Desolation", room_id = 19532, min_lvl = 130, max_lvl = 180 },
			["dhalgora"] = 		{ area_name = "Dhal'Gora Outlands", room_id = 16755, min_lvl = 1, max_lvl = 50 },
			["diatz"] = 		{ area_name = "The Three Pillars of Diatz", room_id = 1254, min_lvl = 60, max_lvl = 80 },
			["diner"] = 		{ area_name = "Tumari's Diner", room_id = 36700, min_lvl = 130, max_lvl = 140 },
			["doh"] = 			{ area_name = "Disciples of Hassan Clan Hall", room_id = 16803, min_lvl = 1, max_lvl = 201 },
			["dominion"] = 		{ area_name = "Dominion Clan Area", room_id = 5863, min_lvl = 1, max_lvl = 201 },
			["dortmund"] = 		{ area_name = "Dortmund", room_id = 16577, min_lvl = 1, max_lvl = 25 },
			["drageran"] = 		{ area_name = "The Drageran Empire", room_id = 25894, min_lvl = 125, max_lvl = 150 },
			["dragon"] = 		{ area_name = "The White Dragon Clan", room_id = 642, min_lvl = 1, max_lvl = 201 },
			["dread"] = 		{ area_name = "Dread Tower", room_id = 26075, min_lvl = 160, max_lvl = 201 },
			["druid"] = 		{ area_name = "Isle of Anglesey", room_id = 29582, min_lvl = 1, max_lvl = 201 },
			["dsr"] = 			{ area_name = "Diamond Soul Revelation", room_id = 30030, min_lvl = 35, max_lvl = 90 },
			["dundoom"] = 		{ area_name = "The Dungeon of Doom", room_id = 25661, min_lvl = 190, max_lvl = 201 },
			["dungeon"] =       { area_name = "Bloodlust Dungeon", room_id = 45933, min_lvl = 201, max_lvl = 201 },
			["dunoir"] = 		{ area_name = "Mount duNoir", room_id = 14222, min_lvl = 175, max_lvl = 201 },
			["duskvalley"] = 	{ area_name = "Dusk Valley", room_id = 37301, min_lvl = 100, max_lvl = 120 },
			["dynasty"] = 		{ area_name = "The Eighteenth Dynasty", room_id = 30799, min_lvl = 120, max_lvl = 140 },
			["earthlords"] = 	{ area_name = "The Earth Lords", room_id = 42000, min_lvl = 190, max_lvl = 201 },
			["earthplane"] = 	{ area_name = "Earth Plane 4", room_id = 1354, min_lvl = 50, max_lvl = 80 },
			["elemental"] = 	{ area_name = "Elemental Chaos", room_id = 41624, min_lvl = 90, max_lvl = 150 },
			["emerald"] = 		{ area_name = "The Emerald Clan HQ", room_id = 831, min_lvl = 1, max_lvl = 201 },
			["empire"] = 		{ area_name = "The Empire of Aiighialla", room_id = 32203, min_lvl = 150, max_lvl = 186 },
			["empyrean"] = 		{ area_name = "Empyrean, Streets of Downfall", room_id = 14042, min_lvl = 170, max_lvl = 201 },
			["entropy"] = 		{ area_name = "The Archipelago of Entropy", room_id = 29773, min_lvl = 120, max_lvl = 145 },
			["fantasy"] = 		{ area_name = "Fantasy Fields", room_id = 15205, min_lvl = 1, max_lvl = 30 },
			["farm"] = 			{ area_name = "Kimr's Farm", room_id = 10676, min_lvl = 1, max_lvl = 10 },
			["fayke"] = 		{ area_name = "All in a Fayke Day", room_id = 30418, min_lvl = 1, max_lvl = 30 },
			["fens"] = 			{ area_name = "The Curse of the Midnight Fens", room_id = 16528, min_lvl = 190, max_lvl = 201 },
			["fields"] = 		{ area_name = "The Killing Fields", room_id = 29232, min_lvl = 60, max_lvl = 80 },
			["firebird"] = 		{ area_name = "Realm of the Firebird", room_id = 32885, min_lvl = 80, max_lvl = 110 },
			["firenation"] = 	{ area_name = "Realm of the Sacred Flame", room_id = 41879, min_lvl = 190, max_lvl = 201 },
			["fireswamp"] = 	{ area_name = "The Fire Swamp", room_id = 34755, min_lvl = 1, max_lvl = 15 },
			["fortress"] = 		{ area_name = "The Goblin Fortress", room_id = 31835, min_lvl = 60, max_lvl = 80 },
			["fortune"] = 		{ area_name = "Crossroads of Fortune", room_id = 38561, min_lvl = 201, max_lvl = 201 },
			["fractured"] = 	{ area_name = "The Fractured Lands", room_id = 17033, min_lvl = 20, max_lvl = 40 },
			["ft1"] = 			{ area_name = "Faerie Tales", room_id = 1205, min_lvl = 100, max_lvl = 120 },
			["ftii"] = 			{ area_name = "Faerie Tales II", room_id = 26673, min_lvl = 120, max_lvl = 140 },
			["gaardian"] = 		{ area_name = "Midgaardian Publishing House", room_id = 20026, min_lvl = 1, max_lvl = 201 },
			["gallows"] = 		{ area_name = "Gallows Hill", room_id = 4344, min_lvl = 1, max_lvl = 20 },
			["gathering"] = 	{ area_name = "The Gathering Horde", room_id = 36451, min_lvl = 140, max_lvl = 170 },
			["gauntlet"] = 		{ area_name = "The Gauntlet", room_id = 31652, min_lvl = 1, max_lvl = 30 },
			["gelidus"] = 		{ area_name = "Gelidus", room_id = 18780, min_lvl = 1, max_lvl = 201 },
			["geniewish"] = 	{ area_name = "A Genie's Last Wish", room_id = 38464, min_lvl = 201, max_lvl = 201 },
			["gilda"] = 		{ area_name = "Gilda And The Dragon", room_id = 4243, min_lvl = 120, max_lvl = 140 },
			["glamdursil"] = 	{ area_name = "The Glamdursil", room_id = 35055, min_lvl = 170, max_lvl = 201 },
			["glimmerdim"] = 	{ area_name = "Brightsea and Glimmerdim", room_id = 26252, min_lvl = 1, max_lvl = 40 },
			["gnomalin"] = 		{ area_name = "Cloud City of Gnomalin", room_id = 34397, min_lvl = 1, max_lvl = 35 },
			["goldrush"] = 		{ area_name = "Gold Rush", room_id = 15014, min_lvl = 30, max_lvl = 70 },
			["graveyard"] = 	{ area_name = "The Graveyard", room_id = 28918, min_lvl = 1, max_lvl = 15 },
			["greece"] = 		{ area_name = "Ancient Greece", room_id = 2089, min_lvl = 20, max_lvl = 55 },
			["gwillim"] = 		{ area_name = "The Trouble with Gwillimberry", room_id = 25974, min_lvl = 185, max_lvl = 201 },
			["hades"] = 		{ area_name = "Entrance to Hades", room_id = 29161, min_lvl = 180, max_lvl = 201 },
			["hatchling"] = 	{ area_name = "Hatchling Aerie", room_id = 34670, min_lvl = 1, max_lvl = 55 },
			["hawklord"] = 		{ area_name = "The Realm of the Hawklords", room_id = 40550, min_lvl = 80, max_lvl = 100 },
			["hedge"] = 		{ area_name = "Hedgehogs' Paradise", room_id = 15146, min_lvl = 60, max_lvl = 80 },
			["helegear"] = 		{ area_name = "Helegear Sea", room_id = 30699, min_lvl = 160, max_lvl = 180 },
			["hell"] = 			{ area_name = "Descent to Hell", room_id = 30984, min_lvl = 30, max_lvl = 85 },
			["hoard"] = 		{ area_name = "Swordbreaker's Hoard", room_id = 1675, min_lvl = 1, max_lvl = 60 },
			["hodgepodge"] = 	{ area_name = "A Magical Hodgepodge", room_id = 30469, min_lvl = 1, max_lvl = 35 },
			["horath"] = 		{ area_name = "The Broken Halls of Horath", room_id = 91, min_lvl = 120, max_lvl = 175 },
			["horizon"] = 		{ area_name = "Nebulous Horizon", room_id = 31959, min_lvl = 190, max_lvl = 201 },
			["icefall"] = 		{ area_name = "Icefall", room_id = 38701, min_lvl = 201, max_lvl = 201 },
			["illoria"] = 		{ area_name = "The Tournament of Illoria", room_id = 10420, min_lvl = 70, max_lvl = 90 },
			["imagi"] = 		{ area_name = "Imagi's Nation", room_id = 36800, min_lvl = 140, max_lvl = 160 },
			["immhomes"] =		{ area_name = "The Aardwolf Plaza Hotel", room_id = 26151, min_lvl = 0, max_lvl = 220 },
			["imperial"] = 		{ area_name = "Imperial Nation", room_id = 16966, min_lvl = 40, max_lvl = 201 },
			["imperium"] = 		{ area_name = "The Stronghold of the Imperium", room_id = 30415, min_lvl = 1, max_lvl = 201 },
			["infamy"] = 		{ area_name = "The Realm of Infamy", room_id = 26641, min_lvl = 190, max_lvl = 201 },
			["inferno"] = 		{ area_name = "Journey to the Inferno", room_id = 37213, min_lvl = 200, max_lvl = 201 },
			["infest"] = 		{ area_name = "The Infestation", room_id = 16165, min_lvl = 1, max_lvl = 35 },
			["insan"] = 		{ area_name = "Insanitaria", room_id = 6850, min_lvl = 95, max_lvl = 115 },
			["jenny"] = 		{ area_name = "Jenny's Tavern", room_id = 29637, min_lvl = 55, max_lvl = 100 },
			["jotun"] = 		{ area_name = "Jotunheim", room_id = 31508, min_lvl = 1, max_lvl = 40 },
			["kearvek"] = 		{ area_name = "The Keep of Kearvek", room_id = 29722, min_lvl = 180, max_lvl = 201 },
			["kerofk"] = 		{ area_name = "Kerofk", room_id = 16405, min_lvl = 1, max_lvl = 30 },
			["ketu"] = 			{ area_name = "Ketu Uplands", room_id = 35114, min_lvl = 190, max_lvl = 201 },
			["kingsholm"] = 	{ area_name = "Kingsholm", room_id = 27522, min_lvl = 1, max_lvl = 70 },
			["knossos"] = 		{ area_name = "The Great City of Knossos", room_id = 28193, min_lvl = 60, max_lvl = 80 },
			["kobaloi"] = 		{ area_name = "Keep of the Kobaloi", room_id = 10691, min_lvl = 1, max_lvl = 201 },
			["kultiras"] = 		{ area_name = "Kul Tiras", room_id = 31161, min_lvl = 1, max_lvl = 30 },
			["lab"] = 			{ area_name = "Chaprenula's Laboratory", room_id = 28684, min_lvl = 1, max_lvl = 15 },
			["labyrinth"] = 	{ area_name = "The Labyrinth", room_id = 31405, min_lvl = 30, max_lvl = 60 },
			["lagoon"] = 		{ area_name = "Black Lagoon", room_id = 30549, min_lvl = 155, max_lvl = 195 },
			["landofoz"] = 		{ area_name = "The Land of Oz", room_id = 510, min_lvl = 40, max_lvl = 75 },
			["laym"] = 			{ area_name = "Tai'rha Laym", room_id = 6005, min_lvl = 50, max_lvl = 120 },
			["legend"] = 		{ area_name = "Land of Legend", room_id = 16224, min_lvl = 1, max_lvl = 20 },
			["lemdagor"] = 		{ area_name = "Storm Ships of Lem-Dagor", room_id = 1966, min_lvl = 40, max_lvl = 100 },
			["lidnesh"] = 		{ area_name = "The Forest of Li'Dnesh", room_id = 27995, min_lvl = 1, max_lvl = 10 },
			["light"] = 		{ area_name = "The Order of Light", room_id = 2339, min_lvl = 1, max_lvl = 201 },
			["livingmine"] = 	{ area_name = "Living Mines of Dak'Tai", room_id = 37008, min_lvl = 110, max_lvl = 140 },
			["longnight"] = 	{ area_name = "Into the Long Night", room_id = 26367, min_lvl = 100, max_lvl = 201 },
			["loqui"] = 		{ area_name = "Loqui Clan Area", room_id = 28580, min_lvl = 1, max_lvl = 201 },
			["losttime"] = 		{ area_name = "Island of Lost Time", room_id = 28584, min_lvl = 80, max_lvl = 110 },
			["lowlands"] = 		{ area_name = "Lowlands Paradise '96", room_id = 28044, min_lvl = 1, max_lvl = 10 },
			["lplanes"] = 		{ area_name = "The Lower Planes", room_id = 29364, min_lvl = 70, max_lvl = 100 },
			["maelstrom"] = 	{ area_name = "The Maelstrom", room_id = 38058, min_lvl = 20, max_lvl = 45 },
			["manor"] = 		{ area_name = "Death's Manor", room_id = 10621, min_lvl = 20, max_lvl = 40 },
			["manor1"] = 		{ area_name = "The Aardwolf Real Estates", room_id = 14460, min_lvl = 1, max_lvl = 201 },
			["manor3"] = 		{ area_name = "Aardwolf Estates 2000", room_id = 20836, min_lvl = 1, max_lvl = 201 },
			["manorisle"] = 	{ area_name = "The Aardwolf Isle Estates", room_id = 6366, min_lvl = 1, max_lvl = 201 },
			["manormount"] = 	{ area_name = "Mountain View Estates", room_id = 39449, min_lvl = 1, max_lvl = 201 },
			["manorsea"] = 		{ area_name = "Seaside Height Estates", room_id = 35003, min_lvl = 1, max_lvl = 201 },
			["manorville"] = 	{ area_name = "Prairie Village Estates", room_id = 35004, min_lvl = 1, max_lvl = 201 },
			["manorwoods"] = 	{ area_name = "Shady Acres Estates", room_id = 35002, min_lvl = 1, max_lvl = 201 },
			["masaki"] = 		{ area_name = "Masaki Clan Area", room_id = 15852, min_lvl = 1, max_lvl = 201 },
			["masq"] = 			{ area_name = "Masquerade Island", room_id = 29840, min_lvl = 100, max_lvl = 130 },
			["mayhem"] = 		{ area_name = "Artificer's Mayhem", room_id = 1866, min_lvl = 180, max_lvl = 201 },
			["melody"] = 		{ area_name = "Art of Melody", room_id = 14172, min_lvl = 1, max_lvl = 15 },
			["mesolar"] = 		{ area_name = "The Continent of Mesolar", room_id = 12664, min_lvl = 1, max_lvl = 201 },
			["minos"] = 		{ area_name = "The Shadows of Minos", room_id = 20472, min_lvl = 1, max_lvl = 35 },
			["mistridge"] = 	{ area_name = "The Covenant of Mistridge", room_id = 4491, min_lvl = 160, max_lvl = 186 },
			["monastery"] = 	{ area_name = "The Monastery", room_id = 15756, min_lvl = 85, max_lvl = 115 },
			["mudwog"] = 		{ area_name = "Mudwog's Swamp", room_id = 2347, min_lvl = 30, max_lvl = 45 },
			["nanjiki"] = 		{ area_name = "Nanjiki Ruins", room_id = 11203, min_lvl = 140, max_lvl = 160 },
			["necro"] = 		{ area_name = "Necromancers' Guild", room_id = 29922, min_lvl = 1, max_lvl = 35 },
			["nenukon"] = 		{ area_name = "Nenukon and the Far Country", room_id = 31784, min_lvl = 70, max_lvl = 110 },
			["newthalos"] = 	{ area_name = "New Thalos", room_id = 23853, min_lvl = 1, max_lvl = 35 },
			["ninehells"] = 	{ area_name = "The Nine Hells", room_id = 4613, min_lvl = 190, max_lvl = 201 },
			["northstar"] = 	{ area_name = "Northstar", room_id = 11127, min_lvl = 70, max_lvl = 150 },
			["nottingham"] = 	{ area_name = "Nottingham", room_id = 11077, min_lvl = 190, max_lvl = 201 },
			["nulan"] = 		{ area_name = "Plains of Nulan'Boar", room_id = 37900, min_lvl = 60, max_lvl = 80 },
			["nursing"] = 		{ area_name = "Ascension Bluff Nursing Home", room_id = 31977, min_lvl = 100, max_lvl = 130 },
			["nynewoods"] = 	{ area_name = "The Nyne Woods", room_id = 23562, min_lvl = 190, max_lvl = 201 },
			["oceanpark"] = 	{ area_name = "Andolor's Ocean Adventure Park", room_id = 39600, min_lvl = 190, max_lvl = 201 },
			["omentor"] = 		{ area_name = "The Witches of Omen Tor", room_id = 15579, min_lvl = 160, max_lvl = 201 },
			["ooku"] = 			{ area_name = "Ookushka Garrison", room_id = 39000, min_lvl = 201, max_lvl = 201 },
			["oradrin"] = 		{ area_name = "Oradrin's Chosen", room_id = 25436, min_lvl = 201, max_lvl = 201 },
			["origins"] = 		{ area_name = "Tribal Origins", room_id = 35900, min_lvl = 175, max_lvl = 186 },
			["orlando"] = 		{ area_name = "Hotel Orlando", room_id = 30331, min_lvl = 1, max_lvl = 20 },
			["paradise"] = 		{ area_name = "Paradise Lost", room_id = 29624, min_lvl = 50, max_lvl = 70 },
			["partroxis"] = 	{ area_name = "The Partroxis", room_id = 5814, min_lvl = 180, max_lvl = 201 },
			["peninsula"] = 	{ area_name = "Tairayden Peninsula", room_id = 35701, min_lvl = 115, max_lvl = 125 },
			["perdition"] = 	{ area_name = "Perdition Clan Area", room_id = 19968, min_lvl = 1, max_lvl = 201 },
			["petstore"] = 		{ area_name = "Giant's Pet Store", room_id = 995, min_lvl = 1, max_lvl = 20 },
			["pompeii"] = 		{ area_name = "Pompeii", room_id = 57, min_lvl = 90, max_lvl = 110 },
			["promises"] = 		{ area_name = "Foolish Promises", room_id = 25819, min_lvl = 130, max_lvl = 140 },
			["prosper"] = 		{ area_name = "Prosper's Island", room_id = 28268, min_lvl = 100, max_lvl = 201 },
			["pyre"] = 			{ area_name = "Twilight Hall", room_id = 15141, min_lvl = 1, max_lvl = 201 },
			["qong"] = 			{ area_name = "Qong", room_id = 16115, min_lvl = 190, max_lvl = 201 },
			["quarry"] = 		{ area_name = "Gnoll's Quarry", room_id = 23510, min_lvl = 105, max_lvl = 125 },
			["radiance"] = 		{ area_name = "Radiance Woods", room_id = 19805, min_lvl = 190, max_lvl = 201 },
			["raga"] = 			{ area_name = "Raganatittu", room_id = 19861, min_lvl = 40, max_lvl = 60 },
			["raukora"] = 		{ area_name = "The Blood Opal of Rauko'ra", room_id = 6040, min_lvl = 130, max_lvl = 201 },
			["rebellion"] = 	{ area_name = "Rebellion of the Nix", room_id = 10305, min_lvl = 150, max_lvl = 201 },
			["remcon"] = 		{ area_name = "The Reman Conspiracy", room_id = 25837, min_lvl = 130, max_lvl = 201 },
			["reme"] = 			{ area_name = "The Imperial City of Reme", room_id = 32703, min_lvl = 20, max_lvl = 150 },
			["romani"] = 		{ area_name = "A Clearing in the Woods", room_id = 24180, min_lvl = 1, max_lvl = 201 },
			["rosewood"] = 		{ area_name = "Rosewood Castle", room_id = 6901, min_lvl = 65, max_lvl = 150 },
			["ruins"] = 		{ area_name = "The Ruins of Diamond Reach", room_id = 16805, min_lvl = 60, max_lvl = 125 },
			["sagewood"] = 		{ area_name = "Sagewood Grove", room_id = 28754, min_lvl = 145, max_lvl = 195 },
			["sahuagin"] = 		{ area_name = "The Abyssal Caverns of Sahuagin", room_id = 34592, min_lvl = 140, max_lvl = 160 },
			["salt"] = 			{ area_name = "The Great Salt Flats", room_id = 4538, min_lvl = 40, max_lvl = 75 },
			["sanctity"] = 		{ area_name = "Sanctity of Eternal Damnation", room_id = 10518, min_lvl = 100, max_lvl = 201 },
			["sanctum"] = 		{ area_name = "The Blood Sanctum", room_id = 15307, min_lvl = 180, max_lvl = 201 },
			["sandcastle"] = 	{ area_name = "Sho'aram, Castle in the Sand", room_id = 37701, min_lvl = 1, max_lvl = 30 },
			["sanguine"] = 		{ area_name = "The Sanguine Tavern", room_id = 15436, min_lvl = 120, max_lvl = 150 },
			["scarred"] = 		{ area_name = "The Scarred Lands", room_id = 34036, min_lvl = 90, max_lvl = 110 },
			["seaking"] = 		{ area_name = "Sea King's Dominion", room_id = 145, min_lvl = 210, max_lvl = 210 },
			["seekers"] = 		{ area_name = "The Fortress of Knowledge", room_id = 14165, min_lvl = 1, max_lvl = 201 },
			["sendhian"] = 		{ area_name = "Adventures in Sendhia", room_id = 20288, min_lvl = 1, max_lvl = 60 },
			["sennarre"] = 		{ area_name = "Sen'narre Lake", room_id = 15491, min_lvl = 1, max_lvl = 20 },
			["shadokil"] = 		{ area_name = "The Shadokil Guildhouse", room_id = 32407, min_lvl = 1, max_lvl = 201 },
			["shouggoth"] = 	{ area_name = "The Temple of Shouggoth", room_id = 34087, min_lvl = 1, max_lvl = 65 },
			["siege"] = 		{ area_name = "Kobold Siege Camp", room_id = 43265, min_lvl = 80, max_lvl = 100 },
			["sirens"] = 		{ area_name = "Siren's Oasis Resort", room_id = 16298, min_lvl = 1, max_lvl = 15 },
			["slaughter"] = 	{ area_name = "The Slaughter House", room_id = 1601, min_lvl = 120, max_lvl = 145 },
			["snuckles"] = 		{ area_name = "Snuckles Village", room_id = 182, min_lvl = 80, max_lvl = 100 },
			["soh"] = 			{ area_name = "The School of Horror", room_id = 25611, min_lvl = 125, max_lvl = 201 },
			["sohtwo"] = 		{ area_name = "The School of Horror", room_id = 30752, min_lvl = 165, max_lvl = 201 },
			["solan"] = 		{ area_name = "The Town of Solan", room_id = 23713, min_lvl = 1, max_lvl = 35 },
			["songpalace"] = 	{ area_name = "The Palace of Song", room_id = 47013, min_lvl = 60, max_lvl = 80 },
			["southern"] = 		{ area_name = "The Southern Ocean", room_id = 5192, min_lvl = 1, max_lvl = 201 },
			["spyreknow"] = 	{ area_name = "Guardian's Spyre of Knowledge", room_id = 34800, min_lvl = 1, max_lvl = 30 },
			["stone"] = 		{ area_name = "The Fabled City of Stone", room_id = 11386, min_lvl = 70, max_lvl = 135 },
			["storm"] = 		{ area_name = "Storm Mountain", room_id = 6304, min_lvl = 1, max_lvl = 40 },
			["stormhaven"] = 	{ area_name = "The Ruins of Stormhaven", room_id = 20649, min_lvl = 150, max_lvl = 201 },
			["stronghold"] = 	{ area_name = "Dark Elf Stronghold", room_id = 20572, min_lvl = 70, max_lvl = 125 },
			["stuff"] = 		{ area_name = "The Stuff of Shadows", room_id = 40400, min_lvl = 110, max_lvl = 130 },
			["takeda"] = 		{ area_name = "Takeda's Warcamp", room_id = 15952, min_lvl = 140, max_lvl = 201 },
			["talsa"] = 		{ area_name = "The Empire of Talsa", room_id = 26917, min_lvl = 65, max_lvl = 140 },
			["tanelorn"] = 		{ area_name = "The Legendary City of Tanelorn", room_id = 31561, min_lvl = 1, max_lvl = 201 },
			["tanra"] = 		{ area_name = "Tanra'vea", room_id = 46913, min_lvl = 180, max_lvl = 201 },
			["tao"] = 			{ area_name = "The Collective Mind of Tao", room_id = 29210, min_lvl = 1, max_lvl = 201 },
			["temple"] = 		{ area_name = "The Temple of Shal'indrael", room_id = 31597, min_lvl = 180, max_lvl = 201 },
			["terra"] = 		{ area_name = "The Cracks of Terra", room_id = 19679, min_lvl = 190, max_lvl = 201 },
			["terramire"] = 	{ area_name = "Fort Terramire", room_id = 4493, min_lvl = 1, max_lvl = 35 },
			["thieves"] = 		{ area_name = "Den of Thieves", room_id = 7, min_lvl = 1, max_lvl = 20 },
			["tilule"] = 		{ area_name = "Tilule Rehabilitation Clinic", room_id = 39771, min_lvl = 50, max_lvl = 80 },
			["times"] = 		{ area_name = "Intrigues of Times Past", room_id = 28463, min_lvl = 180, max_lvl = 201 },
			["tirna"] = 		{ area_name = "Tir na nOg", room_id = 20136, min_lvl = 130, max_lvl = 150 },
			["titan"] = 		{ area_name = "The Titans' Keep", room_id = 38234, min_lvl = 190, max_lvl = 201 },
			["tol"] = 			{ area_name = "The Tree of Life", room_id = 16325, min_lvl = 175, max_lvl = 201 },
			["tombs"] = 		{ area_name = "The Relinquished Tombs", room_id = 15385, min_lvl = 45, max_lvl = 100 },
			["touchstone"] = 	{ area_name = "Touchstone Cavern", room_id = 28346, min_lvl = 1, max_lvl = 201 },
			["twinlobe"] = 		{ area_name = "The Twinlobe Clan HQ", room_id = 15575, min_lvl = 1, max_lvl = 201 },
			["umari"] = 		{ area_name = "Umari's Castle", room_id = 36601, min_lvl = 190, max_lvl = 201 },
			["uncharted"] = 	{ area_name = "The Uncharted Oceans", room_id = 7701, min_lvl = 1, max_lvl = 201 },
			["underdark"] = 	{ area_name = "The UnderDark", room_id = 27341, min_lvl = 1, max_lvl = 50 },
			["uplanes"] = 		{ area_name = "The Upper Planes", room_id = 29365, min_lvl = 60, max_lvl = 85 },
			["uprising"] = 		{ area_name = "The Uprising", room_id = 15382, min_lvl = 120, max_lvl = 160 },
			["vale"] = 			{ area_name = "Sundered Vale", room_id = 1036, min_lvl = 1, max_lvl = 30 },
			["vanir"] = 		{ area_name = "The Halls of Vanir", room_id = 878, min_lvl = 1, max_lvl = 201 },
			["verdure"] = 		{ area_name = "Verdure Estate", room_id = 24090, min_lvl = 120, max_lvl = 140 },
			["verume"] = 		{ area_name = "Jungles of Verume", room_id = 30607, min_lvl = 1, max_lvl = 40 },
			["vidblain"] = 		{ area_name = "Vidblain, the Ever Dark", room_id = 33570, min_lvl = 1, max_lvl = 201 },
			["village"] = 		{ area_name = "A Peaceful Giant Village", room_id = 30850, min_lvl = 135, max_lvl = 170 },
			["vlad"] = 			{ area_name = "Castle Vlad-Shamir", room_id = 15970, min_lvl = 50, max_lvl = 100 },
			["volcano"] = 		{ area_name = "The Silver Volcano", room_id = 6091, min_lvl = 30, max_lvl = 100 },
			["watchmen"] = 		{ area_name = "The World of the Watchmen", room_id = 32342, min_lvl = 1, max_lvl = 201 },
			["weather"] = 		{ area_name = "Weather Observatory", room_id = 40499, min_lvl = 20, max_lvl = 40 },
			["werewood"] = 		{ area_name = "The Were Wood", room_id = 30956, min_lvl = 190, max_lvl = 201 },
			["wildwood"] = 		{ area_name = "Wildwood", room_id = 322, min_lvl = 1, max_lvl = 40 },
			["winds"] = 		{ area_name = "Winds of Fate", room_id = 39900, min_lvl = 201, max_lvl = 201 },
			["winter"] = 		{ area_name = "Winterlands", room_id = 1306, min_lvl = 150, max_lvl = 170 },
			["wizards"] = 		{ area_name = "War of the Wizards", room_id = 31316, min_lvl = 1, max_lvl = 35 },
			["wonders"] = 		{ area_name = "Seven Wonders", room_id = 32981, min_lvl = 100, max_lvl = 120 },
			["wooble"] = 		{ area_name = "The Wobbly Woes of Woobleville", room_id = 11335, min_lvl = 40, max_lvl = 60 },
			["woodelves"] = 	{ area_name = "The Wood Elves of Nalondir", room_id = 32199, min_lvl = 1, max_lvl = 30 },
			["wtc"] = 			{ area_name = "Warrior's Training Camp", room_id = 37895, min_lvl = 1, max_lvl = 15 },
			["wyrm"] = 			{ area_name = "The Council of the Wyrm", room_id = 28847, min_lvl = 190, max_lvl = 201 },
			["xmas"] = 			{ area_name = "Christmas Vacation", room_id = 6212, min_lvl = 110, max_lvl = 150 },
			["xylmos"] = 		{ area_name = "Xyl's Mosaic", room_id = 472, min_lvl = 100, max_lvl = 120 },
			["yarr"] = 			{ area_name = "The Misty Shores of Yarr", room_id = 30281, min_lvl = 115, max_lvl = 135 },
			["ygg"] = 			{ area_name = "Yggdrasil: The World Tree", room_id = 24186, min_lvl = 180, max_lvl = 201 },
			["yurgach"] = 		{ area_name = "The Yurgach Domain", room_id = 29450, min_lvl = 35, max_lvl = 110 },
			["zangar"] = 		{ area_name = "Zangar's Demonic Grotto", room_id = 6164, min_lvl = 40, max_lvl = 60 },
			["zodiac"] = 		{ area_name = "Realm of the Zodiac", room_id = 15857, min_lvl = 1, max_lvl = 45 },
			["zoo"] = 			{ area_name = "Aardwolf Zoological Park", room_id = 5920, min_lvl = 1, max_lvl = 35 },
			["zyian"] = 		{ area_name = "The Dark Temple of Zyian", room_id = 729, min_lvl = 120, max_lvl = 150 },
		};
		
		local sql = [[
			INSERT OR IGNORE INTO area VALUES(%s, %s, %d, %d, %d);
		]];
		
		database.mobber:exec("BEGIN TRANSACTION;", true);
		
		local numChanges = 0;
		
		for k,v in pairs(zones) do
			local stmt = sql:format(fixsql(k), fixsql(v.area_name), v.min_lvl, v.max_lvl, v.room_id);
			database.mobber:exec(stmt);
			numChanges = numChanges + database.mobber:changes();
		end
			
		database.mobber:exec("END TRANSACTION;", true);
		
		local dif = GetInfo(232) - start;
		
		utility.print(numChanges .. " area(s) added to the mobber database.\r\nAreas update completed in: " .. formatSeconds(dif), "lime");
	end
end

----------------------------------
-- Utility
----------------------------------

utility = {};

function utility.initialize()
	AddAlias("alias_utility_help_main", "^(?:mobber help|help mobber)$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"utility.help.main"
	);
	
	AddAlias("alias_utility_help_quests", "^mobber help quests?$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"utility.help.quests"
	);
	
	AddAlias("alias_utility_help_searching", "^mobber help search(?:ing)?$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"utility.help.searching"
	);
	
	AddAlias("alias_utility_help_utils", "^mobber help (?:utils?|utility)$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"utility.help.utils"
	);
	
	AddAlias("alias_utility_help_developer", "^mobber help dev(?:eloper)?$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"utility.help.developer"
	);

	AddAlias("alias_utility_help_igo", "^mobber help igo$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"utility.help.igo"
	);

	local initializers = {
		database.initialize,
		campaign.initialize,
		globalQuest.initialize,
		roomHandler.initialize,
		roomSearch.initialize,
		mobSearch.initialize,
		quickScan.initialize,
		quickWhere.initialize,
		autoHunt.initialize,
		huntTrick.initialize,
		autoKill.initialize,
		noexp.initialize,
		quest.initialize,
		colorPalette.initialize,
		igo.initialize
	};
	
	for k,v in ipairs(initializers) do
		v();
	end
	
	if (var.isQuestMuted == "false") then
		quest.isMuted = false;
	else
		quest.isMuted = true;
	end
	
	database.openDatabase();
	OnPluginListChanged()
end

function utility.deinitialize()
	local aliases = GetAliasList();
	
	if (aliases) then
		for i = 1, #aliases do
			EnableAlias(aliases[i], false);
			DeleteAlias(aliases[i]);
		end
	end

	local triggers = GetTriggerList();
	
	if (triggers) then
		for i = 1, #triggers do
			EnableTrigger(triggers[i], false);
			DeleteTrigger(triggers[i]);
		end
	end
	
	database.closeDatabase();
end

function utility.runToRoomId(roomId)
	local STATE_ACTIVE = 3;
	local canRun = true;
	
	if (utility.gmcp.getPlayerRoomId() ~= roomId) then
		if (utility.gmcp.getPlayerState() == STATE_ACTIVE) then
			Execute(igo.go .. roomId);
		else
			canRun = false;
			Execute("mapper where " .. roomId);
		end
	else
		utility.print("You are already in that room.");
	end
	
	return canRun;
end

function utility.setTarget(target, keyword)
	utility.targetName = target;
	utility.targetKeyword = keyword;
	
	var.target = target;
end

function utility.getTargetName()
	return utility.targetName
end

function utility.getTargetKeyword()
	return utility.targetKeyword
end

function utility.updateEnemy()
	local player_enemy = utility.gmcp.getPlayerEnemy():lower();

	if (player_enemy ~= "" and utility.playerEnemy ~= player_enemy) then
		utility.playerEnemy = player_enemy;
	end
end

function utility.getMobKeyword(mobName)
	mobName = mobName:lower();

	local mobKeyword;

	local splitMobName = {};

	for token in mobName:gmatch("[^ ]+") do
		token = token:gsub("[^%a]", "");
		table.insert(splitMobName, token);
	end -- for each non-space word strip any non-letter/"-"
	
	local keywords = {};
	
	for i = 1, #splitMobName do
		local token = splitMobName[i];
		
		if (#splitMobName == 2 and (token:find("^evil$") == 1 or token:find("^good$") == 1)) then
			return splitMobName[1];
		end -- sohtwo mobs
		
		local prefixPatterns = {
			"^a$",
			"^an$",
			"^the$",
			"^of$",
			"^some$",
			"^whelp$",
			"^dragon$",
			"^lizardman$",
			"^sea$"
		};
		
		for k,v in ipairs(prefixPatterns) do
			token = token:gsub(v, "");
		end -- strip certain non-keyword prefixes
		
		if (token ~= "") then
			table.insert(keywords, token);
		end -- if token still exists put into keywords table
	end

	if (not next(keywords)) then
		mobKeyword = mobName;
	else
		mobKeyword = #keywords == 1 and keywords[1] or (keywords[1]:sub(1, 4) .. " " .. keywords[#keywords]:sub(1, 4));
	end
	
	return mobKeyword;
end

function utility.print(message, color)
	color = color or "white";
	
	ColourNote(
		pluginPalette.mobberParentheses, "", "\r\n(",
		pluginPalette.mobber, "", "Mobber",
		pluginPalette.mobberParentheses, "", ") ",
		color, "", message .. "\r\n\r\n"
	);
end

----------------------------------
-- Sath's Aardwolf Incremental Go
----------------------------------

igo = {}
igo.scan = "scan"
igo.go   = "mapper goto "
igo.enabled  = true

function igo.initialize()
	AddAlias("alias_igo_setting", "^mobber igo(?: (?<enabled>true|false|on|off))?$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"igo.setEnabled"
	);
    igo.setEnabled(nil, nil, { enabled = true, gagOutput = true, initialize = true })
end

function igo.setEnabled(name, line, wildcards)
	local enabled = wildcards.enabled

	if enabled == nil or enabled == "" then
		igo.enabled = not igo.enabled
	else

		--local newMode = enabled == true or enabled == "on" or enabled == "true"
		--if newMode == igo.enabled and not wildcards.initialize then
		--	return
		--end
		--igo.enabled = newMode
		igo.enabled = enabled == true or enabled == "on" or enabled == "true"
	end
 
    if not wildcards.gagOutput then
      local mode = igo.enabled and "Enabled" or "Disabled"
      ColourNote(pluginPalette.border, "", mode .. " [Incremental Go] cmds if plugin is installed");
    end

	local igoInstalled = GetPluginInfo("c34c487f941b4f483fae2867", 17)
print("mobberhere", igo.enabled, igoInstalled) -- was true, nil
	igo.scan = igo.enabled and igoInstalled and "igo queue scan" or "scan"
	igo.go   = igo.enabled and igoInstalled and "igo cancel;igo resume;igo " or "mapper goto "
end

function OnPluginListChanged()
  print("mobberhere plugin changed")
  igo.setEnabled(nil, nil, { enabled = igo.enabled })
end

----------------------------------
-- GMCP
----------------------------------

utility.gmcp = {};

function utility.gmcp.getPlayerName()
	return gmcp("char.base.name");
end

function utility.gmcp.getPlayerLevel()
	return tonumber(gmcp("char.status.level"));
end

function utility.gmcp.getPlayerTnl()
	return tonumber(gmcp("char.status.tnl"));
end

function utility.gmcp.getPlayerRoomId()
	return tonumber(gmcp("room.info.num"));
end

function utility.gmcp.getPlayerRoomName()
	return gmcp("room.info.name");
end

function utility.gmcp.getPlayerZone()
	return gmcp("room.info.zone");
end

function utility.gmcp.getPlayerState()
	return tonumber(gmcp("char.status.state"));
end

function utility.gmcp.getPlayerEnemy()
	return gmcp("char.status.enemy"):lower();
end

function utility.gmcp.requestPlayerArea()
	Send_GMCP_Packet("request area");
end

----------------------------------
-- Help
----------------------------------

utility.help = {};

function utility.help.main()
	print();
	ColourNote(pluginPalette.border, "", string.format('%-15s : ', 'Name'),      pluginPalette.helpDescription, "", "Mobber");
	ColourNote(pluginPalette.border, "", string.format('%-15s : ', 'Author'),    pluginPalette.helpDescription, "", GetPluginInfo(GetPluginID(), 2));
	ColourNote(pluginPalette.border, "", string.format('%-15s : ', 'Version'),   pluginPalette.helpDescription, "", string.format("%.1f", GetPluginInfo(GetPluginID(), 19)));
	ColourNote(pluginPalette.border, "", string.format('%-15s : ', 'Purpose'),   pluginPalette.helpDescription, "", GetPluginInfo(GetPluginID(), 8));
	ColourNote(pluginPalette.border, "", string.format('%-15s : ', 'Mem Usage'), "yellow", "", string.format('%0d KB', collectgarbage('count')));
	print("\r\n\r\n");
	
	ColourNote(pluginPalette.border, "", string.rep("-", 7), pluginPalette.helpTitles, "", " Mobber Topics ", pluginPalette.border, "", string.rep("-", 7));
	print();
	
	utility.help.command("mobber help quests", "Campaigns and global quests.");
	utility.help.command("mobber help searching", "Searching for mobs and rooms.");
	utility.help.command("mobber help utils", "Utility commands.");
	utility.help.command("mobber help developer", "Adding areas, rooms and mobs to the database.");
	utility.help.command("mobber help igo", "Usage of Incremental Go commands.");
	print("\r\n\r\n");
	
	collectgarbage("collect");
end

function utility.help.quests()
	print();
	ColourNote(pluginPalette.border, "", string.rep("-", 7), pluginPalette.helpTitles, "", " Mobber Quests ", pluginPalette.border, "", string.rep("-", 7));
	print();
	
	utility.help.command("cp c", "Send 'campaign check' to process cp mobs.");
	utility.help.command("xcp <#>", "Select a mob from the campaign list.");
	print();
	
	utility.help.command("gq c", "Send 'gquest check' to process gq mobs.");
	utility.help.command("xgq <#>", "Select a mob from the global quest list.");
	print();
	
	utility.help.command("xgo <#>", "Go to a room in the current room list.");
	utility.help.command("xnext", "Go to the next room in the room list.");
	utility.help.command("xprev", "Go to the previous room in the room list.");
	print();
	
	utility.help.command("mobber quest", "Show quest info for current quest mob.");
	utility.help.command("mobber mute|unmute quest", "Mute or unmute quest messages/sounds.");
	print("\r\n\r\n");
end

function utility.help.searching()
	print();
	ColourNote(pluginPalette.border, "", string.rep("-", 7), pluginPalette.helpTitles, "", " Mobber Searching ", pluginPalette.border, "", string.rep("-", 7));
	print();
	
	utility.help.command("mf <mob name> zone <zone>", "Search for a mob in the current zone.");
	print();
	
	utility.help.command("mfa <mob name> lvl <min> <max>", "Search for a mob in all zones.");
	print();
	
	utility.help.command("rf <room name> zone <zone>", "Search for a room in the current zone.");
	print();
	utility.help.command("rfa <room name> lvl <min> <max>", "Search for a room in all zones.");
	print();
	
	utility.help.command("mobber show zone <zone>", "Show information for a single zone.");
	utility.help.command("mobber show zones sort <order>", "Show all of the zones in the database.");
	utility.help.command("", "<order> can be 'mobs', 'rooms' or 'level'.");
	print("\r\n\r\n");
	
	ColourNote("silver", "", "Note: Most arguments/parameters are optional.");
	print("\r\n\r\n");
end

function utility.help.utils()
	print();
	
	ColourNote(pluginPalette.border, "", string.rep("-", 7), pluginPalette.helpTitles, "", " Mobber Utilities ", pluginPalette.border, "", string.rep("-", 7));
	print();
	
	utility.help.command("xrt <zone name>", "Run to the marked room of a zone.");
	utility.help.command("xset mark", "Mark the landing room of a zone.");
	utility.help.command("xset mark <zone name> <room id>", "Mark the given landing room for the given zone.");
	print();
	
	utility.help.command("qs <mob name>", "Quick scan for current target.");
	utility.help.command("", "<mob name> is optional. Default is target.");
	print();
	
	utility.help.command("qw <mob name>", "Quick where a mob to get its location.");
	utility.help.command("", "<mob name> is optional. Default is target.");
	print();
	
	utility.help.command("ak", "Send the set autokill command.");
	utility.help.command("ak <skill>", "Set the command to use for autokill.");
	utility.help.command("toggle ak", "Toggle appending the current target.");
	print();
	
	utility.help.command("ah <mob>", "Auto-hunt a mob. No arg will abort hunt.");
	utility.help.command("ht <mob>", "Hunt-trick a mob. No arg will abort hunt.");
	print();
	
	utility.help.command("mobber noexp <threshold>", "Auto noexp. Default is 1000 exp threshold.");
	print();
	
	utility.help.command("mobber color <color>", "Options: red, blue, green, yellow, purple.");
	print();
	
	utility.help.command("mobber btncolor <color> window", "Change text color of the window buttons.");
	utility.help.command("mobber hide|show window", "Show or hide the window.");
	utility.help.command("mobber reset window", "Reset the window if it goes off-screen.");
	print("\r\n\r\n");
	
	ColourNote("silver", "", "Note: Window commands require the miniwindow plugin to be installed.");
	print("\r\n\r\n");
end

function utility.help.developer()
	print();
	
	ColourNote(pluginPalette.border, "", string.rep("-", 7), pluginPalette.helpTitles, "", " Mobber Developer ", pluginPalette.border, "", string.rep("-", 7));
	print();
	
	utility.help.command("mobber developer", "Enable or disable developer mode.");
	utility.help.command("mobber backup", "Manually force a backup of the database.");
	utility.help.command("mobber vacuum", "Defragment and reduce size of the db.");
	print();
	
	utility.help.command("mobber addzone <min> <max>", "Add the current zone to the database.");
	utility.help.command("mobber update lvlrange <#> <#>", "Update a zone's level range.");
	print();
	
	utility.help.command("mobber update zones", "Update zones with default values.");
	utility.help.command("mobber update rooms", "Update rooms from Aardwolf.db to the database.");
	utility.help.command("mobber update notes", "Update notes from Aardwolf.db to the database.");
	print();
	
	utility.help.command("mobber addmob <name>", "Add a mob to the current room.");
	utility.help.command("mobber consider [on|off]", "Toggle or set logging mobs with 'consider' command.");
	print();
	
	utility.help.command("mobber removemob single <name>", "Remove matching mobs from the current zone.");
	utility.help.command("mobber removemob room", "Remove all mobs from the current room.");
	utility.help.command("mobber removemob zone", "Remove all mobs from the current zone.");
	utility.help.command("mobber remove zone", "Remove the current zone from the database.");
	print();
	
	utility.help.command("mobber update keywords", "Update keywords for all mobs in the database.");
	utility.help.command("mobber keyword <word> mob <mob>", "Update keyword for a single mob.");
	utility.help.command("mobber clean keywords", "Remove unused keywords from the database.");
	print()

	utility.help.command("mobber priority <#> mob <mob>", "Update GQ priority of a mob in the current zone.");
	utility.help.command("mobber rprio <#> mob <mob> room <id>", "Update room priority of a mob in roomid/current.");
	utility.help.command("mobber aprio <#> zone <zone> mob <mob>", "Update mob area_mob priority in zone/current.")
	utility.print("lower priority means higher on the list")
	print("\r\n\r\n");
	

	ColourNote("silver", "", "Note: See the README.txt before using developer commands.");
	print("\r\n\r\n");
end

function utility.help.igo()
	print();
	ColourNote(pluginPalette.border, "", string.rep("-", 7), pluginPalette.helpTitles, "", " Mobber Incremental go ", pluginPalette.border, "", string.rep("-", 7));
	print();
	
	
	utility.help.command("mobber igo [true|false]", "Toggles usage of igo for move/scan commands.");
	print("\r\n\r\n");
end

function utility.help.command(cmd, desc)
	ColourNote(pluginPalette.helpCommand, "", string.format('%-31s', cmd), pluginPalette.border, "", " : ", pluginPalette.helpDescription, "", desc);
end

----------------------------------
-- Mob Target Prototype
----------------------------------

mobTarget = {
	name = "",
	keyword = "",
	location = "",
	isDead = false,
	lookupType = "",
	amount = 1,
	rooms = {}
};

function mobTarget:new(mob)
	mob = mob or {};
	setmetatable(mob, self);
	self.__index = self;
	return mob;
end

function mobTarget:initialize()
	self.keyword = database.lookupMobKeyword(self.name) or utility.getMobKeyword(self.name);
	
	local lookups = {
		database.lookupMobRoomOrAreaByLvl,
		database.lookupMobRoomOrArea,
		database.lookupArea,
		database.lookupRoomAreaByLvl,
		database.lookupRoomArea
	};
	
	for k,v in ipairs(lookups) do
		self.rooms, self.lookupType = v(self.location, self.name);
		
		if (next(self.rooms)) then
			break;
		end
	end
	
	if (not next(self.rooms)) then
		self.lookupType = "none";
		table.insert(self.rooms, {zone_name = self.location});
	end
end

----------------------------------
-- Color Palette
----------------------------------

colorPalette = {};

function colorPalette.initialize()
	AddAlias("alias_color_palette_set_color", "^mobber color (?<color>.+?)$", "",
		alias_flag.Enabled + alias_flag.IgnoreAliasCase + alias_flag.RegularExpression + alias_flag.Temporary,
		"colorPalette.setColor"
	);

	if (var.pluginPalette) then
		pluginPalette = loadstring("return " .. var.pluginPalette)();
	else
		pluginPalette = colorPalette.getDefault();
		var.pluginPalette = serialize.save_simple(pluginPalette);
	end
end

function colorPalette.getDefault()
	return {
		border = "maroon",
		header = "white",
		indexNumbering = "white",
		deadMob = "red",
		foundMobRoom = "paleturquoise",
		foundArea = "deepskyblue",
		roomOrMobAll = "darkgray",
		missingAreaRoom = "yellow",
		rooms = "paleturquoise",
		highlightTarget = "red",
		highlightTargetParentheses = "#4D4D4D",
		mobber = "white",
		mobberParentheses = "maroon",
		helpDescription = "white",
		helpTitles = "darkgray",
		helpCommand = "firebrick"
	};
end

function colorPalette.setColor(name, line, wildcards)
	local color = wildcards.color;

	if (color == "green") then
		pluginPalette.border = "forestgreen";
		pluginPalette.highlightTarget = "lime";
		pluginPalette.mobberParentheses = "forestgreen";
		pluginPalette.helpCommand = "chartreuse";
	elseif (color == "blue") then
		pluginPalette.border = "steelblue";
		pluginPalette.highlightTarget = "lightskyblue";
		pluginPalette.mobberParentheses = "blue";
		pluginPalette.helpCommand = "mediumturquoise";
	elseif (color == "purple") then
		pluginPalette.border = "slateblue";
		pluginPalette.highlightTarget = "blueviolet";
		pluginPalette.mobberParentheses = "darkorchid";
		pluginPalette.helpCommand = "mediumorchid";
	elseif (color == "yellow") then
		pluginPalette.border = "#B1B55F";
		pluginPalette.highlightTarget = "yellow";
		pluginPalette.mobberParentheses = "khaki";
		pluginPalette.helpCommand = "#F3FF00";
	else
		color = "default";
		pluginPalette = colorPalette.getDefault();
	end
	
	var.pluginPalette = serialize.save_simple(pluginPalette);
	
	utility.print("Color scheme set to: " .. color);
end

----------------------------------
-- Mushclient Plugin Callbacks
----------------------------------

function OnPluginInstall()
	utility.initialize();
end

function OnPluginConnect()
	Send_GMCP_Packet("request char");
	Send_GMCP_Packet("request room");
	Send_GMCP_Packet("request quest");
end

function OnPluginClose()
	utility.deinitialize();
end

function OnPluginEnable()
	OnPluginInstall();
	OnPluginConnect();
end

function OnPluginDisable()
	OnPluginClose();
end

function isOmniEnabled()
	local pluginId = "b16d151337abc0f39a282125"
	return IsPluginInstalled(pluginId) and GetPluginInfo(pluginId, 17)
end

function OnPluginBroadcast(msg, id, name, text)
	if (id == "3e7dedbe37e44942dd46d264") then
		if (text == "char.status") then
			utility.updateEnemy();
		elseif (text == "room.area" and database.area and database.area.isAddingArea) then
			local zoneName = gmcp("room.area.id");
			local areaName = gmcp("room.area.name");
			
			database.addArea(zoneName, areaName);
		elseif (text == "comm.quest") then
			local newQuest = gmcp("comm.quest");
			
			if (newQuest.action == "ready") then
				if (not quest.isMuted) then
					local commMsg = quest.commPrefix .. " @WAvailable!@w";
					CallPlugin("b555825a4a5700c35fa80780", "storeFromOutside", commMsg);
				end
			elseif (newQuest.action == "start") then
				quest.start(newQuest);
			--elseif (newQuest.action == "status" and (newQuest.targ or newQuest.status == "ready")) then
			elseif (newQuest.action == "status") then
				local omniEnabled = isOmniEnabled();
				if not omniEnabled or (newQuest.targ or newQuest.status == "ready") then
					quest.showRequest(newQuest);
				end
			elseif (newQuest.action == "fail") then
				quest.fail(newQuest);
			elseif (newQuest.action == "comp") then
				quest.complete(newQuest);
			end
		elseif (text == "config") then
			noexp.isNoExp = gmcp("config.noexp") == "YES" and true or false;
		end
	end
end