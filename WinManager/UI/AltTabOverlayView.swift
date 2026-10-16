import AppKit
import Combine

/// AppKit-only custom app switcher styled to resemble the system switcher.
/// macOS does not expose a public API for modifying Apple's actual switcher UI.
final class AltTabOverlayView: NSVisualEffectView {
    private let model: SwitcherViewModel
    private let scrollView = NSScrollView()
    private let documentView = NSView()
    private var cellsByPID: [pid_t: SwitcherIconCell] = [:]
    private var itemOrder: [pid_t] = []
    private var cancellables = Set<AnyCancellable>()
    
    static let cellSize = NSSize(width: 140, height: 145)
    static let cellSpacing: CGFloat = 12
    private let horizontalInset: CGFloat = 10
    private let verticalInset: CGFloat = 5
    
    init(frame: NSRect, model: SwitcherViewModel) {
        self.model = model
        super.init(frame: frame)
        configureAppearance()
        configureScrollView()
        bindModel()
        rebuildCells()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
    
    private func configureAppearance() {
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
        setAccessibilityLabel("Win Manager App Switcher")
    }
    
    private func configureScrollView() {
        scrollView.frame = bounds.insetBy(dx: horizontalInset, dy: verticalInset)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = documentView
        addSubview(scrollView)
    }
    
    private func bindModel() {
        model.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildCells() }
            .store(in: &cancellables)
        
        model.$selectedIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateSelection(scrollToSelectedCell: true) }
            .store(in: &cancellables)
    }
    
    override func layout() {
        super.layout()
        let targetFrame = bounds.insetBy(dx: horizontalInset, dy: verticalInset)
        if scrollView.frame != targetFrame { scrollView.frame = targetFrame }
        layoutCells()
    }
    
    private func rebuildCells() {
        for cell in cellsByPID.values { cell.removeFromSuperview() }
        cellsByPID.removeAll(keepingCapacity: true)
        itemOrder = model.items.map(\.id)
        
        for item in model.items {
            let cell = SwitcherIconCell(item: item, size: Self.cellSize)
            documentView.addSubview(cell)
            cellsByPID[item.id] = cell
        }
        
        layoutCells()
        updateSelection(scrollToSelectedCell: true)
    }
    
    private func layoutCells() {
        let viewportSize = scrollView.contentSize
        let count = itemOrder.count
        // The scroll view already provides the outer insets; the document view
        // should contain only the icon strip, otherwise it scrolls unnecessarily.
        let stripWidth = CGFloat(count) * Self.cellSize.width
        + CGFloat(max(0, count - 1)) * Self.cellSpacing
        let documentWidth = max(viewportSize.width, stripWidth)
        let documentHeight = max(viewportSize.height, Self.cellSize.height)
        let targetDocumentFrame = NSRect(x: 0, y: 0, width: documentWidth, height: documentHeight)
        if documentView.frame != targetDocumentFrame { documentView.frame = targetDocumentFrame }
        
        let originY = floor((documentHeight - Self.cellSize.height) / 2)
        for (index, pid) in itemOrder.enumerated() {
            guard let cell = cellsByPID[pid] else { continue }
            let x = CGFloat(index) * (Self.cellSize.width + Self.cellSpacing)
            let targetFrame = NSRect(origin: NSPoint(x: x, y: originY), size: Self.cellSize)
            if cell.frame != targetFrame { cell.frame = targetFrame }
        }
    }
    
    private func updateSelection(scrollToSelectedCell: Bool) {
        guard !itemOrder.isEmpty else { return }
        for (index, pid) in itemOrder.enumerated() {
            cellsByPID[pid]?.isSelected = index == model.selectedIndex
        }
        
        guard scrollToSelectedCell,
              model.items.indices.contains(model.selectedIndex),
              let selectedCell = cellsByPID[model.items[model.selectedIndex].id] else { return }
        
        // Scroll the clip view directly; avoid forcing a recursive layout pass.
        let visibleRect = scrollView.contentView.bounds
        let cellRect = selectedCell.frame
        var targetX = visibleRect.origin.x
        let margin: CGFloat = 8
        
        if cellRect.minX < visibleRect.minX + margin {
            targetX = cellRect.minX - margin
        } else if cellRect.maxX > visibleRect.maxX - margin {
            targetX = cellRect.maxX - visibleRect.width + margin
        }
        
        let maxX = max(0, documentView.bounds.width - visibleRect.width)
        targetX = min(max(targetX, 0), maxX)
        if abs(targetX - visibleRect.origin.x) > 0.5 {
            scrollView.contentView.scroll(to: NSPoint(x: targetX, y: visibleRect.origin.y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

/// App icon tile. The selected app's name appears under the icon, like the system switcher.
private final class SwitcherIconCell: NSView {
    private let imageView = NSImageView()
    private let selectionBackdrop = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let appName: String
    var isSelected = false {
        didSet { updateSelectionAppearance() }
    }
    
    init(item: SwitcherItem, size: NSSize) {
        appName = item.name
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        
        // Tighter selection highlight around the app icon.
        selectionBackdrop.frame = NSRect(
            x: 16,
            y: 28,
            width: size.width - 32,
            height: 90
        )
        
        selectionBackdrop.wantsLayer = true
        selectionBackdrop.layer?.cornerRadius = 18
        selectionBackdrop.layer?.masksToBounds = true
        
        addSubview(
            selectionBackdrop,
            positioned: .below,
            relativeTo: nil
        )
        
        // Slightly smaller icon with balanced padding.
        let iconSize: CGFloat = 78
        
        imageView.image = item.icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = NSRect(
            x: floor((size.width - iconSize) / 2),
            y: 34,
            width: iconSize,
            height: iconSize
        )
        
        imageView.animates = false
        imageView.setAccessibilityElement(false)
        addSubview(imageView)
        
        nameLabel.stringValue = appName
        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        nameLabel.frame = NSRect(x: 4, y: 5, width: size.width - 8, height: 19)
        nameLabel.isHidden = true
        nameLabel.setAccessibilityElement(false)
        addSubview(nameLabel)
        
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(appName)
        toolTip = appName
        updateSelectionAppearance()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
    
    override var mouseDownCanMoveWindow: Bool { false }
    
    private func updateSelectionAppearance() {
        selectionBackdrop.isHidden = !isSelected
        nameLabel.isHidden = !isSelected
        if isSelected {
            selectionBackdrop.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            selectionBackdrop.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            selectionBackdrop.layer?.borderWidth = 1
        } else {
            selectionBackdrop.layer?.backgroundColor = NSColor.clear.cgColor
            selectionBackdrop.layer?.borderColor = NSColor.clear.cgColor
            selectionBackdrop.layer?.borderWidth = 0
        }
    }
}
