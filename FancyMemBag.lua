local Logger = require("ge_tts/Logger")
local Instance = require("ge_tts/Instance")
local TableUtils = require('ge_tts/TableUtils')
local EventManager = require("ge_tts/EventManager")

---@class MemBagInstance : ge_tts__Instance

---@shape MemBag_entry
---@field pos tts__Vector
---@field rot tts__Vector
---@field lock nil | boolean
---@field parent nil | string

---@alias entries table<string, MemBag_entry>

---@shape MemBag_config
---@field smoothTake nil | boolean
---@field lift nil | number

---@type MemBag_config
local defaultConfig = {
	smoothTake = true,
	lift = 1,
	delay = 0.4,
}

local configMeta = {__index = defaultConfig}

---@shape MemBagInstance_SavedState : ge_tts__Instance_SavedState
---@field entries entries
---@field config MemBag_config

---@class static_MemBagInstance : ge_tts__static_Instance
---@overload fun(savedState: MemBagInstance_SavedState): CenteredMemBagInstance
---@overload fun(object: tts__Container): CenteredMemBagInstance
---@overload fun(object: tts__Container, objects: tts__Object[]): CenteredMemBagInstance
---@overload fun(object: tts__Container, objects: nil | tts__Object[], config: MemBag_config): CenteredMemBagInstance
local MemBagInstance = {}

MemBagInstance.INSTANCE_TYPE = "Absolute MemBag"

setmetatable(MemBagInstance, TableUtils.merge(getmetatable(Instance), {
	---@param objOrSavedState tts__Container | CenteredMemBagInstance_SavedState
	---@param nilOrEntries nil | entries
	---@param nilOrConfig nil | MemBag_config
	__call = function(objOrSavedState, nilOrEntries, nilOrConfig)
		local self = --[[---@type MemBagInstance]] Instance(objOrSavedState) -- super constructor

		---@type entries
		local entries
		---@type MemBag_config
		local config

		---@param entry MemBag_entry
		---@param guid string
		---@return MemBag_entry
		local function entryMapFunc(entry, guid)
			return self.addEntry(guid, entry)
		end

		local isSavedState = MemBagInstance.isSavedState(objOrSavedState)
		if isSavedState then
			local savedState = --[[---@type MemBagInstance_SavedState]] objOrSavedState

			config = setmetatable(savedState.config, configMeta)
			TableUtils.map(savedState.entries, entryMapFunc)
		else
			if nilOrEntries then
				TableUtils.map(--[[---@not nil]] nilOrEntries, entryMapFunc)
			else
				entries = {}
			end

			if nilOrConfig then
				config = setmetatable(TableUtils.copy(config), configMeta)
			else
				config = setmetatable({}, configMeta)
			end
		end

		local superSave = self.save
		-- Then, we replace this method with our own implementation...

		---@return MemBagInstance_SavedState
		function self.save()
			-- ge_tts__Instance (our super class) has its own data that it needs to save. So we call
			-- through to the original (super) save() method, and merge its result with our own data
			-- i.e. our object entries
			return --[[---@type MemBagInstance_SavedState]] TableUtils.merge(superSave(), {
				config = config,
				entries = entries,
			})
		end

		---@return string
		function self.getInstanceType()
			return MemBagInstance.INSTANCE_TYPE
		end

		local superGetObject = self.getObject
		---This overload is really just for Luanalysis, i didn't feel like casting to container every time
		---@return tts__Container
		function self.getObject()
			return superGetObject()
		end

		---Fetches existing entry instance
		---@param guid string
		---@return nil | MemBag_entry
		function self.getEntryData(guid)
			return TableUtils.copy(entries[guid], true)
		end

		---This is basically ripped from Instance.takeObject().
		---Looks for guid in the scene and in `parent` (self obj by default, or whatever guid is in entry)
		---@param guid string
		---@return tts__IndexedSimpleObjectState | tts__Object
		function self.findEntry(guid)
			---@type tts__Container, nil | tts__IndexedSimpleObjectState, any
			local parent, nilOrState, _

			local parentGUID = entries[guid] and entries[guid].parent
			parent = --[[---@type tts__Container]] (parentGUID and getObjectFromGUID(--[[---@not nil]] parentGUID) or self.getObject()) -- jeez
			Logger.assert(parent ~= nil,
					string.format("MemBag %s: parent %s of entry %s doesn't exist", self.getInstanceGuid(), parentGUID, guid))
			Logger.assert(parent.getObjects(),
					string.format("MemBag %s: parent %s of entry %s is not a container", self.getInstanceGuid(), parentGUID, guid))

			nilOrState, _ = TableUtils.detect(parent.getObjects(), function(objectState)
				return objectState.guid == guid
			end)

			local nilOrObj = getObjectFromGUID(guid)

			Logger.assert(nilOrState or nilOrObj,
					"object with guid " .. guid .. "not found!")
			Logger.assert(not (nilOrState and nilOrObj),
					"objects with guid" .. guid .. " exist both in and out of parent!")

			return --[[---@not nil]] nilOrState or --[[---@not nil]] nilOrObj
		end

		---Gets bag position from real-world position, used when adding entries
		---This one i straightforward but meant to be overridden.
		---@param pos tts__CharVectorShape
		---@param rot tts__CharVectorShape
		---@return tts__Vector, tts__Vector
		function self.getTransform(pos, rot)
			return Vector(pos), Vector(rot)
		end

		---Reverse of getTransform- gets real-world position from bag position. Used when placing entries
		---@param entry MemBag_entry
		---@return tts__Vector, tts__Vector
		function self.applyTransform(entry)
			return entry.pos, entry.rot
		end

		---Looks inside and outside self for matching object and makes an Instance for it, then adds it to entries.
		---Errors if matching object does not exist either directly in the scene or inside selfObj.
		---@param guid string
		---@param nilOrData nil | MemBag_entry
		---@return MemBag_entry
		---@overload fun(guid: string): ge_tts__Instance
		function self.addEntry(guid, nilOrData)
			addToAllEntries(guid, self)

			---@type tts__Object
			local entryObj

			-- this next block is just paranoia to ensure the obj exists

			---@type tts__Object | tts__IndexedSimpleObjectState
			local foundEntry = self.findEntry(guid)
			if type(foundEntry == "table") then
				entryObj = self.getObject()
			else -- it's an object
				entryObj = --[[---@type tts__Object]] foundEntry
			end

			if nilOrData then
				local data = TableUtils.copy(--[[---@not nil]] nilOrData)
				data.pos, data.rot = self.getTransform(data.pos, data.rot)
				entries[guid] = data
			else
				local pos, rot = self.getTransform(entryObj.getPosition(), entryObj.getRotation())
				entries[guid] = {
					pos = pos,
					rot = rot,
					lock = entryObj.getLock()
				}
			end

			self.invalidateSavedState()
			return entries[guid]
		end

		---@param guid string
		---@param parent nil | string
		function self.setParent(guid, parent)
			Logger.assert(entries[guid],
					string.format("setParent: MemBag %s does not have entry %s", self.getInstanceGuid(), guid))
			entries[guid].parent = parent
			self.invalidateSavedState()
		end

		---@param guid string
		function self.removeEntry(guid)
			entries[guid] = nil
			allMemBagEntries[guid] = nil
			self.invalidateSavedState()
		end

		---@param obj tts__Object
		---@param nilOrDelay nil | number
		function self.placeEntryCallback(obj, nilOrDelay)
			local lock = entries[obj.getGUID()].lock or false
			obj.setLock(lock)
			if nilOrDelay then

			end
		end

		---@param guid string
		---@param nilOrSmoothTake nil | boolean
		---@param nilOrDelay nil | number
		-- just copy/paste from parent
		function self.placeEntry(guid, nilOrSmoothTake, nilOrDelay)
			Logger.assert(entries[guid], "no entry with guid " .. guid)
			local entry = entries[guid]

			-- todo: man handling default args is awkward. ask for feedback on style
			local smoothTake = (nilOrSmoothTake == nil) and config.smoothTake or nilOrSmoothTake
			local delay = (nilOrDelay == nil) and config.delay or nilOrDelay

			local pos, rot = self.applyTransform(entry)

			local parent = --[[---@not nil]] entries[guid].parent
			if parent then
				---@type tts__Object_GuidTakeObjectParameters
				local params = {
					guid = guid,
					position = pos,
					rotation = rot,
					smooth = smoothTake,
					callback_function = function(obj) self.placeEntryCallback(obj, delay) end,
				}
				(--[[---@not nil]] getObjectFromGUID(parent)).takeObject(params)
			else -- it's an object
				local entryObj = --[[---@not nil]] getObjectFromGUID(guid)

				if smoothTake then
					entryObj.setPositionSmooth(pos, false, true)
					entryObj.setRotationSmooth(pos, false, true)
				else
					entryObj.setPosition(pos)
					entryObj.setRotation(rot)
				end

				self.placeEntryCallback(entryObj, delay)
			end
		end

		---by default we only let children go into their parent bag. This can be overridden to be more permissive ofc
		---@param container tts__Object
		---@param obj tts__Object
		function self.filterObject(container, obj)
			if container == self.getObject() then
				return true
			end
		end

		---@param entryObj tts__Object
		---@param co thread
		---@param nilOrDelay nil | number
		function self.recallEntry_callback(entryObj, co, nilOrDelay)
			self.getObject().putObject(entryObj)
			if nilOrDelay then
				Wait.time(function() coroutine.resume(co) end,  --[[---@not nil]] nilOrDelay)
			else
				coroutine.resume(co)
			end
		end

		---@param guid string
		---@param nilOrDelay nil | number
		function self.recallEntry(guid, nilOrDelay)
			---@type nil | number
			local delay = (nilOrDelay == nil) and config.delay or nilOrDelay

			local selfObj = self.getObject()

			local parent = --[[---@not nil]] entries[guid].parent
			if parent then
				local parentObj = --[[---@not nil]] getObjectFromGUID(parent)

				---@type tts__Object_GuidTakeObjectParameters
				local params = {
					guid = guid,
					position = parentObj.getPosition() + Vector(0,1,0),
					smooth = true,
					callback_function = function(obj)
						local co, _ = coroutine.running()
						self.recallEntry_callback(obj, delay, co)
					end
				}
				(--[[---@not nil]] getObjectFromGUID(parent)).takeObject(params)
			else -- it's an object
				selfObj.putObject(--[[---@not nil]] getObjectFromGUID(guid))
			end

			if delay then
				coroutine.yield() -- it's now up to the callback to resume
			end
		end

		---@param nilOrSmoothTake nil | boolean
		---@param nilOrDelay nil | number
		---@overload fun(nilOrSmoothTake: nil | number)
		---@overload fun()
		function self.place(nilOrSmoothTake, nilOrDelay)
			local smoothTake = (nilOrSmoothTake == nil) and config.smoothTake or nilOrSmoothTake
			local delay = (nilOrDelay == nil) and config.delay or nilOrDelay

			return TableUtils.map(entries, function(_, guid)
				return self.placeEntry(guid, smoothTake, delay)
			end)
		end

		---@param nilOrDelay nil | number
		---@overload fun(nilOrDelay: nil | number)
		---@overload fun()
		function self.recall(nilOrSmoothTake, nilOrDelay)
			local smoothTake = (nilOrSmoothTake == nil) and config.smoothTake or nilOrSmoothTake
			local delay = (nilOrDelay == nil) and config.delay or nilOrDelay

			return TableUtils.map(entries, function(_, guid)
				return self.recallEntry(guid, delay)
			end)
		end

		return self
	end,
	__index = Instance,
}))