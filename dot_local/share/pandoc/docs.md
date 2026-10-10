# Pandoc and Typst presets

Desktop machines receive named presets in `~/.local/share/pandoc/defaults/`:

```sh
pandoc --defaults pdf notes.md -o notes.pdf
pandoc --defaults markdown input.md -o notes.md
pandoc --defaults tex notes.md -o notes.tex
pandoc --defaults typst notes.md -o notes.typ
typst compile notes.typ notes.pdf
```

PDF and TeX use XeLaTeX, A4 paper, 11pt New Computer Modern Sans prose,
New Computer Modern Math, JuliaMono code, Noto Sans CJK KR text, and
NanumGothicCoding for Korean code. Both accept `$...$`, `\(...\)`, and
`\[...\]` math, use 0.75-inch margins and colored links, and render citations
when a bibliography is supplied. Missing glyphs fail the LaTeX build. Markdown
export preserves math, citation keys, and metadata, with ATX headings and no
paragraph wrapping. Typst export uses the same font choices, blue headings,
and citeproc references, with compatibility for the installed Pandoc writer.
Use `--from docx` or `--from latex` when importing another format.

The desktop apt manifest provisions Pandoc, TeX Live, latexmk, and Noto fonts;
`packages.fonts.archives` supplies the New Computer Modern faces through
`run_once_after_50`. The PDF header resolves relative to the preset, so it
works from any working directory. Settings and path syntax follow the
[Pandoc guide](https://pandoc.org/MANUAL.html#defaults-files); the font archive
comes from [CTAN](https://ctan.org/pkg/newcomputermodern). The Cargo manifest
provisions the Typst CLI.

Keep input/output filenames, bibliographies, citation styles, and document
filters in each project. Add `--bibliography references.bib` when needed.
Later defaults files override preset variables: put
`variables: {papersize: letter}` in `project.yaml` and pass
`--defaults pdf --defaults project.yaml`. Compile generated TeX with
`latexmk -xelatex notes.tex`.

Native Typst documents can use the installed local package:

```typst
#import "@local/docstyle:0.1.0": notes
#show: notes.with(title: [My Notes], author: "Your Name")

= First topic
$ E = ℏ omega $
```

The package also exports `margin-notes`, `mnote`, and `slides`. For slides,
each level-one heading starts a new 16:9 page. These are reusable native
layouts; existing TeX and Typst projects continue using their own preambles
and imports. Local package lookup follows the
[Typst package convention](https://github.com/typst/packages#local-packages).

`hxp` currently supplies its own Pandoc options; it does not load these presets
automatically.
