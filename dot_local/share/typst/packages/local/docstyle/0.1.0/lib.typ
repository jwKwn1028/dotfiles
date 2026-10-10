#let accent = rgb("#2b3f8c")
#let body-fonts = ("New Computer Modern Sans", "Noto Sans CJK KR")
#let code-fonts = ("JuliaMono", "NanumGothicCoding")

#let style(body, fontsize: 11pt, lang: "en", region: none) = {
  set text(font: body-fonts, size: fontsize, lang: lang, region: region)
  set par(justify: true)
  show raw: set text(font: code-fonts, ligatures: false, features: (calt: 0))
  show math.equation: set text(font: "New Computer Modern Math")
  show heading: set text(fill: accent)
  show strong: set text(fill: accent)
  show link: set text(fill: accent)
  show figure.caption: set text(size: .9em)
  body
}

#let notes(
  title: none,
  author: "",
  date: none,
  abstract: none,
  paper: "a4",
  margin: .75in,
  fontsize: 11pt,
  lang: "en",
  region: none,
  section-numbering: none,
  equation-numbering: none,
  body,
) = {
  set document(title: title, author: if type(author) == str { author } else { () })
  set page(
    paper: paper,
    margin: margin,
    footer: context align(center, text(.8em, counter(page).display("1 / 1", both: true))),
  )
  set heading(numbering: section-numbering)
  set math.equation(numbering: equation-numbering)
  style(fontsize: fontsize, lang: lang, region: region)[
    #if title != none {
      align(center, text(size: 1.8em, weight: "bold", title))
      v(.5em)
    }
    #if author != "" and author != [] { align(center, author) }
    #if date != none { align(center, date) }
    #if abstract != none {
      block(inset: (x: 1em))[*Abstract.* #abstract]
    }
    #body
  ]
}

#let margin-notes = notes.with(
  margin: (left: 2.2cm, right: 5.4cm, top: 2.6cm, bottom: 2.4cm),
)

#let mnote(body, dy: -.35em) = place(
  right,
  dx: 3.6cm,
  dy: dy,
  box(width: 3cm, text(size: .78em, fill: luma(110), body)),
)

#let slides(title: none, author: "", body) = {
  set document(title: title, author: if type(author) == str { author } else { () })
  set page(
    width: 16cm,
    height: 9cm,
    margin: 1cm,
    footer: context align(right, text(.65em, counter(page).display())),
  )
  show heading.where(level: 1): it => {
    pagebreak(weak: true)
    block(below: .8em, text(size: 1.25em, weight: "bold", it.body))
  }
  style(fontsize: 20pt)[
    #set par(justify: false)
    #if title != none {
      align(center + horizon)[
        #text(size: 1.5em, weight: "bold", title)
        #if author != "" { parbreak(); author }
      ]
      pagebreak(weak: true)
    }
    #body
  ]
}
