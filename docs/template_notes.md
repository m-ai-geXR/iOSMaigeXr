# Template Literal Notes - Critical Issues and Solutions

## Overview

This document captures critical lessons learned about using template literals inside HTML `<script>` tags, particularly when generating HTML/JavaScript code dynamically in the m{ai}geXR playground files.

---

## The Critical Problem: `</script>` Tag Parsing

### Issue Description

When you have a JavaScript template literal inside an HTML `<script>` tag that contains the string `</script>`, the browser's HTML parser will interpret it as the **actual closing tag** for the outer script block, even though it's inside a JavaScript string.

This causes catastrophic failures:
- The JavaScript code gets truncated mid-execution
- The page fails to load
- Monaco editor doesn't initialize
- Canvas remains black/empty
- Console shows "EMERGENCY_FALLBACK" injection attempts

### Example of the Problem

```javascript
// ❌ BROKEN - This will break the page!
<script>
function generateHTML(code) {
    return `<!DOCTYPE html>
    <html>
    <head>
        <script src="library.js"></script>  <!-- Parser sees this as closing the outer script! -->
    </head>
    <body>
        <script>
            ${code}
        </script>  <!-- And this closes it again! -->
    </body>
    </html>`;
}
</script>
```

### The Solution: Escape the Forward Slash

**Always escape `</script>` as `<\/script>` in template literals:**

```javascript
// ✅ CORRECT - This works perfectly
<script>
function generateHTML(code) {
    return `<!DOCTYPE html>
    <html>
    <head>
        <script src="library.js"><\/script>  <!-- Escaped! -->
    </head>
    <body>
        <script>
            ${code}
        <\/script>  <!-- Escaped! -->
    </body>
    </html>`;
}
</script>
```

The escape sequence `<\/script>` outputs the exact same string `</script>` but doesn't confuse the HTML parser.

---

## Where This Issue Occurred

### Files Affected in m{ai}geXR

1. **playground-babylonjs.html**
   - `generateStandaloneHTML()` function (lines ~1106-1152)
   - Had 2 unescaped `</script>` tags

2. **playground-threejs.html**
   - `generateStandaloneHTML()` function (lines ~1520-1560)
   - Had 2 unescaped `</script>` tags

3. **playground-aframe.html**
   - `generateStandaloneHTML()` function (lines ~2257-2278)
   - Had 1 unescaped `</script>` tag

4. **playground-react-three-fiber.html**
   - Less problematic because R3F generates a simpler HTML structure
   - Still needs attention for any embedded script tags

### Specific Examples from Our Codebase

**Babylon.js - generateStandaloneHTML():**
```javascript
function generateStandaloneHTML(userCode) {
    const timestamp = new Date().toISOString();
    return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>maigeXR - Babylon.js Scene</title>
    <script src="https://cdn.babylonjs.com/babylon.js"><\/script>  <!-- MUST be escaped -->
    <style>
        /* styles */
    </style>
</head>
<body>
    <canvas id="renderCanvas"></canvas>
    <script>
        // Generated code
        const canvas = document.getElementById('renderCanvas');
        const engine = new BABYLON.Engine(canvas, true);

        ${userCode}

        engine.runRenderLoop(() => {
            if (scene && scene.activeCamera) {
                scene.render();
            }
        });
    <\/script>  <!-- MUST be escaped -->
</body>
</html>`;
}
```

**Three.js - generateStandaloneHTML():**
```javascript
function generateStandaloneHTML(userCode) {
    return `<!DOCTYPE html>
<html lang="en">
<head>
    <script type="importmap">
    {
        "imports": {
            "three": "https://cdn.jsdelivr.net/npm/three@0.158.0/build/three.module.js"
        }
    }
    <\/script>  <!-- MUST be escaped -->

    <script type="module">
        import * as THREE from 'three';
        ${userCode}
    <\/script>  <!-- MUST be escaped -->
</head>
</html>`;
}
```

---

## Detection and Debugging

### Symptoms of Unescaped Script Tags

1. **Page won't load** - Blank/black screen
2. **Console errors**:
   - "Current readiness result: NOT_READY"
   - "Max retries reached, injection failed"
   - "EMERGENCY_FALLBACK"
   - "JavaScript executed successfully" but nothing renders
3. **Monaco editor fails to initialize**
4. **Template code doesn't appear** in the editor
5. **No 3D canvas** renders

### How to Find the Issue

**Manual Search:**
```bash
grep -n "</script>" playground-*.html
```

**Python Detection Script:**
```python
# Check for unescaped </script> in template literals
import sys
content = open('playground-babylonjs.html', 'r').read()
lines = content.split('\n')
backtick_count = 0

for i, line in enumerate(lines, start=1):
    backtick_count += line.count('`')
    # If inside template literal (odd backtick count) and has </script>
    if '</script>' in line and backtick_count % 2 == 1:
        if '<\\/script>' not in line:  # Not already escaped
            print(f'Line {i}: Unescaped </script> in template literal')
            print(f'  {line.strip()}')
```

---

## Prevention Guidelines

### Rule #1: Always Escape Script Tags in Template Literals

**Any time you write a template literal that generates HTML:**
- Search for `</script>` in your template
- Replace with `<\/script>`
- This applies to **all** script tags, including:
  - External script sources: `<script src="..."><\/script>`
  - Inline scripts: `<script>code<\/script>`
  - Module scripts: `<script type="module">code<\/script>`

### Rule #2: Be Careful with Nested Contexts

Template literals that generate:
- HTML containing `<script>` tags
- JavaScript containing template literals
- CSS containing `</style>` tags (same issue!)
- SVG containing embedded scripts

All require careful escaping.

### Rule #3: Test After Every Template Change

After modifying any function that returns template literals containing HTML:
1. **Force quit** the app completely
2. **Clean build** (⇧⌘K in Xcode)
3. **Rebuild and run**
4. **Check console** for any "NOT_READY" or "EMERGENCY_FALLBACK" messages
5. **Verify** the default template loads in Monaco editor
6. **Test** the 3D canvas renders

---

## Related Issues

### Other Tags That Need Escaping

The same issue can occur with:
- `</style>` in CSS template literals → use `<\/style>`
- `</textarea>` in form templates → use `<\/textarea>`
- Any closing tag in string/template literals inside matching tag contexts

### Why This Is Confusing

The HTML parser runs **before** the JavaScript parser:
1. Browser reads HTML sequentially
2. Sees `<script>` - enters script parsing mode
3. Sees `</script>` - **immediately** exits script mode (doesn't check if it's in a string!)
4. JavaScript parser never gets correct code

This is why JavaScript escaping rules don't help - the HTML parser doesn't understand JavaScript syntax.

---

## Quick Reference

### Common Patterns

```javascript
// ❌ WRONG
`<script src="file.js"></script>`
`<script>code</script>`

// ✅ CORRECT
`<script src="file.js"><\/script>`
`<script>code<\/script>`

// ❌ WRONG
`<style>css</style>`

// ✅ CORRECT
`<style>css<\/style>`
```

### Files to Always Check

When adding or modifying template generation:
- `playground-babylonjs.html` - generateStandaloneHTML(), generateBabylonReadme()
- `playground-threejs.html` - generateStandaloneHTML(), generateThreeReadme()
- `playground-aframe.html` - generateStandaloneHTML(), generateAFrameReadme()
- `playground-react-three-fiber.html` - generateIndexHTML(), etc.

### Safe Alternative: String Concatenation

If template literals are too error-prone for complex HTML:

```javascript
// Alternative: Use array join (less elegant but safer)
function generateHTML(code) {
    return [
        '<!DOCTYPE html>',
        '<html>',
        '<head>',
        '<script src="lib.js"></script>',  // No escaping needed!
        '</head>',
        '<body>',
        '<script>',
        code,
        '</script>',
        '</body>',
        '</html>'
    ].join('\n');
}
```

---

## Commit Reference

This issue was identified and fixed in commit:
- **Date**: 2025-01-07
- **Commit**: "feat(playground): Implement complete scene save functionality across all 3D frameworks"
- **Files Modified**:
  - playground-babylonjs.html (lines 1112, 1149)
  - playground-threejs.html (lines 1548, 1556)
  - playground-aframe.html (line 2265)

See [docs/COMMIT_MESSAGES.md](COMMIT_MESSAGES.md) "Bug Fixes - Critical HTML Parser Issue" section for full details.

---

## Additional Resources

- MDN: [The Script Element](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/script)
- Stack Overflow: ["Why does "</script>" inside a string break the page?"](https://stackoverflow.com/questions/14780858)
- HTML Standard: [Script data state parsing](https://html.spec.whatwg.org/multipage/parsing.html#script-data-state)

---

**Last Updated**: 2025-01-07
**Maintainer**: See git history
**Severity**: CRITICAL - Can break entire playground functionality
