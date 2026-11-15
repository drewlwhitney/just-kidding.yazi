-- you can use this to write an UNDO plugin

local utils = require(".utils")

-- used by `invert_operation()`
local inverses = {
    rename_or_move = function(original)
        local payload = {}
        -- swap the "to" and "from" locations
        for from, to in pairs(original) do
            payload[to] = from
        end
        return {
            kind = original.kind,
            payload = payload,
        }
    end,
    trash = function(original)
        return {
            kind = "restore",
            payload = original.payload,
        }
    end,
    restore = function(original)
        return {
            kind = "trash",
            payload = original.payload,
        }
    end,
    delete = function(_)
        -- cannot undo delete operation
        return nil
    end,
}

---Invert an operation.
---@param original Operation
---@return Operation?
local function invert_operation(original)
    return inverses[original.kind](original)
end

---Get the top undo operation. TODO: replace with `pop_undo_operation()`
local get_undo_operation = ya.sync(function(state)
    local op = state.undo_operation
    -- reset the operation
    state.undo_operation = nil
    return op
end)

---Set the undo operation. TODO: replace with `push_undo_operation()`
local set_undo_operation = ya.sync(function(state, undo_operation)
    state.undo_operation = undo_operation
end)

---Get the config.
---@return Config
local get_config = ya.sync(function(state)
    return state.config
end)

-- used by `run_operation()`
local operations = {
    ---Move files and maybe notify.
    ---@param location_map PathMap
    ---@param config Config
    ---@return boolean? ran, string? error
    move = function(location_map, config)
        local err = utils.move_paths(location_map)
        if err then
            return nil, err
        end
        if config.notify then
            utils.notify(
                "Moved Files",
                utils.path_map_to_string(location_map, config.shorten_home)
            )
        end
        return true, nil
    end,

    ---Move files and maybe notify.
    ---@param location_map PathMap
    ---@param config Config
    ---@return boolean? ran, string? error
    rename = function(location_map, config)
        local err = utils.move_paths(location_map)
        if err then
            return nil, err
        end
        if config.notify then
            utils.notify(
                "Renamed Files",
                utils.path_map_to_string(location_map, config.shorten_home)
            )
        end
        return true, nil
    end,

    ---Restore files from the trash.
    ---@param paths Url[]
    ---@param config Config
    ---@return boolean? ran, string? error
    restore = function(paths, config)
        local err = utils.restore_from_trash(paths)
        if err then
            return nil, err
        end
        if config.notify then
            utils.notify("Restored Files", utils.paths_to_string(paths, config.shorten_home))
        end
        return true, err
    end,

    ---Permanently delete files/folders. Cannot be undone.
    ---@param paths Url[]
    ---@param config Config
    ---@return boolean? ran, string? error
    delete = function(paths, config)
        if config.prompt_delete then
            local proceed = ya.confirm({
                pos = { "center", w = 70, h = 20 },
                title = "Permanently delete " .. #paths .. " files?",
                body = ui.Text(
                    utils.format_path_list(paths, config.shorten_home)
                ):align(ui.Align.LEFT),
            })
            if not proceed then
                return false, nil
            end
        end
        local err = utils.delete_paths(paths)
        if err then
            return nil, err
        end
        return true, nil
    end,

    ---Send files/folders to the trash.
    ---@param paths Url[]
    ---@param config Config
    ---@return boolean? ran, string? error
    trash = function(paths, config)
        local err = utils.send_to_trash(paths)
        if err then
            return nil, err
        end
        return true, nil
    end,
}

---Run an operation.
---@param operation Operation
---@param config Config
---@return boolean? ran, string? error
local function run_operation(operation, config)
    local ran, err = operations[operation.kind](operation.payload, config)
    if err then
        return nil, err
    end
    return ran, nil
end

---Handle files being moved (i.e. cut/paste).
---@param state State
---@param body MoveBody
local function handle_move(state, body)
    local payload = {}
    for _, item in ipairs(body.items) do
        payload[item.to] = item.from
    end

    -- store the "from-to" path map in reverse
    state.undo_operation = {
        kind = "move",
        payload = payload,
    }
end

---Handle a single file being renamed.
---@param state State
---@param body RenameBody
local function handle_rename(state, body)
    --don't do anything if the name didn't actually change
    --TODO: maybe remove this depending on the answer to
    --https://github.com/sxyazi/yazi/discussions/4499
    if tostring(body.to) == tostring(body.from) then
        return
    end

    local payload = {}
    payload[body.to] = body.from
    -- store the "from" and "to" paths in reverse
    state.undo_operation = {
        kind = "rename",
        -- using the same payload as a bulk rename
        payload = payload,
    }
end

---Handle multiple files being renamed at once.
---@param state State
---@param body BulkRenameBody
local function handle_bulk_rename(state, body)
    -- store the "from" and "to" paths in reverse
    local payload = {}
    for from, to in pairs(body) do
        payload[to] = from
    end
    state.undo_operation = {
        kind = "rename",
        payload = payload,
    }
end

---Handle files being trashed.
---@param state State
---@param body TrashBody
local function handle_trash(state, body)
    -- store the trashed paths
    state.undo_operation = {
        kind = "restore",
        payload = body.urls,
    }
end

---Handle files being copied.
---@param state State
---@param body CopyBody
---@param use_trash boolean
local function handle_copy(state, body, use_trash)
    -- discard the sources, store the destinations
    local destinations = {}
    for _, item in ipairs(body.items) do
        destinations[#destinations + 1] = item.to
    end

    state.undo_operation = {
        kind = use_trash and "trash" or "delete",
        payload = destinations,
    }
end

---Handle a single file being created.
---@param state State
---@param body CreateBody
---@param use_trash boolean
local function handle_create(state, body, use_trash)
    state.undo_operation = {
        kind = use_trash and "trash" or "delete",
        payload = { body.url },
    }
end

---Handle multiple files being created.
---@param state State
---@param body BulkCreateBody
---@param use_trash boolean
local function handle_bulk_create(state, body, use_trash)
    state.undo_operation = {
        kind = use_trash and "trash" or "delete",
        payload = body.urls,
    }
end


---Create the config, overriding any options provided.
---@param opts Options
---@return Config
local function create_config(opts)
    ---Merge the `config_table` with the `opts_table`.
    ---@param config_table table
    ---@param opts_table table
    ---@return string? error
    local function merge_config(config_table, opts_table)
        for key, opts_value in pairs(opts_table) do
            local config_value = config_table[key]
            if config_value == nil then
                return "Unknown config option: " .. key
            end

            local opts_value_type = type(opts_value)
            local config_value_type = type(config_value)

            if opts_value_type == "table" then
                if config_value_type ~= "table" then
                    return "Invalid value for key: " .. key
                end
                merge_config(config_value, opts_value)
            else
                if config_value_type ~= opts_value_type then
                    return "Invalid value for key: " .. key
                end
                config_table[key] = opts_value
            end
        end
    end

    ---@type Config
    local config = {
        notify = true,
        prompt_delete = true,
        shorten_home = false,
        use_trash = true,
        operations = {
            move = true,
            rename = true,
            bulk_rename = true,
            trash = true,
            copy = true,
            create = true,
            bulk_create = true,
        },
    }

    merge_config(config, opts)

    return config
end

---Setup.
---@param state State
---@param opts Options?
local function setup(state, opts)
    state.undo_operation = nil

    state.config = create_config(opts or {})
    local oper_config = state.config.operations
    local use_trash = state.config.use_trash

    -- handle file moves (i.e. cut/paste)
    if oper_config.move then
        if state.config.operations.move then
            ps.sub("move", function(body)
                ---@cast body MoveBody
                handle_move(state, body)
            end)
        end
    end

    -- handle single-file renames
    if oper_config.rename then
        ps.sub("rename", function(body)
            ---@cast body RenameBody
            handle_rename(state, body)
        end)
    end

    -- handle multi-file renames
    if oper_config.bulk_rename then
        ps.sub("bulk-rename", function(body)
            ---@cast body BulkRenameBody
            handle_bulk_rename(state, body)
        end)
    end

    -- handle files being sent to the trash
    if oper_config.trash then
        ps.sub("trash", function(body)
            ---@cast body TrashBody
            handle_trash(state, body)
        end)
    end

    -- handle files being copied
    if oper_config.copy then
        ps.sub("duplicate", function(body)
            ---@cast body CopyBody
            handle_copy(state, body, use_trash)
        end)
    end

    --handle single-file creation
    if oper_config.create then
        ps.sub("create", function(body)
            ---@cast body CreateBody
            handle_create(state, body, use_trash)
        end)
    end

    --handle multi-file creation
    if oper_config.create then
        ps.sub("bulk-create", function(body)
            ---@cast body BulkCreateBody
            handle_bulk_create(state, body, use_trash)
        end)
    end
end

return {
    setup = setup,
    entry = function(_self, _job)
        local undo_operation = get_undo_operation()
        ---@cast undo_operation Operation

        if undo_operation == nil then
            return
        end

        local config = get_config()

        local ran, err = run_operation(undo_operation, config)
        if err then
            utils.notify_err(err)
        end
        -- if the operation did not run, put it back on the stack
        if err ~= nil or not ran then
            set_undo_operation(undo_operation)
        end
    end,
}
