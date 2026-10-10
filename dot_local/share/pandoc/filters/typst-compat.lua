function Math(math)
    if FORMAT == "typst" then
        math.text = math.text:gsub("{\\rm%s+([^{}]+)}", "{\\mathrm{%1}}")
        return math
    end
end

function Cite(citation)
    if FORMAT == "typst" then
        return pandoc.Span(citation.content)
    end
end

function Div(block)
    if FORMAT ~= "typst" then
        return
    end
    if block.classes:includes("csl-entry") then
        block.content:insert(pandoc.RawBlock("typst", "<" .. block.identifier .. ">"))
        return block.content
    elseif block.identifier == "refs" then
        return block.content
    end
end
