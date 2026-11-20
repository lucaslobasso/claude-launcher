// json.js: the JSON side of Claude Launcher on macOS, run with the JavaScript engine macOS ships
// (no Node, no jq):
//
//   osascript -l JavaScript json.js get   <launcher.json>
//   osascript -l JavaScript json.js set   <launcher.json> key=value [key=value ...]
//   osascript -l JavaScript json.js trust <~/.claude.json> <absolute folder path>
//
// get    Prints the settings merged over the defaults, one `key=value` line each, always in this order:
//          folder=~
//          claudeArgs=agents
//          keepShellOpen=false        (always "true" or "false")
//          terminal=terminal          (lowercased)
//        A key that is present wins, even when it is "" (claudeArgs "" = a plain `claude` session); null means
//        the default. Line breaks inside a value become spaces, so every value is exactly one line.
//        A missing or blank file gives the defaults; a file that doesn't parse gives the defaults and a warning
//        on stderr. Exit 0.
// set    Merges the pairs into the file (keys: folder, claudeArgs, keepShellOpen, terminal) and writes it with
//        2-space indentation and a trailing newline. keepShellOpen is stored as a boolean. Other keys already in
//        the file are kept. A file that doesn't parse is replaced (warning on stderr). Exit 2 on bad usage.
// trust  Sets projects[<path>].hasTrustDialogAccepted = true in Claude Code's config, only when it isn't already
//        true. Missing file: nothing happens. A file that doesn't parse: a warning, the file is left alone.
//        The write is atomic (temp file + rename) and keeps the file's permissions; a symlinked config is
//        written through the link. Always exit 0 (pre-trusting is best effort).
//
// The helpers below the ObjC section are plain JavaScript (tested without macOS by feeding them strings).

'use strict';

var DEFAULTS = { folder: '~', claudeArgs: 'agents', keepShellOpen: false, terminal: 'terminal' };
var KEYS = ['folder', 'claudeArgs', 'keepShellOpen', 'terminal'];

// ---- Pure helpers ----

function stripBom(text) {
    return text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
}

// Parses launcher.json text. Returns { obj } or { error }. Blank text is an empty object.
function parseSettingsText(text) {
    text = stripBom(text || '');
    if (/^\s*$/.test(text)) return { obj: {} };
    var obj;
    try { obj = JSON.parse(text); } catch (e) { return { error: e.message }; }
    if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) return { error: 'not a JSON object' };
    return { obj: obj };
}

function toBool(v) {
    if (v === true) return true;
    if (typeof v === 'string') return /^(true|1|yes|on)$/i.test(v.trim());
    if (typeof v === 'number') return v !== 0;
    return false;
}

function oneLine(v) {
    return String(v).replace(/[\r\n\u2028\u2029]+/g, ' ');
}

// Settings merged over the defaults (file values win when present and not null).
function mergeSettings(obj) {
    var out = {};
    KEYS.forEach(function (k) {
        var v = obj && Object.prototype.hasOwnProperty.call(obj, k) && obj[k] !== null && obj[k] !== undefined ? obj[k] : DEFAULTS[k];
        if (k === 'keepShellOpen') v = toBool(v);
        else if (typeof v === 'object') v = DEFAULTS[k];  // arrays/objects make no sense here
        else v = String(v);
        if (k === 'terminal') v = v.trim().toLowerCase();
        out[k] = v;
    });
    return out;
}

// The `get` output: one key=value line per setting, fixed order.
function formatSettings(settings) {
    return KEYS.map(function (k) {
        var v = settings[k];
        return k + '=' + (k === 'keepShellOpen' ? (v ? 'true' : 'false') : oneLine(v));
    }).join('\n') + '\n';
}

// Applies key=value pairs to a parsed launcher.json object. Returns { obj } or { error }.
// The known keys come first, in their usual order; any other keys the file had follow.
function applySettings(obj, pairs) {
    var merged = mergeSettings(obj);
    for (var i = 0; i < pairs.length; i++) {
        var eq = pairs[i].indexOf('=');
        if (eq < 1) return { error: 'expected key=value, got "' + pairs[i] + '"' };
        var key = pairs[i].slice(0, eq), value = pairs[i].slice(eq + 1);
        if (KEYS.indexOf(key) < 0) return { error: 'unknown setting "' + key + '" (known: ' + KEYS.join(', ') + ')' };
        merged[key] = key === 'keepShellOpen' ? toBool(value) : (key === 'terminal' ? value.trim().toLowerCase() : value);
    }
    var out = {};
    KEYS.forEach(function (k) { out[k] = merged[k]; });
    Object.keys(obj || {}).forEach(function (k) { if (KEYS.indexOf(k) < 0) out[k] = obj[k]; });
    return { obj: out };
}

function settingsJson(obj) {
    return JSON.stringify(obj, null, 2) + '\n';
}

// The trust edit on ~/.claude.json text. Returns { text } when the file must be rewritten, { unchanged: true }
// when the folder is already trusted, or { error } when the text isn't a JSON object.
function trustText(text, projectPath) {
    var hadBom = text.charCodeAt(0) === 0xfeff;
    var body = stripBom(text);
    var data;
    try { data = JSON.parse(body); } catch (e) { return { error: e.message }; }
    if (data === null || typeof data !== 'object' || Array.isArray(data)) return { error: 'not a JSON object' };
    var projects = data.projects;
    if (projects === null || typeof projects !== 'object' || Array.isArray(projects)) {
        projects = {};
        data.projects = projects;
    }
    var proj = Object.prototype.hasOwnProperty.call(projects, projectPath) ? projects[projectPath] : undefined;
    if (proj && typeof proj === 'object' && !Array.isArray(proj) && proj.hasTrustDialogAccepted === true) return { unchanged: true };
    if (!proj || typeof proj !== 'object' || Array.isArray(proj)) {
        proj = {};
        projects[projectPath] = proj;
    }
    proj.hasTrustDialogAccepted = true;
    var trailing = /\n$/.test(body) ? '\n' : '';
    return { text: (hadBom ? '\ufeff' : '') + JSON.stringify(data, null, 2) + trailing };
}

// ---- macOS side (ObjC bridge) ----

function osEnv() {
    ObjC.import('Foundation');
    ObjC.import('stdlib');
    var fm = $.NSFileManager.defaultManager;

    function write(handle, text) {
        handle.writeData($(text).dataUsingEncoding($.NSUTF8StringEncoding));
    }
    function out(text) { write($.NSFileHandle.fileHandleWithStandardOutput, text); }
    function warn(text) { write($.NSFileHandle.fileHandleWithStandardError, 'Claude Launcher: ' + text + '\n'); }

    function exists(path) { return fm.fileExistsAtPath($(path).stringByStandardizingPath); }

    // UTF-8 text of a file, or null when it can't be read.
    function readText(path) {
        var s = $.NSString.stringWithContentsOfFileEncodingError($(path).stringByStandardizingPath, $.NSUTF8StringEncoding, null);
        if (!s || s.isNil()) return null;
        return ObjC.unwrap(s);
    }

    // Atomic UTF-8 write (Foundation writes a temp file next to it and renames it over the target).
    // A symlink is followed so the link stays a link; the old file's permissions are kept.
    function writeText(path, text) {
        var target = $(path).stringByStandardizingPath.stringByResolvingSymlinksInPath;
        var perms = null;
        if (fm.fileExistsAtPath(target)) {
            var attrs = fm.attributesOfItemAtPathError(target, null);
            if (attrs && !attrs.isNil()) perms = attrs.objectForKey($.NSFilePosixPermissions);
        }
        var ok = $(text).writeToFileAtomicallyEncodingError(target, true, $.NSUTF8StringEncoding, null);
        if (!ok) return false;
        if (perms && !perms.isNil()) {
            fm.setAttributesOfItemAtPathError($.NSDictionary.dictionaryWithObjectForKey(perms, $.NSFilePosixPermissions), target, null);
        }
        return true;
    }

    return { out: out, warn: warn, exists: exists, readText: readText, writeText: writeText, exit: function (c) { $.exit(c); } };
}

function main(argv, os) {
    var cmd = argv[0];
    if (cmd === 'get' && argv.length === 2) {
        var text = os.exists(argv[1]) ? os.readText(argv[1]) : '';
        if (text === null) {
            os.warn("couldn't read " + argv[1] + '; using the defaults.');
            text = '';
        }
        var parsed = parseSettingsText(text);
        if (parsed.error) os.warn("couldn't read " + argv[1] + ' (' + parsed.error + '); using the defaults.');
        os.out(formatSettings(mergeSettings(parsed.obj || {})));
        return 0;
    }
    if (cmd === 'set' && argv.length >= 2) {
        var current = os.exists(argv[1]) ? os.readText(argv[1]) : '';
        var p = parseSettingsText(current || '');
        if (p.error) os.warn(argv[1] + " didn't parse (" + p.error + '); writing the defaults plus your changes.');
        var applied = applySettings(p.obj || {}, argv.slice(2));
        if (applied.error) { os.warn(applied.error); return 2; }
        if (!os.writeText(argv[1], settingsJson(applied.obj))) { os.warn("couldn't write " + argv[1]); return 1; }
        return 0;
    }
    if (cmd === 'trust' && argv.length === 3) {
        if (!os.exists(argv[1])) return 0;
        var raw = os.readText(argv[1]);
        if (raw === null) { os.warn("couldn't read " + argv[1] + '; you may see the trust prompt.'); return 0; }
        var r = trustText(raw, argv[2]);
        if (r.error) { os.warn("couldn't pre-trust the folder (" + argv[1] + ': ' + r.error + '). You may see the trust prompt.'); return 0; }
        if (r.unchanged) return 0;
        if (!os.writeText(argv[1], r.text)) os.warn("couldn't write " + argv[1] + '; you may see the trust prompt.');
        return 0;
    }
    os.warn('usage: json.js get <file> | set <file> key=value... | trust <claude.json> <path>');
    return 2;
}

// osascript calls run(); Node (for testing the helpers) never does.
// eslint-disable-next-line no-unused-vars
function run(argv) {
    var os = osEnv();
    os.exit(main(argv, os));
}

if (typeof module !== 'undefined' && module.exports) {
    module.exports = { DEFAULTS: DEFAULTS, parseSettingsText: parseSettingsText, mergeSettings: mergeSettings, formatSettings: formatSettings, applySettings: applySettings, settingsJson: settingsJson, trustText: trustText, main: main };
}
