local _, ns = ...

-- Reagents sold by vendors. Their cost is what you last paid a vendor (Market
-- King notes merchant prices when you open a vendor), or four times what the
-- vendor buys them back for until you've seen one.
ns.VENDOR_ITEMS = {
    -- thread, flux, coal
    [2320] = true, [2321] = true, [4291] = true, [8343] = true, [14341] = true,
    [2880] = true, [3466] = true, [3857] = true,
    -- dyes and bleach
    [2324] = true, [2325] = true, [2604] = true, [2605] = true, [4340] = true,
    [4341] = true, [4342] = true, [6260] = true, [6261] = true, [10290] = true,
    -- vials
    [3371] = true, [3372] = true, [8925] = true, [18256] = true,
    -- cooking
    [159] = true, [1179] = true, [2596] = true, [2665] = true, [2678] = true,
    [2692] = true, [3713] = true, [4289] = true, [30817] = true,
    -- engineering and enchanting
    [4399] = true, [4400] = true, [10647] = true, [10648] = true, [6217] = true,
    [4470] = true, [11291] = true,
    -- poisons and misc
    [2928] = true, [8923] = true, [8924] = true, [5173] = true,
}
