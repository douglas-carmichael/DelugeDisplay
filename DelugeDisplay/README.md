# DelugeDisplay for macOS

DelugeDisplay is a macOS application designed to mirror the display of a [Synthstrom Audible Deluge](https://synthstrom.com/) groovebox onto your Mac's screen. This allows for better visibility of the Deluge's interface, especially useful for screen recording, streaming, or for users who prefer a larger display.

## Features

*   **Dual Display Mode Support:** Mirrors both the OLED and 7-Segment display modes of the Deluge.
*   **Real-time Updates:** Captures and displays the Deluge screen data in real-time via MIDI SysEx messages.
*   **Mode Selection:** Allows users to manually select which display mode (OLED or 7-Segment) they want to view and request from the Deluge.

## Current Status

The application can successfully mirror both OLED and 7-Segment display modes from the Deluge. Users can switch between these modes, and the application will command the Deluge to change its active display output and request the corresponding data.

Future development will focus on enhancing stability, user experience, and potentially adding new features.

## How it Works

The DelugeDisplay app communicates with the Deluge over MIDI. It sends SysEx messages to:
1.  Tell the Deluge which display mode (OLED or 7-Segment) to activate on the hardware.
2.  Request the Deluge to send its current screen data for the active mode.

The app then receives SysEx messages containing the screen data, decodes it, and renders it on the Mac's display.

## How to Use

1.  **Connect Your Deluge:**
    *   Ensure your Deluge is connected to your Mac via a MIDI interface.
    *   Power on your Deluge.

2.  **Launch DelugeDisplay:**
    *   Open the DelugeDisplay application on your Mac.

3.  **Select MIDI Input Port:**
    *   In the DelugeDisplay menu bar, go to **MIDI**.
    *   If your Deluge is not automatically selected, choose its MIDI port from the list. Available ports will be shown as toggle items.
    *   If your port isn't listed, you can try "Rescan MIDI Ports".
    *   The app will attempt to connect. The display window will update once a connection is established and data is received.

4.  **Choose Display Mode:**
    *   To select the display mode you want to mirror (and command the Deluge to output):
        *   Go to the **View** menu in the menu bar.
        *   Select **Show OLED** (Shortcut: `⌘1`) or **Show 7SEG** (`⌘2`).
    *   This action sends a command to your Deluge to switch its physical display output *and* tells the DelugeDisplay app which type of data to expect and render.

5.  **View Display:**
    *   The Deluge's screen content for the selected mode should now be mirrored in the DelugeDisplay window.

6.  **Additional Controls (View Menu):**
    *   **Display Colors:** Under **View > Display Colors**, you can change the color scheme for the mirrored display (e.g., White on Black, Green on Black).
    *   **Zoom:** Use **View > Actual Size** (`⌘0`), **Zoom In** (`⌘+`), or **Zoom Out** (`⌘-`) to adjust the display size.
    *   **Smoothing:** Toggle image smoothing and adjust its quality via **View > Enable Smoothing** (`⌘S`) and **View > Smoothing Quality**.

7.  **Save Screenshot:**
    *   To save an image of the current display, go to **File > Save Screenshot...** (Shortcut: `⇧⌘S`). This is active when the Deluge is connected.

## Downloading a Release

Pre-built versions of DelugeDisplay can be downloaded from the [Releases page](https://github.com/douglas-carmichael/DelugeDisplay/releases) on GitHub.

1.  Go to the Releases page.
2.  Download the latest `.dmg` or `.zip` file for macOS.
3.  Open the downloaded file and drag `DelugeDisplay.app` to your Applications folder.

## Building and Running

1.  Clone the repository.
2.  Open `DelugeDisplay.xcodeproj` in Xcode.
3.  Select the "DelugeDisplay" scheme.
4.  Choose a macOS destination (e.g., "My Mac").
5.  Build and run the application (Cmd+R).

**Prerequisites:**
*   macOS
*   Xcode
*   A Synthstrom Audible Deluge connected via MIDI to your Mac.

## Technologies Used

*   **Swift**
*   **SwiftUI** (for the user interface)
*   **CoreMIDI** (for MIDI communication)

## Future Enhancements (Potential)

*   Improved error handling and connection stability.
*   Customizable display appearance (e.g., themes, scaling options).
*   Recording/snapshot functionality.

## Contributing

Contributions, bug reports, and feature requests are welcome! Please open an issue or submit a pull request.

*(You might want to add a LICENSE file and a section here linking to it if you plan to make this open source more formally.)*
