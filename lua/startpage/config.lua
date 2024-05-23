local M = {}

---@class StartpageOptions
---@field enabled? boolean
---@field default_bindings? boolean Enable default bindings

---@type StartpageOptions
M.default_opts = {
    enabled = true,
    default_bindings = true,
}


---@param user_opts StartpageOptions?
function M.setup(user_opts)
    local opts = vim.tbl_deep_extend("force", M.default_opts, user_opts or {})

    if opts and opts.default_bindings then
    end

    -- Expose configuration variables
    for k,v in pairs(opts) do
        M[k] = v
    end

end

return M
