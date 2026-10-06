# Store listing copy

Draft text for App Store Connect and the Play Console, for both apps. Every claim
below matches what v1 does today; check it again if a feature changes. Character
limits are noted where the stores enforce them.

---

## Name

**m{ai}geXR** (both stores)

## Subtitle (App Store, 30)

`3D scenes from plain words` (26)

## Short description (Play, 80)

`Describe a 3D scene and watch it run. AI-built Babylon.js, Three.js and more.` (77)

## Promotional text (App Store, 170)

`Describe a scene, run it, then tweak the code. Start with built-in demos and add your own AI key when you are ready to create.` (128)

## Description (App Store 4000, Play 4000)

> Turn a sentence into a running 3D scene.
>
> m{ai}geXR is a pocket studio for interactive 3D. Describe what you want, "a
> glowing torus field that pulses to the beat", and the AI writes the code and
> runs it in a live playground beside the chat. Change the prompt, edit the code,
> run it again.
>
> **Five 3D engines**
> Babylon.js, Three.js, A-Frame, React Three Fiber and the Nova64 retro fantasy
> console. Pick one and the assistant writes for it.
>
> **A real playground**
> Every scene opens in an editor with the full code, a console, and a one-line
> command bar for poking at the live scene. Export a scene as a standalone project
> to keep working on a computer.
>
> **Learn from examples**
> Dozens of built-in scenes, searchable by topic and difficulty, run with one tap,
> no account and no key needed.
>
> **Your keys, your models**
> Bring your own API key from Together AI, OpenAI, Anthropic, Google AI or xAI and
> choose the model. Keys are stored on your device and sent only to the provider
> they belong to. m{ai}geXR has no accounts and runs no servers of its own.
>
> **Keep what you make**
> Conversations are saved on your device with a thumbnail of each scene. Star the
> ones you like to find them again in Favorites.
>
> The app is free with ads. A single in-app purchase removes them.

## Keywords (App Store, 100, comma-separated, no spaces needed)

`3d,ai,babylonjs,threejs,aframe,webgl,creative coding,code,scene,generator,playground,shader,game` (96)

## What's new (first release)

`First release: describe a 3D scene, run it, and learn from built-in examples.`

## Category

App Store: **Developer Tools** (secondary: Education). Play: **Tools**.

## Support and marketing URLs

- Support URL: the site home page or a GitHub issues link (required by Apple).
- Marketing URL: the site home page (optional).
- Privacy policy URL: `<site>/privacy` (required by both).

## Notes

- The description says "dozens of built-in scenes". Recount before submitting if
  examples are added or removed; there are about 50 across the five engines.
- Do not mention VR on iOS: WebXR is not available in iOS web views. On Android,
  mention VR only after an A-Frame or Nova64 VR scene has been tested on a
  headset; it has not been verified.
- Screenshots: see `SUBMISSION.md` section 7 for sizes. Debug iOS builds open any
  screen with `-maigeScreen <scene|examples|settings|history|favorites>`.
