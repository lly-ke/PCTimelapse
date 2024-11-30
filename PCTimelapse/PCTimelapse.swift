//
//  PCTimelapseApp.swift
//  PCTimelapse
//
//  Created by llyke on 2024/11/29.
//

import SwiftUI

@main
struct PCTimelapseApp: App {
    @StateObject private var settings = AppSettings.shared
    
    var body: some Scene {
        WindowGroup {
            if settings.shouldShowWindow() {
                ContentView()
            }
        }
    }
}
