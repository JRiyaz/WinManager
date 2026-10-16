import AppKit
import Combine

/// AppKit-only app switcher surface. Keeping this view out of SwiftUI avoids nested
/// NSHostingView/ScrollView layout passes while the global hotkey rapidly changes selection.
final class AltTabOverlayView: NSVisualEffectView {
    private let model: SwitcherViewModel
    private let scrollView = NSScrollView()
    private let documentView = NSView()
    private var cellsByPID: [pid_t: SwitcherIconCell] = [:]
    private var itemOrder: [pid_t] = []
    private var cancellables = Set<AnyCancellable>()
    
    private let cellSize = NSSize(width: 78, height: 78)
    private let cellSpacing: CGFloat = 2
    private let horizontalInset: CGFloat = 10
    private let verticalInset: CGFloat = 8
    
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
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
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
            .sink { [weak self] _ in
                self?.rebuildCells()
            }
            .store(in: &cancellables)
        
        model.$selectedIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSelection(scrollToSelectedCell: true)
            }
            .store(in: &cancellables)
    }
    
    override func layout() {
        super.layout()
        
        let targetFrame = bounds.insetBy(dx: horizontalInset, dy: verticalInset)
        if scrollView.frame != targetFrame {
            scrollView.frame = targetFrame
        }
        layoutCells()
    }
    
    private func rebuildCells() {
        // Preserve the model's process-ID identity; do not create a new SwiftUI tree for
        // every key press or selected-index change.
        for cell in cellsByPID.values {
            cell.removeFromSuperview()
        }
        cellsByPID.removeAll(keepingCapacity: true)
        itemOrder = model.items.map(\.id)
        
        for item in model.items {
            let cell = SwitcherIconCell(item: item, size: cellSize)
            documentView.addSubview(cell)
            cellsByPID[item.id] = cell
        }
        
        layoutCells()
        updateSelection(scrollToSelectedCell: true)
    }
    
    private func layoutCells() {
        let viewportSize = scrollView.contentSize
        let count = itemOrder.count
        let stripWidth = CGFloat(count) * cellSize.width
        + CGFloat(max(0, count - 1)) * cellSpacing
        + horizontalInset * 2
        let documentWidth = max(viewportSize.width, stripWidth)
        let documentHeight = max(viewportSize.height, cellSize.height)
        let targetDocumentFrame = NSRect(x: 0, y: 0, width: documentWidth, height: documentHeight)
        
        if documentView.frame != targetDocumentFrame {
            documentView.frame = targetDocumentFrame
        }
        
        let originY = floor((documentHeight - cellSize.height) / 2)
        for (index, pid) in itemOrder.enumerated() {
            guard let cell = cellsByPID[pid] else { continue }
            let x = horizontalInset + CGFloat(index) * (cellSize.width + cellSpacing)
            let targetFrame = NSRect(origin: NSPoint(x: x, y: originY), size: cellSize)
            if cell.frame != targetFrame {
                cell.frame = targetFrame
            }
        }
    }
    
    private func updateSelection(scrollToSelectedCell: Bool) {
        guard !itemOrder.isEmpty else { return }
        
        for (index, pid) in itemOrder.enumerated() {
            cellsByPID[pid]?.isSelected = index == model.selectedIndex
        }
        
        guard scrollToSelectedCell,
              model.items.indices.contains(model.selectedIndex),
              let selectedCell = cellsByPID[model.items[model.selectedIndex].id] else {
            return
        }
        
        // Move only the clip view's origin. This avoids forcing an immediate recursive
        // layout pass via layoutSubtreeIfNeeded while AppKit is laying out the panel.
        let visibleRect = scrollView.contentView.bounds
        let cellRect = selectedCell.frame
        var targetX = visibleRect.origin.x
        let margin: CGFloat = 4
        
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

/// A compact icon-only tile similar to the built-in macOS app switcher.
private final class SwitcherIconCell: NSView {
    private let imageView = NSImageView()
    private let appName: String
    var isSelected = false {
        didSet { updateSelectionAppearance() }
    }
    
    init(item: SwitcherItem, size: NSSize) {
        appName = item.name
        super.init(frame: NSRect(origin: .zero, size: size))
        
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        
        imageView.image = item.icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = NSRect(
            x: floor((size.width - 58) / 2),
            y: floor((size.height - 58) / 2),
            width: 58,
            height: 58
        )
        imageView.animates = false
        imageView.setAccessibilityElement(false)
        addSubview(imageView)
        
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
        if isSelected {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.88).cgColor
            layer?.borderWidth = 1.25
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
        }
    }
}
