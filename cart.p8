pico-8 cartridge // http://www.pico-8.com
version 8
__lua__

--[[

quickdraw gambit?

need to despawn most things from one level when entering another (barrels that roll off screen...)
need to come up with another way to create a scrolling background
need to just make everything way more efficient

hazards so far:
	bullets
	cannonballs
	dynamite
	rolling barrels
	rolling explosive barrels
	quicksand

hazards to build:
	lasso
	boulders
	quickshot
	(jump pads)
	(boomerangs)
	(sandstorm/wind)
	(bow & arrow)

collision_channels:
	1: ground
	2: left wall, right wall
	4: crates
	8: barrels

hitbox_channels:
	1: player swing
	2: enemy bullets
	4: level exit
	8: explosions
	16: rolling barrels
	32: quicksand

render_layers:
	0: the sky
	1: the sun
	2: far background entities (clouds)
	3: background entities (ridges)
	4: blood, muzzle flash
	5: ??
	6: twinkle
	7: quicksand

update priority:
 5: ???
 6: player

axis:
      +y (up)
       |
  -x --+-- +x (right)
(left) |
      -y (down)

how pixels should be drawn:
  [-0.5,0.5)
       |
       v
     +---+---+
     |   |   | <- (0,1]
     +---+---+
     |   |   | <- (-1,0]
     +---+---+
           ^
           |
       [0.5,1.5)

]]

local debug_skip_amt=1
local debug_num_steps=0

-- global vars
local player
local sun
local sky
local left_wall
local right_wall
local scene
local level_num
local scene_frame
local slow_mo_frames
local freeze_frames
local pause_frames
local slide_frames
local skip_frames=0
local entities
local new_entities
local smoke
local light_sources
local wind
local buttons={}
local button_presses={}
function noop() end


-- constants
local ground={vx=0,vy=0}
local directions={"left","right","bottom","top"}
local dir_lookup={
	-- axis,size,increment
	left={"x","width",-1},
	right={"x","width",1},
	bottom={"y","height",-1},
	top={"y","height",1}
}
local scenes={}
local color_ramps={
	debug={1,5,13,6,7},
	red={1,2,8,8,14},
	grey={1,5,13,6,7},
	brown={1,2,4,4,15}
}
local levels={
	-- name,shooter_params
	{
		"shooter",{
			name="outlaw 1",
			weapon="barrels",
			behavior=function(self)
				if self.frames_alive%50==10 then
					self:shoot()
				end
			end
		},
		"rolling_barrel",{x=20},
		-- "barrel",{x=20,y=10},
		"cactus",{x=88},
		"small_ridge",{x=58+7},
		"tiny_ridge",{x=66+7},
		"cloud",{x=15},
		"crate",{x=50},
		"quicksand",{x=20,width=2+8*4}
	},
	{
		"shooter",{
			name="jumpin' jane",
			behavior=function(self)
				if self.frames_alive%25==8 then
					self:shoot()
				end
				if self.frames_alive%50==1 then
					self:jump(0,3)
				end
			end
		},
		"barrel",{x=35+4},
		"cactus",{x=88},
		"small_ridge",{x=58+7-44},
		"tiny_ridge",{x=66+7-44},
		"cloud",{x=15}
	},
	{
		"shooter",{
			name="outlaw 3",
			behavior=function(self)
				if self.frames_alive%5==4 and self.frames_alive%50<=14 then
					self:shoot()
				end
				if self.frames_alive%50==35 then
					self:shoot()
				end
				if self.frames_alive%100==26 then
					self:jump(0,3)
				end
				if self.frames_alive%100==80 then
					self:jump(0,1)
				end
			end
		},
	},
	{
		"shooter",{
			name="shotgun shane",
			behavior=function(self)
				if self.frames_alive%55==15 then
					self:jump(0,3)
				end
				if self.frames_alive%55==19 then
					local i
					for i=-4,4,2 do
						self:shoot({
							angle=i,
							skip_effects=(i!=0),
							vel_change_frames=22
						})
					end
				end
			end
		},
		"distant_ranch",{x=10,flipped=false}
	},
	{
		"shooter",{
			name="outlaw 5",
			weapon="barrels",
			behavior=function(self)
				if self.frames_alive%80==1 then
					self:jump(0,3)
				end
				if self.frames_alive%40==5 then
					self.weapon="barrels"
					self:shoot()
				end
			end
		},
		-- "barrel",{x=40},
		-- "barrel",{x=50},
		-- "barrel",{x=60,y=10},
		-- "barrel",{x=60,y=20},
		-- "barrel",{x=60},
		-- "barrel",{x=70},
		-- "barrel",{x=80},
		"barrel",{x=20},
		"crate",{x=110}
		-- "rolling_barrel",{x=100,vx=-1},
		-- "rolling_barrel",{x=35,y=3,vx=1}
	}
}
local entity_classes={
	person={
		-- spatial props
		width=3,
		height=5,
		facing=1,
		anti_grav_frames=0,
		-- collision props
		collision_channel=15, -- ground, invisible walls, crates, barrels
		standing_platform=nil,
		-- state props
		is_jumping=false,
		is_jumping_upwards=false,
		has_been_hurt=false,
		-- frame data
		bleed_frames=0,
		turn_around=function(self)
			self.facing=-self.facing
		end,
		bleed=function(self)
			decrement_counter_prop(self,"bleed_frames")
			if self.bleed_frames>0 then
				local ang=self.bleed_frames/40+0.05-rnd(0.12)
				create_entity("blood",{
					x=self.x+1,
					y=self.y+3,
					vx=self.vx/2-self.facing*sin(ang),
					vy=self.vy/2+0.75*cos(ang)
				})
			end
		end,
		on_collide=function(self,dir,platform)
			if dir=="bottom" then
				self.standing_platform=platform
				self.is_jumping=false
				self.is_jumping_upwards=false
				self.anti_grav_frames=0
				if self.has_been_hurt then
					self.vx=0
				end
			end
		end,
		on_hurt=function(self,other)
			self.hurtbox_channel=0
			self.has_been_hurt=true
			self.anti_grav_frames=0
			if other.facing then
				self.facing=-other.facing
			elseif other.vx>0 then
				self.facing=-1
			elseif other.vx<0 then
				self.facing=1
			elseif other.x+other.width/2<self.x+self.width/2 then
				self.facing=-1
			else
				self.facing=1
			end
			self.vx=-self.facing
			self.vy=1.5
			self.standing_platform=nil
			if other.causes_bleeding then
				self.bleed_frames=10
			end
			pause_frames=max(pause_frames,17)
		end
	},
	player={
		extends="person",
		x=5,
		is_crouching=false,
		is_slide_pause_immune=false,
		update_priority=6,
		slash_frames=0,
		slash_cooldown_frames=0,
		input_dir=0,
		slash_dir=1,
		pose_frames=0,
		hitbox_channel=1,
		causes_bleeding=true,
		hurtbox_channel=62, -- enemy bullets, level exit, explosions, rolling barrels, quicksand
		update=function(self)
			decrement_counter_prop(self,"pose_frames")
			decrement_counter_prop(self,"slash_frames")
			decrement_counter_prop(self,"slash_cooldown_frames")
			decrement_counter_prop(self,"anti_grav_frames")
			self.input_dir=ternary(buttons[1],1,0)-ternary(buttons[0],1,0)
			self.is_jumping_upwards=self.is_jumping_upwards and buttons[2]
			if not self.has_been_hurt and self.pose_frames<=0 then
				-- change facing
				if self.slash_frames==0 and self.input_dir!=0 then
					self.facing=self.input_dir
				end
				-- slash
				if self.slash_cooldown_frames==0 and (buttons[4] or buttons[5]) and not self.is_stuck_in_quicksand then
					self.slash_dir*=-1
					self.slash_frames=9
					self.slash_cooldown_frames=20
					if self.is_jumping then
						self.vy=0
						self.anti_grav_frames=15
					end
				end
			end
			if not self.has_been_hurt then
				-- move
				if (self.slash_frames>0 and not self.is_jumping) or self.pose_frames>0 then
					self.vx=0
				else
					self.vx=self.input_dir
				end
			end
			-- gravity
			if self.anti_grav_frames>0 then
				self.vy-=0.05
			else
				self.vy-=0.2
			end
			if not self.has_been_hurt then
				-- jump
				if self.standing_platform and buttons[2] and self.pose_frames<=0 then
					self.vy=2.1
					self.is_jumping=true
					self.is_jumping_upwards=true
				end
				-- end jump
				if self.is_jumping and not self.is_jumping_upwards and self.vy==mid(0.6,self.vy,1.8) then
					self.vy=0.6
				end
			end
			-- move/find collisions
			self.standing_platform=nil
			self:apply_velocity()
			-- crouch
			self.is_crouching=self.standing_platform and self.vx==0 and buttons[3] and self.pose_frames<=0
			self.height=ternary(self.is_crouching,4,5)
			self:bleed()
		end,
		draw=function(self)
			-- figure out the correct sprite
			local sprite=0
			if self.is_stuck_in_quicksand then
				sprite=ternary(self.has_been_hurt,8,0)
			elseif self.has_been_hurt then
				sprite=ternary(self.standing_platform,8,7)
			elseif self.pose_frames>0 and self.pose_frames<45 then
				sprite=ternary(self.pose_frames>40,9,10)
			elseif self.slash_frames>0 then
				sprite=ternary(self.is_jumping and self.vx!=0 and (self.facing<0)==(self.vx<0),7,6)
			elseif self.is_jumping then
				sprite=ternary(self.vx==0,4,5)
			elseif self.is_crouching then
				sprite=1
			elseif self.vx!=0 then
				sprite=2+flr(self.frames_alive/4)%2
			end
			-- draw the sprite
			self:apply_lighting(self.facing<0)
			sspr(8*sprite,0,8,6,self.x-ternary(self.facing<0,2.5,1.5),-self.y-6,8,6,self.facing<0)
			pal()
			-- draw the sword slash
			if self.slash_frames>0 then
				local slash_sprite=({6,6,5,4,4,3,2,1,0})[self.slash_frames]
				sspr(10*slash_sprite,ternary(self.slash_dir<0,15,6),10,9,self.x-ternary(self.facing<0,4.5,1.5),-self.y-7,10,9,self.facing<0)
			end
			-- draw pose schwing
			if self.pose_frames==mid(17,self.pose_frames,30) then
				local pose_sprite=flr(60-(self.pose_frames-18)/2)
				spr(pose_sprite,self.x+ternary(self.facing<0,-5.5,1.5),-self.y-8,1,1,self.facing<0)
			end
		end,
		pose=function(self)
			self.pose_frames=45
			self.is_jumping_upwards=false
			self.slash_frames=0
			self.facing=1
		end,
		check_for_hits=function(self,other)
			return
				self.slash_frames>=3 and
				self.slash_frames<=7 and
				rects_overlapping(
					self.x-ternary(self.facing<0,7,0),self.y-3,10,10,
					other.x,other.y,other.width,other.height)
		end,
		on_hit=function(self,other)
			-- other.is_slashed=true
			self.slash_cooldown_frames=self.slash_frames
		end,
		on_hurt=function(self,other)
			if not other.is_slashed then
				self:super_on_hurt(other)
				self.hurtbox_channel=32 -- quicksand
				self.slash_frames=0
				self.pose_frames=0
			end
		end
	},
	shooter={
		-- name
		extends="person",
		x=118,
		height=6,
		facing=-1,
		hurtbox_channel=1,
		walk_frames=0,
		collision_channel=13, -- ground, crates, barrels
		weapon="gun",
		init=function(self)
			self.name_tag=create_entity("name_tag",{
				x=127+self.slide_rate*max(0,slide_frames-1),
				text=self.name
			})
		end,
		update=function(self)
			decrement_counter_prop(self,"walk_frames")
			if not self.has_been_hurt then
				self:behavior()
			end
			self.vy-=0.2
			self.standing_platform=nil
			self:apply_velocity()
			if self.standing_platform and self.walk_frames<=0 then
				self.vx=0
			end
			self:bleed()
		end,
		behavior=noop,
		walk=function(self,vx,frames)
			self.vx=vx/4
			self.walk_frames=frames
		end,
		shoot=function(self,options)
			options=options or {}
			local angle=options.angle or 0
			if self.weapon=="gun" then
				create_entity(ternary(options.is_cannonball,"cannonball","bullet"),{
					x=self.x+ternary(self.facing<0,-4,5),
					y=ceil(self.y+ternary(options.is_cannonball,1.5,2.5)),
					vx=self.facing,
					vy=angle/10,
					vel_change_frames=options.vel_change_frames or 0
				})
				if not options.skip_effects then
					create_entity("muzzle_flash",{
						x=self.x+ternary(self.facing<0,-4,6),
						y=self.y+4,
						facing=self.facing,
						is_big=options.is_cannonball
					})
				end
			-- elseif self.weapon=="boomerang" then
			-- 	create_entity("boomerang",{
			-- 		x=self.x+ternary(self.facing<0,-1,2),
			-- 		y=ceil(self.y+1.5),
			-- 		angle=80
			-- 	})
			elseif self.weapon=="dynamite" then
				create_entity("dynamite",{
					x=self.x+ternary(self.facing<0,-1,2),
					y=ceil(self.y+1.5)
				})
			elseif self.weapon=="barrels" then
				create_entity("rolling_barrel",{
					x=self.x+ternary(self.facing<0,-1,0),
					y=self.y+2,
					vx=self.facing,
					small_bounce_vy=ternary(self.y>5,1.4,0.7),
					large_bounce_vy=ternary(self.y>5,1.7,1),
					is_explosive=options.is_explosive
				})
			end
		end,
		jump=function(self,vx,jump_lvl)
			self.vx=vx/4
			self.vy=({1.1,1.6,2.1,2.4})[jump_lvl]
		end,
		draw=function(self)
			self:apply_lighting(self.facing<0)
			local sprite=ternary(self.standing_platform,25,27)
			if self.has_been_hurt then
				sprite=ternary(self.standing_platform,29,28)
			elseif vx!=0 and self.standing_platform then
				sprite=ternary(self.walk_frames%10<5,25,26)
			end
			spr(sprite,self.x-ternary(self.facing<0,2.5,1.5),-self.y-7.5,1,1,self.facing<0)
			-- draw weapon
			local weapon_sprite=nil
			if self.weapon=="gun" then
				weapon_sprite=44
			end
			if not self.has_been_hurt and weapon_sprite then
				spr(44,self.x+ternary(self.facing<0,-6.5,2),-self.y-7,1,1,self.facing<0)
			end
			pal()
		end,
		on_hurt=function(self,other)
			self:super_on_hurt(other)
			self.vy=2
			self.vx=-self.facing/2
			self.is_slide_pause_immune=false
			self.name_tag:get_slashed()
			create_entity("level_exit")
		end
	},
	level_exit={
		x=124,
		width=2,
		height=15,
		hitbox_channel=4,
		draw=function(self)
			if self.frames_alive>42 and (self.frames_alive-42)%30>10 then
				spr(53,self.x-6.5,-self.y-14)
			end
		end,
		draw_shadow=noop,
		on_hit=function(self)
			self:die()
			return false
		end,
		on_death=function(self)
			freeze_frames=max(freeze_frames,3)
			pause_frames=max(pause_frames,30)
			slide_frames=max(slide_frames,40)
			left_wall.x+=117
			right_wall.x+=117
			load_level(level_num+1,117)
			-- player:pose()
		end
	},
	invisible_wall={
		width=4,
		height=4,
		platform_channel=2,
		draw=noop,
		draw_shadow=noop
	},
	bullet={
		width=2,
		height=0.1,
		hitbox_channel=2, -- enemy bullets
		hurtbox_channel=1, -- player swing
		frames_to_death=120,
		collision_channel=1, -- ground
		vel_change_frames=0,
		causes_bleeding=true,
		update=function(self)
			if decrement_counter_prop(self,"vel_change_frames") then
				self.vy=0
			end
			self:apply_velocity()
		end,
		on_collide=function(self)
			self:spawn_hit_flash()
			self:die()
		end,
		on_hit=function(self)
			self:spawn_hit_flash()
			self:die()
		end,
		on_hurt=function(self)
			self.is_slashed=true;
			self:die()
			create_entity("twinkle",{x=self.x+self.vx,y=self.y+self.vy})
			freeze_frames=max(freeze_frames,2)
		end,
		spawn_hit_flash=function(self)
			-- todo facing and x+/-1 for facing=-1
			create_entity("hit_flash",{x=self.x,y=self.y})
		end
	},
	cannonball={
		extends="bullet",
		height=1.1,
		is_destructive=true,
		hurtbox_channel=0
	},
	boomerang={
		-- angle (0=up,90=left,180=down,270=right),speed
		width=3,
		height=2,
		power=2,
		reversed=false,
		init=function(self)
			self.dir_x=sin(self.angle/360)
			self.dir_y=cos(self.angle/360)
		end,
		update=function(self)
			self.vx=mid(-1.5,self.power,1.5)*self.dir_x
			self.vy=mid(-1.5,self.power,1.5)*self.dir_y
			self.power-=0.03
			self:apply_velocity()
		end,
		draw=function(self)
			local f=flr(self.frames_alive/4)
			local flip_x=f%4>=2
			local flip_y=f%4==0 or f%4==3
			spr(112,self.x-ternary(flip_x,1.5,2.5),-self.y-5,1,1,flip_x,ternary(self.reversed,not flip_y,flip_y))
		end
	},
	dynamite={
		width=3,
		height=3,
		vx=-1.75,
		vy=1.6,
		collision_channel=13, -- ground, crates, barrels
		-- hitbox_channel=2, -- enemy bullets
		hurtbox_channel=1, -- player swing
		is_light_source=true,
		intensity=3,
		max_range=40,
		update=function(self)
			self.vy-=0.07
			local f=flr(self.frames_alive/4)
			if self.y>5 then
				add(smoke,{
					x=self.x+({-1,0,1,0})[1+f%4],
					y=self.y+({1.1,0.1,1.1,2.1})[1+f%4],
					vx=self.vx/4,
					vy=max(-0.25,self.vy/4),
					frames_to_death=rnd_int(5,20)
				})
			end
			self:apply_velocity()
		end,
		draw=function(self)
			-- self:draw_shape(8)
			spr(113+flr(self.frames_alive/2)%8,self.x-2.5,-self.y-6,1,1,false)
		end,
		on_death=function(self)
			create_entity("explosion",{x=self.x+self.width/2-6,y=self.y})
		end,
		on_hurt=function(self,other)
			self.vy=1
			self.vx=other.facing*(0.3+rnd(0.5))
		end,
		on_hit=function(self,other)
			self.vy=0.2
			self.vx=other.vx+other.facing/5
			self.hitbox_channel=0
			return false
		end,
		on_collide=function(self)
			self:die()
		end
	},
	twinkle={
		frames_to_death=9,
		draw=function(self)
			spr(51+flr(self.frames_alive/3)%2,self.x-2.5,-self.y-5)
		end
	},
	blood={
		render_layer=4,
		is_slide_pause_immune=false,
		collision_channel=1, -- ground
		update=function(self)
			self.vx*=0.97
			self.vy-=0.1
			self:apply_velocity()
		end,
		draw=function(self)
			pset(self.x+0.5,-self.y,ternary(self.y<=0,2,8))
		end,
		on_collide=function(self)
			if self.frames_to_death<=0 then
				self.vx=0
				self.frames_to_death=30
			end
		end
	},
	name_tag={
		-- x,text
		y=-5,
		top_hidden=false,
		bottom_hidden=false,
		is_pause_immune=true,
		update=function(self)
			if self.frames_to_death>0 then
				if self.frames_to_death==84 then
					self.bottom_hidden=true
					self.vx=1
					create_entity("name_tag",{
						x=self.x-1,
						y=self.y-2,
						vx=-0.5,
						text=self.text,
						top_hidden=true,
						frames_to_death=82
					})
					self.x+=2
				elseif self.frames_to_death<=82 then
					self.vy-=0.2
				end
				self.vx*=0.97
				self:apply_velocity()
			end
		end,
		draw=function(self)
			print(self.text,self.x-4*#self.text+0.5,-self.y,2)
			if self.top_hidden then
				rectfill(self.x-4*#self.text+0.5,-self.y,self.x-1.5,-self.y+2,0)
			elseif self.bottom_hidden then
				rectfill(self.x-4*#self.text+0.5,-self.y+2,self.x-1.5,-self.y+4,0)
			end
		end,
		get_slashed=function(self)
			create_entity("name_tag_slash",{x=self.x-4*#self.text})
			self.frames_to_death=100
		end
	},
	name_tag_slash={
		-- x
		y=-7,
		frames_to_death=17,
		is_pause_immune=true,
		init=function(self)
			self.left_x=self.x-10
			self.right_x=self.x-6
		end,
		update=function(self)
			self.right_x+=mid(0,(self.frames_alive+0.5)/3,1)*(128-self.right_x)
			self.left_x+=mid(0,self.frames_alive/10,1)*(128-self.left_x)
		end,
		draw=function(self)
			if self.x<self.right_x then
				line(self.x+0.5,-self.y,self.right_x+0.5,-self.y,0)
			end
			line(self.left_x+0.5,-self.y,self.right_x+0.5,-self.y,7)
		end
	},
	muzzle_flash={
		-- x,y,facing,is_big
		render_layer=4,
		frames_to_death=6,
		intensity=5,
		max_range=20,
		is_light_source=true,
		draw=function(self)
			spr(51-ceil(self.frames_to_death/2)+ternary(self.is_big,13,0),self.x+ternary(self.facing<0,-5.5,-0.5),-self.y-3,1,1,self.facing<0)
		end
	},
	hit_flash={
		frames_to_death=4,
		intensity=2,
		max_range=25,
		facing=1,
		is_light_source=true,
		draw=function(self)
			spr(43-ceil(self.frames_to_death/2),self.x-ternary(self.facing<0,7,0),-self.y-5,1,1,self.facing<0)
		end
	},
	debug_cube={
		width=8,
		height=8,
		update=function(self)
			self.vx=(ternary(buttons[1],1,0)-ternary(buttons[0],1,0))/0.97
			self.vy=(ternary(buttons[2],1,0)-ternary(buttons[3],1,0))/0.97
			self:apply_velocity()
		end,
		draw=function(self)
			self:apply_lighting()
			spr(43,self.x+0.5,-self.y-8)
		end
	},
	explosion={
		width=12,
		height=7,
		sprite_height=15,
		-- hitbox_channel=8, -- explosions
		frames_to_death=15,
		is_light_source=true,
		intensity=4,
		min_range=6,
		max_range=70,
		is_destructive=true,
		init=function(self)
			if self.y>0 then
				self.y-=5
				self.height+=5
				self.sprite_height=21
			end
		end,
		update=function(self)
			self.hitbox_channel=ternary(self.frames_alive==2,8,0)
			self.intensity-=0.2
		end,
		draw=function(self)
			sspr(flr(self.frames_alive/3)*24,64,24,self.sprite_height,self.x-5.5,-self.y-self.height-8,24,self.sprite_height)
			-- self:draw_shape(8)
		end,
		draw_shadow=noop,
		on_hit=noop
	},
	quicksand={
		-- width=4n+2
		height=4.01,
		y=-4,
		hitbox_channel=32,
		render_layer=7,
		on_hit=function(self,other)
			if not other.is_stuck_in_quicksand then
				other.is_stuck_in_quicksand=true
				other.y-=1
				other:on_stuck()
			end
			return false
		end,
		draw=function(self)
			-- self:draw_shape(8)
			for x=self.x,self.x+self.width+4,4 do
				spr(ternary(x==self.x,126,127),x-5.5,-self.y-7)
			end
		end,
		draw_shadow=function(self)
			-- self:draw_shape(8)
			for x=self.x,self.x+self.width+4,4 do
				spr(ternary(x==self.x,110,111),x-5.5,-self.y-7)
			end
		end,
	},
	crate={
		width=4,
		height=4,
		collision_channel=13, -- ground, crates, barrels
		platform_channel=4, -- crates
		hurtbox_channel=42, -- bullets, explosions, quicksand
		gravity=0.2,
		color_ramp=color_ramps.brown,
		sprite=14,
		draw=function(self)
			self:apply_lighting()
			spr(self.sprite,self.x-1.5,-self.y-8)
		end,
		on_hurt=function(self,other)
			if other.is_destructive then
				self:die()
			end
		end,
		on_death=function(self)
			create_entity("plank",{x=self.x,y=self.y})
			create_entity("plank",{x=self.x,y=self.y})
		end
	},
	barrel={
		extends="crate",
		height=6,
		sprite=15,
		platform_channel=8, -- barrels
		hurtbox_channel=59, -- player swing, bullets, rolling barrels, explosions, quicksand
		is_explosive=false,
		init=function(self)
			if self.is_explosive then
				self.color_ramp=color_ramps.red
			end
		end,
		on_hurt=function(self,other)
			if other.is_destructive then
				if self.is_explosive then
					create_entity("explosion",{x=self.x-4,y=self.y})
				end
				self:die()
			elseif other.class_name=="player" and other.y<self.y+self.height then
				self:despawn()
				create_entity("rolling_barrel",{
					x=self.x,
					y=self.y+1,
					vx=other.facing,
					is_explosive=self.is_explosive
				})
			elseif other.class_name=="rolling_barrel" then
				self:despawn()
				create_entity("rolling_barrel",{
					x=self.x,
					y=self.y+1,
					vx=other.vx,
					is_explosive=self.is_explosive
				})
			end
		end,
		on_death=function(self)
			self:super_on_death()
			create_entity("barrel_ring",{x=self.x,y=self.y})
		end
	},
	plank={
		width=3,
		height=3,
		gravity=0.1,
		init=function(self)
			self.vx=rnd(0.8)-0.4
			self.vy=0.9+rnd(0.7)
			self.rot_speed=rnd_int(1,2)
		end,
		update=function(self)
			if self.y+self.height<0 then
				self:die()
			end
			self:apply_velocity()
		end,
		draw=function(self)
			local f=flr(self.frames_alive/self.rot_speed)%4
			spr(121+ternary(self.vx<0,3-f,f),self.x-1.5,-self.y-6)
		end,
		draw_shadow=noop
	},
	barrel_ring={
		extends="plank",
		width=4,
		height=4,
		init=function(self)
			self:super_init()
			self.vx*=0.4
		end,
		draw=function(self)
			spr(125,self.x-1.5,-self.y-6)
		end
	},
	rolling_barrel={
		height=4,
		width=4,
		vy=1,
		collision_channel=5, -- ground, crates
		bounce_x=1,
		color_ramp=color_ramps.brown,
		hurtlock_frames=5,
		hitbox_channel=16, -- rolling barrels
		hurtbox_channel=59, -- player swing, bullets, rolling barrels, explosions, quicksand
		large_bounce_vy=1,
		small_bounce_vy=0.7,
		gravity=0.1,
		is_explosive=false,
		init=function(self)
			if self.is_explosive then
				self.color_ramp=color_ramps.red
			end
		end,
		update=function(self)
			self:apply_velocity()
		end,
		on_hit=function(self,other)
			other:on_hurt(self)
			self:bounce_off(other)
			return false
		end,
		on_stuck=function(self)
			self:despawn()
			create_entity("barrel",{x=self.x,y=self.y-1})
		end,
		on_hurt=function(self,other)
			if other.is_destructive then
				if self.is_explosive then
					create_entity("explosion",{x=self.x-4,y=self.y+2})
				end
				self:die()
			-- bug: player still gets a slash reset
			elseif other.class_name!="player" or other.y<self.y+self.height then
				self:bounce_off(other)
			end
		end,
		on_collide=function(self,dir)
			if dir=="bottom" then
				self.vy=self.small_bounce_vy
			elseif dir=="left" or dir=="right" then
				self.vy=self.large_bounce_vy
			end
		end,
		bounce_off=function(self,other)
			self.vy=self.large_bounce_vy
			if other.x<self.x then
				self.vx=1
			elseif other.x>self.x then
				self.vx=-1
			end
			self.hurtlock_frames=max(self.hurtlock_frames,2)
		end,
		draw=function(self)
			self:apply_lighting()
			spr(13,self.x-1.5,-self.y-8)
		end,
		on_death=function(self)
			create_entity("plank",{x=self.x,y=self.y})
			create_entity("plank",{x=self.x,y=self.y})
			create_entity("barrel_ring",{x=self.x,y=self.y})
		end
	},
	background_entity={
		render_layer=2,
		flipped=false,
		init=function(self)
			self.width=self.bg_params[3]
			self.height=self.bg_params[4]
			self.slide_rate=self.bg_params[5]
		end,
		draw=function(self)
			-- self:draw_shape(8)
			sspr(self.bg_params[1],self.bg_params[2],self.width,self.height,self.x,-self.y-self.height,self.width,self.height,self.flipped)
		end,
		draw_shadow=noop
	},
	cactus={
		extends="background_entity",
		bg_params={0,32,8,12,1.5}
	},
	distant_ranch={
		extends="background_entity",
		bg_params={8,32,11,5,0.75}
	},
	cloud={
		extends="background_entity",
		bg_params={19,32,25,5,0.25},
		render_layer=2,
		y=12
	},
	big_ridge={
		extends="background_entity",
		bg_params={8,37,17,7,0.5}
	},
	small_ridge={
		extends="background_entity",
		bg_params={25,37,9,6,0.5}
	},
	tiny_ridge={
		extends="background_entity",
		bg_params={34,37,5,6,0.5}
	},
	sky={
		-- x,y,width,height,color_1,color_2,
		render_layer=0,
		breakpoint=0, -- 0=all bottom color, 10=all top color
		slide_rate=0,
		bottom_color=9,
		top_color=8,
		draw=function(self)
			local x,y,c
			for y=1,5 do
				for c=1,6 do
					pal(c+6,ternary(self.breakpoint+y-5<c,self.bottom_color,self.top_color))
				end
				for x=1,32 do
					spr(70,4*x-5,-4*y)
				end
			end
		end
	},
	sun={
		slide_rate=0,
		intensity=3,
		min_range=15,
		x=63,
		y=-4, -- -11 to 3
		render_layer=1,
		phase=1,
		is_light_source=true,
		draw=function(self)
			color(({10,9,8})[self.phase])
			local widths={17,17,17,16,16,15,15,14,13,12,11,9,7,4}
			local i
			for i=flr(4-self.y),14 do
				line(self.x-widths[i],-self.y-i+3,self.x+widths[i],-self.y-i+3)
			end
		end,
		draw_shadow=noop
	}
}


-- main functions
function _init()
	local i
	for i=0,5 do
		buttons[i]=false
		button_presses[i]=99
	end
	init_scene("game")
end

function _update()
	-- skip frames
	local will_skip_frame=false
	skip_frames=increment_counter(skip_frames)
	if skip_frames%debug_skip_amt>0 then
		will_skip_frame=true
	-- freeze frames
	elseif freeze_frames>0 then
		freeze_frames=decrement_counter(freeze_frames)
		will_skip_frame=true
	-- pause/slow-mo frames
	else
		pause_frames=decrement_counter(pause_frames)
		if slow_mo_frames>0 then
			slow_mo_frames=decrement_counter(slow_mo_frames)
			will_skip_frame=(slow_mo_frames%4>0)
		end
	end
	-- keep track of inputs (because btnp repeats presses)
	-- todo change buttons[] to button_presses[] which works a little better
	local i
	for i=0,5 do
		if btn(i) and not buttons[i] then
			button_presses[i]=0
		elseif not will_skip_frame then
			increment_counter_prop(button_presses,i)
		end
		buttons[i]=btn(i)
	end
	-- call the update function of the current scene
	if not will_skip_frame then
		scene_frame=increment_counter(scene_frame)
		scenes[scene][2]()
	end
end

function _draw()
	-- reset the canvas
	camera()
	rectfill(0,0,127,127,0)
	-- draw guidelines
	-- color(1)
	-- rect(0,0,63,63)
	-- rect(66,0,127,63)
	-- rect(0,66,63,127)
	-- rect(66,66,127,127)
	-- call the draw function of the current scene
	scenes[scene][3]()
	-- draw debug info
	camera()
	print("steps:    "..debug_num_steps,2,100,ternary(debug_num_steps>=50,2,1))
	print("mem:      "..flr(100*(stat(0)/1024)).."%",2,107,ternary(stat(1)>=1024,2,1))
	print("cpu:      "..flr(100*stat(1)).."%",2,114,ternary(stat(1)>=1,2,1))
	print("entities: "..#entities,2,121,ternary(#entities>50,2,1))
end


-- game functions
function init_game()
	-- reset everything
	entities,new_entities,smoke,light_sources={},{},{},{}
	slide_frames=0
	wind=0
	-- create initial entities
	sky=create_entity("sky")
	sun=create_entity("sun")
	player=create_entity("player")
	left_wall=create_entity("invisible_wall",{x=-3,y=-4,height=40})
	right_wall=create_entity("invisible_wall",{x=125,y=-4,height=40})
	-- create_entity("debug_cube",{x=60,y=5})
	-- load the first level
	load_level(1,0)
	-- immediately add new entities to the game
	add_new_entities()
end

function update_game()
	debug_num_steps=0
	-- sort entities for updating
	sort_list(entities,function(a,b)
		return a.update_priority>b.update_priority
	end)
	-- slide entities
	local entity
	slide_frames=decrement_counter(slide_frames)
	if slide_frames>0 then
		for entity in all(entities) do
			entity:slide()
		end
	end
	-- update entities
	for entity in all(entities) do
		if (pause_frames<=0 or entity.is_pause_immune) and (slide_frames<=0 or entity.is_slide_pause_immune) then
			decrement_counter_prop(entity,"stasis_frames")
			if entity.stasis_frames<=0 then
				-- call the entity's update function
				entity:update()
				-- do some default update stuff
				decrement_counter_prop(entity,"hurtlock_frames")
				increment_counter_prop(entity,"frames_alive")
				if decrement_counter_prop(entity,"frames_to_death") then
					entity:die()
				end
				-- 10 px out of bounds to the left
				-- 150px out of bounds to the right
				if entity.x+entity.width<-10 or entity.x>276 then
					entity:despawn()
				end
			end
		end
	end
	-- call each entity's post_update function
	for entity in all(entities) do
		if (pause_frames<=0 or entity.is_pause_immune) and (slide_frames<=0 or entity.is_slide_pause_immune) then
			entity:post_update()
		end
	end
	-- check for hits
	local entity2
	for entity in all(entities) do
		for entity2 in all(entities) do
			if (pause_frames<=0 or (entity.is_pause_immune and entity2.is_pause_immune)) and (slide_frames<=0 or (entity.is_slide_pause_immune and entity2.is_slide_pause_immune)) then
				if entity!=entity2 and band(entity.hitbox_channel,entity2.hurtbox_channel)>0 and entity2.hurtlock_frames<=0 then
					if entity:check_for_hits(entity2) then
						if entity:on_hit(entity2)!=false then
							entity2:on_hurt(entity)
						end
					end
				end
			end
		end
	end
	if pause_frames<=0 then
		-- update wind
		wind=mid(-0.1,wind+rnd(0.05)-0.025,0.1)
		-- update smoke
		foreach(smoke,function(particle)
			particle.vx+=wind
			particle.vx*=0.98
			particle.x+=particle.vx
			particle.y+=particle.vy
			particle.frames_to_death-=1
		end)
		filter_list(smoke,function(particle)
			return particle.frames_to_death>0
		end)
	end
	-- add new entities to the game
	add_new_entities()
	-- remove dead entities from the game
	remove_deceased_entities(entities)
	remove_deceased_entities(light_sources)
	-- sort entities for rendering
	sort_list(entities,function(a,b)
		return a.render_layer>b.render_layer
	end)
end

function draw_game()
	camera(-1,-70)
	-- draw the ground
	rectfill(0,0,125,3,4)
	-- draw each entity's shadow
	foreach(entities,function(entity)
		entity:draw_shadow()
		pal()
	end)
	-- draw each entity
	foreach(entities,function(entity)
		entity:draw()
		pal()
	end)
	-- draw smoke
	foreach(smoke,function(particle)
		pset(particle.x+0.5,-particle.y,4)
	end)
	-- black out the area outside the pane
	color(0)
	-- rectfill(-1,4,126,57) -- bottom
	rectfill(-1,-70,126,-21) -- top
	rect(-1,-21,126,4) -- edges
end

function load_level(num,offset)
	level_num=num
	local level=levels[level_num]
	local i
	for i=1,#level,2 do
		local entity=create_entity(level[i],level[i+1],true)
		entity.x+=offset
		init_entity(entity,level[i+1])
	end
end


-- entity functions
function create_entity(class_name,args,skip_init)
	local super_class_name,entity,k,v=entity_classes[class_name].extends
	-- this entity might extend another
	if super_class_name then
		entity=create_entity(super_class_name,args,true)
		entity.super_class_name=super_class_name
		entity.class_name=class_name
	-- if not, create a default entity
	else
		entity={
			class_name=class_name,
			is_alive=true,
			is_light_source=false,
			frames_alive=0,
			frames_to_death=0,
			update_priority=5,
			render_layer=5,
			color_ramp=color_ramps.grey,
			is_pause_immune=false,
			is_slide_pause_immune=true, -- todo
			slide_rate=3,
			gravity=0,
			stasis_frames=0,
			-- spatial props
			x=0,
			y=0,
			width=0,
			height=0,
			vx=0,
			vy=0,
			-- collision props
			bounce_x=0,
			bounce_y=0,
			platform_channel=0,
			collision_channel=0,
			-- hit props
			hitbox_channel=0,
			hurtbox_channel=0,
			hurtlock_frames=0,
			-- entity methods
			init=noop,
			add_to_game=noop,
			update=function(self)
				self:apply_velocity()
			end,
			post_update=noop,
			draw=function(self)
				self:draw_shape(1)
			end,
			draw_shadow=function(self)
				local slope=(self.x-62)/(16+sun.y)
				local y
				local left=self.x+0.5
				local right=self.x+self.width-0.5
				local bottom=self.y
				local top=self.y+self.height
				for y=0,3 do
					local shadow_left=max(0,left+slope*y+ternary(slope<0 and self.height>1,slope,0))
					local shadow_right=min(right+slope*y+ternary(slope>0 and self.height>1,slope,0),125)
					if bottom<=y and top>y and shadow_left<shadow_right then
						line(shadow_left,y,shadow_right,y,2)
					end
				end
			end,
			draw_outline=function(self,color)
				rect(self.x+0.5,-self.y-1,self.x+max(1,self.width)-0.5,-self.y-max(1,self.height),color)
			end,
			draw_shape=function(self,color)
				rectfill(self.x+0.5,-self.y-1,self.x+max(1,self.width)-0.5,-self.y-max(1,self.height),color)
			end,
			apply_lighting=function(self,flip_x,flip_y)
				local c
				-- dark blue = permanent shadow (1st color)
				-- purple = permanent midtone (3rd color)
				-- dark green = permanent highlight (5th color)
				for c=1,3 do
					pal(c,self.color_ramp[2*c-1])
				end
				-- every other color is lit based on the angle and distance to light sources
				for c=4,15 do
					local surface_x=({-2,-0.2,0.2,2})[1+c%4]*ternary(flip_x,-1,1)
					local surface_y=({1,0,-1})[flr(c/4)]*ternary(flip_y,-1,1)
					surface_x,surface_y=normalize(surface_x,surface_y)
					local surface_penalty=ternary(c==9 or c==10,1,0)
					local color_index=1
					local ramp=self.color_ramp
					for light_source in all(light_sources) do
						local dx=mid(-100,light_source.x+light_source.width/2-self.x-self.width/2,100)
						local dy=mid(-100,light_source.y+light_source.height/2-self.y-self.height/2,100)
						local square_dist=dx*dx+dy*dy -- between 0 and 20000
						local dist=sqrt(square_dist) -- between 0 and ~142
						local dx_norm=dx/dist
						local dy_norm=dy/dist
						local max_color_index=light_source.intensity+0.7
						local min_range=ternary(light_source.min_range,light_source.min_range,0)
						local dot=surface_x*dx_norm+surface_y*dy_norm
						if dist<min_range then
							dot=1
						elseif light_source.max_range then
							max_color_index*=1-mid(0,(dist-min_range)/(light_source.max_range-min_range),1)
						end
						local new_color_index=mid(1,flr(max_color_index*dot)-surface_penalty,5)
						if new_color_index>=color_index then
							color_index=new_color_index
							ramp=ternary(light_source.light_ramp,light_source.light_ramp,self.color_ramp)
						end
					end
					pal(c,ramp[color_index])
				end
			end,
			die=function(self)
				if self.is_alive then
					self.is_alive=false
					self:on_death()
				end
			end,
			despawn=function(self)
				self.is_alive=false
			end,
			on_death=noop,
			slide=function(self)
				self.x-=self.slide_rate
			end,
			apply_velocity=function(self)
				if self.is_stuck_in_quicksand then
					self.vx=0
					self.vy=0
					self.y-=0.05
					if self.y+self.height<=0 then
						self:despawn()
					end
				else
					self.vy-=self.gravity
					local vx,vy=self.vx,self.vy
					if self.collision_channel<=1 and self.platform_channel<=0 then
						self.x+=vx
						self.y+=vy
					elseif vx!=0 or vy!=0 then
						local move_steps,t,entity,dir=ceil(max(abs(vx),abs(vy))/1.05)
						for t=1,move_steps do
							debug_num_steps+=1
							if vx==self.vx then
								self.x+=vx/move_steps
							end
							if vy==self.vy then
								self.y+=vy/move_steps
							end
							-- check for collisions against other entities
							if self.collision_channel>1 then
								for dir in all(directions) do
									for entity in all(entities) do
										self:check_for_collision(entity,dir)
									end
								end
							end
							-- if this is a moving obstacle, check to see if it rammed into anything
							if self.platform_channel>0 then
								for entity in all(entities) do
									for dir in all(directions) do
										entity:check_for_collision(self,dir)
									end
								end
							end
						end
					end
					-- check for collisions against the ground
					if self.y<0 and self.vy<0 and band(self.collision_channel,1)>0 then
						self.y=0
						self.vy=-self.vy*self.bounce_y
						self:on_collide("bottom",ground)
					end
				end
			end,
			check_for_collision=function(self,platform,dir)
				local axis=dir_lookup[dir][1] -- e.g. "x"
				local size=dir_lookup[dir][2] -- e.g. "width"
				local vel="v"..axis -- e.g. "vx"
				local bounce="bounce_"..axis -- e.g. "bounce_x"
				local mult=dir_lookup[dir][3] -- e.g. 1
				if band(self.collision_channel,platform.platform_channel)>0 and self!=platform and mult*self[vel]>=mult*platform[vel] and is_overlapping_dir(self,platform,dir) then
					self[axis]=platform[axis]+ternary(mult<0,platform[size],-self[size])
					self[vel]=(platform[vel]-self[vel])*self[bounce]+platform[vel]
					self:on_collide(dir,platform)
				end
			end,
			on_stuck=noop,
			on_collide=noop,
			check_for_hits=function(self,other)
				return is_overlapping(self,other)
			end,
			on_hurt=function(self)
				self:die()
			end,
			on_hit=function(self)
				self:die()
			end
		}
	end
	-- add class properties/methods onto it
	for k,v in pairs(entity_classes[class_name]) do
		if super_class_name and type(entity[k])=="function" then
			entity["super_"..k]=entity[k]
		end
		entity[k]=v
	end
	-- add properties onto it from the arguments
	for k,v in pairs(args or {}) do
		entity[k]=v
	end
	if not skip_init then
		init_entity(entity,args)
	end
	-- return it
	return entity
end

function init_entity(entity,args)
	-- initialize it
	entity:init(args or {})
	-- add it to the list of entities-to-be-added
	add(new_entities,entity)
end

function add_new_entities()
	foreach(new_entities,function(entity)
		entity:add_to_game()
		add(entities,entity)
		if entity.is_light_source then
			add(light_sources,entity)
		end
	end)
	new_entities={}
end

function remove_deceased_entities(list)
	filter_list(list,function(entity)
		return entity.is_alive
	end)
end


-- scene functions
function init_scene(s)
	scene,scene_frame,slow_mo_frames,freeze_frames,pause_frames=s,0,0,0,0
	scenes[scene][1]()
end


-- helper functions
function ceil(n)
	return -flr(-n)
end

-- if condition is true return the second argument, otherwise the third
function ternary(condition,if_true,if_false)
	return condition and if_true or if_false
end

-- gets the character in string s at position n
function char_at(s,n)
	return sub(s,n,n)
end

-- gets the first position of character c in string s
function char_index(s,c)
	local i
	for i=1,#s do
		if char_at(s,i)==c then
			return i
		end
	end
end

-- generates a random integer between min_val and max_val, inclusive
function rnd_int(min_val,max_val)
	return flr(min_val+rnd(1+max_val-min_val))
end

function normalize(x,y)
	local len=sqrt(x*x+y*y)
	return x/len,y/len
end

-- if n is below min, wrap to max. if n is above max, wrap to min
function wrap(min_val,n,max_val)
	return ternary(n<min_val,max_val,ternary(n>max_val,min_val,n))
end

-- increment a counter, wrapping to 20000 if it risks overflowing
function increment_counter(n)
	if n>32000 then
		return 20000
	end
	return n+1
end

-- increment_counter on a property on an object
function increment_counter_prop(obj,k)
	obj[k]=increment_counter(obj[k])
end

-- decrement a counter but not below 0
function decrement_counter(n)
	return max(0,n-1)
end

-- decrement_counter on a property of an object, returns true when it reaches 0
function decrement_counter_prop(obj,k)
	if obj[k]>0 then
		obj[k]=decrement_counter(obj[k])
		return obj[k]<=0
	end
	return false
end

-- washes all non-black colors to c
function colorwash(c)
	local i
	for i=1,15 do
		pal(i,c)
	end
end

-- sorts list (inefficiently) based on func
function sort_list(list,func)
	local i
	for i=1,#list do
		local j=i
		while j>1 and func(list[j-1],list[j]) do
			list[j],list[j-1]=list[j-1],list[j]
			j-=1
		end
	end
end

-- filters list to contain only entries where func is truthy
function filter_list(list,func)
	local num_deleted,i=0
	for i=1,#list do
		if not func(list[i]) then
			list[i]=nil
			num_deleted+=1
		else
			list[i-num_deleted],list[i]=list[i],nil
		end
	end
end


-- hit detection functions
function is_overlapping(a,b)
	if not a or not b then
		return false
	end
	return rects_overlapping(
		a.x,a.y,a.width,a.height,
		b.x,b.y,b.width,b.height)
end

function is_overlapping_dir(a,b,dir)
	if not a or not b then
		return false
	end
	local a_sub={
		x=a.x+1.1,
		y=a.y+1.1,
		width=a.width-2.2,
		height=a.height-2.2
	}
	local axis,size=dir_lookup[dir][1],dir_lookup[dir][2]
	a_sub[axis]=a[axis]+ternary(dir_lookup[dir][3]>0,a[size]/2,0)
	a_sub[size]=a[size]/2
 	return rects_overlapping(
 		a_sub.x,a_sub.y,a_sub.width,a_sub.height,
 		b.x,b.y,b.width,b.height)
end

-- check for aabb overlap
function rects_overlapping(x1,y1,w1,h1,x2,y2,w2,h2)
	return x1+w1>x2 and x2+w2>x1 and y1+h1>y2 and y2+h2>y1
end

-- set up the scenes now that the functions are defined
scenes={
	game={init_game,update_game,draw_game}
}


__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000470000000000000004700000047000004b00000004b0000047000004700000000000000047000000470000800080008000800000000000000000000000000
0081b0000004700000081b0000081b000081b00000081b000008b0000081b000000000000081b0000081b1110080800000808000000000000000000000856b00
1111b0000081b00011111b0011111b001111b00011111b000081b0000081b0000000000000811000008110000008000000080000000000000000000000911a00
008eb0001111b000008ef0000081f00000cee00000cef000008eb0000081f00004567000008eb100008eb00000808000008080000004700000856b000089ab00
00c0f0000c11f0000800f00000cf00000c000f000c0f000000c0f00000080f0008111b0000c0f00000c0f00008000800080008000089ab000089ab000089ab00
000000000000000000000000000000000000010000007770000000777000000000000000000000000000000000000000000000000089ab000089ab0000911a00
00000000000000000000000000000000000017700177777770007777777000770000000000000000000000000000000000000000000cf0000089ab000089ab00
00000000000000000000000000000000000177700017777770017777777000770000008800000000000000000000000000000000000000000000000000000000
07000000000000000000000001110000007777770001777777070077777717700000008800000000000000000000000000000000000000000800080008000800
77110000000700010000000000071100007777770700077777070000777707000000008800467000004670000046700004670000000000000080800000808000
11000000000777010000000007777700007777770770007777000000000707000000008808111b0008111b0008111b008111b000000000000008000000080000
0000000000007777100000077777700000777770007770077000000000000070000000880081b0000081b0000081b000081b0000000000000080800000808000
0000000000007777100000777777700007777770000777007000077000000000000700880081b0000081b0000081b0000811b000004000000800080008000800
000000000000007770000000777000000077700000000770000000777000000000700088008eb000008eb000008eb0000081b000041777000000000000000000
00000000000000000000000077700000007770000000770700000077700000007770008800c0f000000c00000c000f00000c0f00081111b00000000000000000
01000000000000771000007777777000000777700007700770007700000000000000008800000000000000004455667700000000000000000000000000000000
071000000000777100000007777770000007777000777077700070000000000000000088000000000000a0004455667700000000080008000800080008000800
077100000000777100000000077711000007777700770077770700000007001000000088000a0000000000008899aabb00000000008080000080800000808000
07000000000770100000000001110000000777770770077777001000007701000000008800a00000000000008899aabb00110000000800000008000000080000
0000000000000000000000000000000000177777077017777701000007771700000000880a000000000000008899aabb00100000008080000080800000808000
00000000000000000000000000000000000177700701777770177007777000700000008800a00000000000008899aabb00000000080008000800080008000800
00000000000000000000000000000000000017700017777770007777777000777000008800000000000a0000ccddeeff00000000000000000000000000000000
0000000000000000000000000000000000007000000077700000007770000000777000880000000000000000ccddeeff00000000000000000000000000000000
0000000000000000000a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a00
0000000000a00000000000000000000000000000008880000000000000000000000000000000700000000000000000000000000000000000000aa0000000a000
00aa00000a00000000000000000f00000000000008808800000000000000000000070000000070000000070000000000000000000aaa000000aa000000000000
0aaaa0000aaa000000000000000f000000070000888088800000000000000000000700000007700000707000000f000000000000aaaaa0000aaaaaa000000000
00aa00000a0000000000000000fff000777077708880888807700000007770000077700007777700000700000077700000007000aaaaa0000aaaa00000000000
0000000000a0000000000000000f000000070000888888800000000000000000000700000077000000707000000f0000000000000aaa000000aa000000000000
0000000000000000000a0000000f000000000000088088000000000000000000000700000070000007000000000000000000000000000000000aa0000000a000
00000000000000000000000000000000000000000088800000000000000000000000000000700000000000000000000000000000000000000000000000000a00
00044000000000004000000ffffff0000000000000000000c7a80000000000000000000000000000000000000000000000000000000000000000000000000000
0004400000000004440000fffffffff000000000000000008b9b0000080008000800080008000800080008000800080008000800080008000800080008000800
4404400000000044444000ffffffffff0000000000000000a8c70000008080000080800000808000008080000080800000808000008080000080800000808000
440440004444444444400fffffffffffffff0000000000009b8b0000000800000008000000080000000800000008000000080000000800000008000000080000
4444400040404044444ffffffffffffffffffff00fff000000000000008080000080800000808000008080000080800000808000008080000080800000808000
04444044000044444444400000044444000044000000000000000000080008000800080008000800080008000800080008000800080008000800080008000800
00044044000444444444440000044444000044000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00044444000444444444440000044444000044000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00044440000444444444440000444444400444000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00044000004444444444444000444444400444000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00044000004444444444444004444444444444400080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00044000444444444444444440000000000000000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00000000000000000000000000000000000000000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00000000000000000000000000000000000000000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000800080008000080008000800080080008000800080008000800080008000800080008000800080008000800080008000800080008000000000000000000
00808000008080000008080000080800008080000080800000808000008080000080800000808000008080000080800000808000008080000000000000000000
00080000000800000000800000008000000800000008000000080000000800000008000000080000000800000008000000080000000800000ff4fff00004fff0
00808000008080000008080000080800008080000080800000808000008080000080800000808000008080000080800000808000008080000000000000000000
08000800080008000080008000800080080008000800080008000800080008000800080008000800080008000800080008000800080008000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000440000000000000000000
00011100000a0000000001000000100000010000000000000000020000002a000002000000000000004000000004000000004000004004000000000000000000
000100000002110000a0100000001000000010000001120000001a0000001000000010000044400000040000000400000004000000400400444ff440004ff440
000000000000000000020000000a20000000a20000000a0000010000000010000000010000000000000040000004000000400000000440004444444000f44440
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004444444000444440
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004444444000444440
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000044000000000000000000000044000000000008000800
00000000000000000000000000000000000000000000000000000000000044000000000000000000000044400000000000000000000000000000000000808000
00000000000000000000000000000000000000000000000000000000000444400000000000000000000444400004400000000000000000000000000000080000
00000000000000000000000000000000000444400000000000000440004444400044000000000000000044000004400000000000000000000000000000808000
00000000000000000000000000000044004444440000000000000440004444400044400000000000000000000000000000000000000000000000000008000800
000000000000000000000000000004440044a44400a4000000000004400444000004400000000000000000000000000004400000000000000000000000000000
0000000000000000000000000000aa444044a440aa44400000000004400000000000000004400000000000000000000004400000000000000044000000000000
000000000aaaaaa00000000000000aaa44444440a444400004400000000000000000000044400000000000000440000000000000000000000044000000000000
0000000aaaaaaaaaa00000000044400aa444440a0444000004440000000004400444000044400000440000000444000000000000000000000000000008000800
000000aaaaaaaaaaaa000000004444000a4444404400000044440000444004404444000000000000440000000440000000000000000000000000000000808000
000000aaaaaaaaaaaa00000004444400444444444440000044440000444000004444004400000000000000000000000000000000000000000000000000080000
00000aaaaa444aaaaaa000000444aaa044444444444a444004400440444000000440004400000000000000000000000000000000000000000000000000808000
00004a44444aaaa444a0000000444044444444444440444000000440000000000000000000000000000000000000000000000000000000000000000008000800
000044444aaa44444444000000000044044444444000044000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000aaaaaa4444aaaa0000000000000004444404000000000000000000000000000000000000440000000000000000000000000000000000000000000000000
000000aaaa44aaaaa440000000000000444404440000000000000044400004400000000000000440000000000044000000000000000000000000000000000000
000000a44aaaaaaaaa00000000000004444404444000000000044044400004400440000000000000000000000044000000000000000000000000000008000800
0000000aaaaaaaaaa000000000000004444400444000000000044044400000004444000000000000000000000000000000000000000000000000000000808000
000000000aaaaaa00000000000000004404400000000000000000044004400004444000000000000000000000000000000000000000000000000000000080000
00000000000000000000000000000000000000000000000000000000004400000000000000000000000000000000000000000000000000000000000000808000
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888808000800
80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888800000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
010600003063030630306302463024620246202f0002f0002d0002d0052d0002d00500000000002d0002d0002b0002b0052b0002b00500000000002b0002b0002a0002a0002a0002a000300002f0002d0002b000
01060000215502b5512b5512b5412b5310d5012900026000215002b5012b5012b5012b5012b50128000240002900024000280000000000000000000000000000000000000000000000000000000000000002d000
0106000021120211151d1201d1152d000280002d0002f000300002f0002d0002b000290002800000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f000
010300001c7301c730186043060524600182001830018300184001840018500185001860018600187001870018200182000000000000000000000000000000000000000000000000000000000000000000000000
010300001873018730000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0106000024540245302b5202b54013630136111360100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01060000186701865018620247702b7702b7700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010c0000185551c5551f5501f55000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010600000c2200c2210c2110c21100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000003065024631186210c61100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344

