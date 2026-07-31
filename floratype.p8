pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
day = 1

function _init()
	--modes/screens of the game:
	--1 field
	--2 calendar
	atn, atx = 0, 128
	memset(0x8000, 0x44, 0x4000)
	cls()
	init_field_screen()
	init_calendar_screen()
	init_genetics_screen()
	
	start_field_screen()
--	start_calendar_screen()
--	local flower = generate_flower(0)
--	add_flower_to_field(flower, 1, 1)
--	start_genetics_screen(flower)
end

function _update()
	atn = (atn + 1) % atx
	if menu_is_open then
		update_menu()
	else
		if mode == 1 then
			update_field_screen()
		elseif mode == 2 then
			update_calendar_screen()
		elseif mode == 3 then
			update_genetics_screen()
		end
	end
end

function _draw()
	if mode == 1 then
		draw_field_screen()
	elseif mode == 2 then
		draw_calendar_screen()
	elseif mode == 3 then
		draw_genetics_screen()
	end
	if menu_is_open then
		draw_menu()
	end
end

save_magic_number = 0xac01

function save_game()
	--sync field state to sprite memory
	--save to cart
	--reserve the first 4 bytes for future use
	poke2(0x1000,save_magic_number)
	poke(0x1002,day)
	local end_addr = field1:save(0x1004)
	assert(end_addr < 0x2000,"tried to save too much memory "..end_addr)
	
	cstore(0x1000,0x1000,0x1000,"floratype_save.p8")
end

function load_game()
	reload(0x1000,0x1000,0x1000,"floratype_save.p8")
	if %0x1000 == save_magic_number then
		day = @0x1002
		field1 = field_class:load(0x1004)
		init_field_screen()
		sync_flower_sprites()
	end
end

-->8
--utils

function unpacks(s)
	return unpack(split(s))
end

function max_binary(size)
	return 2 ^ size - 1
end

function get_bits(bits, bit_shift, size)
	return (bits << bit_shift) & max_binary(size)
end

function set_bits(bits, new_val, bit_shift, size)
	local mask = 0xffff.ffff ^^ max_binary(size) >> bit_shift
	return bits & mask | new_val >> bit_shift
end



-- copies a sprite from x0,y0
--   (from spritesheet based at
--   memory address base0)
--   into x1,y1 on the spritesheet
--   based at address base1
-- set base1 to 0x6000 to use the
--   screen as the destination
-- all coordinates are measured
--   in pixels
-- note! odd x-coordinates will
--   be rounded down
-- by pancelor
function blit(base1,x1,y1,base0,x0,y0, w,h)
 local a0=base0+y0*64+x0\2 --source
 local a1=base1+y1*64+x1\2 --destination
 local w2=w and w\2 or 4   --half-width
 for da=0,(h or 8)*64-1,64 do
  memcpy(a1+da,a0+da,w2)
 end
end

function draw_filled_rrect(x,y,w,h,d,c1,c2)
	rrectfill(x,y,w,h,d,c2)
	rrect(x,y,w,h,d,c1)
end
-->8
--field screen

field_class = {}
field_class.__index = field_class

empty_flower_magic_numbers = {0xbaaa.aaad, 0x0}

function field_class:new(n)
	local flowers, weeds = {}, {}
	for y=1,f_max_y do
		local flower_row, weed_row = {}, {}
		for x=1,f_max_x do
			add(flower_row, nil)
			add(weed_row, false)
--			add(weed_row, x%2 == y%2)
--			add(weed_row, true)
		end
		add(flowers, flower_row)
		add(weeds, weed_row)
	end

	return setmetatable(
		{
			n=n,
			flowers=flowers,
			weeds=weeds
		},
		self)
end

function field_class:load(addr)
	local field = field_class:new(1)
	for y = 1,f_max_y do
		for x = 1,f_max_x do
			local data1,data2 = $addr, $(addr+4)
			if data1 != empty_flower_magic_numbers[1] then
				field:place(
					flower_class:new(
						data1,data2),
					x, y)
			end
			addr += 8
		end
	end
	return field, addr
end

function field_class:place(flower, x, y)
	--maybe should validate bounds
	if flower then
		--skip for removals
		flower:place(self.n, x, y)
	end
	self.flowers[y][x] = flower
end

function field_class:get(x, y)
	return self.flowers[y][x]
end

function field_class:has_weeds(x,y)
	return check_field_bounds(x,y) and self.weeds[y][x]
end

function field_class:set_weeds(v,x,y)
	if check_field_bounds(x,y) then
		self.weeds[y][x] = v
	end
end


function field_class:save(addr)
	for y = 1,f_max_y do
		for x = 1,f_max_x do
			local f = self:get(x,y)
			local bytes
			if f then
				bytes = {f.chr1, f.chr2}
			else
				bytes = empty_flower_magic_numbers
			end
			for b in all(bytes) do
				poke4(addr, b)
				addr += 4
			end
		end
	end
	return addr
end

--this assumes the same max dimensions
--for every field
function check_field_bounds(x,y)
	return x >=1 and x <= f_max_x and y >= 1 and y <= f_max_y
end

function init_field_screen()
	-- make sprite 0 opaque in the map
	poke(0x5f36,0x08)
	
	--camera coords represent top
	--left corner of current view
	fcam_x, fcam_y = 1, 1
	f_max_x,f_max_y = 16, 16
	bc_x = 1
	field_debug = ""
	if field1 == nil then
		field1 = field_class:new(1)
	end
	selected_tool, selected_seed = 0, 0
end

function resume_field_screen()
	mode = 1
	on_field = true
	animation = nil
	a_frame = 0
	anim_dx, anim_dy = 0 ,0
end

function start_field_screen()
	resume_field_screen()
	fc_x, fc_y = fcam_x+3, fcam_y+3
end

function update_field_screen()
-- i have tested redrawing 1/8th of sprites in a frame
-- this locks the animiation speed to a cycle of 128 frames
--	if atn % 8 == 0 then
--		for_all_flowers(function(flower,x,y)
--			if flower:pollinator_attract_level() > 0 and (y*4 + x%4) % 8 == (atn / 8) % 8 then
--				create_and_place_flower_sprite(flower)
--			end
--		end)
--	end
	if not animation then
		move_field_cursor()
		click_button()
	end
	if animation then
		animation()
	end
end

function draw_field_screen()
	cls()
	clip(unpacks"0,0,128,112")
	camera(anim_dx, anim_dy)
	draw_ground()
	draw_flowers()
	if not menu_is_open then
		draw_field_cursor()
	end
	clip()
	camera()
	draw_filled_rrect(
		unpacks"96,2,31,9,0,0,15")
	print("day "..day,98,4,0)
	draw_toolbar()
	if not menu_is_open and not on_field then
		draw_button_cursor()
	end
	print(field_debug, 80, 116)
end

function start_animation(a)
	a_frame = 0
	animation = a
end

function stop_animation()
	animation = nil
	anim_dx, anim_dy = 0, 0
end

function move_field_cursor()
	if btnp(❎) then
		on_field = not on_field
	end
	if on_field then
		if btnp(⬆️) then
			fc_y -= 1
		elseif btnp(⬇️) then
			fc_y += 1
		elseif btnp(⬅️) then
			fc_x -= 1
		elseif btnp(➡️) then
			fc_x += 1
		end
		fc_y = mid(1,fc_y,f_max_y)
		fc_x = mid(1,fc_x,f_max_x)
		
		if fc_y > fcam_y + 6 then
			start_animation(move_camera_down)
		end
		if fc_y < fcam_y then
			start_animation(move_camera_up)
		end
		if fc_x > fcam_x + 7 then
			start_animation(move_camera_right)
		end
		if fc_x < fcam_x then
			start_animation(move_camera_left)
		end
	else
		if btnp(⬅️) then
			bc_x -= 1
		end
		if btnp(➡️) then
			bc_x += 1
		end
		bc_x = mid(1,bc_x,4)
	end
end

--syncs sprite to spritesheet for
--flower or empty space at actual
--(not camera) coords x,y
function sync_flower_sprite(x,y,sx,sy)
	local flower = field1:get(x,y)
	if flower then
		create_and_place_flower_sprite(flower,sx,sy)
	else
		remove_flower_sprite(x,y,sx,sy)
	end
end

function click_button()
	if btnp(🅾️) then
		if on_field then
			if selected_tool == 0 then
				if selected_seed then
					generate_and_place_flower(selected_seed)
				end
			elseif selected_tool == 1 then
				remove_flower_from_field()
			elseif selected_tool == 2 then
				local flower = field1:get(fc_x, fc_y)
				if flower then
					start_genetics_screen(flower)
				end
			end
		else
			if bc_x == 1 then
				open_seed_menu(
					function(s)
						on_field = true
						selected_tool = 0
						selected_seed = s[3]
					end)
			elseif bc_x == 2 then
				open_tools_menu(
					function(s)
						on_field = true
						selected_tool = s[3]
					end)
			elseif bc_x == 3 then
				time_passes()
			elseif bc_x == 4 then
				open_options_menu(
					function(o)
						local i = o[3]
						if i == 1 then
							start_calendar_screen()
						elseif i == 2 then
							save_game()
						elseif i == 3 then
							load_game()
						end
					end)
			end
		end
	end
end

function generate_and_place_flower(flower_type)
	if not field1:get(fc_x, fc_y) then
		local flower = generate_flower(flower_type)
		add_flower_to_field(flower, fc_x, fc_y)
	end
end

function add_flower_to_field(flower, x, y)
--	field_debug = gene_str(flower)
	field1:place(flower, x, y)
	create_and_place_flower_sprite(flower)
end

function remove_flower_from_field()
	field1:place(nil, fc_x, fc_y)
	remove_flower_sprite(fc_x, fc_y)
end

function draw_ground()
	for x=-2,17 do
		for y=-2,15 do
			spr(2,x*8,y*8)
			if field1:has_weeds(x\2 + fcam_x, y\2 + fcam_y) then
				spr(4,x*8,y*8)
			end
		end
	end
	
	-- 1 pixel outline
	if fcam_y == 1 then
		line(unpacks"-16,0,144,0,15")
	end
	if fcam_y + 6 == f_max_y then
		line(unpacks"-16,111,144,111,15")
	end
	if fcam_x == 1 then
		line(unpacks"0,-16,0,128,15")
	end
	if fcam_x + 7 == f_max_x then
		line(unpacks"127,-16,127,128,15")
	end
end

function draw_flowers()
-- switch sprite sheet to extended sheet 0
	poke(0x5f54,0x80)
	palt(0b0000100000000000)
	map(unpacks"0,0,-16,-16,20,18")
-- switch sprite sheet back to default
	poke(0x5f54,0x00)
	palt()
end

function draw_field_cursor()
	if (atn % 32 < 20 and not animation) or not on_field then
		for fx=0,1 do
			for fy=0,1 do
				spr(
					3,
					(fc_x - fcam_x)*16 + fx*8,
					(fc_y - fcam_y)*16 + fy*8,
					1,1,
					fx == 1,
					fy == 1)
			end
		end
	end
end

function draw_button_cursor()
	if atn % 32 < 20 or on_field then
		for fx=0,1 do
			for fy=0,1 do
				spr(
					3,
					bc_x*16 - 2 + fx*8,
					112 + fy*8,
					1,1,
					fx == 1,
					fy == 1)
			end
		end
	end
end

function draw_toolbar()
	draw_filled_rrect(
		0, 113,
		14, 14,
		0,
		4, 7)
	local s = nil
	if selected_tool == 0 then
		s = 24 + selected_seed
	elseif selected_tool == 1 then
		s = 40
	elseif selected_tool == 2 then
		s = 41
	end
	if s then
		spr(s,3,116)
	end
	
	draw_button(8, 0)
	draw_button(9, 1)
	draw_button(10, 2)
	draw_button(11, 3)
end

function draw_button(s, bx)
	local x=14+bx*16
	draw_filled_rrect(
		x+1, 113,
		14, 14,
		4,
		4, 7)
--	rrectfill(
--		x+1,
--		unpacks"113,14,14,4,15")
--	rrect(
--		x+1,
--		unpacks"113,14,14,4,4")
	spr(s,x+4,116)
end


-- scrolling code
function move_camera_down()
	if a_frame == 0 then
		sync_flower_sprites_row(fcam_y+7, true)
	end
	a_frame += 1
	if a_frame == 10 then
		fcam_y += 1
		for y=0,80,16 do
			blit(
				0x8000,0,y,
				0x8000,0,y+16,
				128,16)
		end
		sync_flower_sprites_row(fcam_y+6)
		stop_animation()
	else
		anim_dy = 1.6 * a_frame
	end
end

function move_camera_up()
	if a_frame == 0 then
		sync_flower_sprites_row(fcam_y-1, true)
	end
	a_frame += 1
	if a_frame == 10 then
		fcam_y -= 1
		for y=80,0,-16 do
			blit(
				0x8000,0,y+16,
				0x8000,0,y,
				128,16)
		end
		sync_flower_sprites_row(fcam_y)
		stop_animation()
	else
		anim_dy = -1.6 * a_frame
	end
end

function move_camera_right()
	if a_frame == 0 then
		sync_flower_sprites_col(fcam_x+8, true)
	end
	a_frame += 1
	if a_frame == 10 then
		fcam_x += 1
		for x=0,96,16 do
			blit(
				0x8000,x,0,
				0x8000,x+16,0,
				16,128)
		end
		sync_flower_sprites_col(fcam_x+7)
		stop_animation()
	else
		anim_dx = 1.6 * a_frame
	end
end

function move_camera_left()
	if a_frame == 0 then
		sync_flower_sprites_col(fcam_x-1, true)
	end
	a_frame += 1
	if a_frame == 10 then
		fcam_x -= 1
		for x=96,0,-16 do
			blit(
				0x8000,x+16,0,
				0x8000,x,0,
				16,128)
		end
		sync_flower_sprites_col(fcam_x)
		stop_animation()
	else
		anim_dx = -1.6 * a_frame
	end
end

function sync_flower_sprites_row(y, extra)
	for dx=0,7 do
		sync_flower_sprite(
			fcam_x+dx,
			y,
			extra and dx or nil,
			extra and 7 or nil)
	end
end

function sync_flower_sprites_col(x, extra)
	for dy=0,6 do
		sync_flower_sprite(
			x,
			fcam_y+dy,
			extra and dy or nil,
			extra and 7 or nil)
	end
end

function sync_flower_sprites()
	for y=1,f_max_y do
		sync_flower_sprites_row(y)
	end
end

-->8
--flowers and genes

--primary and secondary colors
--for different color phenotypes
flower_colors = {
	{8,14},
	{12,1},
	{9,10},
	{2,13}
}

--right shift index where
--genes vs other state starts
gene_start = 11
--number of bits per chromosome
--starting with the least
--significant bit
chr_sizes = {1,1,2,1,1,1}

flower_class = {}
flower_class.__index = flower_class

function flower_class:new(chr1,chr2)
	return setmetatable(
		{
			chr1=chr1,
			chr2=chr2,
		},
		self)
end

function flower_class:create(chr1,chr2)
	local f = flower_class:new(chr1,chr2)
	--flowers always start as a seed
	--with 3 days on growth timer
	f:set_growth_state(0,3)
	return f
end

function flower_class:place(fn, x, y)
	self.fn, self.x, self.y = fn, x, y
end

function flower_class:get_alleles(offset, size)
	local bit_shift = gene_start - offset
	return 
		get_bits(self.chr1, bit_shift, size),
		get_bits(self.chr2, bit_shift, size)
end

function flower_class:type()
	return get_bits(self.chr1, 16, 2)
end

function flower_class:growth_state()
	--value 1 is time
	--number of days left in current state	

	--value 2 is stage
	--0 seedling
	--1 growing
	--2 full grown
	--3 unused
	return get_bits(self.chr2, 13, 2), get_bits(self.chr2, 16, 3)
end

function flower_class:is_adult()
	return self:growth_state() == 2
end

function flower_class:set_growth_state(stage, t)
	self.chr2 = set_bits(
		set_bits(self.chr2, stage, 13, 2),
		t, 16, 3)
end

function is_recessive(a1, a2)
	return a1*a2 == 1
end

function combine_gene_level(a1, a2)
	return a1+a2
end

function flower_class:color_gene_level()
	-- color gene expression
	-- 0 0 -> red
	-- 0 1 -> blue
	-- 1 0 -> blue
	-- 1 1 -> yellow
	return combine_gene_level(self:get_alleles(0,1))
end

function flower_class:has_dark_gene()
	-- dark gene expression
	-- dark (1) is recessive
	-- 0 0 -> light
	-- 0 1 -> light
	-- 1 1 -> dark
	return is_recessive(self:get_alleles(1,1))
end

function flower_class:color()
	--if the flower has the dark gene
	--it's always purple. otherwise
	--it's the color dictated by the
	--color gene
	if self:has_dark_gene() then
		return 3
	else
		return self:color_gene_level()
	end
end

function flower_class:pollinator_attract_level()
	if not self:is_adult() then
		return 0
	end
	return max(self:get_alleles(2,2))
end

function flower_class:needs_pollinator_gene()
	-- needs pollinator (0) is dominant
	return not is_recessive(self:get_alleles(4,1))
end

function flower_class:has_vigorous_gene()
	-- vigorous (1) is recessive
--	return self:type() == 2
	return is_recessive(self:get_alleles(5,1))
end

function flower_class:has_weed_defense_gene()
	-- weed defenese (0) is dominant
--	return self:type() == 2
	return not is_recessive(self:get_alleles(6,1))
end


function flower_class:is_compatible(flower)
	return self:type() == flower:type()
end

function flower_class:can_breed()
	if not self:needs_pollinator_gene() then
		return true
	end
	--right now cannot attract pollinators that you need to yourself
	--because generate_neighbors excludes self
	for coords, d in pairs(generate_neighbors(self.x, self.y, 2)) do
		local neighbor = field1:get(unpacks(coords))
		if neighbor and neighbor:pollinator_attract_level() >= d then
			return true
		end
	end
end

--end flower class definition

function generate_flower(flower_type)
	--right now, this uses a
	--one of three template image
	--and recolors into 1 of 4
	--color palettes.

	--chr1 and chr2 have different meanings
	--of their first 5 bits
	--in chr1, bits 1-2 are the flower type
	--in chr2, bits 4-5 are the flower growth stage
	--bits 1-3 are the time in stage
	local chr1,chr2 = flower_type >> 16, 0
	--the rest of the bits have identical
	--meaning between chromosomes
	--bits 6-7 are the colors
	chr1 += flr(rnd(4)) >> 11
	chr2 += flr(rnd(4)) >> 11
	--bits 8-9 are pollinator attract level
	--value is pollinator level (0-2)
--	chr1 += 1 >> 9
--	chr2 += 1 >> 9
	--bit 10 is needs pollinator
	--0 means needs pollinator
	--1 means doesn't need
	chr1 += 1 >> 7
	chr2 += 1 >> 7
	--bit 11 is vigorous (can grown over other plants and weeds)
	--1 means vigorous
	--bit 12 is weed defense
	--0 means causes nearby weeds to die
	chr1 += 1 >> 5
	chr2 += 1 >> 5
	
	return flower_class:create(chr1, chr2)
end

function spr_pos(s)
	--get sprite sheet position
	--from sprite number
	return s % 16 * 8, s \ 16 * 8
end

function breed(flower1, flower2)
	local chr1, chr2, offset = 0, 0, 0
	--take the flower type from a parent
	chr1 += flower1.chr1 & (0b11 >> 16)
	
	--go gene by gene, taking one
	--allele from each parent
	--since all entries in chr_sizes
	--are 1 right now, there are no
	--linked traits, but we can adjust
	--this to make adjacent genes
	--inherited together
	for size in all(chr_sizes) do
		local a1 = rnd(pack(flower1:get_alleles(offset,size)))
		local a2 = rnd(pack(flower2:get_alleles(offset,size)))
		chr1 += a1 >> gene_start - offset
		chr2 += a2 >> gene_start - offset
		offset += size
	end
	return flower_class:create(chr1, chr2)
end

function gene_str(flower)
	return tostr(flower.chr1, true).."\n"..tostr(flower.chr2, true)
end

function draw_to_swap_sprite(s,x_off,y_off,w,h,f)
	local sx, sy = spr_pos(s)
	for x=0,w do
		for y=0,h do
			local pc = sget(sx+x, sy+y)
			if pc != 4 then
				sset(x_off+x,y_off+y,f and f(pc) or pc)
			end
		end
	end
end

function create_flower_sprite(flower)
	--always must immediately copy this somewhere
	--as it will be overwritten on next
	--call to create_sprite
	local template = 32 + flower:type() * 2
	local growth_stage = flower:growth_state()
	local c = flower:color()

	local w,h,offx,offy=unpacks"15,15,0,0"
	if growth_stage == 0 then
		w,h,offx,offy,template=unpacks"7,7,4,8,19"
	elseif growth_stage == 1 then
		h,offy,template=unpacks"7,8,20"
	end
	
	--erase sprite swap space
	poke(0x5f55,0x00)
	rectfill(unpacks"0,0,15,15,4")
	poke(0x5f55,0x60)
	
	--draw template to the sprite sheet
	draw_to_swap_sprite(
		template,offx,offy,w,h,
		function(pc)
			if pc <= 2 then
				pc = flower_colors[c+1][pc]
			end
			return pc
		end
	)
	
	-- add a bee
--animated
--	local dy = atn \ 64
	local dy = 0
	if flower:pollinator_attract_level() > 0 then
		draw_to_swap_sprite(5,9,dy,4,4)
	end
end

function create_and_place_flower_sprite(flower, sx, sy)
	local screen_x, screen_y = sx and sx or flower.x - fcam_x, sy and sy or flower.y - fcam_y
	if sx or (screen_x >= 0 and screen_x <= 7 and screen_y >= 0 and screen_y <= 6) then
		create_flower_sprite(flower)
		--copy sprite to correct location in
		--extended sprite sheet 0
		blit(
			0x8000,
			screen_x * 16, screen_y * 16,
			0x0000,
			0, 0,
			16, 16
		)
	end
end

function remove_flower_sprite(x, y, sx, sy)
	--the beginning of extended sprite sheet 1
	--should be empty, so copy 0s from there
	--i think this is more efficient than
	--using memset since we need to
	--remove each row of pixels
	--todo: there's a lot of reuse between
	--this and the function above - possibly
	--can refactor to save tokens
	local screen_x, screen_y = sx and sx or x - fcam_x, sy and sy or y - fcam_y
	blit(
		0x8000,
		screen_x * 16, screen_y * 16,
		0xa000,
		0, 0,
		16, 16
	)
end
-->8
--flower breeding

breed_rate = 20
--breed_rate = 100

function for_all_flowers(fn)
	for x=1,f_max_x do
		for y=1,f_max_y do
			local flower = field1:get(x,y)
			if flower then
				fn(flower,x,y)
			end
		end
	end
end

function time_passes()
	breed_all_flowers()
	for_all_flowers(function(flower)
		local growth_stage, growth_time = flower:growth_state()
		if growth_stage < 2 then
			if growth_time == 0 then
				flower:set_growth_state(growth_stage+1, 3)
			else 
				flower:set_growth_state(growth_stage, growth_time - 1)
			end
		else
			if flower:has_weed_defense_gene() then
				for coords, _ in pairs(generate_neighbors(flower.x, flower.y, 2)) do
					field1:set_weeds(false, unpacks(coords))
				end
			end
		end
	end)
	sync_flower_sprites()
	day += 1
end

function breed_all_flowers()
	--breeding logic:
	--cribbed this from ac wiki
	--for each flower, it has some
	--chance to breed.
	--if a flower has an adjacent
	--flower of the same type with
	--an adjacent space next to
	--both, they breed.
	--otherwise, if it has no
	--partner, it makes a clone
	
	--make a list of flowers that will
	--breed
	breeding = {}
	for_all_flowers(function(flower)
		if flower:is_adult() and flower:can_breed() and rnd(100) < breed_rate then
			add(breeding, flower)
		end
	end)

	--shuffle the order they're
	--processed in
	for i=#breeding,2,-1 do
		local j=flr(rnd(i)) + 1
		breeding[i],breeding[j]=breeding[j],breeding[i]
	end
	
	for flower in all(breeding) do
		--determine eligible neighbors
		local all_neighbors = generate_neighbors(flower.x, flower.y)
		local eligible_neighbors={}

		for coords,_ in pairs(all_neighbors) do
			local nx, ny = unpacks(coords)
			local neighbor = field1:get(nx, ny)
			if neighbor and neighbor:is_adult() and flower:is_compatible(neighbor) then
				local child_spaces = {}
				for coords in all(intersection(
						all_neighbors,
						generate_neighbors(nx, ny))) do
					if can_flower_spread_to_coords(flower, coords) then
						add(child_spaces, coords)
					end
				end
				if #child_spaces > 0 then
					local cx,cy = unpacks(rnd(child_spaces))
					add(eligible_neighbors, {neighbor, cx, cy})
				end
			end
		end
		
		--create a new flower
		if #eligible_neighbors > 0 then
			local neighbor,cx,cy = unpack(rnd(eligible_neighbors))
			local child = breed(flower, neighbor)
			add_flower_to_field(child, cx, cy)
		else
			local clone_spaces = {}
			for coords,_ in pairs(all_neighbors) do
				if can_flower_spread_to_coords(flower, coords) then
					add(clone_spaces, coords)
				end
			end
			if #clone_spaces > 0 then
				local cx, cy = unpacks(rnd(clone_spaces))
				local child = flower_class:create(flower.chr1, flower.chr2)
				add_flower_to_field(child, cx, cy)
			end
		end
	end
end

function intersection(coords1, coords2)
	local ins = {}
	for coords,_ in pairs(coords1) do
		if coords2[coords] then
			add(ins, coords)
		end
	end
	return ins
end

function generate_neighbors(x,y,radius)
	local coords = {}
	radius = radius or 1
	for dx=-1*radius,radius do
		for dy=-1*radius,radius do
			if dx !=0 or dy != 0 then
				local x2, y2 = x+dx, y+dy
				if check_field_bounds(x2, y2) then
					coords[x2..","..y2] = max(abs(dx),abs(dy))
				end
			end
		end
	end
	return coords
end

function can_flower_spread_to_coords(flower, coords)
	local cx,cy = unpacks(coords)
	local cf = field1:get(cx,cy)
	return 
		(flower:has_vigorous_gene() and not (cf and cf:has_vigorous_gene())) or
			not (cf or field1:has_weeds(cx,cy))
end

-->8
--calendar screen

function init_calendar_screen()
	days_of_week = split"mon,tue,wed,thu,fri,sat,sun"
	days_in_month = split"31,28,31,30,31,30,31,31,30,31,30,31"
	months = split"january,february,march,april,may,june,july,august,september,october,november,december"
	current_y,current_m,current_d = get_current_date()
end

function start_calendar_screen()
	mode = 2
	y,m,d=current_y,current_m,current_d
	cc_x,cc_y = 0,0
	--6 row month for test
--	local y,m,d=2026,8,12
	--longest month name for test
--	local y,m,d=2026,9,12
end

function update_calendar_screen()
	if btnp(❎) then
		start_field_screen()
	end
	if btnp(⬆️) then
		cc_y -= 1
	elseif btnp(⬇️) then
		cc_y += 1
	elseif btnp(⬅️) then
		cc_x -= 1
	elseif btnp(➡️) then
		cc_x += 1
	end
	cc_y = mid(0,cc_y,5)
	cc_x = mid(0,cc_x,6)
end

function draw_calendar_screen()
	draw_calendar()
	draw_calendar_cursor()
end

function draw_calendar()
	draw_filled_rrect(unpacks"0,0,128,128,0,4,15")
	rectfill(unpacks"5,5,122,18,14")
	draw_filled_rrect(unpacks"4,19,120,15,0,0,7")
	
	for i=1,7 do
		print(days_of_week[i], -10+17*i, 21)
	end
	
	local first_day = get_day_of_week(y,m,1)
	
	--we could center this text, but probably not worth it
	print("\^w\^t"..months[m].." "..y,10,7,7)
	
	for j=0,5 do
		for i=0,6 do
			local date = get_date_from_coord(i,j,first_day)
			local x,y,c=4+i*17,27+j*16,7
			if date <= 0 or date > days_in_month[m] then
				c = 5
			end
			draw_filled_rrect(x,y,18,17,0,0,c)
			if c != 5 then
				print(date,x+2,y+2,date == d and 8 or 0)
				spr(date % 2 == 0 and 10 or 24,x+9,y+8)
			end
		end
	end
	
	rect(unpacks"4,4,123,123,4")
end

function draw_calendar_cursor()
	--i do not remember what this math means
	local x1,y1=4+cc_x*17,27+cc_y*16
	rect(x1,y1,x1+17,y1+16,14)
end

function get_date_from_coord(i,j,first_day)
	return i+j*7 - first_day + 2
end

function get_current_date()
	return stat(90), stat(91), stat(92)
end

function get_day_of_week(y,m,d)
	local t = split"0,3,2,5,0,3,5,1,4,6,2,4"
	if m < 3 then
		y -= 1
	end
	return (y + y\4 - y\100 + y\400 + t[m] + d) % 7 + 1
end
-->8
--menus

menu_is_open = false

function open_menu(on_close)
	menu_on_close = on_close
	menu_is_open = true
	mc_y = 1
end

function open_seed_menu(on_close)
	open_menu(on_close)
	menu_title = "seeds"
	--max name is 11 characters
	--without adjusting menu size
	--should format option line
	--as part of generating from
	--inventory
	options = {
		split"24,tulip       Xinf,0",
		split"25,primrose    Xinf,1",
		split"26,trumpet     Xinf,2"
	}
	menu_min_x,menu_min_y = 20,20
	menu_w,menu_h = 87,60
end

function open_tools_menu(on_close)
	open_menu(on_close)
	menu_title = "tools"
	options = {
		split"40,destroy,1",
		split"41,genetics,2",
	}
	menu_min_x,menu_min_y = 31,67
	menu_w,menu_h = 55,41
end

function open_options_menu(on_close)
	open_menu(on_close)
	menu_title = "options"
	options = {
		split"56,calendar,1",
		split"57,save,2",
		split"58,load,3",
	}
	menu_min_x,menu_min_y = 63,55
	menu_w,menu_h = 55,55
end

function update_menu()
	if btnp(🅾️) then
		menu_is_open = false
		menu_on_close(options[mc_y])
	end
	if btnp(❎) then
		menu_is_open = false
	end
	if btnp(⬆️) then
		mc_y -= 1
	elseif btnp(⬇️) then
		mc_y += 1
	end
	mc_y = mid(1,mc_y,#options)
end

function draw_menu()
	draw_filled_rrect(
		menu_min_x,
		menu_min_y,
		menu_w,
		menu_h,
		0,5,15)
	print(
		menu_title,
		menu_min_x+4,
		menu_min_y+4,0)
	for i = 1,#options do
		local line_y = menu_min_y - 3 + i * 14
		sprite, text = unpack(options[i])
		draw_filled_rrect(
			menu_min_x+4,
			line_y,
			12,12,0,4,7)
		spr(
			sprite,
			menu_min_x+6,
			line_y+2)
		print(
			text,
			menu_min_x+20,
			line_y+3,0)
	end
	
	local cursor_line_y = menu_min_y - 3 + mc_y * 14
	rect(
		menu_min_x+4,
		cursor_line_y,
		menu_min_x+15,
		cursor_line_y+11,
		6)
end




-->8
--genetics screen
--first draft just show a vertical list
--with name + both values

function init_genetics_screen()
	gene_info = {
		"0,1,color",
		"1,1,darkness",
		"2,2,attractiv",
		"4,1,rq polntr",
		"5,1,vigorous",
		"6,1,weed def",
		"0,0,save"
	}
	gc_max_y = #gene_info
end

function start_genetics_screen(flower)
	mode = 3
	g_flower = flower
	gc_y,gc_x,g_current_value = 1,1
	gc_cy = 1
end

function update_genetics_screen()
	local gene_offset, gene_size, gene_name = unpacks(gene_info[gc_y])
	if g_current_value then
		if btnp(⬆️) then
			g_current_value += 1
			atn = 0
		elseif btnp(⬇️) then
			g_current_value -= 1
			atn = 0
		end
		g_current_value = mid(0,g_current_value,max_binary(gene_size))

		if btnp(❎) then
			g_current_value = nil
		elseif btnp(🅾️) then
			local bit_shift = gene_start - gene_offset
			if gc_x == 1 then
				g_flower.chr1 = set_bits(g_flower.chr1, g_current_value, bit_shift, gene_size)
			else
				g_flower.chr2 = set_bits(g_flower.chr2, g_current_value, bit_shift, gene_size)
			end
			g_current_value = nil
		end
	else
		if btnp(🅾️) then
			if gc_y == gc_max_y then
				sync_flower_sprite(g_flower.x,g_flower.y)
				resume_field_screen()
			else
				g_current_value = pack(g_flower:get_alleles(gene_offset, gene_size))[gc_x]
			end
		end
		if btnp(⬆️) then
			gc_y -= 1
		elseif btnp(⬇️) then
			gc_y += 1
		elseif btnp(⬅️) then
			gc_x -= 1
		elseif btnp(➡️) then
			gc_x += 1
		end
	end
	gc_y = mid(1,gc_y,gc_max_y)
	gc_x = mid(1,gc_x,2)
	gc_cy = min(gc_y,max(gc_cy,gc_y-7))
end

function draw_genetics_screen()
	--draw frame
	draw_filled_rrect(unpacks"0,0,128,128,0,5,6")
	-- camera + clip
	camera(0,gc_cy*15-15)
	draw_genetics_screen_info()
	draw_genetics_screen_cursor()
	camera()
end

function draw_genetics_screen_info()
	local y
	for i=1,gc_max_y do
		y = -5 + i*15
		local gene_offset, gene_size, gene_name = unpacks(gene_info[i])
		local chr1, chr2 = g_flower:get_alleles(gene_offset, gene_size)
		print(gene_name, 10, y, 0)
		if i < gc_max_y then
			print(genetics_screen_disp_value(chr1,1,i),60,y)
			print(genetics_screen_disp_value(chr2,2,i),74,y)
		end
	end
end

function genetics_screen_disp_value(v,x,y)
	if not g_current_value or x != gc_x or y != gc_y then
		return v
	else
		return atn % 32 < 20 and g_current_value or ""
	end
end

function draw_genetics_screen_cursor()
	if gc_y == gc_max_y then
		rect(8,-7+gc_y*15,26,1+gc_y*15,0)
	else
		print("⬆️",44+gc_x*14,-11+gc_y*15)
		print("⬇️",44+gc_x*14,1+gc_y*15)
	end
end

__gfx__
00000000000000004444f44477700000033000004466444400000000000000000044440004440066009999000000000000000000000000000000000000000000
777777777777777744444444700000000000003346644444000000000000000004ffff4000400604097757900555555000000000000000000000000000000000
000000000000000044f44444700000000000030009094444000000000000000004f55f4000406004977757790000000000000000000000000000000000000000
000000000000700044f44444000000003300000099090444000000000000000004ffff4000400004977757790555555000000000000000000000000000000000
0000000000007000444444f4000000000030000040444444000000000000000004ff8f4000400004975557790000000000000000000000000000000000000000
7770077070700770444444f4000000000000033044444444000000000000000004f83f4066666004977777790555555000000000000000000000000000000000
707070007070070744444444000000003300300044444444000000000000000004f33f4066666004097777900000000000000000000000000000000000000000
77007770707007074444f44400000000000000034444444400000000000000000544445006660004009999000000000000000000000000000000000000000000
70700070777007070000000044444444444444444444444400000000000000000080020000cccc00999999990000000000000000000000000000000000000000
7070770007000777000000004444444444444444444b34440000000000000000008822000cccccc0099999900000000000000000000000000000000000000000
000000000000000000000000444444444444444444b334440000000000000000088882200cc99cc0009999000000000000000000000000000000000000000000
0000000000000000000000004444444444443b444b3344440000000000000000088888200cc99cc0009999000000000000000000000000000000000000000000
0000000000000000000000004444b444444433bb333444440000000000000000088888800cccccc0009999000000000000000000000000000000000000000000
777777777777777700000000444b344444444333b444444400000000000000000088880000cccc00000990000000000000000000000000000000000000000000
00000000000000000000000044433444444444433444444400000000000000000003300000033000000330000000000000000000000000000000000000000000
00000000000000000000000044533544444444533544444400000000000000000003300000033000000330000000000000000000000000000000000000000000
44444444444444444444444444444444444444444122444400000000000000000000066000199c00000000000000000000000000000000000000000000000000
4444414114144444444444411444444444444444121124440000000000000000000046660001c000000000000000000000000000000000000000000000000000
444441211214444444441121121144444444444412111244000000000000000000004066000c1000000000000000000000000000000000000000000000000000
44441112121144444444112112114444444444411121124400000000000000000004000600188c00000000000000000000000000000000000000000000000000
44441111211144444444221771224444444444411122244400000000000000000040000600199c00000000000000000000000000000000000000000000000000
4444111112114444444111777711144444444441112444440000000000000000040000600001c000000000000000000000000000000000000000000000000000
444411111121444444411177771114444444444112444444000000000000000004000000000c1000000000000000000000000000000000000000000000000000
44444111111444444444221771224444444444411444444400000000000000004000000000188c00000000000000000000000000000000000000000000000000
4444441111444444444411211211444444444443344b34440000000000000000eeeeeeeed6656d00ffff00000000000000000000000000000000000000000000
44444443344b344444441121121144444444444334b334440000000000000000eeeeeeeed6656dd0ffffffff0000000000000000000000000000000000000000
4444444334b33444444444411444444444443b433b334444000000000000000067777776d6666dddf777777f0000000000000000000000000000000000000000
44443b433b3344444444444334b34444444433b333344444000000000000000067755776ddddddddf755557f0000000000000000000000000000000000000000
444433b33334444444443b433b3344444444433334444444000000000000000067775776d666666df777777f0000000000000000000000000000000000000000
4444433334444444444433b3333444444444444334444444000000000000000067755576d655556df755557f0000000000000000000000000000000000000000
444444433444444444444333344444444444444334444444000000000000000066777776d666666df777777f0000000000000000000000000000000000000000
444444533544444444444453354444444444445335444444000000000000000056666666d666666dffffffff0000000000000000000000000000000000000000
__label__
7774f4444444f7774444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
74444444444444474444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
74f4444444f4444744f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
744444f4444444f7444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
74444444444444474444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
7774f4444444f7774444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
44444444444444444444444444444444444448488484444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44f4444444f4444444f4444444f4444444f448e88e84444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
44f4444444f4444444f4444444f4444444f4888e8e88444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
444444f4444444f4444444f4444444f444448888e88844f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
444444f4444444f4444444f4444444f4444488888e8844f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
444444444444444444444444444444444444888888e8444444444444444444444444444444444444444444444444444444444444444444444444444444444444
4444f4444444f4444444f4444444f4444444f8888884f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
4444f4444444f4444444f4444444f4444444f4888844f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
44444444444444444444444444444444444444433443344444444444444444444444444444444444444444444444444444444444444444444444444444444444
44f4444444f4444444f4444444f4444444f444433433344444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
44f4444444f4444444f4444444f4444444f433433333444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
444444f4444444f4444444f4444444f444443333333444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
444444f4444444f4444444f4444444f444444333344444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
44444444444444444444444444444444444444433444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
4444f4444444f4444444f4444444f4444444f4433444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
44f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f44444
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
4444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f4444444f444
77700000000007770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
70004444444400070000444444440000000044444444000000004444444400000000444444440000000000000000000000000000000000000000000000000000
7004ffffffff40070004ffffffff40000004ffffffff40000004ffffffff40000004ffffffff4000000000000000000000000000000000000000000000000000
004ffffffffff400004ffffffffff400004ffffffffff400004ffffffffff400004ffffffffff400000000000000000000000000000000000000000000000000
04ffff8ff2ffff4004ffffccccffff4004ff8ffffff8ff4004ffff7777ffff4004ffd6656dffff40000000000000000000000000000000000000000000000000
04ffff8822ffff4004fffccccccfff4004fff8ffff8fff4004fff777577fff4004ffd6656ddfff40000000000000000000000000000000000000000000000000
04fff888822fff4004fffcc99ccfff4004ffff8ff8ffff4004ff77775777ff4004ffd6666dddff40000000000000000000000000000000000000000000000000
04fff888882fff4004fffcc99ccfff4004fffff88fffff4004ff77775777ff4004ffddddddddff40000000000000000000000000000000000000000000000000
04fff888888fff4004fffccccccfff4004fffff88fffff4004ff77555777ff4004ffd666666dff40000000000000000000000000000000000000000000000000
04ffff8888ffff4004ffffccccffff4004ffff8ff8ffff4004ff77777777ff4004ffd655556dff40000000000000000000000000000000000000000000000000
04fffff33fffff4004fffff33fffff4004fff8ffff8fff4004fff777777fff4004ffd666666dff40000000000000000000000000000000000000000000000000
04fffff33fffff4004fffff33fffff4004ff8ffffff8ff4004ffff7777ffff4004ffd666666dff40000000000000000000000000000000000000000000000000
004ffffffffff400004ffffffffff400004ffffffffff400004ffffffffff400004ffffffffff400000000000000000000000000000000000000000000000000
7004ffffffff40070004ffffffff40000004ffffffff40000004ffffffff40000004ffffffff4000000000000000000000000000000000000000000000000000
70004444444400070000444444440000000044444444000000004444444400000000444444440000000000000000000000000000000000000000000000000000
77700000000007770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

__map__
0000e0e1e2e3e4e5e6e7e8e9eaeb00edeeef0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
e0e1000102030405060708090a0b0c0d0e0fe0e1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f0f1101112131415161718191a1b1c1d1e1ff0f1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
e2e3202122232425262728292a2b2c2d2e2fe2e3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f2f3303132333435363738393a3b3c3d3e3ff2f3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
e4e5404142434445464748494a4b4c4d4e4fe4e5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f4f5505152535455565758595a5b5c5d5e5ff4f5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
e6e7606162636465666768696a6b6c6d6e6fe6e7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f6f7707172737475767778797a7b7c7d7e7ff6f7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
e8e9808182838485868788898a8b8c8d8e8fe8e9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f8f9909192939495969798999a9b9c9d9e9ff8f9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
eaeba0a1a2a3a4a5a6a7a8a9aaabacadaeafeaeb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
fafbb0b1b2b3b4b5b6b7b8b9babbbcbdbebffafb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
ecedc0c1c2c3c4c5c6c7c8c9cacbcccdcecfeced000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
fcfdd0d1d2d3d4d5d6d7d8d9dadbdcdddedffcfd000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000e0e1e2e3e4e5e6e7e8e9eaebecedeeef0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
