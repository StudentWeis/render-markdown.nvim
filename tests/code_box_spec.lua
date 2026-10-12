---@module 'luassert'

local util = require('tests.util')

---@param lines string[]
---@param opts? render.md.UserConfig
local function setup(lines, opts)
    local config = vim.tbl_deep_extend('force', {
        debounce = 0,
        code = {
            border = 'box',
            width = 'block',
            sign = false,
            language_icon = false,
            disable_background = true,
            highlight_border = 'Comment',
        },
    }, opts or {})
    util.setup.text(lines, config)
end

describe('code box', function()
    it('frames code without changing buffer text', function()
        local lines = { '```lua', 'x', '', '  y', '```' }
        setup(lines)
        assert.same({}, require('render-markdown.state').validate())
        util.assert_screen({
            '┌─ lua ─┐',
            '│ x     │',
            '│       │',
            '│   y   │',
            '└───────┘',
        })
        assert.same(lines, vim.api.nvim_buf_get_lines(0, 0, -1, false))
        require('render-markdown').disable()
        vim.wait(1000, function()
            local ns = require('render-markdown.core.ui').ns
            return #vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) == 0
        end)
        util.assert_screen(lines)
    end)

    it('supports empty blocks and hidden language labels', function()
        setup({ '```', '```', '', '```lua', 'hi', '```' }, {
            code = { language = false },
        })
        util.assert_screen({
            '┌──┐',
            '└──┘',
            '',
            '┌────┐',
            '│ hi │',
            '└────┘',
        })
    end)

    it('preserves incomplete fences and visible delimiters', function()
        local lines = { '```lua', 'x', '' }
        setup(lines)
        util.assert_screen(lines)
        lines = { '```lua', 'x', '```' }
        setup(lines, { code = { conceal_delimiters = false } })
        util.assert_screen(lines)
        setup(lines, { code = { highlight_border = false } })
        util.assert_screen(lines)
    end)

    it('supports language position, padding and minimum width', function()
        local lines = { '```lua', 'x', '```' }
        setup(lines, {
            code = {
                position = 'right',
                min_width = 16,
                left_pad = 2,
                right_pad = 1,
            },
        })
        util.assert_screen({
            '┌──────── lua ─┐',
            '│   x          │',
            '└──────────────┘',
        })
        setup(lines, { code = { position = 'center', min_width = 16 } })
        util.assert_screen({
            '┌──── lua ─────┐',
            '│ x            │',
            '└──────────────┘',
        })
    end)

    it('handles list and quote prefixes on blank lines', function()
        setup({
            '- item',
            '',
            '  ```',
            '  hi',
            '',
            '  ```',
            '',
            '> ```',
            '> hi',
            '>',
            '> ```',
        }, { bullet = { enabled = false }, quote = { enabled = false } })
        util.assert_screen({
            '- item',
            '',
            '  ┌────┐',
            '  │ hi │',
            '  │    │',
            '  └────┘',
            '',
            '> ┌────┐',
            '> │ hi │',
            '> │    │',
            '> └────┘',
        })
    end)

    it(
        'measures tabs at their rendered column and handles wide characters',
        function()
            setup({ '```', '\t中🙂', 'x', '```' })
            util.assert_screen({
                '┌────────┐',
                '│   中🙂 │',
                '│ x      │',
                '└────────┘',
            })
        end
    )

    it('does not indent long lines or affect their wrapping', function()
        local text = string.rep('x', 90)
        setup({ '```lua', text, '```' })
        util.assert_screen({
            '─ lua ' .. string.rep('─', 74),
            string.rep('x', 80),
            string.rep('─', 80),
        })
        vim.wo.wrap = true
        util.assert_screen({
            '─ lua ' .. string.rep('─', 74),
            string.rep('x', 80),
            string.rep('x', 10),
            string.rep('─', 80),
        })
        vim.wo.wrap = false
    end)

    it('uses available text width for full width boxes', function()
        setup({ '```', 'x', '```' }, { code = { width = 'full' } })
        util.assert_screen({
            '┌' .. string.rep('─', 78) .. '┐',
            '│ x' .. string.rep(' ', 76) .. '│',
            '└' .. string.rep('─', 78) .. '┘',
        })
    end)

    it('reveals only the cursor line through native anti conceal', function()
        setup({ '```lua', 'x', 'y', '```', '', 'text' }, {
            anti_conceal = { enabled = true },
        })
        util.set_row(2)
        util.assert_screen({
            '┌─ lua ─┐',
            'x',
            '│ y     │',
            '└───────┘',
            '',
            'text',
        })
        util.set_row(6)
        util.assert_screen({
            '┌─ lua ─┐',
            '│ x     │',
            '│ y     │',
            '└───────┘',
            '',
            'text',
        })
    end)
    it('keeps borders aligned with margins and section indentation', function()
        setup({ '# Heading', '', '```', '\tx', '```' }, {
            heading = { enabled = false },
            indent = {
                enabled = true,
                per_level = 2,
                skip_level = 0,
                icon = '',
                skip_heading = true,
            },
            code = { left_margin = 2 },
        })
        util.assert_screen({
            '# Heading',
            '',
            '      ┌───────┐',
            '      │     x │',
            '      └───────┘',
        })
    end)

    it('preserves language info and configured surrounding text', function()
        setup({ '```lua title', 'x', '```' }, {
            code = { language_left = '[', language_right = ']' },
        })
        util.assert_screen({
            '┌─ [lua title] ─┐',
            '│ x             │',
            '└───────────────┘',
        })
    end)

    it('accounts for concealed text in injected languages', function()
        setup({ '```html', '<!-- hidden -->', 'x', '```' }, {
            html = { comment = { conceal = true } },
        })
        util.assert_screen({
            '┌─ html ─┐',
            '│        │',
            '│ x      │',
            '└────────┘',
        })
    end)
    it('uses horizontal borders around rendered nested Markdown', function()
        setup({ '```markdown', '**bold**', '```' })
        util.assert_screen({
            '─ markdown ' .. string.rep('─', 69),
            'bold',
            string.rep('─', 80),
        })
        setup({ '```markdown', '**bold**', '```' }, { nested = false })
        util.assert_screen({
            '┌─ markdown ─┐',
            '│ bold       │',
            '└────────────┘',
        })
    end)

    it(
        'fits both splits and restores the box when the narrow split closes',
        function()
            local lines = { '```lua', 'local answer = 42', '```' }
            setup(lines)
            local buf = vim.api.nvim_get_current_buf()
            vim.cmd('vsplit')
            local narrow = vim.api.nvim_get_current_win()
            vim.api.nvim_win_set_width(narrow, 10)
            require('render-markdown').render({ buf = buf })
            vim.wait(0)
            vim.cmd('redraw')
            local function line(win, row)
                local info = vim.fn.getwininfo(win)[1]
                local screen = vim.fn.screenpos(win, row, 1).row
                local result = ''
                for col = info.wincol, info.wincol + vim.api.nvim_win_get_width(win) - 1 do
                    result = result .. vim.fn.screenstring(screen, col)
                end
                return result:gsub('%s+$', '')
            end
            assert.same('─ lua ────', line(narrow, 1))
            assert.same('local answ', line(narrow, 2))
            vim.cmd('wincmd p')
            assert.same(
                '─ lua ────',
                line(vim.api.nvim_get_current_win(), 1)
            )
            assert.same(
                'local answer = 42',
                line(vim.api.nvim_get_current_win(), 2)
            )
            vim.api.nvim_win_close(narrow, true)
            require('render-markdown').render({ buf = buf })
            vim.wait(0)
            util.assert_screen({
                '┌─ lua ─────────────┐',
                '│ local answer = 42 │',
                '└───────────────────┘',
            })
        end
    )
    it('does not scroll a full width empty line under the cursor', function()
        setup({ '```', '', '```' }, { code = { width = 'full' } })
        util.set_row(2)
        util.assert_screen({
            '┌' .. string.rep('─', 78) .. '┐',
            '│' .. string.rep(' ', 78) .. '│',
            '└' .. string.rep('─', 78) .. '┘',
        })
        assert.same(0, vim.fn.winsaveview().leftcol)
    end)
end)
