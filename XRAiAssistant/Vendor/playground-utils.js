/**
 * m{ai}geXR Playground Shared Utilities
 * Common functions used across all playground implementations
 *
 * This file eliminates ~750+ lines of duplicate code across:
 * - playground-babylonjs.html
 * - playground-threejs.html
 * - playground-aframe.html
 * - playground-react-three-fiber.html
 */

// ============================================================================
// LIBRARY MANAGEMENT
// ============================================================================

/**
 * Verify JSZip library is loaded
 * JSZip is loaded via <script src="app://jszip.min.js"> in HTML head
 */
async function loadJSZip() {
    if (window.JSZip) {
        console.log('✅ JSZip available:', typeof window.JSZip);
        return;
    }

    // If not loaded yet, wait a bit and retry
    console.log('⏳ Waiting for JSZip to load...');
    await new Promise(resolve => setTimeout(resolve, 100));

    if (window.JSZip) {
        console.log('✅ JSZip loaded successfully:', typeof window.JSZip);
        return;
    }

    throw new Error('JSZip library not available - script tag may have failed to load');
}

// ============================================================================
// SWIFT COMMUNICATION
// ============================================================================

/**
 * Send message to Swift via WKWebView message handler
 * @param {string} action - Action identifier
 * @param {Object} data - Data payload
 */
function notifySwift(action, data) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playgroundHandler) {
        window.webkit.messageHandlers.playgroundHandler.postMessage({
            action: action,
            data: data
        });
    } else {
        console.warn('⚠️ Swift message handler not available');
    }
}

// ============================================================================
// DATA CONVERSION
// ============================================================================

/**
 * Convert ArrayBuffer to base64 using chunked approach
 * Prevents call stack overflow for large files
 * @param {ArrayBuffer} arrayBuffer - Binary data
 * @param {number} chunkSize - Chunk size in bytes (default 32KB)
 * @returns {string} Base64 encoded string
 */
function arrayBufferToBase64Chunked(arrayBuffer, chunkSize = 0x8000) {
    const bytes = new Uint8Array(arrayBuffer);
    let binary = '';

    for (let i = 0; i < bytes.length; i += chunkSize) {
        const chunk = bytes.subarray(i, Math.min(i + chunkSize, bytes.length));
        binary += String.fromCharCode.apply(null, chunk);
    }

    return btoa(binary);
}

// ============================================================================
// UTILITIES
// ============================================================================

/**
 * Debounce function execution
 * @param {Function} func - Function to debounce
 * @param {number} wait - Wait time in milliseconds
 * @returns {Function} Debounced function
 */
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

/**
 * Escape HTML special characters
 * @param {string} text - Text to escape
 * @returns {string} Escaped HTML
 */
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// ============================================================================
// ERROR DISPLAY
// ============================================================================

/**
 * Show error message in error display element
 * @param {string} message - Error message
 * @param {number} duration - Display duration in milliseconds (default 5000)
 */
function showError(message, duration = 5000) {
    const errorDisplay = document.getElementById('errorDisplay');
    if (errorDisplay) {
        errorDisplay.textContent = message;
        errorDisplay.style.display = 'block';
        setTimeout(() => {
            errorDisplay.style.display = 'none';
        }, duration);
    } else {
        console.error('❌', message);
    }
}

/**
 * Hide error display
 */
function hideError() {
    const errorDisplay = document.getElementById('errorDisplay');
    if (errorDisplay) {
        errorDisplay.style.display = 'none';
    }
}

// ============================================================================
// CLIPBOARD UTILITIES
// ============================================================================

/**
 * Copy text to clipboard with fallback
 * @param {string} text - Text to copy
 * @returns {Promise<boolean>} Success status
 */
async function copyToClipboard(text) {
    try {
        // Try modern Clipboard API first
        if (navigator.clipboard && navigator.clipboard.writeText) {
            await navigator.clipboard.writeText(text);
            console.log('✅ Copied to clipboard');
            return true;
        } else {
            // Fallback to legacy method
            return fallbackCopy(text);
        }
    } catch (err) {
        console.error('❌ Failed to copy:', err);
        return fallbackCopy(text);
    }
}

/**
 * Fallback clipboard copy using textarea
 * @param {string} text - Text to copy
 * @returns {boolean} Success status
 */
function fallbackCopy(text) {
    const textArea = document.createElement('textarea');
    textArea.value = text;
    textArea.style.position = 'fixed';
    textArea.style.left = '-999999px';
    textArea.style.top = '-999999px';
    document.body.appendChild(textArea);
    textArea.focus();
    textArea.select();

    try {
        const successful = document.execCommand('copy');
        textArea.remove();
        if (successful) {
            console.log('✅ Copied to clipboard (fallback)');
        }
        return successful;
    } catch (err) {
        console.error('❌ Fallback copy failed:', err);
        textArea.remove();
        return false;
    }
}

/**
 * Show visual feedback for copy operation
 * @param {string} buttonId - Button element ID (optional)
 */
function showCopyFeedback(buttonId = null) {
    let button = null;
    if (buttonId) {
        button = document.getElementById(buttonId);
    }

    if (button) {
        const originalText = button.textContent;
        button.textContent = '✓ Copied!';
        button.style.background = '#4CAF50';

        setTimeout(() => {
            button.textContent = originalText;
            button.style.background = '';
        }, 2000);
    }
}

// ============================================================================
// MONACO EDITOR UTILITIES
// ============================================================================

/**
 * Insert code at cursor position in Monaco editor
 * @param {Object} editor - Monaco editor instance
 * @param {string} code - Code to insert
 */
function insertCodeAtCursor(editor, code) {
    if (!editor) {
        console.error('❌ Editor not available');
        return;
    }

    const selection = editor.getSelection();
    const id = { major: 1, minor: 1 };
    const op = {
        identifier: id,
        range: selection,
        text: code,
        forceMoveMarkers: true
    };
    editor.executeEdits('insert-code', [op]);
    editor.focus();
}

/**
 * Set full content of Monaco editor
 * @param {Object} editor - Monaco editor instance
 * @param {string} code - New editor content
 */
function setFullEditorContent(editor, code) {
    if (!editor) {
        console.error('❌ Editor not available');
        return;
    }

    editor.setValue(code);
    editor.focus();
}

/**
 * Toggle editor visibility
 * @param {Object} config - Configuration object
 * @param {string} config.editorContainerId - Editor container element ID
 * @param {string} config.canvasContainerId - Canvas container element ID
 * @param {string} config.storageKey - LocalStorage key for state persistence
 */
function toggleEditor(config) {
    const { editorContainerId, canvasContainerId, storageKey } = config;
    const editorContainer = document.getElementById(editorContainerId);
    const canvasContainer = document.getElementById(canvasContainerId);

    if (!editorContainer || !canvasContainer) {
        console.error('❌ Editor or canvas container not found');
        return;
    }

    if (editorContainer.style.display === 'none') {
        editorContainer.style.display = 'flex';
        canvasContainer.style.flex = '1';
        if (storageKey) {
            localStorage.setItem(storageKey, 'visible');
        }
    } else {
        editorContainer.style.display = 'none';
        canvasContainer.style.flex = '1 1 100%';
        if (storageKey) {
            localStorage.setItem(storageKey, 'hidden');
        }
    }
}

// ============================================================================
// ZIP PACKAGE CREATION
// ============================================================================

/**
 * Create zip package from files object
 * @param {Object} files - Files object with paths as keys and content as values
 * @param {Object} options - Zip generation options
 * @returns {Promise<string>} Base64 encoded zip file
 */
async function createZipPackage(files, options = {}) {
    await loadJSZip();

    const zip = new JSZip();

    // Add files to zip
    for (const [path, content] of Object.entries(files)) {
        zip.file(path, content);
    }

    // Generate zip with compression
    const zipBlob = await zip.generateAsync({
        type: 'blob',
        compression: 'DEFLATE',
        compressionOptions: { level: 9 },
        ...options
    });

    // Convert to base64
    const arrayBuffer = await zipBlob.arrayBuffer();
    return arrayBufferToBase64Chunked(arrayBuffer);
}

/**
 * Send scene save to Swift with zip package
 * @param {Object} params - Save parameters
 * @param {Object} params.files - Files object for zip package
 * @param {string} params.filename - Output filename
 * @param {string} params.format - Format identifier (default: 'zip')
 * @returns {Promise<void>}
 */
async function saveScenePackage(params) {
    const { files, filename, format = 'zip' } = params;

    console.log('💾 Creating scene package...');

    try {
        const base64Data = await createZipPackage(files);
        const size = Math.round((base64Data.length * 0.75) / 1024); // Approximate size in KB

        console.log(`✅ Package created: ${filename} (~${size} KB)`);

        notifySwift('sceneSaved', {
            format: format,
            filename: filename,
            data: base64Data,
            size: size,
            success: true
        });

        return true;
    } catch (error) {
        console.error('❌ Save failed:', error);
        showError(`Failed to save scene: ${error.message}`);

        notifySwift('sceneSaved', {
            format: format,
            filename: filename,
            success: false,
            error: error.message
        });

        return false;
    }
}

// ============================================================================
// CONSOLE MANAGEMENT
// ============================================================================

/**
 * Create a console manager instance
 * @param {Object} config - Configuration object
 * @param {string} config.storageKey - LocalStorage key for state persistence
 * @param {number} config.maxMessages - Maximum messages to keep (default: 50)
 * @returns {Object} Console manager object
 */
function createConsoleManager(config = {}) {
    const { storageKey = 'consoleState', maxMessages = 50 } = config;
    let messages = [];

    return {
        /**
         * Add console message
         * @param {string} type - Message type (log, warn, error, info)
         * @param {string} message - Message content
         */
        addMessage(type, message) {
            messages.push({ type, message, timestamp: Date.now() });
            if (messages.length > maxMessages) {
                messages = messages.slice(-maxMessages);
            }
            this.updateDisplay();
        },

        /**
         * Clear all console messages
         */
        clear() {
            messages = [];
            this.updateDisplay();
        },

        /**
         * Get all messages
         * @returns {Array} Array of message objects
         */
        getMessages() {
            return [...messages];
        },

        /**
         * Get messages as formatted text
         * @returns {string} Formatted console output
         */
        getMessagesAsText() {
            return messages.map(msg => {
                const time = new Date(msg.timestamp).toLocaleTimeString();
                return `[${time}] [${msg.type.toUpperCase()}] ${msg.message}`;
            }).join('\n');
        },

        /**
         * Copy console to clipboard
         * @returns {Promise<boolean>} Success status
         */
        async copyToClipboard() {
            const text = this.getMessagesAsText();
            const success = await copyToClipboard(text);
            if (success) {
                showCopyFeedback('copy-console-btn');
            }
            return success;
        },

        /**
         * Update console display (to be implemented per playground)
         */
        updateDisplay() {
            // Override this method in each playground
            console.log('📊 Console updated:', messages.length, 'messages');
        },

        /**
         * Save console state to localStorage
         * @param {Object} state - State object to save
         */
        saveState(state) {
            try {
                localStorage.setItem(storageKey, JSON.stringify(state));
            } catch (err) {
                console.error('❌ Failed to save console state:', err);
            }
        },

        /**
         * Load console state from localStorage
         * @returns {Object|null} Saved state or null
         */
        loadState() {
            try {
                const saved = localStorage.getItem(storageKey);
                return saved ? JSON.parse(saved) : null;
            } catch (err) {
                console.error('❌ Failed to load console state:', err);
                return null;
            }
        }
    };
}

// ============================================================================
// FLOATING CONSOLE DRAG & RESIZE
// ============================================================================

/**
 * Make an element draggable
 * @param {HTMLElement} element - Element to make draggable
 * @param {HTMLElement} handle - Drag handle element
 * @param {Function} onDragEnd - Callback when drag ends (receives {x, y})
 */
function makeDraggable(element, handle, onDragEnd = null) {
    let pos1 = 0, pos2 = 0, pos3 = 0, pos4 = 0;

    const dragMouseDown = (e) => {
        e.preventDefault();
        pos3 = e.clientX;
        pos4 = e.clientY;
        document.addEventListener('mousemove', elementDrag);
        document.addEventListener('mouseup', closeDragElement);
    };

    const elementDrag = (e) => {
        e.preventDefault();
        pos1 = pos3 - e.clientX;
        pos2 = pos4 - e.clientY;
        pos3 = e.clientX;
        pos4 = e.clientY;
        element.style.top = (element.offsetTop - pos2) + 'px';
        element.style.left = (element.offsetLeft - pos1) + 'px';
    };

    const closeDragElement = () => {
        document.removeEventListener('mousemove', elementDrag);
        document.removeEventListener('mouseup', closeDragElement);

        if (onDragEnd) {
            onDragEnd({
                x: element.offsetLeft,
                y: element.offsetTop
            });
        }
    };

    handle.addEventListener('mousedown', dragMouseDown);
}

/**
 * Make an element resizable
 * @param {HTMLElement} element - Element to make resizable
 * @param {HTMLElement} handle - Resize handle element
 * @param {Function} onResizeEnd - Callback when resize ends (receives {width, height})
 */
function makeResizable(element, handle, onResizeEnd = null) {
    let startX, startY, startWidth, startHeight;

    const initResize = (e) => {
        e.preventDefault();
        startX = e.clientX;
        startY = e.clientY;
        startWidth = parseInt(getComputedStyle(element).width, 10);
        startHeight = parseInt(getComputedStyle(element).height, 10);
        document.addEventListener('mousemove', doResize);
        document.addEventListener('mouseup', stopResize);
    };

    const doResize = (e) => {
        const width = startWidth + (e.clientX - startX);
        const height = startHeight + (e.clientY - startY);
        element.style.width = Math.max(300, width) + 'px';
        element.style.height = Math.max(200, height) + 'px';
    };

    const stopResize = () => {
        document.removeEventListener('mousemove', doResize);
        document.removeEventListener('mouseup', stopResize);

        if (onResizeEnd) {
            onResizeEnd({
                width: element.offsetWidth,
                height: element.offsetHeight
            });
        }
    };

    handle.addEventListener('mousedown', initResize);
}

// ============================================================================
// EXPORTS (for module environments)
// ============================================================================

// Make functions globally available for inline script usage
if (typeof window !== 'undefined') {
    window.PlaygroundUtils = {
        // Library management
        loadJSZip,

        // Swift communication
        notifySwift,

        // Data conversion
        arrayBufferToBase64Chunked,

        // Utilities
        debounce,
        escapeHtml,

        // Error display
        showError,
        hideError,

        // Clipboard
        copyToClipboard,
        fallbackCopy,
        showCopyFeedback,

        // Monaco editor
        insertCodeAtCursor,
        setFullEditorContent,
        toggleEditor,

        // Zip packages
        createZipPackage,
        saveScenePackage,

        // Console management
        createConsoleManager,

        // Drag & resize
        makeDraggable,
        makeResizable
    };
}
