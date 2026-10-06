import Foundation

/// Nova64 — retro 3D fantasy console (https://nova64.io)
///
/// Nova64 differs from the other libraries here: it is a console runtime rather
/// than a script you drop on a page. The playground embeds Nova64's hosted
/// "studio" runner and pushes cart source into it over postMessage, so carts must
/// be written as plain `init` / `update` / `draw` declarations with no `export`
/// keyword — studio evaluates carts as a script, not a module.
struct Nova64Library: Library3D {
    let id = "nova64"
    let displayName = "Nova64"
    let description = "Retro 3D fantasy console — N64/PS1-era games in JavaScript"
    let version = "v0.5.6"
    let playgroundTemplate = "playground-nova64.html"
    let codeLanguage = CodeLanguage.javascript
    let iconName = "gamecontroller.fill"
    let documentationURL = "https://nova64.io/docs/api-3d"

    let supportedFeatures: Set<Library3DFeature> = [
        .webgl, .webxr, .vr, .ar, .physics, .animation,
        .lighting, .materials, .postProcessing, .imperative
    ]

    var systemPrompt: String {
        return """
        You are an expert Nova64 assistant helping users create retro 3D games and scenes.
        You are a **creative fantasy-console mentor**: Nova64 renders Nintendo 64 and
        PlayStation-era low-poly 3D on top of Three.js, so lean into that aesthetic —
        flat shading, low segment counts, punchy saturated palettes, fog for depth,
        chunky 2D HUDs — while always delivering **fully working Nova64 cart code**.

        When users ask you ANYTHING about creating 3D scenes, games, objects, animations, or Nova64, ALWAYS respond with:
        1. A brief explanation of what you're creating
        2. The complete working cart code wrapped in [INSERT_CODE]```javascript\\ncode here\\n```[/INSERT_CODE]
        3. A brief explanation of the key console features you used
        4. Automatically add [RUN_SCENE] at the end to run the code

        CRITICAL — cart shape:
        - A cart is three plain function declarations:
            function init() { }        // once, for setup — may be async
            function update(dt) { }    // every frame, dt in seconds
            function draw() { }        // optional 2D HUD overlay
        - Do NOT use the `export` keyword. Studio evaluates carts as a script, so the
          plain declaration form is the one to write. Since nova64 0.5.6 a top-level
          export is stripped rather than rejected, so it no longer breaks the cart —
          but `import` still cannot work in a script.
        - Declare mutable state with `let` at the top level, assign it inside init().
        - Create meshes in init(); only transform them in update().

        CRITICAL — the API is namespaced under nova64.*:
        Bare globals were retired, so `createCube(...)` on its own will throw.
        - nova64.scene.*  createCube, createSphere, createPlane, createCylinder, createCone,
          createCapsule, createTorus, loadModel, loadTexture, destroyMesh, setPosition,
          setRotation, setScale, getPosition, rotateMesh, moveMesh, setMeshVisible,
          setMeshOpacity, setFlatShading, setPBRProperties, createInstancedMesh,
          clearScene, setClearColor, raycastFromCamera
        - nova64.camera.* setCameraPosition, setCameraTarget, setCameraLookAt, setCameraFOV
        - nova64.light.*  setAmbientLight, setLightDirection, setLightColor, setDirectionalLight,
          createPointLight, setPointLightPosition, removeLight, setFog, clearFog,
          createSpaceSkybox, createGradientSkybox, createSolidSkybox, animateSkybox, clearSkybox
        - nova64.fx.*     enableBloom, setBloomStrength, enableVignette,
          enableChromaticAberration, enableFXAA, disableBloom
        - nova64.draw.*   cls, print, printCentered, line, circle, rectfill, drawRect, rgba8,
          hexColor, drawGlowText, drawProgressBar, drawHealthBar, drawScanlines,
          screenWidth, screenHeight
        - nova64.input.*  key, keyp, btn, btnp
        - nova64.util.*   lerp, clamp, randRange, randInt, dist, dist3d, remap, pulse, noise, ease
        - nova64.audio.*  sfx, setVolume
        - also nova64.tween.*, nova64.physics.*, nova64.voxel.*, nova64.ui.*,
          nova64.xr.* (enableVR, enableAR, disableXR)

        EXACT SIGNATURES:
        - createCube(size, color, position, options) or createCube(w, h, d, color, position, options) -> meshId
        - createSphere(radius, color, position, segments, options) -> meshId
        - createPlane(width, height, color, position) -> meshId
        - createCylinder(radiusTop, radiusBottom, height, color, position, options) -> meshId
        - createCone(radius, height, color, position, options) -> meshId
        - createTorus(radius, tube, color, position, options) -> meshId
        - setPosition(meshId, x, y, z); setRotation(meshId, rx, ry, rz) in RADIANS;
          rotateMesh(meshId, dx, dy, dz); setScale(meshId, sx, sy, sz); getPosition(meshId) -> [x, y, z]
        - setPBRProperties(meshId, { metalness, roughness, envMapIntensity, color })
        - setAmbientLight(color, intensity); setLightDirection(x, y, z)
        - createPointLight(color, intensity, distance, x, y, z) -> lightId
        - loadModel(url, position, scale) -> Promise<meshId>
        - print(text, x, y, color, scale) — color is packed, from nova64.draw.rgba8(r, g, b, a),
          NOT a palette index
        - 3D colors are hex numbers like 0xff3366

        CRITICAL RULES:
        - Provide the COMPLETE cart every time, not a fragment
        - Always set up a camera and lighting in init() so the scene is visible
        - Multiply all motion by dt so it stays framerate independent
        - Prefer low segment counts and setFlatShading for the authentic retro look
        - Use fog to hide the draw distance, and a bloom or vignette pass for mood
        - Include brief comments explaining the console concepts you use
        """
    }

    var defaultSceneCode: String {
        return """
        // Nova64 cart — retro 3D fantasy console
        // Lifecycle: init() once, update(dt) every frame, draw() for the 2D HUD.
        // No export keyword — studio evaluates carts as a script, not a module.

        let cubeId;
        let orbId;
        let groundId;
        let elapsed = 0;

        function init() {
          // Backdrop and camera
          nova64.scene.setClearColor(0x090a0f);
          nova64.camera.setCameraPosition(0, 5, 11);
          nova64.camera.setCameraTarget(0, 1, 0);
          nova64.camera.setCameraFOV(60);

          // Warm key light, cool fill — that cartridge-era look
          nova64.light.setAmbientLight(0x404060, 0.8);
          nova64.light.setLightDirection(-0.5, -1, -0.3);
          nova64.light.setLightColor(0xffeedd);

          // Fog gives cheap depth and hides the draw distance
          nova64.light.setFog(0x090a0f, 18, 48);

          // Hero cube
          cubeId = nova64.scene.createCube(2, 0xff3366, [0, 1.5, 0]);
          nova64.scene.setPBRProperties(cubeId, { metalness: 0.4, roughness: 0.35 });

          // Low-poly orb — few segments on purpose
          orbId = nova64.scene.createSphere(0.9, 0x33e1ff, [4, 1.2, -1], 10);

          // Ground
          groundId = nova64.scene.createPlane(60, 60, 0x1b2735, [0, -0.01, 0]);
          nova64.scene.setFlatShading(groundId, true);

          // Post-processing
          nova64.fx.enableBloom();
          nova64.fx.setBloomStrength(0.6);
          nova64.fx.enableVignette();
        }

        function update(dt) {
          elapsed += dt;

          // Scale by dt so motion is framerate independent
          nova64.scene.rotateMesh(cubeId, 0, dt * 1.2, 0);
          nova64.scene.setPosition(cubeId, 0, 1.5 + Math.sin(elapsed * 2) * 0.4, 0);

          // Orbit the orb around the cube
          nova64.scene.setPosition(
            orbId,
            Math.cos(elapsed) * 4,
            1.2,
            Math.sin(elapsed) * 4
          );
        }

        function draw() {
          const white = nova64.draw.rgba8(255, 255, 255, 255);
          nova64.draw.print('NOVA64 x m{ai}geXR', 8, 8, white, 1);
        }
        """
    }

    var examples: [CodeExample] {
        return [
            CodeExample(
                title: "Retro Corridor Runner",
                description: "Fly a flat-shaded ship down a scrolling pillar corridor",
                code: """
                let shipId;
                let pillars = [];
                let elapsed = 0;

                function init() {
                  nova64.scene.setClearColor(0x05060f);
                  nova64.camera.setCameraPosition(0, 3.5, 9);
                  nova64.camera.setCameraTarget(0, 1, 0);

                  nova64.light.setAmbientLight(0x303050, 0.9);
                  nova64.light.setLightDirection(-0.4, -1, -0.5);
                  nova64.light.setFog(0x05060f, 14, 60);

                  // A flat-shaded cone reads as a retro fighter
                  shipId = nova64.scene.createCone(0.8, 2, 0xffcc33, [0, 1, 0]);
                  nova64.scene.setFlatShading(shipId, true);
                  nova64.scene.setRotation(shipId, Math.PI / 2, 0, 0);

                  // A corridor of pillars to fly through
                  for (let i = 0; i < 14; i++) {
                    const side = i % 2 === 0 ? -5 : 5;
                    const id = nova64.scene.createCube(1.2, 6, 1.2, 0x2a3f6b, [side, 2, -i * 6]);
                    nova64.scene.setFlatShading(id, true);
                    pillars.push(id);
                  }

                  nova64.scene.createPlane(80, 160, 0x101828, [0, -1, -40]);

                  nova64.fx.enableBloom();
                  nova64.fx.setBloomStrength(0.8);
                  nova64.fx.enableVignette();
                }

                function update(dt) {
                  elapsed += dt;

                  let x = Math.sin(elapsed) * 2.5;
                  if (nova64.input.btn(0)) x -= 3 * dt;
                  if (nova64.input.btn(1)) x += 3 * dt;
                  nova64.scene.setPosition(shipId, x, 1 + Math.sin(elapsed * 3) * 0.2, 0);

                  // Scroll the pillars toward the camera and recycle them
                  for (let i = 0; i < pillars.length; i++) {
                    const p = nova64.scene.getPosition(pillars[i]);
                    let z = p[2] + dt * 14;
                    if (z > 12) z -= 84;
                    nova64.scene.setPosition(pillars[i], p[0], p[1], z);
                  }
                }

                function draw() {
                  const cyan = nova64.draw.rgba8(80, 230, 255, 255);
                  nova64.draw.print('NOVA64', 8, 8, cyan, 1);
                  nova64.draw.print('DIST ' + Math.floor(elapsed * 14), 8, 22, cyan, 1);
                }
                """,
                category: .animation,
                difficulty: .beginner,
                keywords: ["runner", "corridor", "retro", "scrolling", "flat shading", "fog"],
                aiPromptHints: "Scrolling-corridor pattern: recycle meshes by advancing z and wrapping, rather than creating and destroying them each frame."
            ),
            CodeExample(
                title: "Low-Poly Solar System",
                description: "Orbiting planets with a point light at the star",
                code: """
                let sunId;
                let planets = [];
                let elapsed = 0;

                function init() {
                  nova64.scene.setClearColor(0x02030a);
                  nova64.camera.setCameraPosition(0, 12, 22);
                  nova64.camera.setCameraTarget(0, 0, 0);

                  // Starfield backdrop
                  nova64.light.createSpaceSkybox();
                  nova64.light.setAmbientLight(0x101020, 0.4);

                  // The star, plus a point light inside it
                  sunId = nova64.scene.createSphere(2.4, 0xffcc44, [0, 0, 0], 12);
                  nova64.light.createPointLight(0xffdd88, 2.2, 90, 0, 0, 0);

                  // Planets: [radius, color, orbitDistance, orbitSpeed]
                  const defs = [
                    [0.5, 0xc96a4a, 5.5, 1.5],
                    [0.8, 0x4a9ec9, 8.5, 1.0],
                    [0.7, 0x8a5fd6, 12.0, 0.7],
                    [1.2, 0xd6a65f, 16.5, 0.45]
                  ];

                  for (let i = 0; i < defs.length; i++) {
                    const d = defs[i];
                    const id = nova64.scene.createSphere(d[0], d[1], [d[2], 0, 0], 10);
                    nova64.scene.setFlatShading(id, true);
                    planets.push({ id: id, dist: d[2], speed: d[3] });
                  }

                  nova64.fx.enableBloom();
                  nova64.fx.setBloomStrength(1.1);
                }

                function update(dt) {
                  elapsed += dt;

                  nova64.scene.rotateMesh(sunId, 0, dt * 0.2, 0);

                  for (let i = 0; i < planets.length; i++) {
                    const p = planets[i];
                    const a = elapsed * p.speed;
                    nova64.scene.setPosition(
                      p.id,
                      Math.cos(a) * p.dist,
                      0,
                      Math.sin(a) * p.dist
                    );
                    nova64.scene.rotateMesh(p.id, 0, dt * 1.5, 0);
                  }
                }

                function draw() {
                  const amber = nova64.draw.rgba8(255, 210, 120, 255);
                  nova64.draw.print('SYSTEM NOVA', 8, 8, amber, 1);
                }
                """,
                category: .animation,
                difficulty: .beginner,
                keywords: ["solar system", "orbit", "planets", "point light", "skybox", "space"],
                aiPromptHints: "Store per-object orbit parameters in a plain array of objects in init(), then drive positions trigonometrically from accumulated time."
            ),
            CodeExample(
                title: "Interactive Color Grid",
                description: "A grid of cubes that pulse and respond to key presses",
                code: """
                let cubes = [];
                let elapsed = 0;
                let paletteIndex = 0;

                const PALETTES = [
                  [0xff3366, 0xff9933, 0xffee33],
                  [0x33e1ff, 0x3366ff, 0x8a5fd6],
                  [0x33ff88, 0x22cc66, 0x116644]
                ];

                function init() {
                  nova64.scene.setClearColor(0x0a0a14);
                  nova64.camera.setCameraPosition(0, 14, 16);
                  nova64.camera.setCameraTarget(0, 0, 0);

                  nova64.light.setAmbientLight(0x404060, 0.7);
                  nova64.light.setLightDirection(-0.3, -1, -0.4);

                  // 8x8 grid — build once, animate forever
                  const palette = PALETTES[0];
                  for (let x = -4; x < 4; x++) {
                    for (let z = -4; z < 4; z++) {
                      const color = palette[(Math.abs(x) + Math.abs(z)) % palette.length];
                      const id = nova64.scene.createCube(0.9, color, [x * 1.3, 0, z * 1.3]);
                      cubes.push({ id: id, x: x, z: z });
                    }
                  }

                  nova64.scene.createPlane(40, 40, 0x060610, [0, -1.5, 0]);
                  nova64.fx.enableBloom();
                  nova64.fx.enableVignette();
                }

                function update(dt) {
                  elapsed += dt;

                  // SPACE cycles the palette
                  if (nova64.input.keyp('Space')) {
                    paletteIndex = (paletteIndex + 1) % PALETTES.length;
                    const palette = PALETTES[paletteIndex];
                    for (let i = 0; i < cubes.length; i++) {
                      const c = cubes[i];
                      const color = palette[(Math.abs(c.x) + Math.abs(c.z)) % palette.length];
                      nova64.scene.setPBRProperties(c.id, { color: color });
                    }
                  }

                  // A wave travelling out from the centre
                  for (let i = 0; i < cubes.length; i++) {
                    const c = cubes[i];
                    const d = nova64.util.dist(0, 0, c.x, c.z);
                    const y = Math.sin(elapsed * 3 - d * 0.8) * 0.9;
                    nova64.scene.setPosition(c.id, c.x * 1.3, y, c.z * 1.3);
                  }
                }

                function draw() {
                  const white = nova64.draw.rgba8(240, 240, 255, 255);
                  nova64.draw.print('SPACE = PALETTE', 8, 8, white, 1);
                }
                """,
                category: .interaction,
                difficulty: .intermediate,
                keywords: ["grid", "wave", "input", "palette", "keyp", "interactive"],
                aiPromptHints: "Use nova64.input.keyp for one-shot presses and nova64.input.key for held keys. Recolour existing meshes with setPBRProperties rather than rebuilding them."
            ),
            CodeExample(
                title: "VR Mode",
                description: "Enter immersive VR from a Nova64 cart",
                code: """
                let ringIds = [];
                let elapsed = 0;
                let inVR = false;

                function init() {
                  nova64.scene.setClearColor(0x050510);
                  nova64.camera.setCameraPosition(0, 1.6, 6);
                  nova64.camera.setCameraTarget(0, 1.6, 0);

                  nova64.light.setAmbientLight(0x404060, 0.9);
                  nova64.light.setLightDirection(-0.4, -1, -0.3);
                  nova64.light.setFog(0x050510, 10, 40);

                  // A tunnel of torus rings, nice to look around inside in VR.
                  // Mesh colors are plain hex numbers.
                  const RING_COLORS = [
                    0xff3366, 0xff6633, 0xffcc33, 0x99ff33, 0x33ff88,
                    0x33e1ff, 0x3366ff, 0x8a5fd6, 0xd633ff, 0xff33aa
                  ];
                  for (let i = 0; i < RING_COLORS.length; i++) {
                    const id = nova64.scene.createTorus(2.2, 0.16, RING_COLORS[i], [0, 1.6, -i * 3.5]);
                    ringIds.push(id);
                  }

                  nova64.scene.createPlane(60, 60, 0x0b0b18, [0, -0.5, 0]);

                  nova64.fx.enableBloom();
                  nova64.fx.setBloomStrength(1.2);

                  // Ask for an immersive session. Harmless where WebXR is unavailable.
                  if (nova64.xr.isXRSupported && nova64.xr.isXRSupported()) {
                    nova64.xr.enableVR();
                    inVR = true;
                  }
                }

                function update(dt) {
                  elapsed += dt;

                  for (let i = 0; i < ringIds.length; i++) {
                    nova64.scene.rotateMesh(ringIds[i], 0, 0, dt * (0.3 + i * 0.05));
                    const p = nova64.scene.getPosition(ringIds[i]);
                    let z = p[2] + dt * 4;
                    if (z > 4) z -= 35;
                    nova64.scene.setPosition(ringIds[i], 0, 1.6, z);
                  }
                }

                function draw() {
                  // Skip the flat HUD while immersed — it belongs on the 2D screen
                  if (inVR && nova64.xr.isXRActive && nova64.xr.isXRActive()) return;
                  const white = nova64.draw.rgba8(255, 255, 255, 255);
                  nova64.draw.print('VR TUNNEL', 8, 8, white, 1);
                }
                """,
                category: .vr,
                difficulty: .intermediate,
                keywords: ["vr", "webxr", "immersive", "torus", "tunnel", "xr"],
                aiPromptHints: "Guard XR calls with isXRSupported() and skip 2D HUD drawing while isXRActive(), since the flat overlay has no place in an immersive view."
            )
        ]
    }
}
