Global.script_state = ""
local GUIMemBag = require("MemBag/GUIMemBag")

---@param guid string
local function instanceFromGUID(guid)
    return GUIMemBag(--[[---@type tts__Container]] getObjectFromGUID(guid))
end

function onLoad()
    local bag = instanceFromGUID("222a81")
    --local card = instanceFromGUID("4ea443")
    --local deck = instanceFromGUID("6e575e")
    --local tile = instanceFromGUID("0b75fa")
    --local cube = instanceFromGUID("635247")
    --local marble = instanceFromGUID("17c103")
    --local board = instanceFromGUID("077ca6")
    --local sc_board = instanceFromGUID("74868d")


    -----@type LabelInstance[]
    --local instances = {
    --    --card,
    --    --deck,
    --    ---- tile,
    --    --board,
    --    bag,
    --    --sc_board,
    --    ---- cube,
    --}
    --
    --for _, obj in ipairs(instances) do
    --    --local objCreateButton = obj.setLabel
    --    --objCreateButton({
    --    --    color = "Red",
    --    --    label = "at\nsmaller\nwidths\nit\nis\nless\nnoticeable",
    --    --    position = {1, 1},
    --    --    align = {1, -1},
    --    --    -- rotation = 1
    --    --})
    --    -- objCreateButton({
    --    --     color = "Red",
    --    --     label = "but this longer one one overlaps a bit",
    --    --     position = {1, 0},
    --    --     align = {-1, 0},
    --    -- })
    --end
end