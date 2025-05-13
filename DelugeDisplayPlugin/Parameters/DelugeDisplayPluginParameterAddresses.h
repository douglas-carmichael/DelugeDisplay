//
//  DelugeDisplayPluginParameterAddresses.h
//  DelugeDisplayPlugin
//
//  Created by admin on 13/5/25.
//

#pragma once

#include <AudioToolbox/AUParameters.h>

typedef NS_ENUM(AUParameterAddress, DelugeDisplayPluginParameterAddress) {
    sendNote = 0,
    midiNoteNumber = 1
};
