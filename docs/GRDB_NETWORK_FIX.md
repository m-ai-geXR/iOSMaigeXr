# Fix GRDB Network Download Issue

## The Problem

GRDB package is properly configured in the project, but failing to download due to network errors:

```
error: RPC failed; curl 56 Recv failure: Connection reset by peer
fatal: protocol error: bad pack header
```

**Root Cause**: GitHub connection is being interrupted during package download.

---

## Solution: Fix in Xcode (RECOMMENDED)

### Option 1: Reset Package Caches in Xcode

1. **Close Xcode** (Cmd+Q)
2. **Open Xcode** and load `XRAiAssistant.xcodeproj`
3. **Wait 10-15 seconds** for it to fully load
4. Go to **File** → **Packages** → **Reset Package Caches**
5. Wait for reset to complete (~30 seconds)
6. Go to **File** → **Packages** → **Resolve Package Versions**
7. Wait for resolution (may take 1-2 minutes)
8. **Product** → **Build** (Cmd+B)

**Expected Result**: ✅ BUILD SUCCEEDED

---

### Option 2: Manual Cache Clear (If Option 1 Fails)

**Close Xcode first**, then run these commands:

```bash
cd /Users/brendonsmith/exp/maigeXR/iOSMaigeXr

# Kill any Xcode processes
killall Xcode 2>/dev/null

# Clear ALL package caches
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf ~/Library/Developer/Xcode/DerivedData/*
rm -rf XRAiAssistant.xcodeproj/project.xcworkspace/xcshareddata/swiftpm

# Reopen Xcode
open XRAiAssistant.xcodeproj
```

Then follow steps 4-8 from Option 1.

---

### Option 3: Use Different Network (If Still Failing)

If the download keeps failing:

1. **Try different WiFi network** (or mobile hotspot)
2. **Disable VPN** if using one
3. **Check firewall** settings (may be blocking git protocol)
4. **Try again later** (GitHub may be experiencing issues)

---

## Verification

After successful package resolution:

1. **Check Package Dependencies**:
   - In Project Navigator, expand **Package Dependencies**
   - You should see **GRDB** (version 7.0.0)

2. **Check Frameworks**:
   - Select **XRAiAssistant** project
   - Select **XRAiAssistant** target
   - Go to **General** tab
   - Scroll to **Frameworks, Libraries, and Embedded Content**
   - Verify **GRDB** and **GRDB-dynamic** are listed

3. **Build the Project**:
   - **Product** → **Build** (Cmd+B)
   - Expected: **BUILD SUCCEEDED**

---

## Current Status

✅ **GRDB is properly configured** in project.pbxproj
✅ **Package dependencies are correct**
❌ **Network download is failing** (temporary issue)

**Next Step**: Follow Option 1 to reset caches and retry download in Xcode.

---

## If All Else Fails

If network issues persist, you can try downloading GRDB manually:

```bash
# Clone GRDB repository manually
cd ~/Developer
git clone https://github.com/groue/GRDB.swift.git
cd GRDB.swift
git checkout v7.0.0

# Then in Xcode:
# File → Add Package Dependencies → Add Local...
# Select ~/Developer/GRDB.swift
```

This uses a local copy instead of downloading from GitHub.
