local M = {}

local mapped_keys = { 'e', 'i', 'q', '<CR>' }

---@return string
local function version_string()
    local version = vim.version()
    return "Nvim-" ..
           version.major .. "." ..
           version.minor .. "." ..
           version.patch ..
           (type(version.build) == 'string' and
             "-" .. version.build or
             '') ..
           " " .. _VERSION ..
           (jit and " (jit)" or "")
end

local function delete_mappings()
    for _,key in pairs(mapped_keys) do
        vim.keymap.del('n', key, { buffer = vim.g.startpage_buf })
    end
    vim.g.startpage_buf = nil
end

local function close_startpage()
    if vim.g.startpage_buf == nil or
       not vim.api.nvim_buf_is_valid(vim.g.startpage_buf) then
        return
    end

    vim.api.nvim_buf_delete(vim.g.startpage_buf, {})
    vim.g.startpage_buf = nil
end

local function setup_mappings()
    -- Clear to an empty buffer
    vim.keymap.set("n", "e", function ()
        vim.bo.modifiable = true
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {''})
        delete_mappings()

    end, { buffer = vim.g.startpage_buf })

    -- Start editing in an empty buffer
    vim.keymap.set("n", "i", function ()
        vim.bo.modifiable = true
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {''})
        vim.cmd "startinsert"
        delete_mappings()

    end, { buffer = vim.g.startpage_buf })

    -- Quit
    vim.keymap.set("n", "q", function ()
        vim.cmd "qa!"
    end, { buffer = vim.g.startpage_buf })

    -- Go to file
    vim.keymap.set("n", "<CR>", function ()
        local filepath = vim.trim(vim.api.nvim_get_current_line())
        if vim.fn.filereadable(filepath) ~= 1 then
            return
        end

        vim.cmd("edit " .. filepath)

    end, { buffer = vim.g.startpage_buf })
end

---@param line string
---@param winwidth number
---@return string
local function get_center_spacing(line, winwidth)
    local linewidth = vim.api.nvim_strwidth(line)
    local leading_spacing = math.floor((winwidth - linewidth) / 2)
    local spaces = string.rep(" ", leading_spacing)
    return spaces
end

local function center_cursor()
    local winheight = vim.api.nvim_win_get_height(0)
    local winwidth = vim.api.nvim_win_get_width(0)
    local linenr = math.floor(winheight  / 2)
    vim.api.nvim_win_set_cursor(0, {linenr, math.floor(winwidth/2)})
end

---@param spacing string
---@param count number
---@return table<string>
local function get_oldfiles(spacing, count)
    local _, devicons = pcall(require, 'nvim-web-devicons')

    local lines = {}
    local cwd = vim.fn.getcwd() .. "/"

    for i,f in pairs(vim.v.oldfiles) do
        if i == count then
            break
        end

        -- Only list files that exist under the current cwd
        if vim.fn.filereadable(f) ~= 1 or not vim.startswith(f, cwd) then
            goto continue
        end

        local entry = f:sub(#cwd + 1)

        -- Skip .git/COMMIT_EDITMSG
        if vim.startswith(entry, '.git') then
            goto continue
        end

        local filename = vim.fs.basename(entry)
        local splits = vim.split(entry, '.', {plain = true, trimempty = true})
        local ext = #splits >= 1 and splits[#splits] or ''
        local icon
        local hl_group

        if devicons then
            icon, hl_group = devicons.get_icon(filename, ext, {})
        end
        entry = (icon or '') .. " " .. entry

        table.insert(lines, spacing .. entry)

        ::continue::
    end

    if #lines >= 1 then
        table.insert(lines, 1, spacing .. " ")
        table.insert(lines, 1, spacing .. "  Recent files")
    end

    return lines
end

---@param lines table<string>
---@return table<string>
local function vertical_align(lines)
    local height = vim.api.nvim_win_get_height(0)

    local top_offset = math.floor((height - #lines)/2)
    local bottom_spacing = height - top_offset - #lines
    local centered_lines = lines

    -- Top spacing
    for _ = 1,top_offset do
        table.insert(centered_lines, 1, "")
    end

    -- Bottom spacing
    for _ = 1,bottom_spacing do
        table.insert(centered_lines, "")
    end

    return centered_lines
end

function M.setup()
    -- Do not open startpage when reading from stdin
    vim.api.nvim_create_autocmd('StdinReadPre', {
        pattern = {},
        callback = function()
            vim.g.startpage_buf = vim.api.nvim_get_current_buf()
            vim.g.stdin_read = true
        end,
    })

    -- Close the startpage as soon as we open a file, i.e. make it automatically
    -- close when calling :Files etc.
    vim.api.nvim_create_autocmd('BufRead', {
        pattern = {},
        callback = function ()
            if vim.g.startpage_buf ~= vim.api.nvim_get_current_buf() then
                close_startpage()
            end
        end
    })

    vim.api.nvim_create_autocmd("UIEnter", {
        pattern = {},
        callback = function ()
            if vim.g.stdin_read or vim.fn.expand'%' ~= '' then
                return
            end

            vim.g.startpage_buf = vim.api.nvim_get_current_buf()

            setup_mappings()

            -- TODO
            vim.g.startpage_ns_id = vim.api.nvim_create_namespace('startpage')

            -- Make the version string centered and align everything else
            -- to fit with it.
            local winwidth = vim.api.nvim_win_get_width(0)
            local version = version_string()
            local spacing = get_center_spacing(version, winwidth)

            local lines = vim.tbl_flatten({
                    spacing .. version,
                    spacing .. " ",
                    get_oldfiles(spacing, 7),
            })

            local aligned_lines = vertical_align(lines)

            vim.api.nvim_buf_set_lines(0, 0, -1, false, aligned_lines)
            vim.bo.modifiable = false
            vim.bo.modified = false
            center_cursor()
        end
    })
end

return M
