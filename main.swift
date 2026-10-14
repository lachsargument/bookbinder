import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Accepts file drops from Finder and hands the URLs to `onDrop`.
final class DropView: NSView {
    var onDrop: ([URL]) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls =
            sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onDrop(urls)
        return !urls.isEmpty
    }
}

let noFileText = "Choose a PDF, or drag a PDF into this window."
let rowType = NSPasteboard.PasteboardType("Bookbinder.row")

final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource,
    NSTableViewDelegate
{
    var window: NSWindow!

    var extractURL: URL?
    let extractLabel = NSTextField(labelWithString: noFileText)
    let pdfView = PDFView()
    let thumbnails = PDFThumbnailView()
    let fromField = AppDelegate.pageField()
    let toField = AppDelegate.pageField()
    let selectionLabel = NSTextField(labelWithString: "")

    /// A file in the merge list. `pages` is nil when the file cannot be read.
    var mergeItems: [(url: URL, pages: Int?)] = []
    let table = NSTableView()

    var bookletDoc: PDFDocument?
    var bookletURL: URL?
    let bookletLabel = NSTextField(labelWithString: noFileText)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
        let tabs = NSTabView()
        for (title, view) in [
            ("Extract", extractView()), ("Merge", mergeView()), ("Booklet", bookletView()),
        ] {
            let item = NSTabViewItem()
            item.label = title
            item.view = view
            tabs.addTabViewItem(item)
        }
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Bookbinder"
        window.contentView = tabs
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // The thumbnail view has no selection callback, and its inner grid
        // does not post KVO for clicks. Read the selection after each mouse
        // or key release instead.
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .keyUp]) { [weak self] event in
            DispatchQueue.main.async { self?.selectionChanged() }
            return event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: tabs

    func extractView() -> NSView {
        pdfView.autoScales = true
        for field in [fromField, toField] {
            field.target = self
            field.action = #selector(addRange)
        }
        thumbnails.pdfView = pdfView
        thumbnails.allowsMultipleSelection = true
        thumbnails.thumbnailSize = NSSize(width: 100, height: 140)
        thumbnails.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let pages = row([thumbnails, pdfView])
        pages.alignment = .top
        pages.distribution = .fill
        pages.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        thumbnails.heightAnchor.constraint(equalTo: pages.heightAnchor).isActive = true
        pdfView.heightAnchor.constraint(equalTo: pages.heightAnchor).isActive = true
        let view = column(
            [
                row([button("Choose PDF…", #selector(chooseExtract)), extractLabel]),
                NSTextField(
                    wrappingLabelWithString: """
                        Enter a range and click Add Pages. Do this again to add more ranges.
                        You can also click the pages. Hold Command and click to add a page.
                        """),
                row([
                    NSTextField(labelWithString: "From page"), fromField,
                    NSTextField(labelWithString: "to"), toField,
                    button("Add Pages", #selector(addRange)),
                    button("Select All", #selector(selectAllPages)),
                    button("Clear", #selector(clearSelection)),
                ]),
                pages,
                row([button("Save Selected Pages…", #selector(saveExtract)), selectionLabel]),
            ], fill: true)
        pages.widthAnchor.constraint(equalTo: view.subviews[0].widthAnchor).isActive = true
        view.onDrop = { [weak self] urls in self?.loadExtract(urls.first) }
        return view
    }

    func mergeView() -> NSView {
        let col = NSTableColumn()
        col.title = "Name"
        col.resizingMask = .autoresizingMask
        let pagesCol = NSTableColumn(identifier: .init("pages"))
        pagesCol.title = "Pages"
        pagesCol.width = 60
        pagesCol.resizingMask = []
        table.addTableColumn(col)
        table.addTableColumn(pagesCol)
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.allowsMultipleSelection = true
        table.dataSource = self
        table.delegate = self
        table.registerForDraggedTypes([.fileURL, rowType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        let view = column(
            [
                NSTextField(
                    wrappingLabelWithString: """
                        Bookbinder merges the files from top to bottom. Drag files into the list \
                        to add them. Drag a row to move it.
                        """),
                scroll,
                row([
                    button("Add Files…", #selector(addMerge)),
                    button("Remove", #selector(removeMerge)),
                    button("Save As…", #selector(saveMerge)),
                ]),
            ], fill: true)
        scroll.widthAnchor.constraint(equalTo: view.subviews[0].widthAnchor).isActive = true
        return view
    }

    func bookletView() -> NSView {
        let help = NSTextField(
            wrappingLabelWithString: """
                Bookbinder puts two pages on each side of a landscape sheet. \
                An A4 page becomes an A5 page. To make the booklet:

                1. Print on two sides with short-edge binding.
                2. Put the stack with page 1 on top.
                3. Cut the stack in half.
                4. Turn the right half over.
                5. Put the right half below the left half.
                """)
        help.preferredMaxLayoutWidth = 500
        let view = column([
            row([button("Choose PDF…", #selector(chooseBooklet)), bookletLabel]),
            help,
            button("Save As…", #selector(saveBooklet)),
        ])
        view.onDrop = { [weak self] urls in self?.loadBooklet(urls.first) }
        return view
    }

    // MARK: actions

    @objc func chooseExtract() { loadExtract(openPanel([.pdf], multiple: false).first) }

    func loadExtract(_ url: URL?) {
        guard let url, let doc = attempt({ try openPDF(url) }) else { return }
        extractURL = url
        pdfView.document = doc
        extractLabel.stringValue = fileText(url, doc)
        (fromField.formatter as? NumberFormatter)?.maximum = doc.pageCount as NSNumber
        (toField.formatter as? NumberFormatter)?.maximum = doc.pageCount as NSNumber
        // PDFThumbnailView selects the first page on load. Start with no
        // selection so the first range the user adds is the only one.
        thumbnailGrid()?.selectionIndexPaths = []
        selectionChanged()
    }

    /// Adds the pages in the From and To fields to the selection.
    @objc func addRange() {
        guard let doc = pdfView.document else { return }
        let from = fromField.integerValue
        let to = toField.stringValue.isEmpty ? from : toField.integerValue
        guard 1 <= from, from <= to, to <= doc.pageCount else {
            alert(
                "Enter page numbers from 1 to \(doc.pageCount). The first page number must not be larger than the second."
            )
            return
        }
        let paths = Set((from - 1..<to).map { IndexPath(item: $0, section: 0) })
        // Going to a page makes PDFThumbnailView select only that page, so
        // keep the old selection and set the union after the move.
        let grid = thumbnailGrid()
        let old = grid?.selectionIndexPaths ?? []
        pdfView.go(to: doc.page(at: from - 1)!)
        grid?.selectionIndexPaths = old.union(paths)
        fromField.stringValue = ""
        toField.stringValue = ""
        window.makeFirstResponder(fromField)
        selectionChanged()
    }

    @objc func clearSelection() {
        thumbnailGrid()?.selectionIndexPaths = []
        selectionChanged()
    }

    /// Selected pages as 0-based indices in document order.
    func selectedIndices() -> [Int] {
        guard let doc = pdfView.document else { return [] }
        return (thumbnails.selectedPages ?? []).map { doc.index(for: $0) }.sorted()
    }

    func selectionChanged() {
        let indices = selectedIndices()
        selectionLabel.stringValue =
            indices.isEmpty ? "No pages selected." : "Selected pages: \(pageRangeText(indices))"
    }

    @objc func selectAllPages() {
        thumbnailGrid()?.selectAll(nil)
        selectionChanged()
    }

    /// selectedPages is read-only. PDFThumbnailView draws its pages with an
    /// inner NSCollectionView whose selection feeds selectedPages, so change
    /// the selection there. If a future PDFKit drops that view, this is nil
    /// and only mouse selection works.
    func thumbnailGrid() -> NSCollectionView? {
        var stack: [NSView] = [thumbnails]
        while let view = stack.popLast() {
            if let grid = view as? NSCollectionView { return grid }
            stack += view.subviews
        }
        return nil
    }

    @objc func saveExtract() {
        guard let doc = pdfView.document, let src = extractURL else { return }
        let indices = selectedIndices()
        guard !indices.isEmpty else {
            NSAlert(error: BinderError.noSelection).runModal()
            return
        }
        let name = src.deletingPathExtension().lastPathComponent
        save(suggested: "\(name) pages \(pageRangeText(indices)).pdf") {
            try write(extractPages(doc, indices: indices), to: $0)
        }
    }

    @objc func addMerge() {
        addMergeFiles(openPanel([.pdf, .image], multiple: true), at: mergeItems.count)
    }

    func addMergeFiles(_ urls: [URL], at row: Int) {
        let items = urls.map { url in
            (
                url: url,
                pages: url.pathExtension.lowercased() == "pdf"
                    ? PDFDocument(url: url)?.pageCount : NSImage(contentsOf: url).map { _ in 1 }
            )
        }
        mergeItems.insert(contentsOf: items, at: row)
        table.reloadData()
    }

    @objc func removeMerge() {
        for i in table.selectedRowIndexes.reversed() { mergeItems.remove(at: i) }
        table.reloadData()
    }

    @objc func saveMerge() {
        guard !mergeItems.isEmpty else { return }
        let urls = mergeItems.map(\.url)
        save(suggested: "merged.pdf") { try write(try mergeFiles(urls), to: $0) }
    }

    @objc func chooseBooklet() { loadBooklet(openPanel([.pdf], multiple: false).first) }

    func loadBooklet(_ url: URL?) {
        guard let url, let doc = attempt({ try openPDF(url) }) else { return }
        (bookletURL, bookletDoc) = (url, doc)
        bookletLabel.stringValue = fileText(url, doc)
    }

    @objc func saveBooklet() {
        guard let doc = bookletDoc, let src = bookletURL else { return }
        save(suggested: src.deletingPathExtension().lastPathComponent + "-booklet.pdf") {
            try makeBooklet(doc, to: $0)
        }
    }

    // MARK: merge table

    func numberOfRows(in tableView: NSTableView) -> Int { mergeItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
    {
        let item = mergeItems[row]
        let isPages = tableColumn?.identifier.rawValue == "pages"
        let label = NSTextField(
            labelWithString: isPages
                ? item.pages.map(String.init) ?? "Error" : item.url.lastPathComponent)
        label.alignment = isPages ? .right : .natural
        label.lineBreakMode = .byTruncatingMiddle
        // The table stretches a bare label to the row height and the text
        // sits at the top. Center the label in a cell view instead.
        let cell = NSTableCellView()
        cell.textField = label
        cell.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int)
        -> NSPasteboardWriting?
    {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: rowType)
        return item
    }

    func tableView(
        _ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        tableView.setDropRow(row, dropOperation: .above)
        return info.draggingSource as? NSTableView === tableView ? .move : .copy
    }

    func tableView(
        _ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        let pb = info.draggingPasteboard
        if info.draggingSource as? NSTableView === tableView {
            let rows = (pb.pasteboardItems ?? []).compactMap {
                $0.string(forType: rowType).flatMap { Int($0) }
            }
            let moved = rows.map { mergeItems[$0] }
            for r in rows.sorted(by: >) { mergeItems.remove(at: r) }
            mergeItems.insert(contentsOf: moved, at: row - rows.filter { $0 < row }.count)
        } else {
            let urls =
                pb.readObjects(
                    forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
            addMergeFiles(urls ?? [], at: row)
        }
        tableView.reloadData()
        return true
    }

    // MARK: helpers

    func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    func row(_ views: [NSView]) -> NSStackView {
        NSStackView(views: views)
    }

    static func pageField() -> NSTextField {
        let field = NSTextField()
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        field.formatter = formatter
        field.widthAnchor.constraint(equalToConstant: 56).isActive = true
        return field
    }

    func alert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.runModal()
    }

    func fileText(_ url: URL, _ doc: PDFDocument) -> String {
        "\(url.lastPathComponent) (\(doc.pageCount) pages)"
    }

    /// With `fill`, the stack reaches the bottom edge so the view with
    /// the lowest hugging priority (a list or page view) takes the space.
    func column(_ views: [NSView], fill: Bool = false) -> DropView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let drop = DropView()
        drop.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: drop.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: drop.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: drop.trailingAnchor, constant: -20),
            fill
                ? stack.bottomAnchor.constraint(equalTo: drop.bottomAnchor, constant: -20)
                : stack.bottomAnchor.constraint(
                    lessThanOrEqualTo: drop.bottomAnchor, constant: -20),
        ])
        return drop
    }

    func openPanel(_ types: [UTType], multiple: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = multiple
        return panel.runModal() == .OK ? panel.urls : []
    }

    func attempt<T>(_ work: () throws -> T) -> T? {
        do { return try work() } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    // ponytail: runs on the main thread; move to a background queue if
    // huge PDFs make the UI stall noticeably.
    func save(suggested: String, _ work: @escaping (URL) throws -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggested
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if attempt({ try work(url) }) != nil {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // Without a main menu, Cmd-Q and Cmd-C/V in text fields do nothing.
    func makeMenu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(
            withTitle: "Quit Bookbinder", action: #selector(NSApp.terminate),
            keyEquivalent: "q")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste), keyEquivalent: "v")
        edit.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll),
            keyEquivalent: "a")
        for menu in [app, edit] {
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
        }
        return main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
