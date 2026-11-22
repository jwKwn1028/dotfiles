$definitions.typst()$

#import "@local/docstyle:0.1.0": notes
#let planck = symbol("ℎ", ("reduce", "ℏ"))
#let angle = symbol("∠", ("l", "⟨"), ("r", "⟩"))

#show terms: it => it.children.map(child => [
  #strong[#child.term]
  #block(inset: (left: 1.5em))[#child.description]
]).join()

#show: notes.with(
$if(title)$
  title: [$title$],
$endif$
$if(author)$
  author: [$for(author)$$if(author.name)$$author.name$$else$$author$$endif$$sep$; $endfor$],
$endif$
$if(date)$
  date: [$date$],
$endif$
$if(abstract)$
  abstract: [$abstract$],
$endif$
$if(lang)$
  lang: "$lang$",
$endif$
$if(region)$
  region: "$region$",
$endif$
$if(papersize)$
  paper: "$papersize$",
$endif$
$if(fontsize)$
  fontsize: $fontsize$,
$endif$
$if(margin)$
  margin: ($for(margin/pairs)$$margin.key$: $margin.value$,$endfor$),
$endif$
$if(section-numbering)$
  section-numbering: "$section-numbering$",
$endif$
)

$for(header-includes)$
$header-includes$
$endfor$
$for(include-before)$
$include-before$
$endfor$
$if(toc)$
#outline()
$endif$

$body$

$for(include-after)$
$include-after$
$endfor$
