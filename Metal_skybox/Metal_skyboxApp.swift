//
//  Metal_skyboxApp.swift
//  Metal_skybox
//
//  Created by randomyang on 2025/1/22.
//

import SwiftUI

@main
struct Metal_skyboxApp: App {
    var body: some Scene {
        WindowGroup {
            MetalView()
                .ignoresSafeArea()
        }
    }
}
