//
//  ApplicationMain.swift
//  FileHound
//
//  Created by VanJay on 2026/4/8.
//

import AppKit

@main
enum ApplicationMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
