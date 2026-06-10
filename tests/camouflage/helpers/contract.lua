-- Test helper: assert that parser output satisfies the engine's coordinate
-- contract — start_index/end_index are 0-based byte offsets into the
-- '\n'-joined buffer content, end-exclusive, buffer-global; line_number is the
-- 0-based count of newlines preceding start_index.
--
-- Asserting against raw content slices means this helper needs no per-parser
-- knowledge and catches a convention regression anywhere (parser OR a future
-- core/treesitter change). A 1-based emitter shows up as a visibly shifted
-- slice in the failure message.

local assert = require('luassert')

local M = {}

---@param content string The exact content the parser was given
---@param variables table[] Parser output (ParsedVariable[])
function M.assert_offsets(content, variables)
  for i, var in ipairs(variables) do
    -- Multiline values span line boundaries with their own per-line geometry;
    -- the single-slice invariant does not apply to them.
    if not var.is_multiline then
      local slice = content:sub(var.start_index + 1, var.end_index)
      assert.are.equal(
        var.value,
        slice,
        string.format(
          'variable #%d (key=%s): content[%d, %d) = %q but value = %q '
            .. '— 0-based end-exclusive byte-offset contract violated',
          i,
          tostring(var.key),
          var.start_index,
          var.end_index,
          slice,
          var.value
        )
      )

      local _, newlines = content:sub(1, var.start_index):gsub('\n', '')
      assert.are.equal(
        newlines,
        var.line_number,
        string.format(
          'variable #%d (key=%s): line_number = %s but %d newline(s) precede start_index %d',
          i,
          tostring(var.key),
          tostring(var.line_number),
          newlines,
          var.start_index
        )
      )
    end
  end
end

return M
