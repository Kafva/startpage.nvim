local M = {}

local mapped_keys = { 'e', 'i', 'p', 'P', 'q', '<CR>' }

M.default_opts = {
    recent_files_header = "  Recent files",
    oldfiles_count = 7,
}

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

---@param lines table<string>
---@param spacing string
---@return table<string>,number
local function vertical_align(lines, spacing)
    local height = vim.api.nvim_win_get_height(0)

    local top_offset = math.floor((height - #lines)/2)
    local bottom_spacing = height - top_offset - #lines
    local centered_lines = lines

    -- Top spacing
    for _ = 1,top_offset do
        table.insert(centered_lines, 1, spacing)
    end

    -- Bottom spacing
    for _ = 1,bottom_spacing do
        table.insert(centered_lines, spacing)
    end

    return centered_lines, top_offset
end

---@param count number
---@return table
local function get_oldfiles(count)
    local _, devicons = pcall(require, 'nvim-web-devicons')

    local out = {}
    local cwd = vim.fn.getcwd() .. "/"

    for _,f in pairs(vim.v.oldfiles) do
        -- Only list files that exist under the current cwd
        if vim.fn.filereadable(f) ~= 1 or not vim.startswith(f, cwd) then
            goto continue
        end

        local path = f:sub(#cwd + 1)

        -- Skip .git/COMMIT_EDITMSG
        if vim.startswith(path, '.git') then
            goto continue
        end

        local filename = vim.fs.basename(path)
        local splits = vim.split(path, '.', {plain = true, trimempty = true})
        local ext = #splits >= 1 and splits[#splits] or ''
        local icon
        local hl_group

        if devicons then
            icon, hl_group = devicons.get_icon(filename, ext, {})
        end

        table.insert(out, { path = path, icon = icon, hl_group = hl_group })

        if #out == count then
            break
        end

        ::continue::
    end

    return out
end

local function open_under_cursor()
    local line = vim.api.nvim_get_current_line()
    -- Trim away icon if present
    local filepath = vim.trim(line:gsub('[^-_./@a-zA-Z0-9åäöÅÄÖ]', ''))

    if vim.fn.filereadable(filepath) ~= 1 then
        return
    end

    vim.cmd("edit " .. filepath)
end

local function deinit_mappings()
    for _,key in pairs(mapped_keys) do
        vim.keymap.del('n', key, { buffer = vim.g.startpage_buf })
    end
    vim.g.startpage_buf = nil
end

-- Reset the startpage buffer to a regular empty buffer
local function clear_startpage()
    vim.bo.modifiable = true
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {''})
    vim.api.nvim_buf_clear_namespace(0, vim.g.startpage_ns_id, 0, -1)
    deinit_mappings()
end

local function init_mappings()
    -- Clear to an empty buffer
    vim.keymap.set("n", "e", clear_startpage, { buffer = vim.g.startpage_buf })

    -- Start editing in an empty buffer
    vim.keymap.set("n", "i", function ()
        clear_startpage()
        vim.cmd "startinsert"
    end, { buffer = vim.g.startpage_buf })

    -- Paste
    vim.keymap.set("n", "p", function ()
        clear_startpage()
        vim.cmd "normal! p"
    end, { buffer = vim.g.startpage_buf })

    vim.keymap.set("n", "P", function ()
        clear_startpage()
        vim.cmd "normal! P"
    end, { buffer = vim.g.startpage_buf })

    -- Quit
    vim.keymap.set("n", "q", function ()
        vim.cmd "qa!"
    end, { buffer = vim.g.startpage_buf })

    -- Go to file
    vim.keymap.set("n", "<CR>", open_under_cursor, { buffer = vim.g.startpage_buf })
end

-- Close the startpage buffer, keymaps and highlights are buffer local so
-- they do not need to be cleared here.
local function close_startpage()
    if vim.g.startpage_buf == nil or
       not vim.api.nvim_buf_is_valid(vim.g.startpage_buf) then
        return
    end

    vim.api.nvim_buf_delete(vim.g.startpage_buf, {})
    vim.g.startpage_buf = nil
end

local function init_startpage()
    if vim.g.stdin_read or vim.fn.expand'%' ~= '' then
        return
    end

    vim.g.startpage_buf = vim.api.nvim_get_current_buf()
    vim.g.startpage_ns_id = vim.api.nvim_create_namespace('startpage')

    -- Make the version string centered and align everything else
    -- to fit with it.
    local winwidth = vim.api.nvim_win_get_width(0)
    local version = version_string()
    local spacing = get_center_spacing(version, winwidth)

    local oldfiles = get_oldfiles(M.oldfiles_count)
    local oldfiles_lines = {}
    local header = {
            spacing .. version,
            spacing .. " ",
            #oldfiles >= 1 and (spacing .. M.recent_files_header) or
                               (spacing .. "No recent files"),
            spacing .. " "
    }

    if #oldfiles >= 1 then
        for _,oldfile in pairs(oldfiles) do
            local icon = oldfile.icon or " "
            local line = spacing .. icon .. string.rep(' ', 2) .. oldfile.path
            table.insert(oldfiles_lines, line)
        end
    end

    local content_lines = vim.tbl_flatten({ header, oldfiles_lines })

    local aligned_lines, top_offset = vertical_align(content_lines, spacing .. " ")

    vim.api.nvim_buf_set_lines(0, 0, -1, false, aligned_lines)

    -- Set highlighting for icons
    for i,oldfile in ipairs(oldfiles) do
        if oldfile.hl_group == nil then
            goto continue
        end

        local linenr = top_offset + #header + (i-1)
        local col_start = #spacing
        local col_end = #spacing + 1
        -- local location = oldfile.hl_group .. " " .. tostring(linenr) .. ":" .. tostring(col_start)
        -- vim.notify("[startpage] " ..  location , vim.log.levels.debug)
        vim.api.nvim_buf_add_highlight(vim.g.startpage_buf,
                                       vim.g.startpage_ns_id,
                                       oldfile.hl_group,
                                       linenr,
                                       col_start,
                                       col_end)
        ::continue::
    end

    vim.bo.modifiable = false
    vim.bo.modified = false
    center_cursor()
    init_mappings()
end

function M.setup(user_opts)
    local opts = vim.tbl_deep_extend("force", M.default_opts, user_opts or {})

    -- Expose configuration variables
    for k,v in pairs(opts) do
        M[k] = v
    end

    -- Do not open startpage when reading from stdin
    vim.api.nvim_create_autocmd('StdinReadPre', {
        pattern = {},
        callback = function()
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
        callback = init_startpage
    })
end

return M
