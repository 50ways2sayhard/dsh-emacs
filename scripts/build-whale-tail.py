#!/usr/bin/env python3
"""Convert the web APNG to full GIF masks without frame trails (requires Pillow).

Keep every 50ms frame, even consecutive identical masks.  Use a two-entry
palette so Emacs can tint the foreground without re-encoding the images.
Validate decoded frames against the input, then emit the embedded Elisp constant.
"""

from pathlib import Path
from PIL import Image
import argparse
import base64
import io
import struct
import sys
import textwrap

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path, help='DSH Web running-whale@2x.png')
parser.add_argument('--output', type=Path,
                    help='write the Elisp constant to this file (default: stdout)')
args = parser.parse_args()
source = args.source
im = Image.open(source)
assert im.size == (28, 28) and im.n_frames == 60
out = bytearray(b'GIF89a' + struct.pack('<HHBBB', 28, 28, 0xf0, 0, 0))
out += b'\0\0\0\xff\xff\xff'
out += b'!\xff\x0bNETSCAPE2.0\x03\x01\0\0\0'
expected = []
for index in range(60):
    im.seek(index)
    assert im.info['duration'] == 50
    mask = bytes(int(alpha > 0) for alpha in im.convert('RGBA').getchannel('A').get_flattened_data())
    expected.append(mask)
    frame = Image.frombytes('P', (28, 28), mask)
    frame.putpalette([0, 0, 0, 255, 255, 255])
    encoded = io.BytesIO()
    frame.save(encoded, format='GIF', transparency=0, disposal=2, duration=50, optimize=False)
    data = encoded.getvalue()
    offset = 13 + 3 * 2**((data[10] & 7) + 1)
    # The single-image encoder has a GCE followed by a full frame using the global palette.
    assert data[offset:offset+4] == b'!\xf9\x04\x09'
    assert data[offset+8] == 0x2c and not (data[offset+17] & 0x80)
    out += data[offset:-1]
out += b';'
result = Image.open(io.BytesIO(out))
assert result.n_frames == 60
for index, mask in enumerate(expected):
    result.seek(index)
    assert result.info['duration'] == 50 and result.disposal_method == 2
    actual = bytes(int(alpha > 0) for alpha in result.convert('RGBA').getchannel('A').get_flattened_data())
    assert actual == mask, index
encoded = '\n'.join(textwrap.wrap(base64.b64encode(out).decode('ascii'), 76))
constant = ('(defconst dsh-emacs-modeline--whale-tail-gif-base64\n'
            '  "' + encoded + '"\n'
            '  "Base64 GIF mask: sixty 28×28 frames, each displayed for 50ms.")\n')
if args.output:
    args.output.write_text(constant, encoding='utf-8')
else:
    sys.stdout.write(constant)
print('PASS: all 60 masks and delays match the APNG; disposal clears each frame; bytes',
      len(out), file=sys.stderr)
