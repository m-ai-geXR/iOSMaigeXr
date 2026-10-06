/*
 * m{ai}geXR playground command line.
 *
 * One line at the bottom of the scene for running JavaScript against the live
 * scene. Injected by the native app into every playground (the same file ships on
 * Android and iOS) and switched on or off from Settings via
 * maigeCommandLine.setEnabled(bool).
 *
 * Commands run in the scene's own global scope: the Nova64 console's frame when
 * there is one, otherwise the playground page. So whatever the scene exposes
 * (nova64, scene, engine, camera, THREE, BABYLON, ...) is directly reachable.
 *
 *   Enter     run          Tab   complete a name or property path
 *   Up/Down   history      Esc   hand the keyboard back to the scene
 *   globals() lists what the scene and its libraries put on the global object
 */
(function () {
    'use strict';
    if (window.maigeCommandLine) return;

    var HISTORY_KEY = 'maigexr.commandline.history';
    var HISTORY_MAX = 50;
    var OUTPUT_MAX = 6;
    var COMPLETIONS_SHOWN = 12;

    var root = null;
    var input = null;
    var output = null;
    var enabled = false;
    var history = loadHistory();
    var historyIndex = history.length;
    var draft = '';

    // ------------------------------------------------------------------
    // Where commands run
    // ------------------------------------------------------------------

    /** The Nova64 console frame when present (same-origin), else this page. */
    function targetWindow() {
        var frame = document.getElementById('novaRunner');
        if (frame) {
            try {
                if (frame.contentWindow && frame.contentWindow.document) return frame.contentWindow;
            } catch (e) { /* cross-origin: fall back to the page */ }
        }
        return window;
    }

    /** Names a blank window of the same kind starts with, so globals() can skip them. */
    var builtinNames = null;
    function builtins() {
        if (builtinNames) return builtinNames;
        builtinNames = {};
        try {
            var probe = document.createElement('iframe');
            probe.style.display = 'none';
            document.documentElement.appendChild(probe);
            Object.getOwnPropertyNames(probe.contentWindow).forEach(function (name) { builtinNames[name] = true; });
            probe.remove();
        } catch (e) { /* without a probe every name is listed; still usable */ }
        return builtinNames;
    }

    function listGlobals(win) {
        var skip = builtins();
        return Object.getOwnPropertyNames(win)
            .filter(function (name) {
                return !skip[name] && name.indexOf('__maige') !== 0 && !/^on[a-z]/.test(name) && name !== 'maigeCommandLine';
            })
            .sort();
    }

    /** Helpers available as plain names on the command line. */
    function installHelpers(win) {
        if (win.__maigeHelpers) return;
        win.__maigeHelpers = true;
        try {
            Object.defineProperty(win, 'globals', {
                configurable: true,
                writable: true,
                value: function () { return listGlobals(win); }
            });
            Object.defineProperty(win, 'clear', {
                configurable: true,
                writable: true,
                value: function () { clearOutput(); return undefined; }
            });
        } catch (e) { /* the scene defined its own; leave it */ }
    }

    // ------------------------------------------------------------------
    // Output
    // ------------------------------------------------------------------

    function describe(value) {
        if (value === undefined) return 'undefined';
        if (value === null) return 'null';
        var type = typeof value;
        if (type === 'string') return JSON.stringify(value);
        if (type === 'function') return 'ƒ ' + (value.name || 'anonymous') + '()';
        if (type !== 'object') return String(value);
        if (Array.isArray(value)) {
            var items = value.slice(0, 20).map(function (item) {
                return typeof item === 'object' && item !== null ? summarise(item) : describe(item);
            });
            return '[' + items.join(', ') + (value.length > 20 ? ', … ' + (value.length - 20) + ' more' : '') + ']';
        }
        return summarise(value);
    }

    function summarise(obj) {
        var name = (obj.constructor && obj.constructor.name) || 'Object';
        var keys = [];
        try { keys = Object.keys(obj); } catch (e) { /* exotic object */ }
        try {
            if (name === 'Object') {
                var json = JSON.stringify(obj);
                if (json && json.length <= 160) return json;
            }
        } catch (e) { /* cyclic */ }
        return name + ' {' + keys.slice(0, 8).join(', ') + (keys.length > 8 ? ', …' : '') + '}';
    }

    function print(kind, text) {
        if (!output) return;
        var line = document.createElement('div');
        line.className = 'maige-cl-line maige-cl-' + kind;
        line.textContent = text;
        output.appendChild(line);
        while (output.childNodes.length > OUTPUT_MAX) output.removeChild(output.firstChild);
        output.hidden = false;
        output.scrollTop = output.scrollHeight;

        // Mirror into the playground's own console window when it has one.
        if (typeof window.addConsoleMessage === 'function' && kind !== 'hint') {
            try { window.addConsoleMessage(kind === 'error' ? 'error' : 'log', text); } catch (e) { /* ignore */ }
        }
    }

    function clearOutput() {
        if (!output) return;
        output.textContent = '';
        output.hidden = true;
    }

    // ------------------------------------------------------------------
    // Running a command
    // ------------------------------------------------------------------

    function run(source) {
        var win = targetWindow();
        installHelpers(win);
        print('input', '› ' + source);
        var result;
        try {
            // Indirect eval: runs in the target's global scope, so `let`-free
            // assignments and declarations persist between commands.
            result = win.eval(source);
        } catch (e) {
            print('error', (e && e.name ? e.name + ': ' : '') + (e && e.message ? e.message : String(e)));
            return;
        }
        if (result && typeof result.then === 'function') {
            print('hint', '… waiting for promise');
            result.then(
                function (value) { print('result', describe(value)); },
                function (e) { print('error', 'Rejected: ' + (e && e.message ? e.message : String(e))); }
            );
            return;
        }
        if (result !== undefined || !/^\s*(clear\(\)|var |let |const |function )/.test(source)) {
            print('result', describe(result));
        }
    }

    // ------------------------------------------------------------------
    // Completion
    // ------------------------------------------------------------------

    function propertyNames(obj) {
        var names = {};
        var depth = 0;
        while (obj !== null && obj !== undefined && depth < 4) {
            try {
                Object.getOwnPropertyNames(obj).forEach(function (name) { names[name] = true; });
            } catch (e) { break; }
            obj = Object.getPrototypeOf(obj);
            depth++;
            if (obj === Object.prototype) break;
        }
        return Object.keys(names).filter(function (name) { return name !== 'constructor'; }).sort();
    }

    function commonPrefix(words) {
        if (!words.length) return '';
        var prefix = words[0];
        words.forEach(function (word) {
            while (word.indexOf(prefix) !== 0) prefix = prefix.slice(0, -1);
        });
        return prefix;
    }

    function complete() {
        var cursor = input.selectionStart;
        var before = input.value.slice(0, cursor);
        var match = /[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*\.?$/.exec(before);
        var path = match ? match[0] : '';
        var dot = path.lastIndexOf('.');
        var base = dot >= 0 ? path.slice(0, dot) : '';
        var partial = dot >= 0 ? path.slice(dot + 1) : path;

        var win = targetWindow();
        installHelpers(win);
        var scope;
        try {
            scope = base ? win.eval(base) : win;
        } catch (e) {
            return;
        }
        if (scope === null || scope === undefined) return;

        var candidates = (base ? propertyNames(scope) : listGlobals(win).concat(propertyNames(win)))
            .filter(function (name, i, all) { return name.indexOf(partial) === 0 && all.indexOf(name) === i; });
        if (!candidates.length) return;

        var fill = candidates.length === 1 ? candidates[0] : commonPrefix(candidates);
        if (fill.length > partial.length) {
            var insert = fill.slice(partial.length);
            input.value = before + insert + input.value.slice(cursor);
            input.selectionStart = input.selectionEnd = cursor + insert.length;
        }
        if (candidates.length > 1) {
            print('hint', candidates.slice(0, COMPLETIONS_SHOWN).join('   ') +
                (candidates.length > COMPLETIONS_SHOWN ? '   … ' + (candidates.length - COMPLETIONS_SHOWN) + ' more' : ''));
        }
    }

    // ------------------------------------------------------------------
    // History
    // ------------------------------------------------------------------

    function loadHistory() {
        try {
            var saved = JSON.parse(window.localStorage.getItem(HISTORY_KEY) || '[]');
            return Array.isArray(saved) ? saved : [];
        } catch (e) {
            return [];
        }
    }

    function remember(source) {
        if (history[history.length - 1] !== source) history.push(source);
        if (history.length > HISTORY_MAX) history = history.slice(-HISTORY_MAX);
        historyIndex = history.length;
        try { window.localStorage.setItem(HISTORY_KEY, JSON.stringify(history)); } catch (e) { /* storage off */ }
    }

    function step(delta) {
        if (!history.length) return;
        if (historyIndex === history.length) draft = input.value;
        historyIndex = Math.max(0, Math.min(history.length, historyIndex + delta));
        input.value = historyIndex === history.length ? draft : history[historyIndex];
        input.selectionStart = input.selectionEnd = input.value.length;
    }

    // ------------------------------------------------------------------
    // UI
    // ------------------------------------------------------------------

    function container() {
        return document.getElementById('canvasContainer') ||
            document.getElementById('sceneContainer') ||
            document.body;
    }

    function injectStyles() {
        if (document.getElementById('maige-cl-style')) return;
        var style = document.createElement('style');
        style.id = 'maige-cl-style';
        style.textContent = [
            '#maige-cl{position:absolute;left:0;right:0;bottom:0;z-index:900;',
            'font:13px/1.4 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;color:#f3f2f2;',
            'background:rgba(11,13,18,.82);border-top:1px solid rgba(91,130,245,.6);',
            '-webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px)}',
            '#maige-cl-out{max-height:7.5em;overflow-y:auto;padding:4px 10px 0}',
            '.maige-cl-line{white-space:pre-wrap;word-break:break-word}',
            '.maige-cl-input{color:#9b9797}',
            '.maige-cl-result{color:#f3f2f2}',
            '.maige-cl-error{color:#f97066}',
            '.maige-cl-hint{color:#8aa6ff}',
            '#maige-cl-row{display:flex;align-items:center;gap:6px;padding:4px 10px}',
            '#maige-cl-prompt{color:#5b82f5;font-weight:700}',
            '#maige-cl-input{flex:1;min-width:0;background:transparent;border:0;outline:0;',
            'color:#f3f2f2;font:inherit;padding:6px 0;caret-color:#5b82f5}',
            '#maige-cl-input::placeholder{color:#9b9797}',
            '#maige-cl:focus-within{border-top-color:#8aa6ff}'
        ].join('');
        document.head.appendChild(style);
    }

    function build() {
        injectStyles();
        var host = container();
        if (host !== document.body && getComputedStyle(host).position === 'static') {
            host.style.position = 'relative';
        }

        root = document.createElement('div');
        root.id = 'maige-cl';
        root.setAttribute('role', 'region');
        root.setAttribute('aria-label', 'Scene command line');

        output = document.createElement('div');
        output.id = 'maige-cl-out';
        output.setAttribute('role', 'log');
        output.setAttribute('aria-live', 'polite');
        output.hidden = true;

        var row = document.createElement('div');
        row.id = 'maige-cl-row';

        var prompt = document.createElement('span');
        prompt.id = 'maige-cl-prompt';
        prompt.textContent = '›';
        prompt.setAttribute('aria-hidden', 'true');

        input = document.createElement('input');
        input.id = 'maige-cl-input';
        input.type = 'text';
        input.autocomplete = 'off';
        input.autocapitalize = 'off';
        input.spellcheck = false;
        input.setAttribute('autocorrect', 'off');
        input.setAttribute('enterkeyhint', 'go');
        input.setAttribute('aria-label', 'Run JavaScript in the scene');
        input.placeholder = 'Run JS in the scene — try globals()   ·   Tab completes   ·   ↑↓ history';

        input.addEventListener('keydown', onKeyDown);
        // Typing here must not drive the scene's own keyboard controls.
        input.addEventListener('keyup', function (e) { e.stopPropagation(); });
        input.addEventListener('keypress', function (e) { e.stopPropagation(); });

        row.appendChild(prompt);
        row.appendChild(input);
        root.appendChild(output);
        root.appendChild(row);
        host.appendChild(root);
    }

    function onKeyDown(e) {
        e.stopPropagation();
        if (e.key === 'Enter') {
            e.preventDefault();
            var source = input.value.trim();
            if (!source) return;
            input.value = '';
            draft = '';
            remember(source);
            run(source);
        } else if (e.key === 'Tab') {
            e.preventDefault();
            complete();
        } else if (e.key === 'ArrowUp') {
            e.preventDefault();
            step(-1);
        } else if (e.key === 'ArrowDown') {
            e.preventDefault();
            step(1);
        } else if (e.key === 'Escape') {
            e.preventDefault();
            input.blur();
            if (typeof window.focusScene === 'function') window.focusScene();
        }
    }

    function setEnabled(on) {
        enabled = !!on;
        if (enabled && !root) build();
        if (root) root.hidden = !enabled;
        return enabled;
    }

    window.maigeCommandLine = {
        setEnabled: setEnabled,
        isEnabled: function () { return enabled; },
        run: function (source) { setEnabled(true); remember(source); run(source); },
        focus: function () { if (enabled && input) input.focus(); }
    };
})();
