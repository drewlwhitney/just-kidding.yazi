-- utility functions for the plugin

local M = {}

---Show a notification.
---@param title string
---@param content string
function M.notify(title, content)
    ya.notify({
        title = title,
        content = content,
        timeout = 4.0,
        level = "info",
    })
end

---Show an error notification.
---@param message string
function M.notify_err(message)
    ya.notify({
        title = "Error",
        content = message,
        timeout = 4.0,
        level = "error",
    })
end

---Get the keys of a table.
---@generic K
---@generic V
---@param tab table<K, V>
---@return K[]
local function keys(tab)
    local out = {}
    for key, _ in pairs(tab) do
        out[#out + 1] = key
    end
    return out
end

---Get the values of a table.
---@generic K
---@generic V
---@param tab table<K, V>
---@return V[]
local function values(tab)
    local out = {}
    for _, value in pairs(tab) do
        out[#out + 1] = value
    end
    return out
end

---Replace `/home/[USER]` with `~`.
---@param path string
function M.shorten_home(path)
    local homedir = os.getenv("HOME")
    if homedir == nil then
        return path
    end

    return string.gsub(path, homedir, '~', 1)
end

local function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            local foo = ""
            if type(k) ~= 'number' then foo = '"' .. foo .. '"' end
            s = s .. '[' .. foo .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

---Ensure none of the paths exist. If any do, return the first one.
---@param paths Url[]
---@return Url?
local function ensure_none_exist(paths)
    for _, path in ipairs(paths) do
        local cha, _ = fs.cha(path)
        -- this indicates the file exists
        if cha ~= nil then
            return path
        end
    end
end

---Format a path map as a newline-separated string.
---@param path_map PathMap
---@param should_shorten_home boolean
---@return string
function M.path_map_to_string(path_map, should_shorten_home)
    local content = ""
    for from, to in pairs(path_map) do
        local from_string = tostring(from)
        local to_string = tostring(to)
        if should_shorten_home then
            from_string = M.shorten_home(from_string)
            to_string = M.shorten_home(to_string)
        end
        content = content .. string.format("%s => %s\n", from_string, to_string)
    end
    return content
end

---Format a list of paths (`Url`s) as a newline-separated string.
---@param paths Url[]
---@param should_shorten_home boolean
---@return string
function M.paths_to_string(paths, should_shorten_home)
    local content = ""
    for _, path in ipairs(paths) do
        local path_string = tostring(path)
        if should_shorten_home then
            path_string = M.shorten_home(path_string)
        end
        content = content .. path_string .. "\n"
    end
    return content
end

---Format a list of paths (`Url`s) as a list of `Line`s.
---@param paths Url[]
---@param should_shorten_home boolean
---@return ui.Line[]
function M.format_path_list(paths, should_shorten_home)
    local lines = {}
    for _, path in ipairs(paths) do
        local path_string = tostring(path)
        if should_shorten_home then
            path_string = M.shorten_home(path_string)
        end
        lines[#lines + 1] = ui.Line(path_string):align(ui.Align.LEFT)
    end
    return lines
end

---Restore a list of files from the trash. Restores the most recent entries.
---@param paths Url[]
---@return string? error
function M.restore_from_trash(paths)
    local trash_entries, list_err = fs.trash.list() -- top level of the trash
    if list_err then
        return tostring(list_err)
    end

    -- sort by most-recently-trashed
    -- NOTE: this only works if the files have not been modified while
    -- in the trash bin
    table.sort(trash_entries, function(first, second)
        return first.stat.ctime > second.stat.ctime
    end)

    local entries_to_restore = {}

    for _, path in ipairs(paths) do
        for _, entry in ipairs(trash_entries) do
            if tostring(entry.original) == tostring(path) then
                entries_to_restore[#entries_to_restore + 1] = entry
                break
            end
        end
    end

    local _, restore_err = fs.trash.restore(entries_to_restore)
    if restore_err then
        return tostring(restore_err)
    end
end

---Send files to the trash (currently uses `trash-cli`).
---@param paths Url[]
---@return string? error
function M.send_to_trash(paths)
    local path_strings = {}
    for _, path in ipairs(paths) do
        path_strings[#path_strings + 1] = tostring(path)
    end
    local _, error = Command("trash-put"):arg(path_strings):output()
    if error then
        return tostring(error)
    end
end

---Move (or rename) files in the map.
---@param path_map PathMap
---@return string? error
function M.move_paths(path_map)
    local existing_path = ensure_none_exist(values(path_map))
    if existing_path ~= nil then
        return "File exists: " .. tostring(existing_path)
    end

    for from, to in pairs(path_map) do
        local _, err = fs.rename(from, to)
        if err then
            return tostring(err)
        end
    end
end

---Permanently delete files/folders.
---@param paths Url[]
---@return string? error
function M.delete_paths(paths)
    for _, path in pairs(paths) do
        local cha, cha_err = fs.cha(path)
        if cha_err then
            return tostring(cha_err)
        end

        ---@cast cha Cha already checked the error

        local _, remove_err = fs.remove(cha.is_dir and "dir_all" or "file", path)
        if remove_err then
            return tostring(remove_err)
        end
    end
end

return M
