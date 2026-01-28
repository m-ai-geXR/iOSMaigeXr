# Xcode GUI Tasks - Step-by-Step Guide

**Project:** m{ai}geXR iOS
**Date:** 2025-12-30
**Estimated Time:** 1-2 hours
**Status:** Ready to Execute

---

## 📋 Current State (Before Changes)

```
Product Name:           XRAiAssistant
Bundle Identifier:      com.example.XRAiAssistant
Display Name:           XRAiAssistant (default)
App Icon:               Placeholder only
Scheme Name:            XRAiAssistant
```

## 🎯 Target State (After Changes)

```
Product Name:           m{ai}geXR
Bundle Identifier:      com.maigexr.ios
Display Name:           m{ai}geXR
App Icon:               Custom 1024x1024 (AR/VR headset)
Scheme Name:            m{ai}geXR (optional)
```

---

## 🚀 Getting Started

### Prerequisites

- ✅ Mac with Xcode 15+ installed
- ✅ Project pulled from git: `/Users/brendonsmith/exp/maigeXR/iOSMaigeXr`
- ✅ All code changes committed (no uncommitted changes)

### Open Project

```bash
cd /Users/brendonsmith/exp/maigeXR/iOSMaigeXr
open XRAiAssistant.xcodeproj
```

**Wait for Xcode to:**
1. Index the project (progress bar in toolbar)
2. Resolve Swift packages (automatic)
3. Show project navigator on left

---

## 📝 Task 1: Update Product Name & Display Name

**Time:** 5 minutes

### Steps

1. **Select Project Root**
   - In left sidebar (Project Navigator), click the top-level **"XRAiAssistant"** (blue icon)

2. **Select Target**
   - In main editor area, under "TARGETS", click **"XRAiAssistant"**
   - Ensure you're on the **"General"** tab (top of editor)

3. **Update Display Name**
   - Scroll to **"Identity"** section at top
   - Find field: **"Display Name"**
   - Change from: `XRAiAssistant`
   - Change to: `m{ai}geXR`
   - Press Enter to confirm

4. **Update Bundle Name** (Optional)
   - Still in "General" tab
   - Find: **"Bundle Name"** (below Display Name)
   - If present, change to: `m{ai}geXR`
   - Press Enter to confirm

### Verification

- Display Name field shows: `m{ai}geXR`
- No build errors appear
- Yellow warning indicator may appear (ignore for now)

### What This Does

- Changes the app name displayed under the icon on iPhone home screen
- Updates the app name in Settings
- Updates the app name in multitasking view

---

## 📝 Task 2: Update Bundle Identifier

**Time:** 5 minutes

### Steps

1. **Same Target Screen**
   - Still in **"XRAiAssistant"** target → **"General"** tab

2. **Find Bundle Identifier**
   - Scroll to **"Identity"** section
   - Locate: **"Bundle Identifier"**
   - Current value: `com.example.XRAiAssistant`

3. **Update Bundle Identifier**
   - Click in the field
   - Change to: `com.maigexr.ios`
   - Press Enter to confirm

### Expected Warnings

You may see warnings like:
- ⚠️ "No provisioning profiles found"
- ⚠️ "Signing requires a development team"

**These are NORMAL and SAFE for local development.**

### Fixing Code Signing (If Needed)

If you want to run on a real device later:

1. Stay in **"General"** tab
2. Scroll to **"Signing & Capabilities"** section
3. Under **"Team"**, select your Apple Developer account
4. Xcode will automatically create a provisioning profile

**For simulator testing only:** You can ignore code signing warnings.

### Verification

- Bundle Identifier shows: `com.maigexr.ios`
- Xcode may show yellow warning (safe to ignore)
- Project still builds successfully

### What This Does

- Changes the unique app identifier in Apple's ecosystem
- Required for App Store submission (future)
- Affects iCloud, push notifications, app groups
- Keeps your app separate from other apps

---

## 📝 Task 3: Rename Xcode Scheme (Optional)

**Time:** 2 minutes

### Why This Matters

The scheme name appears in:
- Xcode scheme dropdown (top toolbar)
- Build logs and reports
- Derived data folder names

### Steps

1. **Open Scheme Manager**
   - Top toolbar, click scheme dropdown (shows "XRAiAssistant")
   - Select **"Manage Schemes..."**

2. **Edit Scheme**
   - In the schemes list, find **"XRAiAssistant"**
   - Double-click the name (not the checkbox)
   - Or: Select it and press Enter

3. **Rename**
   - Type: `m{ai}geXR`
   - Press Enter

4. **Close**
   - Click **"Close"** button

### Verification

- Scheme dropdown now shows: `m{ai}geXR`
- Build destination still shows (e.g., "iPhone 15 Pro")

### What This Does

- Makes Xcode UI clearer with correct app name
- Organizes build folders by app name
- Cosmetic improvement (no functional change)

---

## 📝 Task 4: Create App Icon

**Time:** 30 minutes - 1 hour

### Design Specifications (From Android)

**Visual Elements:**
- Background: Teal circle (#006A6B)
- Icon: White AR/VR headset with two lenses
- AI Indicator: Neon cyan dot (#9CF1F0) at center
- Style: Minimalist, scalable, flat design

**Required Sizes:**
- **1024x1024 PNG** (mandatory for App Store)
- Single @1x asset (Xcode generates all sizes automatically)

### Option A: Export from Android Assets

#### Android Source Files

```bash
# Vector XML (original design)
/Users/brendonsmith/exp/maigeXR/AndroidMaigeXr/app/src/main/res/drawable/ic_launcher.xml

# Raster PNGs (if available)
/Users/brendonsmith/exp/maigeXR/AndroidMaigeXr/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
```

#### Check What's Available

```bash
# List Android icon files
find /Users/brendonsmith/exp/maigeXR/AndroidMaigeXr -name "ic_launcher*" -type f
```

#### Convert XML to PNG

If you have the XML file:

**Online Tools:**
- CloudConvert: https://cloudconvert.com/svg-to-png
- Vector Asset Studio (Android Studio)

**Mac Apps:**
- Sketch (if you have it)
- Figma (free account)
- Affinity Designer

**Steps:**
1. Open `ic_launcher.xml` in text editor
2. Copy the SVG code
3. Paste into online converter
4. Set output size: 1024x1024
5. Download PNG

#### Use Existing PNG

If Android has high-res PNGs:

```bash
# Copy the largest Android icon
cp /Users/brendonsmith/exp/maigeXR/AndroidMaigeXr/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png ~/Desktop/app_icon_temp.png

# Use Preview.app or online tool to resize to 1024x1024
open ~/Desktop/app_icon_temp.png
```

In Preview:
1. Tools → Adjust Size...
2. Width: 1024, Height: 1024
3. Resolution: 72 pixels/inch
4. File → Export → PNG

---

### Option B: Use SF Symbols (Quick Method)

**Best for:** Fast prototyping, will look native iOS

#### Steps

1. **Open SF Symbols App**
   ```bash
   open -a "SF Symbols"
   ```

   If not installed: Download from https://developer.apple.com/sf-symbols/

2. **Search for VR Icon**
   - Search: `visionpro`
   - Or: `arkit`, `headset`, `goggles`

3. **Export as PNG**
   - File → Export Symbol...
   - Format: PNG
   - Size: 1024pt @ 1x
   - Color: White foreground, teal background

4. **Customize in Preview** (Optional)
   - Open exported PNG in Preview
   - Add teal background circle
   - Add cyan dot at center

---

### Option C: Design from Scratch

**Best for:** Exact Android match

**Recommended Tools:**
- **Figma** (Free, web-based): https://www.figma.com
- **Canva** (Free templates): https://www.canva.com
- **Sketch** (Mac native, paid)
- **Pixelmator Pro** (Mac native, paid)

#### Figma Instructions

1. **Create New File**
   - Go to https://www.figma.com
   - New Design File → 1024x1024 frame

2. **Create Background**
   - Draw circle: 1024x1024
   - Fill: #006A6B (teal)

3. **Draw VR Headset**
   - Create rounded rectangle: ~800x300px
   - Fill: White (#FFFFFF)
   - Border radius: 50px
   - Add two circles inside (lenses): 200x200px each

4. **Add AI Indicator**
   - Small circle: 40x40px
   - Fill: #9CF1F0 (neon cyan)
   - Position: Center of headset
   - Add glow effect (outer shadow, cyan)

5. **Export**
   - Select entire frame
   - Export → PNG
   - 1x scale (1024x1024)
   - Download

---

### Add Icon to Xcode

#### Steps

1. **Open Assets Catalog**
   - In Project Navigator, expand **"XRAiAssistant"** folder
   - Click **"Assets.xcassets"**

2. **Select AppIcon**
   - In main editor, click **"AppIcon"**
   - You'll see a grid of icon slots (various sizes)

3. **Add 1024x1024 Icon**
   - Find the **"iOS App Store"** slot (largest, usually bottom right)
   - Drag your 1024x1024 PNG file onto this slot
   - Or: Click the slot → Select your PNG file

4. **Xcode Auto-Generates Other Sizes**
   - Xcode 14+ automatically creates all required sizes from your 1024x1024 image
   - You should see the icon appear in other slots automatically

5. **Verify**
   - All icon slots should show your icon (or auto-generated versions)
   - No yellow warnings in Assets.xcassets

#### What If Auto-Generation Doesn't Work?

If you need to manually add icons for each size:

**Sizes Required:**
- 20pt @2x, @3x (40px, 60px)
- 29pt @2x, @3x (58px, 87px)
- 40pt @2x, @3x (80px, 120px)
- 60pt @2x, @3x (120px, 180px)
- 1024pt @1x (1024px) ← App Store

**Use online tool:**
- https://appicon.co
- Upload 1024x1024 PNG
- Download all sizes
- Drag each size to appropriate Xcode slot

---

## 📝 Task 5: Update Launch Screen (Optional)

**Time:** 30 minutes

### Option A: Use Existing SwiftUI Launch Screen

Already created at: `XRAiAssistant/LaunchScreenView.swift`

**Activate it:**

1. Open `XRAiAssistant/XRAiAssistant.swift`
2. Find the `@main` struct
3. Add launch screen configuration (if not already present)

This is **optional** and can be done later.

---

### Option B: Create Storyboard Launch Screen

**Skip this for now** - SwiftUI approach is modern and sufficient.

---

## ✅ Build & Test

### Build the Project

1. **Clean Build Folder**
   - Menu: Product → Clean Build Folder
   - Shortcut: ⌘⇧K (Cmd+Shift+K)

2. **Build**
   - Menu: Product → Build
   - Shortcut: ⌘B (Cmd+B)

3. **Check for Errors**
   - Should see: **"Build Succeeded"** in toolbar
   - If errors appear, read them carefully (likely signing issues)

### Run on Simulator

1. **Select Simulator**
   - Top toolbar scheme dropdown → Select device
   - Recommended: iPhone 15 Pro (iOS 17+)

2. **Run**
   - Menu: Product → Run
   - Shortcut: ⌘R (Cmd+R)

3. **Wait for Launch**
   - Simulator opens (may take 30 seconds first time)
   - App launches automatically

### Verification Checklist

**On Simulator Home Screen:**
- [ ] App name shows: **"m{ai}geXR"** (not "XRAiAssistant")
- [ ] App icon appears (not generic placeholder)
- [ ] Icon matches Android design

**In App:**
- [ ] Chat interface loads with neon cyan glow
- [ ] Settings button works (bottom nav)
- [ ] All UI elements have neon glows
- [ ] Dark mode is enforced (no light theme)

**In Settings UI:**
- [ ] Provider cards show color-coded borders
- [ ] Temperature/Top-P sliders have glows
- [ ] Save button has neon pink glow
- [ ] All text is readable

**Test AI Generation:**
1. Configure API key (Together.ai or Google AI free tier)
2. Select a model
3. Type: "Create a rotating cube"
4. Verify streaming response appears
5. Check for code generation

---

## 🎨 App Icon Quality Check

### Visual Verification

**Good Icon Characteristics:**
- ✅ Sharp at all sizes (no blur)
- ✅ Recognizable when small (40x40px)
- ✅ Matches Android brand identity
- ✅ Cyan AI dot visible and clear
- ✅ No transparency (solid teal background)
- ✅ No gradients that look muddy when small

**Common Issues:**
- ❌ Icon appears blurry → Re-export at exact 1024x1024
- ❌ White background → Ensure teal fill covers entire canvas
- ❌ Details lost when small → Simplify design
- ❌ Colors look off → Verify hex codes match Android

### Test on Device Sizes

In Simulator, test on various devices:
- iPhone SE (small screen)
- iPhone 15 Pro (standard)
- iPhone 15 Pro Max (large)
- iPad Air (tablet)

Icon should look good on all sizes.

---

## 💾 Commit Your Changes

### What Changed

After Xcode GUI tasks, these files will be modified:

```
XRAiAssistant.xcodeproj/project.pbxproj              # Project settings
XRAiAssistant.xcodeproj/xcuserdata/                  # User preferences (optional)
XRAiAssistant.xcodeproj/xcshareddata/                # Shared schemes
XRAiAssistant/Assets.xcassets/AppIcon.appiconset/    # App icon images
```

### Stage Changes

```bash
cd /Users/brendonsmith/exp/maigeXR/iOSMaigeXr

# Check what changed
git status

# Stage project file changes
git add XRAiAssistant.xcodeproj/project.pbxproj
git add XRAiAssistant.xcodeproj/xcshareddata/

# Stage app icon
git add XRAiAssistant/Assets.xcassets/AppIcon.appiconset/

# Optionally stage user data (scheme changes)
git add XRAiAssistant.xcodeproj/xcuserdata/
```

### Commit

```bash
git commit -m "feat(ios): Complete Xcode GUI branding tasks

- Updated product name to m{ai}geXR
- Updated display name to m{ai}geXR
- Updated bundle identifier to com.maigexr.ios
- Added app icon (1024x1024 AR/VR headset with cyan AI dot)
- Renamed Xcode scheme to m{ai}geXR

Phase 7/7 complete - 100% iOS branding parity with Android

Files modified:
- XRAiAssistant.xcodeproj/project.pbxproj
- Assets.xcassets/AppIcon.appiconset/

🤖 Generated with Claude Code
Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

### Push to Remote

```bash
# Push to main branch
git push origin main

# Or if on different branch
git push origin <your-branch-name>
```

---

## 🚨 Common Issues & Solutions

### Issue 1: Code Signing Errors

**Error:** "Signing for XRAiAssistant requires a development team"

**Solution:**
1. Select project → Target → Signing & Capabilities
2. Check: "Automatically manage signing"
3. Select your team in "Team" dropdown
4. If no team: Sign in with Apple ID in Xcode → Settings → Accounts

**For simulator only:** Ignore signing warnings.

---

### Issue 2: Bundle Identifier Already Exists

**Error:** "An App ID with Identifier 'com.maigexr.ios' is not available"

**Solution:**
- You own this identifier, this is expected
- If you don't own it, use: `com.YOUR_NAME.maigexr.ios`
- For local development, any unique identifier works

---

### Issue 3: App Icon Not Appearing

**Symptoms:**
- Generic placeholder icon shows instead of custom icon
- Xcode shows warnings in Assets.xcassets

**Solutions:**

**A. Wrong Size**
- Icon must be exactly 1024x1024 pixels
- Check in Preview: Tools → Show Inspector (⌘I)
- Re-export if needed

**B. Wrong Format**
- Must be PNG, not JPEG
- No alpha channel (transparency) allowed
- In Preview: File → Export → Format: PNG

**C. Simulator Cache**
- Reset simulator: Device → Erase All Content and Settings
- Clean build folder: Product → Clean Build Folder (⌘⇧K)
- Rebuild: Product → Build (⌘B)

**D. Xcode Cache**
- Quit Xcode
- Delete derived data:
  ```bash
  rm -rf ~/Library/Developer/Xcode/DerivedData/XRAiAssistant-*
  ```
- Reopen Xcode, rebuild

---

### Issue 4: Display Name Not Changing

**Symptoms:**
- Home screen still shows "XRAiAssistant"
- After building with new display name

**Solutions:**

**A. Simulator Cache**
- Reset simulator home screen
- Uninstall app from simulator
- Rebuild and run

**B. Info.plist Override**
- Check if Info.plist has `CFBundleDisplayName`
- If present, update it to match
- Or remove it to use Xcode setting

---

### Issue 5: Build Fails After Changes

**Error:** Various Swift compilation errors

**Solution:**
1. Clean build folder (⌘⇧K)
2. Close Xcode
3. Delete derived data:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/
   ```
4. Reopen Xcode
5. Resolve Swift packages: File → Packages → Resolve Package Versions
6. Rebuild (⌘B)

---

## 📊 Progress Tracking

### Before Starting

- [ ] Mac with Xcode 15+ ready
- [ ] Project opened: `XRAiAssistant.xcodeproj`
- [ ] No uncommitted changes
- [ ] Swift packages resolved

### Task Completion

- [ ] Task 1: Product Name → m{ai}geXR ✅
- [ ] Task 2: Bundle ID → com.maigexr.ios ✅
- [ ] Task 3: Scheme renamed (optional) ✅
- [ ] Task 4: App icon created & added ✅
- [ ] Task 5: Launch screen (optional, skip for now)

### Verification

- [ ] Build succeeds (⌘B)
- [ ] Runs on simulator (⌘R)
- [ ] App name shows "m{ai}geXR" on home screen
- [ ] App icon appears (not placeholder)
- [ ] Chat interface loads with neon glows
- [ ] Settings UI styled correctly

### Git Commit

- [ ] Changes staged
- [ ] Commit created with descriptive message
- [ ] Pushed to remote (origin/main)

---

## 🎯 Success Criteria

**When you're done:**

✅ App displays as **"m{ai}geXR"** on iPhone home screen
✅ Custom **app icon** visible (AR/VR headset with cyan dot)
✅ Bundle identifier: **com.maigexr.ios**
✅ App builds without errors
✅ App runs on simulator successfully
✅ All UI elements have neon cyberpunk styling
✅ Changes committed to git

**Result:** **100% iOS branding parity with Android** 🎉

---

## 📞 Need Help?

### Xcode Documentation

- App Icons: https://developer.apple.com/design/human-interface-guidelines/app-icons
- Asset Catalogs: https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/

### Design Resources

- SF Symbols: https://developer.apple.com/sf-symbols/
- Icon Generator: https://appicon.co
- Figma: https://www.figma.com

### Quick Reference Files

- Android icon source: `../AndroidMaigeXr/app/src/main/res/drawable/ic_launcher.xml`
- Color reference: `docs/STYLING_PROGRESS.md`
- Full status: `docs/STATUS_2025-12-30.md`

---

**Ready to complete the final 10% and achieve 100% Android parity!** 🚀

**Estimated Total Time:** 1-2 hours
**Difficulty:** Easy (point-and-click in Xcode GUI)
**Risk Level:** Low (no code changes, only project settings)
