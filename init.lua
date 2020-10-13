-- Land Value Protection
-- Protect an area for as long as the lvt node is active.
-- Price is determined dynamically.

-- based on AndrejIT's protectior and brazier mod
-- based on Zeg9's protector mod
-- based on glomie's mod of the same name
-- protects against placing tnt near protected area.

local S = minetest.get_translator("lvt")
lvt = {}
lvt.cache = {}
lvt.landvalue = {}
lvt.radius = 3--(tonumber(minetest.setting_get("lvt_radius")) or 3)
lvt.pspawnpos = (minetest.setting_get_pos("static_spawnpoint") or {x=0, y=3, z=0})
lvt.pspawn = true -- protect area aound spawn

minetest.register_privilege("delprotect",S("Delete other's protection by sneaking"))

--
-- members
--

lvt.get_member_list = function(meta)
	local s = meta:get_string("members")
	local list = s:split(" ")
	return list
end

lvt.set_member_list = function(meta, list)
	meta:set_string("members", table.concat(list, " "))
end

lvt.is_member = function (meta, name)
	local list = lvt.get_member_list(meta)
	for _, n in ipairs(list) do
		if n == name then
			return true
		end
	end
	return false
end

lvt.add_member = function(meta, name)
	name=string.sub(name, 1, 30)	--protection
	if lvt.is_member(meta, name) then return end
	local list = lvt.get_member_list(meta)
	table.insert(list,name)
	lvt.set_member_list(meta,list)
end

lvt.del_member = function(meta,name)
	local list = lvt.get_member_list(meta)
	for i, n in ipairs(list) do
		if n == name then
			table.remove(list, i)
			break
		end
	end
	lvt.set_member_list(meta,list)
end

--
-- interact
--

-- r: radius to check for protects
-- Infolevel:
-- * 0 for no info
-- * 1 for "This area is owned by <owner> !" if you can't dig
-- * 2 for "This area is owned by <owner>.
--   Members are: <members>.", even if you can dig
lvt.can_interact = function(r, pos, name, onlyowner, infolevel)
	local player
	if type(name) == "string" then
		player = minetest.get_player_by_name(name)
	elseif name and name:is_player() then
		player = name
		name = player:get_player_name()
	else
		return false
	end
	--fast check from cached data. no messages etc, just deny.
	if lvt.cache[name..minetest.pos_to_string(pos)] then
		return false
	end

	if infolevel == nil then infolevel = 1 end
	-- Delprotect privileged users can override protections by holding sneak
	if minetest.get_player_privs( name ).delprotect and
	   player:get_player_control().sneak then
		return true
	end
	-- Find the protection nodes
	local positions = minetest.find_nodes_in_area(
		{x=pos.x-r, y=pos.y-r, z=pos.z-r},
		{x=pos.x+r, y=pos.y+r, z=pos.z+r},
		{"lvt:engine_active"})
	if not positions then return true end
	for _, pos in ipairs(positions) do
		local meta = minetest.get_meta(pos)
		local owner = meta:get_string("owner")
		if not owner then return true end
		if owner ~= name then
			if onlyowner or not lvt.is_member(meta, name) then
				if infolevel == 1 then
					minetest.chat_send_player(name, "This area is owned by "..owner.."!")
				elseif infolevel == 2 then
					minetest.chat_send_player(name, "This area is owned by "..meta:get_string("owner")..".")
					if meta:get_string("members") ~= "" then
						minetest.chat_send_player(name, "Members are: "..meta:get_string("members")..".")
					end
				end
				lvt.cache[name..minetest.pos_to_string(pos)] = 1
				return false
			end
		end
	end
	if infolevel == 2 then
		if #positions < 1 then
			minetest.chat_send_player(name, "This area is not protected.")
		else
			local meta = minetest.get_meta(positions[1])
			minetest.chat_send_player(name, "This area is owned by "..meta:get_string("owner")..".")
			if meta:get_string("members") ~= "" then
				minetest.chat_send_player(name,"Members are: "..meta:get_string("members")..".")
			end
		end
		minetest.chat_send_player(name,"You can build here.")
	end
	return true
end

--additional protection against tnt!
if minetest.registered_nodes["tnt:tnt"] then
	lvt.prot_tnt_radius_max = tonumber(minetest.setting_get("tnt_radius_max") or 25) + lvt.radius
end --tnt

--for all "on_place" functions
local old_item_place = minetest.item_place
minetest.item_place = function(itemstack, placer, pointed_thing)
	local itemname = itemstack:get_name()
	local pos = pointed_thing.above
	if pos == nil then
		local name = placer:get_player_name()
		minetest.log("action", "Player "..name.." placing "..itemname.." without pos");
		return itemstack

	elseif itemname == lvt.node then
		if not lvt.can_interact(lvt.radius*2, pos, placer, true) then
			return itemstack
		end
		if	lvt.pspawn and lvt.pspawnpos and
			pos.x > lvt.pspawnpos.x - 121 and pos.x < lvt.pspawnpos.x + 121 and
			pos.z > lvt.pspawnpos.z - 121 and pos.z < lvt.pspawnpos.z + 121 and
			not minetest.get_player_privs(placer:get_player_name()).delprotect
		then
			minetest.chat_send_player(placer:get_player_name(), "Spawn is protected.")
			return itemstack
		end
	elseif minetest.get_item_group(itemname, "lvt") > 0 then
		if not lvt.can_interact(lvt.radius*2, pos, placer, true) then
			return itemstack
		end
		if	lvt.pspawn and lvt.pspawnpos and
			pos.x > lvt.pspawnpos.x - 21 and pos.x < lvt.pspawnpos.x + 21 and
			pos.z > lvt.pspawnpos.z - 21 and pos.z < lvt.pspawnpos.z + 21 and
			not minetest.get_player_privs(placer:get_player_name()).delprotect
		then
			minetest.chat_send_player(placer:get_player_name(), "Spawn is protected.")
			return itemstack
		end
	elseif minetest.get_item_group(itemname, "sapling") > 0 then
		pos = {x=pos.x, y=pos.y+5, z=pos.z}
		if not lvt.can_interact(lvt.radius, pos, placer) then
			return itemstack
		end
	elseif itemname == "tnt:tnt" then
		if not lvt.can_interact(lvt.prot_tnt_radius_max or 25, pos, placer) then
			return itemstack
		end
	end

	return old_item_place(itemstack, placer, pointed_thing)
end


--"is_protected". not aware of item being placed or used
local old_is_protected = minetest.is_protected
function minetest.is_protected(pos, name)
	local node = minetest.get_node(pos)
	local nodename = node.name

	if nodename == lvt.node then
		if not lvt.can_interact(lvt.radius, pos, name, true) then
			return true
		end
	elseif node.name == "bones:bones" then
		--lvt has no effect on bones
	else
		if not lvt.can_interact(lvt.radius, pos, name) then
			return true
		end
	end

	return old_is_protected(pos, name)
end

local function swap_node(pos, name)
	local node = minetest.get_node(pos)
	if node.name == name then
		return
	end
	node.name = name
	minetest.swap_node(pos, node)
end

local function activate_protection(pos, player)
	local meta = minetest.get_meta(pos)
	meta:set_string("owner", player:get_player_name() or "")
	meta:set_string("infotext", "Protection (owned by "..
			meta:get_string("owner")..")")
	meta:set_string("members", "")
end

local function deactivate_protection(pos, player)
	local meta = minetest.get_meta(pos)
	meta:set_string("owner", nil)
	meta:set_string("infotext", nil)
	meta:set_string("members", "")
	swap_node(pos, "lvt:engine")
	meta:set_string("formspec",lvt.generate_formspec(meta, pos))
end

--
-- formspec
--

local function can_dig(pos, player)
	local meta = minetest.get_meta(pos);
	local inv = meta:get_inventory()
	return inv:is_empty("fuel")
end

local function allow_metadata_inventory_put(pos, listname, index, stack, player)
	if not lvt.can_interact(1,pos,player,true) then
		return 0
	end
--	local meta = minetest.get_meta(pos)
--	local inv = meta:get_inventory()
	return stack:get_count()
end

local function allow_metadata_inventory_take(pos, listname, index, stack, player)
	if not lvt.can_interact(1,pos,player,true)  then
		return 0
	end
	return stack:get_count()
end

lvt.generate_formspec = function (meta, pos)
	local formspec = "size[8,10]"
		-- Fuel and start
		.."list[context;fuel;3.5,4.75;1,1;]"
		.."button[1.5,4.75;2,1;lvt_start;START]"
		-- Player inventory
		.."list[current_player;main;0,6;8,1;]"
		.."list[current_player;main;0,7.25;8,3;8]"
		.."listring[context;dst]"
		.."listring[current_player;main]"
		.."listring[context;src]"
		.."listring[current_player;main]"
		.."listring[context;fuel]"
		.."listring[current_player;main]"


	return formspec
end

lvt.generate_formspec_active = function (meta, pos)
	local formspec = "size[8,10]"
		.."label[0,0;Punch the node to show the protected area.]"
		-- Fuel and stop
		.."list[context;fuel;3.5,4.75;1,1;]"
		.."button[4.5,4.75;2,1;lvt_stop;STOP]"
		-- Player inventory
		.."list[current_player;main;0,6;8,1;]"
		.."list[current_player;main;0,7.25;8,3;8]"
		.."listring[context;dst]"
		.."listring[current_player;main]"
		.."listring[context;src]"
		.."listring[current_player;main]"
		.."listring[context;fuel]"
		.."listring[current_player;main]"
		-- Members
		.."label[0,0.4;Current members:]"
	local members = lvt.get_member_list(meta)
	local npp = 16 -- names per page, is 4*4
	local i = 0
	for _, member in ipairs(members) do
		if i < npp then
			formspec = formspec .."button["..(i%4*2)..","..math.floor(i/4+1)..";1.5,0.5;lvt_member;"..member.."]"
			formspec = formspec .."button["..(i%4*2+1.25)..","..math.floor(i/4+1)..";.75,.5;lvt_del_member_"..member..";X]"
		end
		i = i +1
	end
	if i < npp then
		local spos = pos.x .. "," ..pos.y .. "," .. pos.z
		formspec = formspec
			.."field["..(i%4*2+1/3)..","..(math.floor(i/4+1)+1/3)..";1.433,.5;lvt_add_member;;]"

--			.."list[nodemeta:" .. spos .. ";fuel;3.5,8.25;1,1;]"..
			.."button["..(i%4*2+1.25)..","..math.floor(i/4+1)..";.75,.5;lvt_submit;+]"
	end

	return formspec
end

-- Buttons
minetest.register_on_player_receive_fields(function(player,formname,fields)
	-- formname contains the position as a string in the format of "lvt_(x,y,z)"
	if string.sub(formname,0,string.len("lvt_")) == "lvt_" then
		local pos_s = string.sub(formname,string.len("lvt_")+1)
		local pos = minetest.string_to_pos(pos_s)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		local fuellist = inv:get_list("fuel")
		if not lvt.can_interact(1,pos,player,true) then
			return
		end

		-- Start protector
		if fields.lvt_start then
			-- activate protection when fueled
			if minetest.get_node(pos).name == "lvt:engine"
					and fuellist and not fuellist[1]:is_empty() then
					swap_node(pos, "lvt:engine_active")
					meta:set_string("formspec",lvt.generate_formspec_active(meta, pos))
					activate_protection(pos,player)
					minetest.show_formspec(
						player:get_player_name(),
						"lvt_"..minetest.pos_to_string(pos),
						lvt.generate_formspec_active(meta, pos)
					)
			end
			return
		end

		-- Stop protector
		if fields.lvt_stop then
			deactivate_protection(pos, player)
			-- Change to new formspec
			minetest.show_formspec(
				player:get_player_name(), formname,
				lvt.generate_formspec(meta, pos)
			)
			return
		end

		-- Handle members
		if fields.lvt_add_member then
			for _, i in ipairs(fields.lvt_add_member:split(" ")) do
				lvt.add_member(meta,i)
			end
		end
		for field, value in pairs(fields) do
			if string.sub(field,0,string.len("lvt_del_member_"))=="lvt_del_member_" then
				lvt.del_member(meta, string.sub(field,string.len("lvt_del_member_")+1))
			end
		end

		-- Update the active formspec after add/del members.
		if not fields["quit"] then
			minetest.show_formspec(
				player:get_player_name(), formname,
				lvt.generate_formspec_active(meta, pos)
			)
		end
	end
end)

--
-- Node timer
--

local function engine_node_timer(pos, elapsed)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local timer = minetest.get_node_timer(pos)
	local fuellist = inv:get_list("fuel")

	if minetest.get_node(pos).name == "lvt:engine_active" then
		-- burn fuel
		local stk = inv:get_stack("fuel", 1)
		stk:set_count(1)
		inv:remove_item("fuel", stk)
		-- deactivate protection when empty
		if fuellist and fuellist[1]:is_empty() then
			deactivate_protection(pos)
		end
	end

	-- make sure timer restarts automatically
	timer:start(5.0)
end

--
-- Protector node
--

minetest.register_node("lvt:engine", {
	description = S("Protector"),
	tiles = {"lvt_engine.png"},
	groups = {dig_immediate=2, protector=1},
	sounds = default.node_sound_stone_defaults(),
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		inv:set_size('fuel', 1)
		engine_node_timer(pos, 0)
		meta:set_string("formspec",lvt.generate_formspec(meta, pos))
	end,
-- [[
	on_metadata_inventory_put = function(pos)
		-- start engine when fueled
		minetest.get_node_timer(pos):start(1.0)
	end,
	on_metadata_inventory_take = function(pos)
		-- check whether the engine is empty or not
		minetest.get_node_timer(pos):start(1.0)
	end,
--]]
	on_rightclick = function(pos, node, player, itemstack)
		local meta = minetest.get_meta(pos)
		if lvt.can_interact(1,pos,player,true) then
			minetest.show_formspec(
				player:get_player_name(),
				"lvt_"..minetest.pos_to_string(pos),
				lvt.generate_formspec(meta)
			)
		end
	end,
	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_take = allow_metadata_inventory_take,
	can_dig = can_dig,
	on_timer = engine_node_timer,
})

minetest.register_node("lvt:engine_active", {
	description = S("Protector"),
	tiles = {
		{
			image = "lvt_engine_active.png",
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 1.5
			}
		}
		},
	light_source = 5,
	drop = "lvt:engine",
	groups = {dig_immediate=2, protector=1},
	sounds = default.node_sound_stone_defaults(),
	on_rightclick = function(pos, node, player, itemstack)
		local meta = minetest.get_meta(pos)
		if lvt.can_interact(1,pos,player,true) then
			minetest.show_formspec(
				player:get_player_name(),
				"lvt_"..minetest.pos_to_string(pos),
				lvt.generate_formspec_active(meta, pos)
			)
		end
	end,
	on_punch = function(pos, node, puncher)
		if not lvt.can_interact(1, pos, puncher, true) then
			return
		end
		local objs = minetest.get_objects_inside_radius(pos, 0.5) -- a radius of .5 since the entity serialization seems to be not that precise
		local removed = false

		for _, o in pairs(objs) do
			if o and not o:is_player() and o:get_luaentity().name == "lvt:display" then
				o:remove()
				removed = true
			end
		end
		if not removed then -- nothing was removed: there wasn't the entity
			minetest.add_entity(pos, "lvt:display")
		end
	end,
	on_metadata_inventory_put = function(pos)
		-- start engine when fueled
		minetest.get_node_timer(pos):start(1.0)
	end,
	on_metadata_inventory_take = function(pos)
		-- check whether the engine is empty or not
		minetest.get_node_timer(pos):start(1.0)
	end,
	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_take = allow_metadata_inventory_take,
	can_dig = can_dig,
	on_timer = engine_node_timer,
})

minetest.register_craft({
	output = "lvt:engine",
	recipe = {
		{"", "default:steel_ingot", ""},
		{"default:steel_ingot", "default:furnace", "default:steel_ingot"},
		{"", "default:steel_ingot", ""},
	}
})

--
-- Diplay protection
--
-- frame to show protected area when node is punched

minetest.register_entity("lvt:display", {
	physical = false,
	collisionbox = {0,0,0,0,0,0},
	visual = "wielditem",
	visual_size = {x=1.0/1.5,y=1.0/1.5}, -- wielditem seems to be scaled to 1.5 times original node size
	textures = {"lvt:display_node"},
	on_step = function(self, dtime)
		self.timer = (self.timer or 0) + dtime
		if self.timer > 10 then
			self.object:remove()
		end
	end,
})

-- Display-zone node.
-- Do NOT place the display as a node
-- it is made to be used as an entity (see above)
local x = lvt.radius
minetest.register_node("lvt:display_node", {
	tiles = {"lvt_display.png"},
	use_texture_alpha = true,
	walkable = false,
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {

			-- sides
			{-(x+.55), -(x+.55), -(x+.55), -(x+.45), (x+.55), (x+.55)},
			{-(x+.55), -(x+.55), (x+.45), (x+.55), (x+.55), (x+.55)},
			{(x+.45), -(x+.55), -(x+.55), (x+.55), (x+.55), (x+.55)},
			{-(x+.55), -(x+.55), -(x+.55), (x+.55), (x+.55), -(x+.45)},
			-- top
			{-(x+.55), (x+.45), -(x+.55), (x+.55), (x+.55), (x+.55)},
			-- bottom
			{-(x+.55), -(x+.55), -(x+.55), (x+.55), -(x+.45), (x+.55)},
			-- middle (surround protector)
			{-.55,-.55,-.55, .55,.55,.55},
		},
	},
	selection_box = {
		type = "regular",
	},
	paramtype = "light",
	groups = {dig_immediate=3,not_in_creative_inventory=1},
	drop = "",
})
