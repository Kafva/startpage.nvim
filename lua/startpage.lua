M = {}

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

-- draw the graphics into the screen center
local function center_align(tbl)
    vim.validate({
        tbl = { tbl, 'table' },
    })
    local function fill_sizes(lines)
        local fills = {}
        for _, line in pairs(lines) do
            table.insert(fills, math.floor((vim.o.columns - vim.api.nvim_strwidth(line)) / 2))
        end
        return fills
    end

    local centered_lines = {}
    local fills = fill_sizes(tbl)

    for i = 1, #tbl do
        local fill_line = (' '):rep(fills[i]) .. tbl[i]
        table.insert(centered_lines, fill_line)
    end

    return centered_lines
end

function M.setup()
    vim.api.nvim_create_autocmd('StdinReadPre', {
      callback = function()
        vim.g.read_from_stdin = 1
      end,
    })

    vim.api.nvim_create_autocmd("VimEnter", {
        callback = function ()
            if vim.g.read_from_stdin == 1 then
                return
            end
            vim.api.nvim_buf_set_lines(0, 0, -1, false, center_align({
                "",
                version_string(),
                "",
                "Empty buffer: e",
                "Insert mode: i",
                "Quit: q",
                "",
            }))
            vim.bo.modifiable = false
            vim.bo.modified = false
        end
    })
end

return M
