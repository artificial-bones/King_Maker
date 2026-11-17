local _, KM = ...
local ns = KM.Module("Econ")

-- Econ's price and supply graphs. The chart itself moved into the shared UI kit in King Maker 2.6 (UI.Chart in
-- Core\Chart.lua, the same :Draw(spec)), so the Farming Ledger and anything else can draw the same way; this keeps
-- ns.CreateGraph working for Econ\Item.lua and any caller that still uses it.
--
--   local g = ns.CreateGraph(parent, width, height)   -- g.frame to anchor, g:Draw(spec) as before

function ns.CreateGraph(parent, w, h) return KM.UI.Chart(parent, w, h) end
