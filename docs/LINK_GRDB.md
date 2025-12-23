# Link GRDB to XRAiAssistant Target

## The Problem

GRDB package is added to the project but **not linked to the XRAiAssistant target**.

Error: `No such module 'GRDB'`

## Solution (Must be done in Xcode)

### Option 1: Link Existing Package

1. Open `XRAiAssistant.xcodeproj` in Xcode
2. Select **XRAiAssistant** project (blue icon in left sidebar)
3. Select **XRAiAssistant** target (under TARGETS)
4. Go to **"General"** tab
5. Scroll down to **"Frameworks, Libraries, and Embedded Content"**
6. Click the **"+"** button
7. In the popup, find **GRDB** (should be under "GRDB Package Product")
8. Select **GRDB** and click **"Add"**
9. Build the project (Cmd+B)

### Option 2: Re-add Package (If Option 1 doesn't work)

1. Open Xcode
2. Go to **File** → **Packages** → **Reset Package Caches**
3. Select **XRAiAssistant** project
4. Go to **"Package Dependencies"** tab
5. Find **GRDB.swift** in the list
6. Click **"-"** to remove it
7. Click **"+"** to add it back:
   - URL: `https://github.com/groue/GRDB.swift`
   - Version: 7.0.0 (Up to Next Major)
8. **IMPORTANT**: In the dialog, check **GRDB** for **XRAiAssistant target**
9. Click **"Add Package"**
10. Wait for resolution
11. Build (Cmd+B)

### Option 3: Manual .pbxproj Edit (Advanced)

Only if Options 1 & 2 fail. Let me know and I'll do this programmatically.

---

## Verification

After linking, verify GRDB appears in:
1. Project → XRAiAssistant target → General → Frameworks section
2. Package Dependencies tab shows GRDB

Then build should succeed! ✅
