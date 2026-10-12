local Base = require('render-markdown.render.base')
local colors = require('render-markdown.core.colors')
local compat = require('render-markdown.lib.compat')
local env = require('render-markdown.lib.env')
local icons = require('render-markdown.lib.icons')
local str = require('render-markdown.lib.str')

---@class render.md.code.Data
---@field info? render.md.Node
---@field language? render.md.Node
---@field language_padding integer
---@field padding integer
---@field body integer
---@field margin integer

---@class render.md.render.Code: render.md.Render
---@field private config render.md.code.Config
---@field private data render.md.code.Data
local Render = setmetatable({}, Base)
Render.__index = Render

---@protected
---@return boolean
function Render:setup()
    self.config = self.context.config.code
    if not self.config.enabled then
        return false
    end
    -- skip single line code block
    if self.node:height() <= 2 then
        return false
    end

    local info = self.node:child('info_string')
    local language = info and info:child('language')

    local widths = self.node:widths()
    local width = vim.fn.max(widths)

    local language_padding = self:offset(self.config.language_pad, width)
    local left = self:offset(self.config.left_pad, width)
    local right = self:offset(self.config.right_pad, width)

    local body = str.width(self.config.language_left)
        + str.width(self.config.language_right)
        + language_padding
        + widths[1]
    body = math.max(body, left + width + right, self.config.min_width)

    self.data = {
        info = info,
        language = language,
        language_padding = language_padding,
        padding = left,
        body = body,
        margin = self:offset(self.config.left_margin, body),
    }

    return self:enabled(self.config.disable)
end

---@private
---@param value integer
---@param used integer
---@return integer
function Render:offset(value, used)
    if value <= 0 then
        return 0
    end
    local result = env.win.percent(self.context.win, value, used)
    if self.node.text:find('\t') then
        -- round to the next multiple of tab
        local tab = env.buf.get(self.context.buf, 'tabstop')
        result = math.ceil(result / tab) * tab
    end
    return result
end

---@private
---@param disable boolean|string[]
---@return boolean
function Render:enabled(disable)
    if type(disable) == 'boolean' then
        return not disable
    else
        local language = self.data.language
        return not language or not vim.tbl_contains(disable, language.text)
    end
end

---@protected
function Render:run()
    local start_row = self.node.start_row
    local end_row = self.node.end_row - 1

    local above = self.node:child('fenced_code_block_delimiter', start_row)
    local below = self.node:child('fenced_code_block_delimiter', end_row)

    if self.config.border == 'box' and compat.has_10 then
        self:box(above, below)
        return
    end

    if self.config.conceal_delimiters then
        self.marks:over(self.config, true, self.data.info, { conceal = '' })
        self.marks:over(self.config, true, above, { conceal = '' })
        self.marks:over(self.config, true, below, { conceal = '' })
    end

    if not self:language(above) then
        self:border(above, self.config.above)
    end
    self:border(below, self.config.below)

    local background = self:enabled(self.config.disable_background)
    if background then
        local inset = self.config.background_inset
        self:background(start_row + inset, end_row - inset)
    end
    self:padding(background)
end

---@private
---@param border_hl? string
---@return render.md.Line
function Render:language_text(border_hl)
    local info, language = self.data.info, self.data.language
    if not self.config.language or not info or not language then
        return self:line()
    end

    local icon, icon_hl = icons.get(language.text)
    if self.config.highlight_language then
        icon_hl = self.config.highlight_language
    end
    self:sign(self.config, self.config.sign, icon, icon_hl)

    local language_hl = { icon_hl or self.config.highlight_fallback } ---@type string[]
    local info_hl = { self.config.highlight_info } ---@type string[]
    if border_hl then
        language_hl[#language_hl + 1] = border_hl
        info_hl[#info_hl + 1] = border_hl
    end

    local text = self:line()
    if self.config.language_icon and icon then
        text:text(icon .. ' ', language_hl)
    end
    if self.config.language_name then
        text:text(language.text, language_hl)
    end
    if self.config.language_info then
        local offset = info.start_col
        text = self:line()
            :text(info.text:sub(1, language.start_col - offset), info_hl)
            :extend(text)
            :text(info.text:sub(language.end_col - offset + 1), info_hl)
    end
    if text:empty() then
        return self:line()
    end

    local surround = border_hl and colors.bg_as_fg(border_hl)
    return self:line()
        :text(self.config.language_left, surround)
        :extend(text)
        :text(self.config.language_right, surround)
end

---@private
---@param delim? render.md.Node
---@return boolean
function Render:language(delim)
    if not delim then
        return false
    end
    local border_hl = self.config.highlight_border or nil
    local body = self:language_text(border_hl)
    if body:empty() then
        return false
    end
    if border_hl then
        border_hl = colors.bg_as_fg(border_hl)
    end
    local padding = self.data.language_padding

    -- code blocks can pick up varying amounts of leading white space
    -- this is lumped into the delimiter node and needs to be handled
    local prefix = str.spaces('start', delim.text)
    local suffix = 0
    -- space within block after accounting for white space and padding
    local width = self.data.body - delim.start_col
    local extra = width - prefix - body:width() - suffix - padding ---@type integer
    if self.config.position == 'left' then
        prefix = prefix + padding
        suffix = suffix + extra
    elseif self.config.position == 'right' then
        prefix = prefix + extra
        suffix = suffix + padding
    else
        prefix = prefix + padding + math.floor(extra / 2)
        suffix = suffix + math.ceil(extra / 2)
    end
    if self.config.width == 'full' then
        suffix = suffix + vim.o.columns
    end

    local border = border_hl and self.config.language_border or ' '
    local line = self:line()
        :rep(border, prefix, border_hl)
        :extend(body)
        :rep(border, suffix, border_hl)
    return self.marks:start(self.config, 'code_language', delim, {
        virt_text = line:get(),
        virt_text_pos = 'overlay',
    })
end

---@private
---@param above? render.md.Node
---@param below? render.md.Node
function Render:box(above, below)
    -- Incomplete or visible fences remain source, including their body.
    if not above or not below or not self.config.conceal_delimiters then
        return
    end
    local highlight = self.config.highlight_border
    if not highlight then
        return
    end
    local buf = self.context.buf
    local lines = vim.api.nvim_buf_get_lines(
        buf,
        above.start_row,
        below.start_row + 1,
        false
    )
    local col = above:col()
    local prefix = lines[1]:sub(1, col)
    if below:col() ~= col or lines[#lines]:sub(1, col) ~= prefix then
        return
    end
    local indent = str.width(prefix)
    local margin = self.data.margin
    local left = 1 + self.data.padding
    local right = 1 + self:offset(self.config.right_pad, self.data.body)
    local start = indent + self:indent():size() + margin + 1 + left
    local rows = {} ---@type { col: integer, pad: integer, width: integer }[]
    local width = 0
    for i = 2, #lines - 1 do
        local line = lines[i]
        local offset = math.min(col, #line)
        -- A container's blank line may omit some or all trailing indentation.
        if line:sub(1, offset) ~= prefix:sub(1, offset) then
            return
        end
        local row = above.start_row + i - 1
        local text = line:sub(offset + 1)
        local body = {
            text = text,
            start_row = row,
            start_col = offset,
            end_row = row,
            end_col = #line,
        }
        local size = vim.fn.strdisplaywidth(text, start)
            + self.context.inline:width(body)
            - self.context.conceal:get(body)
        rows[#rows + 1] = {
            col = offset,
            pad = indent - str.width(line:sub(1, offset)),
            width = size,
        }
        width = math.max(width, size)
    end

    -- Buffer extmarks are shared by windows. Fit the narrowest visible split.
    local available = env.win.width(self.context.win)
    for _, win in ipairs(env.buf.wins(buf)) do
        if
            vim.api.nvim_win_get_tabpage(win)
            == vim.api.nvim_get_current_tabpage()
        then
            available = math.min(available, env.win.width(win))
        end
    end
    available = available - indent - self:indent():size() - margin
    if available < 2 then
        return
    end
    local label = self:language_text()
    if not label:empty() then
        label = self:line():pad(1):extend(label):pad(1)
    end
    local language_pad = math.max(1, self.data.language_padding)
    width = math.max(
        width + left + right + 2,
        label:width() + language_pad * 2 + 2,
        self.config.min_width
    )
    -- Nested Markdown can add virtual lines or render its own code boxes.
    local language = self.data.language
    local nested = require('render-markdown.state').nested
        and language
        and vim.treesitter.language.get_lang(language.text) == 'markdown'
    local sides = width <= available and not nested
    width = sides and self.config.width == 'block' and width or available
    local inner = width - (sides and 2 or 0)
    label = label:sub(1, math.max(0, inner - language_pad * 2))
    local extra = inner - label:width()
    local leading = math.min(language_pad, extra)
    if label:empty() then
        leading = 0
    elseif self.config.position == 'right' then
        leading = extra - leading
    elseif self.config.position == 'center' then
        leading = math.floor(extra / 2)
    end
    local top = self:line()
        :pad(margin)
        :text(sides and '┌' or '', highlight)
        :rep('─', leading, highlight)
        :extend(label)
        :rep('─', extra - leading, highlight)
        :text(sides and '┐' or '', highlight)
    local bottom = self:line()
        :pad(margin)
        :text(sides and '└' or '', highlight)
        :rep('─', inner, highlight)
        :text(sides and '┘' or '', highlight)
    self:box_mark(
        above.start_row,
        col,
        top,
        #lines[1],
        label:empty() and 'code_border' or 'code_language'
    )
    self:box_mark(below.start_row, col, bottom, #lines[#lines])
    -- Long lines retain their original positions and wrapping behavior.
    if not sides then
        return
    end
    local background = self:enabled(self.config.disable_background)
    for i, row in ipairs(rows) do
        local line = lines[i + 1]
        local index = above.start_row + i
        local inset = self.config.background_inset
        local hl = background
                and i >= inset
                and #lines - i - 1 >= inset
                and self.config.highlight
            or nil
        local before = self:line()
            :pad(row.pad + margin)
            :text('│', highlight)
            :pad(left, hl)
        local after =
            self:line():pad(inner - left - row.width, hl):text('│', highlight)
        if row.col == #line then
            self:box_mark(index, row.col, before:extend(after), #line)
        else
            self:box_mark(index, row.col, before)
            self:box_mark(index, #line, after)
            if hl then
                self.marks:add(self.config, 'code_background', index, row.col, {
                    end_col = #line,
                    hl_group = hl,
                    priority = self.config.priority,
                })
            end
        end
    end
end

---@private
---@param row integer
---@param col integer
---@param line render.md.Line
---@param end_col? integer
---@param element? render.md.Element
function Render:box_mark(row, col, line, end_col, element)
    self.marks:add(self.config, element or 'code_border', row, col, {
        virt_text = line:get(),
        virt_text_pos = end_col and 'overlay' or 'inline',
        end_col = end_col,
        conceal = end_col and '' or nil,
    })
end

---@private
---@param node? render.md.Node
---@param thin string
function Render:border(node, thin)
    local kind = self.config.border
    if kind == 'none' or not node then
        return
    end
    if kind == 'hide' then
        self.marks:over(self.config, true, node, { conceal_lines = '' })
        return
    end
    local highlight = self.config.highlight_border or nil
    if not highlight then
        return
    end
    local icon = (kind == 'thin' or kind == 'box') and thin or ' '
    highlight = icon == ' ' and highlight or colors.bg_as_fg(highlight)
    if not highlight then
        return
    end
    local block = self.config.width == 'block'
    local width = block and self.data.body - node.start_col or vim.o.columns
    self.marks:start(self.config, 'code_border', node, {
        virt_text = { { icon:rep(width), highlight } },
        virt_text_pos = 'overlay',
    })
end

---@private
---@param start_row integer
---@param end_row integer
function Render:background(start_row, end_row)
    local padding = self:line()
    local win_col = 0
    if self.config.width == 'block' then
        padding:pad(vim.o.columns * 2)
        win_col = self.data.margin + self.data.body + self:indent():size()
    end
    local col = self.node.start_col
    for row = start_row, end_row do
        self.marks:add(self.config, 'code_background', row, col, {
            end_row = row + 1,
            priority = self.config.priority,
            hl_group = self.config.highlight,
            hl_eol = true,
        })
        if not padding:empty() and win_col > 0 then
            -- overwrite anything beyond width with padding
            self.marks:add(self.config, 'code_background', row, col, {
                priority = 0,
                virt_text = padding:get(),
                virt_text_win_col = win_col,
            })
        end
    end
end

---@private
---@param background boolean
function Render:padding(background)
    local col = self.node.start_col
    local start_row, end_row = self.node.start_row, self.node.end_row - 1
    local empty = {} ---@type integer[]
    local widths = col == 0 and {} or self.node:widths()
    for i, width in ipairs(widths) do
        if width == 0 then
            empty[#empty + 1] = (start_row + i - 1)
        end
    end
    if #empty == 0 and self.data.margin <= 0 and self.data.padding <= 0 then
        return
    end
    local highlight = background and self.config.highlight or nil
    for row = start_row, end_row do
        local line = self:line()
        if vim.tbl_contains(empty, row) then
            line:pad(col)
        end
        line:pad(self.data.margin)
        if row > start_row and row < end_row then
            line:pad(self.data.padding, highlight)
        end
        if not line:empty() then
            self.marks:add(self.config, false, row, col, {
                priority = 100,
                virt_text = line:get(),
                virt_text_pos = 'inline',
            })
        end
    end
end

return Render
