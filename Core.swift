import AppKit
import PDFKit

enum BinderError: LocalizedError {
    case unreadable(URL)
    case noSelection
    case writeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url): return "Bookbinder cannot read \(url.lastPathComponent)."
        case .noSelection: return "Select one or more pages."
        case .writeFailed(let url): return "Bookbinder cannot write \(url.lastPathComponent)."
        }
    }
}

func openPDF(_ url: URL) throws -> PDFDocument {
    // Locked documents report pages but render nothing useful.
    guard let doc = PDFDocument(url: url), !doc.isLocked else {
        throw BinderError.unreadable(url)
    }
    return doc
}

/// Formats sorted 0-based page indices as 1-based ranges: "1-6, 12-24".
func pageRangeText(_ indices: [Int]) -> String {
    var ranges: [(Int, Int)] = []
    for i in indices {
        if let last = ranges.last, last.1 == i - 1 {
            ranges[ranges.count - 1].1 = i
        } else {
            ranges.append((i, i))
        }
    }
    return ranges.map { $0 == $1 ? "\($0 + 1)" : "\($0 + 1)-\($1 + 1)" }
        .joined(separator: ", ")
}

func extractPages(_ src: PDFDocument, indices: [Int]) -> PDFDocument {
    let out = PDFDocument()
    for i in indices {
        if let page = src.page(at: i)?.copy() as? PDFPage { out.insert(page, at: out.pageCount) }
    }
    return out
}

/// Concatenates PDFs and images, in the given order, into one document.
func mergeFiles(_ urls: [URL]) throws -> PDFDocument {
    let out = PDFDocument()
    for url in urls {
        if url.pathExtension.lowercased() == "pdf" {
            let doc = try openPDF(url)
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i)?.copy() as? PDFPage {
                    out.insert(page, at: out.pageCount)
                }
            }
        } else if let image = NSImage(contentsOf: url), let page = PDFPage(image: image) {
            out.insert(page, at: out.pageCount)
        } else {
            throw BinderError.unreadable(url)
        }
    }
    return out
}

/// Booklet imposition: for each sheet, the front side then the back side,
/// each as (left, right) 0-based source page indices; nil means blank.
///
/// Sheet i of N holds front [2i+1 | 4N-2i], back [4N-2i-1 | 2i+2]
/// (1-based). For 4 pages that is front [1|4], back [3|2]. Printed
/// duplex with short-edge flip and cut in half, the left pile reads
/// 1..2N and the right pile, turned over, reads 2N+1..4N.
func bookletSides(pageCount: Int) -> [(Int?, Int?)] {
    let total = (pageCount + 3) / 4 * 4
    let page = { (n: Int) -> Int? in n <= pageCount ? n - 1 : nil }
    var sides: [(Int?, Int?)] = []
    for i in 0..<total / 4 {
        sides.append((page(2 * i + 1), page(total - 2 * i)))
        sides.append((page(total - 2 * i - 1), page(2 * i + 2)))
    }
    return sides
}

/// Writes a 2-up booklet: each sheet is the first page's size turned
/// landscape (A4 -> A4 landscape holding two A5 pages).
func makeBooklet(_ src: PDFDocument, to url: URL) throws {
    guard let first = src.page(at: 0)?.pageRef else { throw BinderError.writeFailed(url) }
    var size = first.getBoxRect(.cropBox).size
    if first.rotationAngle % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
    var sheet = CGRect(
        x: 0, y: 0, width: max(size.width, size.height),
        height: min(size.width, size.height))
    guard let ctx = CGContext(url as CFURL, mediaBox: &sheet, nil) else {
        throw BinderError.writeFailed(url)
    }
    let half = sheet.width / 2
    for (left, right) in bookletSides(pageCount: src.pageCount) {
        ctx.beginPDFPage(nil)
        for (index, slot) in [(left, 0), (right, 1)] {
            guard let index, let page = src.page(at: index)?.pageRef else { continue }
            let rect = CGRect(x: CGFloat(slot) * half, y: 0, width: half, height: sheet.height)
            ctx.saveGState()
            // getDrawingTransform honours /Rotate and only scales down,
            // so pages smaller than a half-sheet stay centred at 100%.
            ctx.concatenate(
                page.getDrawingTransform(
                    .cropBox, rect: rect, rotate: 0,
                    preserveAspectRatio: true))
            ctx.clip(to: page.getBoxRect(.cropBox))
            ctx.drawPDFPage(page)
            ctx.restoreGState()
        }
        ctx.endPDFPage()
    }
    ctx.closePDF()
}

func write(_ doc: PDFDocument, to url: URL) throws {
    guard doc.write(to: url) else { throw BinderError.writeFailed(url) }
}
