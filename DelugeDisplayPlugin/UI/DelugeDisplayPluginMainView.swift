//
//  DelugeDisplayPluginMainView.swift
//  DelugeDisplayPlugin
//
//  Created by admin on 13/5/25.
//

import SwiftUI

struct DelugeDisplayPluginMainView: View {
    var parameterTree: ObservableAUParameterGroup
    
    var body: some View {
        VStack {
            ParameterSlider(param: parameterTree.global.midiNoteNumber)
                .padding()
            MomentaryButton(
                "Play note",
                param: parameterTree.global.sendNote
            )
        }
    }
}
