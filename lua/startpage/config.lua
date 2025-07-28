---@class StartpageOptions
---@field recent_files_header string
---@field oldfiles_count integer
---@field default_icon string
---@field passed_keys? string[]

local M = {}

---@type StartpageOptions
M.default_opts = {
    recent_files_header = '  Recent files',
    oldfiles_count = 7,
    default_icon = '', -- Must be blankspace or a glyph
    -- The keys in this table will cancel out of the startpage and be sent
    -- as they would normally.
    passed_keys = { 'i', 'o', 'p', 'P' },
}

---@param user_opts StartpageOptions?
function M.setup(user_opts)
    local opts = vim.tbl_deep_extend('force', M.default_opts, user_opts or {})

    -- Expose configuration variables
    for k, v in pairs(opts) do
        M[k] = v
    end
end

return M
