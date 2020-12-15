local Instance = require("ge_tts/Instance")
local EventManager = require("ge_tts/EventManager")

---@param container tts__Object
---@param obj tts__Object
---@return nil | boolean
local function filterObjectEnterContainer(_, obj)
    if obj.tag == "Bag" then
        local allInstances = Instance.getAllInstances()
        for _, entry in ipairs((--[[---@type tts__Container]] obj).getObjects()) do
            if allInstances[entry.guid] then
                return false
            end
        end
    end

    return true
end

EventManager.addHandler("filterObjectEnterContainer", filterObjectEnterContainer)