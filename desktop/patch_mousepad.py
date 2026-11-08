#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Adds raw touch support to Zorin Connect's service/plugins/mousepad.js (ES module versions, 58+).

Edits are anchored on code, not line numbers, so small upstream changes do not break it.
Exit status: 0 patched (or already patched), 1 an anchor is missing (file untouched),
2 unsupported old Zorin Connect (55.x and earlier, GNOME 43 and older).

Usage: patch_mousepad.py /path/to/mousepad.js
"""
import os
import re
import sys

path = sys.argv[1]
src = open(path).read()
if 'TouchpadBridge' in src:
    print('already patched')
    sys.exit(0)

if not re.search(r'^import ', src, re.M):
    sys.stderr.write('patch_mousepad: this Zorin Connect is too old (legacy imports, GNOME 43 or older)\n')
    sys.exit(2)

missing = []


def insert(pattern, text, label, after=True, flags=0):
    """Insert `text` after (or before) the first match of `pattern`."""
    global src
    m = re.search(pattern, src, flags)
    if not m:
        missing.append(label)
        return
    pos = m.end() if after else m.start()
    src = src[:pos] + text + src[pos:]


insert(r"import \* as Components from '\.\./components/index\.js';\n",
       "import TouchpadBridge, {isAvailable as touchpadAvailable} from '../utils/touchpad.js';\n",
       'components import')

insert(r"_handleInput\(input\) \{.*?switch \(true\) \{\n",
       "            // Raw phone touch frames, replayed as a virtual touchpad\n"
       "            case input.hasOwnProperty('touch'):\n"
       "                if (this._touchpad === undefined)\n"
       "                    this._touchpad = new TouchpadBridge();\n"
       "\n"
       "                this._touchpad.sendFrame(input.touch);\n"
       "                break;\n"
       "\n",
       '_handleInput switch', flags=re.S)

insert(r"    disconnected\(\) \{\n        super\.disconnected\(\);\n",
       "\n        if (this._touchpad !== undefined)\n            this._touchpad.release();\n",
       'disconnected()')

insert(r"\n        this\.settings\.disconnect\(this\._shareControlChangedId\);\n",
       "\n        if (this._touchpad !== undefined)\n            this._touchpad.destroy();\n",
       'destroy()', after=False)

insert(r"    _sendState\(\) \{.*?state: this\.settings\.get_boolean\('share-control'\),\n",
       "                rawTouch: touchpadAvailable(),\n",
       '_sendState body', flags=re.S)

if missing:
    sys.stderr.write('patch_mousepad: anchors not found: %s\n' % ', '.join(missing))
    sys.exit(1)

tmp = path + '.zc-new'
with open(tmp, 'w') as f:
    f.write(src)
os.replace(tmp, path)
print('patched')
