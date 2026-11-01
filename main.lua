-- you can use this to write an UNDO plugin

-- track for:
-- --rename
-- bulk rename
-- trash
-- --move--

---@class ToFrom
---@field from Url
---@field to Url

---@class MovePayload
---@field items ToFrom[]

---@class RenamePayload
---@field tab integer
---@field from Url
---@field to Url

---@class BulkRenamePayload

---@class TrashPayload
---@field urls Url[]

---@class State
---@field undo_item { kind: string }?

-- TODO: more type annoations

---Handle files being moved (i.e. cut/paste).
---@param state State
---@param body MovePayload
local function handle_file_moves(state, body)
    -- store the "from-to" path map
    state.undo_item = {
        kind = "move",
        move_items = body.items,
    }
end

local function handle_rename(state, body)
    -- store the "from" and "to" paths
    state.undo_item = {
        kind = "rename",
        from = body.from,
        to = body.to,
    }
end

local function setup(state)
    state.undo_item = nil

    -- handle file moves (i.e. cut/paste)
    ps.sub("move", function(body)
        handle_file_moves(state, body)
    end)

    -- handle single-file renames
    ps.sub("rename", function(body)
        handle_rename(state, body)
    end)
end

local get_undo_item = ya.sync(function(state)
    return state.undo_item
end)


---Show a notification.
---@param title string
---@param content string
local function notify(title, content)
    ya.notify({
        title = title,
        content = content,
        timeout = 4.0,
        level = "info",
    })
end

---Replace `/home/USER` with `~`.
---@param path string
local function shorten_home(path)
    -- TODO
end

---Restore a list of files from the trash using `trash-cli`'s `trash-restore`.
---@param paths Url
local function restore_from_trash(paths)
    -- TODO
    -- gonna have to pipe in a "0" and a newline to make `trash-restore` actually go
end

return {
    setup = setup,
    entry = function(_self, _job)
        local undo_item = get_undo_item()
        if undo_item ~= nil then
            if undo_item.kind == "move" then
                local notification_content = ""

                -- move the files back
                for _, move_item in ipairs(undo_item.move_items) do
                    fs.rename(move_item.to, move_item.from)

                    notification_content = notification_content .. string.format(
                        "%s => %s\n",
                        tostring(move_item.to),
                        tostring(move_item.from)
                    )
                end

                notify("Un-Moved Items", notification_content)
            elseif undo_item.kind == "rename" then
                -- un-rename the file
                fs.rename(undo_item.to, undo_item.from)

                notify("Un-Renamed Item", string.format("%s => %s", undo_item.to, undo_item.from))
            end

            -- can't undo the change again
            undo_item = nil
        end
    end,
}
