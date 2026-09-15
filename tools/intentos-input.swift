// Local GUI QA helper. No clipboard, messages, or credentials are read.
import AppKit
import ApplicationServices

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "activate", args.count == 2 {
    NSRunningApplication.runningApplications(withBundleIdentifier: args[1]).first?.activate(options: [.activateAllWindows])
    Thread.sleep(forTimeInterval: 0.5)
}
if args.first == "frames" {
    for screen in NSScreen.screens { print("screen", screen.frame) }
    for app in NSWorkspace.shared.runningApplications where ["net.whatsapp.WhatsApp", "com.google.Chrome.app.pommaclcbfghclhalboakcipcmmndhcj"].contains(app.bundleIdentifier ?? "") {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var raw: CFTypeRef?
        if AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &raw) == .success, let raw {
            let window = raw as! AXUIElement
            var position: CFTypeRef?
            var size: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position)
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size)
            print(app.localizedName ?? "app", position as Any, size as Any)
        }
    }
}
func post(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}
if args.first == "drag", args.count == 5,
   let x1 = Double(args[1]), let y1 = Double(args[2]), let x2 = Double(args[3]), let y2 = Double(args[4]) {
    let start = CGPoint(x: x1, y: y1)
    post(.mouseMoved, start)
    post(.leftMouseDown, start)
    for step in 1...24 {
        Thread.sleep(forTimeInterval: 0.015)
        let t = Double(step) / 24
        post(.leftMouseDragged, CGPoint(x: x1 + (x2-x1)*t, y: y1 + (y2-y1)*t))
    }
    post(.leftMouseUp, CGPoint(x: x2, y: y2))
} else if args.first == "capture" || args.first == "intent" {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: down)
        event?.flags = args.first == "intent" ? [.maskControl, .maskAlternate] : [.maskCommand, .maskAlternate]
        event?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
    }
} else if args.first == "click", args.count == 3, let x = Double(args[1]), let y = Double(args[2]) {
    let point = CGPoint(x: x, y: y)
    post(.leftMouseDown, point)
    post(.leftMouseUp, point)
}
