-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

local obj_tostring = "BSP %s [ %s ]"
local format = string.format

local meta = NikNaks.__metatables["BSP"]
local meta_face = {}
meta_face.__index = meta_face
meta_face.__tostring = function(self) return format( obj_tostring, "Faces", self.__id ) end
meta_face.MetaName = "BSP Faces"
NikNaks.__metatables["BSP Faces"] = meta_face

local MAX_MAP_FACES = 65536 

---Returns all faces. ( Warning, uses a lot of memory )
---@return table
function meta:GetFaces()
	if self._faces then return self._faces end
	self._faces = {}
	local data = self:GetLump( 7 )
	for i = 0, math.min(data:Size() / 448, MAX_MAP_FACES) - 1 do
		local t = {}
		t.planenum = data:ReadUShort()
		t.plane 	= self:GetPlanes()[ t.planenum ]
		t.side 		= data:ReadByte() -- 1 = same direciton as face
		t.onNode 	= data:ReadByte() -- 1 if on node, 0 if in leaf
		t.firstedge = data:ReadLong()
		t.numedges 	= data:ReadShort()
		t.texinfo 	= data:ReadShort() -- Texture info
		t.dispinfo	= data:ReadShort() -- Displacement info
		t.surfaceFogVolumeID	= data:ReadShort()
		t.styles				= {data:ReadByte(), data:ReadByte(), data:ReadByte(), data:ReadByte()}
		t.lightofs				= data:ReadLong()
		t.area					= data:ReadFloat()
		t.LightmapTextureMinsInLuxels	= {data:ReadLong(), data:ReadLong()}
		t.LightmapTextureSizeInLuxels	= {data:ReadLong(), data:ReadLong()}
		t.origFace			= data:ReadLong()
		t.numPrims			= data:ReadUShort()
		t.firstPrimID		= data:ReadUShort()
		t.smoothingGroups	= data:ReadULong()
		t.__bmodel = self:FindBModelIDByFaceIndex( i )
		t.__map = self
		t.__id = i
		setmetatable( t, meta_face )
		self._faces[i] = t
	end
	self:ClearLump( 7 )
	return self._faces
end

-- Returns the original face
function meta:GetOriginalFace()
	return self.__map:GetOriginalFaces()[self.origFace]
end

-- We make a small hack to cache and get the entities using brush-models.
local function __findEntityUsingBrush( self )
	if self.__funcBrush then return self.__funcBrush end
	local entities = self:GetEntities()
	self.__funcBrush = {[0] = entities[0]}
	for k, v in pairs( entities ) do
		local numMdl = string.match(v.model or "","*([%d]+)")
		if not numMdl then continue end
		self.__funcBrush[tonumber( numMdl )] = v
	end
	return self.__funcBrush
end

local function __readColorRGBExp32 ( data )
	return NikNaks.ColorRGBExp32ToColor( {
		r = data:ReadByte(),
		g = data:ReadByte(),
		b = data:ReadByte(),
		exponent = data:ReadSignedByte()
	} )
end

-- Returns the lightmap samples for the face.
-- @return table
function meta_face:GetLightmapSamples()
	local lightofs = self.lightofs
	if lightofs == -1 then return end
	if self._lightmap_samples then return self._lightmap_samples end

	local samples = {
		average = {},
		full = {}
	}

	self._lightmap_samples = samples

	local has_bumpmap = self:GetMaterial():GetString( "$bumpmap" ) ~= nil
	local luxel_count = ( self.LightmapTextureSizeInLuxels[1] + 1 ) * ( self.LightmapTextureSizeInLuxels[2] + 1 )

	local lightstyle_count = 0
	for _, v in ipairs( self.styles ) do
		if v ~= 255 then lightstyle_count = lightstyle_count + 1 end
	end

	-- "For faces with bumpmapped textures, there are four times the usual number of lightmap samples"
	local sample_count = lightstyle_count * luxel_count
	if has_bumpmap then sample_count = sample_count * 4 end

	local data = self.__map:GetLump( 8 )

	-- Get the average samples
	-- "Immediately preceeding the lightofs-referenced sample group,
	--  there are single samples containing the average lighting on the face, one for each lightstyle,
	--  in reverse order from that given in the styles[] array."
	local color, exponent
	data:Seek( ( lightofs * 8 ) - ( 32 * lightstyle_count ) )
	for _ = 1, lightstyle_count do
		color, exponent = __readColorRGBExp32( data )
		table.insert( samples.average, 1, { color = color, exponent = exponent } )
	end

	-- Get the full samples
	for _ = 1, sample_count do
		color, exponent = __readColorRGBExp32( data )
		table.insert( samples.full, { color = color, exponent = exponent } )
	end

	return samples
end


---Returns the face-index.
---@return number
function meta_face:GetIndex()
	return self.__id or -1
end
---Returns the normal for the face
---@return Vector
function meta_face:GetNormal()
	return self.plane.normal
end

---Returns the texture info for the face.
---@return table
function meta_face:GetTexInfo()
	return self.__map:GetTexInfo()[self.texinfo]
end

---Returns the texture data for the face.
---@return table
function meta_face:GetTexData()
	return self.__map:GetTexData()[ self:GetTexInfo().texdata ]
end

---Returns the texture for the face.
function meta_face:GetTexture()
	return self:GetTexData().nameStringTableID
end

---Returns the material the face use. Note: Materials within the BSP is not loaded.
---@return table
function meta_face:GetMaterial()
	if self._mat then return self._mat end
	self._mat = Material( self:GetTexture() or "__error" )
	return self._mat
end

---Returns true if the face should render.
---@return boolean
function meta_face:ShouldRender()
	local texinfo = self:GetTexInfo()
	local flags = texinfo and texinfo.flags or 0
	return bit.band(flags, 0x80) == 0 and bit.band(flags, 0x200) == 0
end

---Returns true if the face-texture is translucent
---@return boolean
function meta_face:IsTranslucent()
	local texinfo = self:GetTexInfo()
	return bit.band(texinfo.flags, 0x10)~= 0
end

---Returns true if the face is part of 2D skybox.
---@return boolean
function meta_face:IsSkyBox()
	local texinfo = self:GetTexInfo()
	return bit.band(texinfo.flags, 0x2) ~= 0
end

---Returns true if the face is part of 3D skybox
---@return boolean
function meta_face:IsSkyBox3D()
	local texinfo = self:GetTexInfo()
	return bit.band(texinfo.flags, 0x4)~= 0
end

---Returns true if the face's texinfo has said flag
---@return boolean
function meta_face:HasTexInfoFlag( flag )
	local texinfo = self:GetTexInfo()
	return bit.band(texinfo.flags, flag) ~= 0
end

---Returns true if the face's texinfo has said flag
---@return boolean
function meta_face:GetTexInfoFlags()
	local texinfo = self:GetTexInfo()
	return texinfo.flags
end

---Returns true if the face is part of the world and not another entity.
---@return boolean
function meta_face:IsWorld()
	return self.__bmodel == 0
end

---Returns the BModel the face has. 0 if it is part of the world.
---@return number
function meta_face:GetBModel()
	return self.__bmodel
end

---Returns the entity-object-data that is part of this face.
---@return string EntityData
function meta_face:GetEntity()
	return __findEntityUsingBrush(self.__map)[self.__bmodel]
end

-- Displacments TODO: Fix Displacment Position and Data

---Returns true if the face is part of Displacment
---@return boolean
function meta_face:IsDisplacment()
	return self.dispinfo > -1
end

function meta_face:GetDispInfo()
	if self.dispinfo < 0 then return nil end
	return self.__map:GetDispInfos()[self.dispinfo]
end

-- Returns the contents for the given face or nil if none.
function meta_face:GetContents()
	local disp = self:GetDispInfo()
	return disp and disp.contents
end

---Returns the vertex positions for the face. [Not Cached]
---Note this will ignore BModel-positions!
---@return table
function meta_face:GetVertexs()
	if self._vertex then return self._vertex end
	local t = {}
	local dispInfo = self:GetDispInfo()
	if not dispInfo then
		for i = 0, self.numedges - 1 do
			t[i + 1] = self.__map:GetSurfEdgesIndex( self.firstedge + i )
		end
		self._vertex = t
		return t
	end
	-- This is a displacment
	-- TODO: Calculate the displacment mesh and return it here
	--local dispVertStart =
end

---Returns a table in form of a polygon-mesh. [Not Cached]
---TAB[ID] = {pos = position, u = u, v = v, lu = lightU, lv = lightV }
---@return table
function meta_face:GenerateVertexData()
	local t = {}
	local tv = self:GetTexInfo().textureVects
	local lv = self:GetTexInfo().lightmapVecs
	local texdata = self:GetTexData()
	local mat_w, mat_h = texdata.view_width, texdata.view_height
	local n = self:GetNormal()

	-- Move the faces to match func_brushes (If any)
	local bNum = self.__bmodel
	local exPos, exAng
	if bNum > 0 then
		-- Get funch_brushes and their location
		local func_brush = __findEntityUsingBrush(self.__map)[bNum]
		if func_brush then
			exPos = func_brush.origin
			exAng = func_brush.angles
		end
	end

	local luxelW = self.LightmapTextureSizeInLuxels[1] + 1
	local luxelH = self.LightmapTextureSizeInLuxels[2] + 1

	for i = 0, self.numedges - 1 do
		local vert = {}
		local a = self.__map:GetSurfEdgesIndex( self.firstedge + i )
		vert.pos = a
		if bNum > 0 then -- WorldPos -> Entity Brush
			a = WorldToLocal( a, Angle(0,0,0), Vector(0,0,0), exAng )
			vert.pos = a + exPos
		end
		vert.normal = n
		-- UV & LV
		vert.u = ( tv[0][0] * a.x + tv[0][1] * a.y + tv[0][2] * a.z + tv[0][3] ) / mat_w
		vert.v = ( tv[1][0] * a.x + tv[1][1] * a.y + tv[1][2] * a.z + tv[1][3] ) / mat_h

		vert.lu = ( ( lv[0][0] * a.x + lv[0][1] * a.y + lv[0][2] * a.z + lv[0][3] ) - self.LightmapTextureMinsInLuxels[1] ) / luxelW
		vert.lv = ( ( lv[1][0] * a.x + lv[1][1] * a.y + lv[1][2] * a.z + lv[1][3] ) - self.LightmapTextureMinsInLuxels[2] ) / luxelH

		vert.userdata = { 0, 0, 0, 0 } -- Todo: Calculate this?

		t[i + 1] = vert
	end
	return t
end

local function PolyChop( o_vert )
	local vert = {}
	if #o_vert < 3 then return end
	local n, triCount = 1, #o_vert - 2
	for i = 1, triCount do
		vert[n] 	= o_vert[1]
		vert[n + 1] = o_vert[i + 1]
		vert[n + 2] = o_vert[i + 2]
		n = n + 3
	end
	return vert
end

---Returns a table in form of a polygon-mesh for triangles. [Not Cached]
---TAB[ID] = {pos = position, u = u, v = v, lu = lightU, lv = lightV }
---@return table
function meta_face:GenerateVertexTriangleData()
	if self._vertTriangleData then return self._vertTriangleData end
	self._vertTriangleData = PolyChop( self:GenerateVertexData() )
	return self._vertTriangleData
end

---All mesh-data regarding said face. Should use face:GenerateVertexTriangleData intead!
---@return table
function meta_face:GenerateMeshData()
	local t = {}
	t.verticies = self:GenerateVertexData()
	t.triangles = PolyChop( t.verticies )
	t.material = self:GetTexture()
	return {t}
end

do
	local mt = getmetatable(Vector(0,0,0))
	local dot = mt.Dot
	local cross, abs = mt.Cross, math.abs
	local function rayTriangleIntersect(orig, dir, v0, v1, v2)
		local v0v1 = v1 - v0
		local v0v2 = v2 - v0
		local pvec = cross(dir,v0v2)
		local det = dot(v0v1, pvec)
	
		// ray and triangle are parallel if det is close to 0
		if abs(det) < 0.01 then return false end 
	
		local invDet = 1 / det
	
		local tvec = orig - v0
		local u = dot(tvec, pvec) * invDet
		if (u < 0 or u > 1) then return false end
	
		local qvec = cross(tvec,v0v1) 
		local v = dot(dir, qvec) * invDet 
		if (v < 0 or u + v > 1) then return false end
	
		t = dot(v0v2, qvec) * invDet
	
		return true, u, v, t
	end

	-- TODO: Fix UV coordinats being relative to triangle-mesh, and not surface.mesh
	function meta_face:IsRayIntersecting( origin, dir )
		local poly = self:GetVertexs()
		local j = 1
		local result_hit, u, v, dis = false
		for i = 1, #poly - 2 do
			local v0 = poly[1]
			local v1 = poly[i + 1]
			local v2 = poly[i + 2]
			local hit, ru, rv, t = rayTriangleIntersect(origin, dir, v0, v1, v2)
			if hit and (not dis or dis < t) and t > 0 then
				result_hit, u, v, dis = true, ru, rv, t
			end
			j = j + 3
		end
		return result_hit, u, v, t
	end
end


if CLIENT then
	NIKNAKS_TABOMESH = NIKNAKS_TABOMESH or {}
	---Builds the mesh if face has none.
	---@return iMesh
	function meta_face:BuildMesh()
		if SERVER then return end
		if self._mesh then return self._mesh end
		-- Tex
		local texinfo = self:GetTexInfo()
		if bit.band(texinfo.flags, 0x80) ~= 0 or bit.band(texinfo.flags, 0x200) ~= 0 then self._mesh = false return self._mesh end
		
		local meshData = self:GenerateVertexTriangleData()
		if not meshData then return self._mesh end
		self._mesh = Mesh( self:GetMaterial() )
		local lData = face:GetLightmapSamples()
		local data = lData.average and lData.average[1]
		local col = color_white
		if (data) then
			col = data
			print("!", col)
		end
		-- Vert
		mesh.Begin( self._mesh, MATERIAL_TRIANGLES, #meshData )
		for i = 1, #meshData do
			local vert = meshData[i]
			-- > Mesh
			mesh.Normal( vert.normal )
			mesh.Position( vert.pos ) -- Set the position
			mesh.Color(col.r, col.g, col.b, col.a)
			mesh.TexCoord( 0, vert.u, vert.v ) -- Set the texture UV coordinates
			mesh.TexCoord( 1, vert.lu, vert.lv ) -- Set the lightmap UV coordinates
			mesh.TexCoord( 2, vert.lu, vert.lv  ) -- Set the lightmap UV coordinates
			--mesh.TexCoord( 2, self.LightmapTextureSizeInLuxels[1], self.LightmapTextureSizeInLuxels[2] ) -- Set the texture UV coordinates
			--mesh.TexCoord( 2, self.LightmapTextureMinsInLuxels[1], self.LightmapTextureMinsInLuxels[2] ) -- Set the texture UV coordinates
			mesh.AdvanceVertex()
		end
		mesh.End()
		table.insert(NIKNAKS_TABOMESH, self._mesh)
		return self._mesh
	end

	---Returns the mesh generated for the face.
	---Note. Need to call face:BuildMesh first.
	---@return iMesh|nil
	function meta_face:GetMesh()
		return self._mesh
	end

	---Deletes the mesh generated for the face.
	---@return self
	function meta_face:DeleteMesh()
		if not self._mesh then return end
		self._mesh:Destroy()
		self._mesh = nil
		return self
	end

	---Pushes the face-mesh into a dynamic-render. Better to generate the mesh and let the engine do this.
	function meta_face:DebugRender( materialOverride )
		local verts = self:GenerateVertexTriangleData()
		if not verts then return end -- Invalid data?
		render.SetMaterial( materialOverride or self:GetMaterial() )
		mesh.Begin( MATERIAL_TRIANGLES, #verts / 3 ) -- Begin writing to the dynamic mesh
		for i = 1, #verts do
			mesh.Position( verts[i].pos ) -- Set the position
			mesh.TexCoord( 0, verts[i].u, verts[i].v ) -- Set the texture UV coordinates
			mesh.AdvanceVertex() -- Write the vertex
		end
		mesh.End()
	end

	function meta_face:GetOrigin()
		local func_brush = __findEntityUsingBrush(self.__map)[self.__bmodel]
		return func_brush and func_brush.origin or vector_origin
	end

	function meta_face:TryMerge( face, planenormal, dontCreate )
		local winding = self:WindingFromFace( self:GetOrigin() )
		return winding:TryMerge( face:WindingFromFace( face:GetOrigin() ), planenormal, dontCreate)		
	end

	for k, _mesh in pairs( NIKNAKS_TABOMESH ) do
		if IsValid(_mesh) then
			_mesh:Destroy()
		end
	end
end
