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

---Fetch a list of all recently opened files in the current directory
---@return table<string>
local function mru_list()
    local files = {}
    local cwd = vim.fn.getcwd() .. "/"
    for _,f in pairs(vim.v.oldfiles) do
        if vim.fn.filereadable(f) == 1 and vim.startswith(f, cwd) then
            local entry = f:sub(#cwd + 1)

            -- Skip .git/COMMIT_EDITMSG
            if not vim.startswith(entry, '.git') then
                table.insert(files, entry)
            end
        end
    end
    return files
end

---@param lines table<string>
---@return table<string>
local function center_align(lines)
    local centered_lines = {}
    local win = vim.api.nvim_get_current_win()
    local width = vim.api.nvim_win_get_width(win)
    local height = vim.api.nvim_win_get_height(win)

    local top_offset = height/2 - 10
    local bottom_height = height - top_offset - #lines

    -- Top spacing
    for _ = 1,top_offset do
        table.insert(centered_lines, "")
    end

    for _,line in pairs(lines) do
        local space_cnt = math.floor((width - vim.api.nvim_strwidth(line)) / 2)
        local spaces = string.rep(" ", space_cnt)
        table.insert(centered_lines, spaces .. line)
    end

    -- Bottom spacing
    for _ = 1,bottom_height do
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

            local lines = vim.tbl_flatten({
                {
                    version_string(),
                    "",
                    "  Recent files"
                },
                mru_list(),
            })

            vim.api.nvim_buf_set_lines(0, 0, -1, false, center_align(lines))
            vim.bo.modifiable = false
            vim.bo.modified = false
        end
    })
end

return M
