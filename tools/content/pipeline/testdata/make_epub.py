"""Builds a tiny made-up EPUB for the text tests: front matter, three chapters and a Notes section.
The spine order differs from the manifest order, so the reading order is really tested."""

import zipfile

WORDS = ("Attention is a narrow door and every task that walks through it must wait its turn while the others "
         "stand outside and the waiting is the cost that nobody sees until the work is measured with care ")


def paragraph(n, words=110):
    text = (WORDS * 4).split()[:words]
    return f"Paragraph {n} says that " + " ".join(text) + "."


def chapter(number, title):
    body = "".join(f"<p>{paragraph(f'{number}.{i}')}</p>" for i in range(1, 6))
    note = '<p>Busy people overrate their work.<a epub:type="noteref" href="notes.xhtml#n1">1</a><sup>2</sup></p>'
    return (f'<html xmlns:epub="http://www.idpf.org/2007/ops"><head><title>x</title><style>p {{}}</style></head>'
            f"<body><h2>Chapter {number}</h2><h3>{title}</h3>{body}{note}<script>alert(1)</script></body></html>")


def make_epub(path):
    files = {
        "front.xhtml": "<html><body><h1>THE BUSY MIND</h1><p>Copyright notice for a made-up test book.</p>"
                       "<p>Contents: one, two, three.</p></body></html>",
        "c1.xhtml": chapter("One", "The door"),
        "c2.xhtml": chapter("Two", "The queue"),
        "c3.xhtml": chapter("Three", "The bill"),
        "notes.xhtml": '<html><body><h2>Notes</h2><p id="n1">1. A note that must not be read.</p></body></html>',
    }
    manifest = "".join(f'<item id="{name[:-6]}" href="{name}" media-type="application/xhtml+xml"/>'
                       for name in ("notes.xhtml", "c3.xhtml", "c1.xhtml", "front.xhtml", "c2.xhtml"))
    spine = "".join(f'<itemref idref="{i}"/>' for i in ("front", "c1", "c2", "c3", "notes"))
    opf = ('<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
           '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>The Busy Mind</dc:title>'
           '<dc:creator>Test Author</dc:creator><dc:language>en</dc:language></metadata>'
           f"<manifest>{manifest}</manifest><spine>{spine}</spine></package>")
    with zipfile.ZipFile(path, "w") as book:
        book.writestr("mimetype", "application/epub+zip")
        book.writestr("META-INF/container.xml",
                      '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
                      'version="1.0"><rootfiles><rootfile full-path="OEBPS/content.opf" '
                      'media-type="application/oebps-package+xml"/></rootfiles></container>')
        book.writestr("OEBPS/content.opf", opf)
        for name, html in files.items():
            book.writestr("OEBPS/" + name, html)
    return path
