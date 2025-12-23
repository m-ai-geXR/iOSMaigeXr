# Fix Xcode Package GUID Conflict

## The Issue
Xcode has a corrupted package cache causing GUID conflicts.

## Solution (Do this in Xcode)

### Step 1: Close Xcode
- Quit Xcode completely (Cmd+Q)

### Step 2: Open Xcode and Reset Packages
1. Open `XRAiAssistant.xcodeproj` in Xcode
2. Wait for it to fully load (10-15 seconds)
3. Go to **File** → **Packages** → **Reset Package Caches**
4. Wait for the reset to complete (~30 seconds)

### Step 3: Resolve Packages
1. Go to **File** → **Packages** → **Resolve Package Versions**
2. Wait for resolution to complete

### Step 4: Verify GRDB
1. In Project Navigator, expand **Package Dependencies**
2. You should see **GRDB** listed
3. If not, re-add it:
   - File → Add Package Dependencies
   - URL: `https://github.com/groue/GRDB.swift`
   - Version: 7.0.0 (Up to Next Major)

### Step 5: Clean and Build
1. **Product** → **Clean Build Folder** (Cmd+Shift+K)
2. **Product** → **Build** (Cmd+B)

## Expected Result
✅ BUILD SUCCEEDED

---

## If Still Failing

Try this terminal command while Xcode is **CLOSED**:

```bash
# Kill any Xcode processes
killall Xcode 2>/dev/null

# Remove all caches
rm -rf ~/Library/Developer/Xcode/DerivedData/*
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf XRAiAssistant.xcodeproj/project.xcworkspace
rm -rf XRAiAssistant.xcodeproj/xcuserdata

# Reopen Xcode
open XRAiAssistant.xcodeproj
```

Then follow Steps 2-5 above.
