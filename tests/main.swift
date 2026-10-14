// Self-check for Core.swift; run via ./test.sh.
import AppKit
import PDFKit

func check(_ ok: Bool, _ what: String) {
    if !ok {
        print("FAIL: \(what)")
        exit(1)
    }
}

// page range text
check(pageRangeText([0, 1, 2, 3, 4, 5, 11, 12, 13]) == "1-6, 12-14", "range text")
check(pageRangeText([4]) == "5", "single page")
check(pageRangeText([]) == "", "empty selection")

// booklet order: 4 pages -> front [1|4], back [3|2]
let sides = { (n: Int) in bookletSides(pageCount: n).map { [$0.0, $0.1] } }
check(sides(4) == [[0, 3], [2, 1]], "4-page imposition")
check(sides(6) == [[0, nil], [nil, 1], [2, 5], [4, 3]], "6 pages padded to 8")

// end to end: 6 numbered A4 pages -> 2 sheets (4 sides) of A4 landscape
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let src = PDFDocument()
for n in 1...6 {
    let image = NSImage(size: NSSize(width: 595, height: 842), flipped: false) { rect in
        NSColor.white.setFill()
        rect.fill()
        NSString(string: "\(n)").draw(
            at: NSPoint(x: 200, y: 300), withAttributes: [.font: NSFont.systemFont(ofSize: 300)])
        return true
    }
    src.insert(PDFPage(image: image)!, at: src.pageCount)
}
let bookletURL = dir.appendingPathComponent("booklet.pdf")
try! makeBooklet(src, to: bookletURL)
let booklet = PDFDocument(url: bookletURL)!
check(booklet.pageCount == 4, "booklet side count")
let box = booklet.page(at: 0)!.bounds(for: .mediaBox)
check(box.width == 842 && box.height == 595, "booklet sheet is A4 landscape")

let extracted = extractPages(src, indices: [1, 2])
check(extracted.pageCount == 2, "extract count")
try! write(extracted, to: dir.appendingPathComponent("extract.pdf"))
let merged = try! mergeFiles([bookletURL, dir.appendingPathComponent("extract.pdf")])
check(merged.pageCount == 6, "merge count")

print("all checks passed; sample output in \(dir.path)")
