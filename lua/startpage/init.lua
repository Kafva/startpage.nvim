local M = {}

M.default_opts = {
    recent_files_header = '  Recent files',
    oldfiles_count = 7,
    default_icon = '', -- Must be blankspace or a glyph
    -- The keys in this table will cancel out of the startpage and be sent
    -- as they would normally.
    passed_keys = { 'i', 'o', 'p', 'P' },
}

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
    local leading_spacing = math.floor((vim.g.startpage_width - linewidth) / 2)
    local spaces = string.rep(' ', leading_spacing)
    return spaces
end

local function center_cursor()
    local linenr = math.floor(vim.g.startpage_height / 2)
    vim.api.nvim_win_set_cursor(
        vim.g.startpage_win,
        { linenr, math.floor(vim.g.startpage_width / 2) }
    )
end

---@param lines table<string>
---@param spacing string
---@return table<string>,number
local function vertical_align(lines, spacing)
    local height = vim.g.startpage_height

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

        table.insert(
            out,
            { path = path, icon = icon or M.default_icon, hl_group = hl_group }
        )

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

local function deinit_mappings()
    local mapped_keys = { 'e', 'q', '<CR>', unpack(M.passed_keys) }
    for _, key in pairs(mapped_keys) do
        vim.keymap.del('n', key, { buffer = vim.g.startpage_buf })
    end
    vim.g.startpage_buf = nil
end

-- Reset the startpage buffer to a regular empty buffer
local function clear_startpage()
    -- stylua: ignore start
    vim.api.nvim_set_option_value('modifiable', true, { buf = vim.g.startpage_buf })
    vim.api.nvim_buf_set_lines(vim.g.startpage_buf, 0, -1, false, {''})
    vim.api.nvim_buf_clear_namespace(vim.g.startpage_buf, vim.g.startpage_ns_id, 0, -1)
    -- stylua: ignore end
    deinit_mappings()
end

local function init_mappings()
    -- stylua: ignore start
    for _,k in pairs(M.passed_keys) do
        vim.keymap.set('n', k, function ()
            clear_startpage()
            if k == 'i' or k == 'o' then
                vim.cmd('startinsert')
            else
                vim.cmd('normal! ' .. k)
            end
        end, { buffer = vim.g.startpage_buf })
    end

    vim.keymap.set('n', 'e', clear_startpage, {
        buffer = vim.g.startpage_buf,
        desc = "Clear startpage into an empty buffer"
    })

    vim.keymap.set('n', 'q', function ()
        vim.cmd 'qa!'
    end, { buffer = vim.g.startpage_buf, desc = "Quit out of startpage" })

    vim.keymap.set('n', '<CR>', open_under_cursor, {
        buffer = vim.g.startpage_buf,
        desc = "Go to file under cursor"
    })
    -- stylua: ignore end
end

-- Close the startpage buffer, keymaps and highlights are buffer local so
-- they do not need to be cleared here.
local function close_startpage()
    if
        vim.g.startpage_buf == nil
        or not vim.api.nvim_buf_is_valid(vim.g.startpage_buf)
        or vim.g.startpage_win == nil
        or not vim.api.nvim_win_is_valid(vim.g.startpage_win)
    then
        return
    end

    vim.api.nvim_buf_delete(vim.g.startpage_buf, {})
    vim.g.startpage_buf = nil
    vim.g.startpage_win = nil
    vim.g.startpage_width = nil
    vim.g.startpage_height = nil
end

local function draw_startpage()
    vim.api.nvim_set_option_value(
        'modifiable',
        true,
        { buf = vim.g.startpage_buf }
    )

    -- Clear everything if we are re-drawing
    vim.api.nvim_buf_set_lines(vim.g.startpage_buf, 0, -1, false, {})

    -- Make the version string centered and align everything else
    -- to fit with it.
    local version = version_string()
    local spacing = get_center_spacing(version)

    local oldfiles = get_oldfiles(M.oldfiles_count)
    local oldfiles_lines = {}
    local header = {
        spacing .. version,
        spacing .. ' ',
        #oldfiles >= 1 and (spacing .. M.recent_files_header)
            or (spacing .. 'No recent files'),
        spacing .. ' ',
    }

    if #oldfiles >= 1 then
        for _, oldfile in pairs(oldfiles) do
            local icon = oldfile.icon or ' '
            local line = spacing .. icon .. string.rep(' ', 2) .. oldfile.path
            table.insert(oldfiles_lines, line)
        end
    end

    local content_lines =
        vim.iter({ header, oldfiles_lines }):flatten():totable()

    local aligned_lines, top_offset =
        vertical_align(content_lines, spacing .. ' ')

    vim.api.nvim_buf_set_lines(vim.g.startpage_buf, 0, -1, false, aligned_lines)

    -- Set highlighting for icons
    for i, oldfile in ipairs(oldfiles) do
        if oldfile.hl_group == nil then
            goto continue
        end

        local linenr = top_offset + #header + (i - 1)
        local col_start = #spacing
        local col_end = #spacing + 1
        vim.api.nvim_buf_add_highlight(
            vim.g.startpage_buf,
            vim.g.startpage_ns_id,
            oldfile.hl_group,
            linenr,
            col_start,
            col_end
        )
        ::continue::
    end

    -- Done
    vim.api.nvim_set_option_value(
        'modifiable',
        false,
        { buf = vim.g.startpage_buf }
    )
    vim.api.nvim_set_option_value(
        'modified',
        false,
        { buf = vim.g.startpage_buf }
    )
end

local function register_winresized_autocmd()
    assert(vim.g.startpage_buf, 'No startpage buffer set')
    vim.api.nvim_create_autocmd('WinResized', {
        buffer = vim.g.startpage_buf,
        callback = function()
            local modified = vim.api.nvim_get_option_value(
                'modified',
                { buf = vim.g.startpage_buf }
            )
            local width = vim.api.nvim_win_get_width(vim.g.startpage_win)
            local height = vim.api.nvim_win_get_height(vim.g.startpage_win)
            local unchanged_dims = width == vim.g.startpage_width
                and height == vim.g.startpage_height
            if unchanged_dims or modified then
                return
            end

            vim.g.startpage_width = width
            vim.g.startpage_height = height
            draw_startpage()
            center_cursor()
        end,
    })
end

function M.setup(user_opts)
    local opts = vim.tbl_deep_extend('force', M.default_opts, user_opts or {})

    -- Expose configuration variables
    for k, v in pairs(opts) do
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
        callback = function()
            if vim.g.startpage_buf ~= vim.api.nvim_get_current_buf() then
                close_startpage()
            end
        end,
    })

    vim.api.nvim_create_autocmd('UIEnter', {
        pattern = {},
        callback = function()
            if
                vim.g.stdin_read
                or vim.fn.expand('%') ~= ''
                or vim.o.ft == 'netrw'
            then
                return
            end
            vim.g.startpage_win = vim.api.nvim_get_current_win()
            vim.g.startpage_buf = vim.api.nvim_get_current_buf()
            vim.g.startpage_ns_id = vim.api.nvim_create_namespace('startpage')

            vim.g.startpage_width =
                vim.api.nvim_win_get_width(vim.g.startpage_win)
            vim.g.startpage_height =
                vim.api.nvim_win_get_height(vim.g.startpage_win)

            register_winresized_autocmd()
            draw_startpage()
            center_cursor()

            init_mappings()
        end,
    })
end

return M
