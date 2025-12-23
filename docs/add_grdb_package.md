# Adding GRDB.swift Package to Xcode Project

## Quick Guide

Since we can't add Swift packages via command line in Xcode 15+, you need to add GRDB.swift through Xcode's GUI:

### Steps:

1. **Open Xcode** (should already be open from earlier)
   ```bash
   open XRAiAssistant.xcodeproj
   ```

2. **Navigate to Package Dependencies:**
   - Click on **XRAiAssistant** (blue project icon) in the left sidebar
   - Select the **XRAiAssistant** target (under TARGETS)
   - Click the **Package Dependencies** tab at the top

3. **Add GRDB Package:**
   - Click the **"+"** button at the bottom left
   - In the search box (top right), paste:
     ```
     https://github.com/groue/GRDB.swift
     ```
   - Press **Enter** or click **"Add Package"**

4. **Configure Version:**
   - Dependency Rule: **"Up to Next Major Version"**
   - Version: **7.0.0**
   - Click **"Add Package"**

5. **Select Target:**
   - Ensure **GRDB** is checked for the **XRAiAssistant** target
   - Click **"Add Package"**

6. **Wait for Resolution:**
   - Xcode will download and resolve dependencies (10-30 seconds)
   - You'll see "GRDB" appear in the Package Dependencies list

### Verification:

After adding the package, verify it's there:

```bash
xcodebuild -resolvePackageDependencies 2>&1 | grep GRDB
```

You should see:
```
GRDB: https://github.com/groue/GRDB.swift @ 7.x.x
```

### Then Build:

```bash
xcodebuild -project XRAiAssistant.xcodeproj \
  -scheme XRAiAssistant \
  -configuration Debug \
  -sdk iphonesimulator \
  build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO
```

---

## Troubleshooting

### If the package doesn't appear in search:
- Make sure you have an internet connection
- Try closing and reopening Xcode
- File → Packages → Reset Package Caches

### If build still fails after adding:
- Product → Clean Build Folder (Cmd+Shift+K)
- Close Xcode
- Delete DerivedData:
  ```bash
  rm -rf ~/Library/Developer/Xcode/DerivedData/XRAiAssistant-*
  ```
- Reopen Xcode and build again

---

Once GRDB is added successfully, come back and let Claude know - we'll immediately proceed to Phase 3! 🚀
