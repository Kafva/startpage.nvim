local M = {}

local config = require('startpage.config')

local startpage_stdin_read = false
local startpage_autocmd_ids = {}
local startpage_ns_id
local startpage_buf
local startpage_win
local startpage_width
local startpage_height

---@return string
local function version_string()
    local version = vim.version()
    local version_number = version.major
        .. '.'
        .. version.minor
        .. '.'
        .. version.patch

    local version_build = (
        type(version.build) == 'string'
        and version.build ~= 'v' .. version_number
    )
            and '-' .. version.build
        or ''
    return 'Nvim-'
        .. version_number
        .. version_build
        .. ' '
        .. _VERSION
        .. (jit and ' (jit)' or '')
end

---@param line string
---@return string
local function get_center_spacing(line)
    local linewidth = vim.api.nvim_strwidth(line)
    local leading_spacing = math.floor((startpage_width - linewidth) / 2)
    local spaces = string.rep(' ', leading_spacing)
    return spaces
end

local function center_cursor()
    if startpage_width <= 2 or startpage_height <= 2 then
        return
    end

    local linenr = math.floor(startpage_height / 2)
    vim.api.nvim_win_set_cursor(
        startpage_win,
        { linenr, math.floor(startpage_width / 2) }
    )
end

---@param lines table<string>
---@param spacing string
---@return table<string>,number
local function vertical_align(lines, spacing)
    local height = startpage_height

    local top_offset = math.floor((height - #lines) / 2)
    local bottom_spacing = height - top_offset - #lines
    local centered_lines = lines

    -- Top spacing
    for _ = 1, top_offset do
        table.insert(centered_lines, 1, spacing)
    end

    -- Bottom spacing
    for _ = 1, bottom_spacing do
        table.insert(centered_lines, spacing)
    end

    return centered_lines, top_offset
end

---@param count number
---@return table
local function get_oldfiles(count)
    local _, devicons = pcall(require, 'nvim-web-devicons')

    local out = {}
    local cwd = vim.fn.getcwd() .. '/'

    for _, f in pairs(vim.v.oldfiles) do
        -- Only list files that exist under the current cwd
        if vim.fn.filereadable(f) ~= 1 or not vim.startswith(f, cwd) then
            goto continue
        end

        local path = f:sub(#cwd + 1)

        -- Skip **/.git/**
        if path:find('.git/', 0, true) ~= nil then
            goto continue
        end

        local filename = vim.fs.basename(path)
        local splits = vim.split(path, '.', { plain = true, trimempty = true })
        local ext = #splits >= 1 and splits[#splits] or ''
        local icon
        local hl_group

        if devicons then
            icon, hl_group = devicons.get_icon(filename, ext, {})
        end

        table.insert(out, {
            path = path,
            icon = icon or config.default_icon,
            hl_group = hl_group,
        })

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
    local filepath =
        vim.trim(line:gsub('[^\32-\126\196\197\214\228\229\246]', ''))

    if vim.fn.filereadable(filepath) ~= 1 then
        return
    end

    vim.cmd('edit ' .. filepath)
end

local function clear_autocmds()
    for _, id in ipairs(startpage_autocmd_ids) do
        -- Ignore errors if buffer has already been deleted
        _ = pcall(vim.api.nvim_del_autocmd, id)
    end
    startpage_autocmd_ids = {}
end

local function deinit_mappings()
    local mapped_keys = { 'e', 'q', '<CR>', unpack(config.passed_keys) }
    for _, key in pairs(mapped_keys) do
        vim.keymap.del('n', key, { buffer = startpage_buf })
    end
    startpage_buf = nil
end

-- Reset the startpage buffer to a regular empty buffer
local function clear_startpage()
    -- stylua: ignore start
    vim.api.nvim_set_option_value('modifiable', true, { buf = startpage_buf })
    vim.api.nvim_buf_set_lines(startpage_buf, 0, -1, false, {''})
    vim.api.nvim_buf_clear_namespace(startpage_buf, startpage_ns_id, 0, -1)
    -- stylua: ignore end
    deinit_mappings()
    clear_autocmds()
end

local function init_mappings()
    -- stylua: ignore start
    for _,k in pairs(config.passed_keys) do
        vim.keymap.set('n', k, function ()
            clear_startpage()
            if k == 'i' or k == 'o' then
                vim.cmd('startinsert')
            else
                vim.cmd('normal! ' .. k)
            end
        end, { buffer = startpage_buf })
    end

    vim.keymap.set('n', 'e', clear_startpage, {
        buffer = startpage_buf,
        desc = "Clear startpage into an empty buffer"
    })

    vim.keymap.set('n', 'q', function ()
        vim.cmd 'qa!'
    end, { buffer = startpage_buf, desc = "Quit out of startpage" })

    vim.keymap.set('n', '<CR>', open_under_cursor, {
        buffer = startpage_buf,
        desc = "Go to file under cursor"
    })
    -- stylua: ignore end
end

---@param oldfiles table
---@param spacing string
local function get_oldfiles_lines(oldfiles, spacing)
    local oldfiles_lines = {}

    if #oldfiles >= 1 then
        for _, oldfile in pairs(oldfiles) do
            local icon = oldfile.icon or ' '
            local line = spacing .. icon .. string.rep(' ', 2) .. oldfile.path
            table.insert(oldfiles_lines, line)
        end
    end

    return oldfiles_lines
end

local function draw_startpage()
    vim.api.nvim_set_option_value('modifiable', true, { buf = startpage_buf })

    -- Clear everything if we are re-drawing
    vim.api.nvim_buf_set_lines(startpage_buf, 0, -1, false, {})

    -- Make the version string centered and align everything else
    -- to fit with it.
    local version = version_string()
    local spacing = get_center_spacing(version)
    local header = {
        spacing .. version,
        spacing .. ' ',
    }
    local lines = {}
    local oldfiles = {}
    local show_oldfiles = startpage_width >= 20 and startpage_height >= 10

    if show_oldfiles then
        oldfiles = get_oldfiles(config.oldfiles_count)
        local oldfiles_lines = get_oldfiles_lines(oldfiles, spacing)
        local subheader = #oldfiles >= 1
                and (spacing .. config.recent_files_header)
            or (spacing .. 'No recent files')
        table.insert(header, subheader)
        table.insert(header, spacing .. ' ')
        lines = vim.iter({ header, oldfiles_lines }):flatten():totable()
    else
        lines = header
    end

    local aligned_lines, top_offset = vertical_align(lines, spacing .. ' ')

    vim.api.nvim_buf_set_lines(startpage_buf, 0, -1, false, aligned_lines)

    if show_oldfiles then
        -- Set highlighting for icons
        for i, oldfile in ipairs(oldfiles) do
            if oldfile.hl_group == nil then
                goto continue
            end

            local linenr = top_offset + #header + (i - 1)
            local col_start = #spacing
            local col_end = #spacing + 1
            vim.hl.range(
                startpage_buf,
                startpage_ns_id,
                oldfile.hl_group,
                { linenr, col_start },
                { linenr, col_end }
            )
            ::continue::
        end
    end

    -- Done
    vim.api.nvim_set_option_value('modifiable', false, { buf = startpage_buf })
    vim.api.nvim_set_option_value('modified', false, { buf = startpage_buf })
end

local function register_winresized_autocmd()
    assert(startpage_buf, 'No startpage buffer set')
    local id = vim.api.nvim_create_autocmd('WinResized', {
        buffer = startpage_buf,
        callback = function()
            local width = vim.api.nvim_win_get_width(startpage_win)
            local height = vim.api.nvim_win_get_height(startpage_win)
            local unchanged_dims = width == startpage_width
                and height == startpage_height
            if unchanged_dims then
                return
            end

            startpage_width = width
            startpage_height = height
            draw_startpage()
            center_cursor()
        end,
    })
    table.insert(startpage_autocmd_ids, id)
end

function M.setup(user_opts)
    local id
    config.setup(user_opts)

    -- Do not open startpage when reading from stdin
    id = vim.api.nvim_create_autocmd('StdinReadPre', {
        pattern = {},
        callback = function()
            startpage_stdin_read = true
        end,
    })
    table.insert(startpage_autocmd_ids, id)

    -- Close the startpage as soon as we leave it, this is needed
    -- to automatically close the page when using
    --  :e <filepath>
    --  :FzfLua files
    -- etc.
    -- Keymaps and highlights are buffer local so they do not need to be
    -- cleared here.
    id = vim.api.nvim_create_autocmd('BufLeave', {
        pattern = { '' },
        callback = function()
            if startpage_buf ~= vim.api.nvim_get_current_buf() then
                return
            end

            -- Loading the new buffer can be buggy if we do not use defer
            -- here, the filetype of the new buffer may not load properly.
            vim.defer_fn(function()
                clear_autocmds()
                -- Ignore errors if buffer has already been closed
                _ = pcall(vim.api.nvim_buf_delete, startpage_buf, {})
                startpage_buf = nil
                startpage_win = nil
                startpage_width = nil
                startpage_height = nil
            end, 100)
        end,
    })
    table.insert(startpage_autocmd_ids, id)

    id = vim.api.nvim_create_autocmd('UIEnter', {
        pattern = {},
        callback = function()
            if
                startpage_stdin_read
                or vim.fn.expand('%') ~= ''
                or vim.o.ft == 'netrw'
            then
                clear_autocmds()
                return
            end
            startpage_win = vim.api.nvim_get_current_win()
            startpage_buf = vim.api.nvim_get_current_buf()
            startpage_ns_id = vim.api.nvim_create_namespace('startpage')

            startpage_width = vim.api.nvim_win_get_width(startpage_win)
            startpage_height = vim.api.nvim_win_get_height(startpage_win)

            register_winresized_autocmd()
            draw_startpage()
            center_cursor()

            init_mappings()
        end,
    })
    table.insert(startpage_autocmd_ids, id)
end

return M
