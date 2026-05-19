# SynoHub iOS

<p align="center">
  <img src="docs/images/1_dashboard.png" width="260" alt="Dashboard Screen"/>
  <img src="docs/images/2_media.png" width="260" alt="Media Center Screen"/>
  <img src="docs/images/3_filemanager.png" width="260" alt="File Manager Screen"/>
</p>

SynoHub is a high-performance, native iOS client built exclusively with SwiftUI to manage your Synology NAS. 
Designed with strict adherence to Apple's Human Interface Guidelines (HIG), it brings a premium, responsive, and seamless experience right to your iPhone and iPad.

## 🚀 Features

### 📡 NAS Manager
- **Premium Card Layout:** Modern horizontal card design to visualize your NAS units.
- **Smart Connectivity:** Supports HTTP, HTTPS, and Synology QuickConnect via automated relay resolving.
- **Real-time Status:** Live pulsing indicators displaying online/offline states.

### 📊 Dashboard & Resource Monitor
- **Hero Metrics:** "Apple Wallet" style information cards for your device details.
- **Live System Stats:** Real-time visualization of CPU, RAM, disk health, and network traffic.
- **Quick Controls:** One-tap utilities to reboot, shutdown, or restart services instantly.

### 📁 File Manager
- **Native Experience:** Fluid folder navigation, intuitive breadcrumbs, and fast contextual menus.
- **Smart Operations:** Copy, move, rename, and delete capabilities with immediate feedback.
- **Upload & Share:** Seamlessly upload iOS files directly to the NAS and generate shareable links (QRCodes included!).

### 🍿 Media Center
- **Apple TV-like UI:** A rich multimedia interface with a dynamic Hero Section for the latest movies.
- **Smart Folders:** Automatically categorized media with beautiful color-coded iconography.
- **Native Playback:** Built-in AVPlayer support for streaming video content directly from your NAS.

### 🖼 Photos
- **Smart Grid:** Smooth infinite scrolling timelines for your Synology photo library.
- **Albums & Sharing:** Native Album management directly inside the app.

---

## 🛠 Tech Stack
- **Architecture:** MVVM + Clean Architecture principles
- **UI Framework:** SwiftUI (iOS 16.0+)
- **Storage:** SwiftData & UserDefaults
- **Networking:** Native URLSession (Async/Await API) + Synology WebAPI
- **Media:** AVKit (AVPlayer)

## 📦 Installation & Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/phuctu1901/synohub-ios.git
   ```
2. **Open the project:**
   Open `SynoHubs/SynoHubs.xcodeproj` in Xcode 15 or later.
3. **Build & Run:**
   Select an iOS Simulator or connected iOS Device (iOS 16+) and press `Cmd + R`.

---

## 🔒 Privacy & Security
SynoHub connects *directly* to your Synology NAS using standard Synology APIs. Credentials are fundamentally processed locally on-device and are never routed through any third-party intermediate servers.

## 📄 License
This project is proprietary software. All rights reserved.
