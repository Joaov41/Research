import AppKit

extension NSAttributedString {
    func createPDF() -> Data {
        // Create a scroll view to handle multiple pages
        let pageSize = NSSize(width: 595, height: 842)  // A4 size
        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: pageSize))
        scrollView.hasVerticalScroller = true
        
        // Create text view inside scroll view
        let textView = NSTextView(frame: NSRect(origin: .zero, size: pageSize))
        textView.minSize = NSSize(width: pageSize.width - 100, height: 0)  // Allow vertical growth
        textView.maxSize = NSSize(width: pageSize.width - 100, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 50, height: 50)
        
        // Configure scroll view
        scrollView.documentView = textView
        
        // Set the content
        textView.textStorage?.setAttributedString(self)
        
        // Calculate total height needed
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let contentHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
        
        // Adjust frame to fit all content
        scrollView.frame.size.height = contentHeight + 100  // Add padding
        
        // Generate PDF with all content
        return scrollView.dataWithPDF(inside: scrollView.bounds)
    }
} 