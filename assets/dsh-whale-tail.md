# Running whale tail

The Base64 GIF in `dsh-emacs-modeline--whale-tail-gif-base64`
(`dsh-emacs-modeline.el`) is derived from DeepSeek Harness's
`packages/client/ui-chat/src/client/chat/running-whale@2x.png` at upstream
commit `5badb15009`. The accompanying `RunningWhaleTail.tsx` owns the static
fallback path used in `dsh-emacs-modeline.el`.

Source APNG SHA-256:
`0fd990d118113d19af7af4480f2b55d610b103451a08be6f7bf5a146823f8bd3`

Rebuild with Python and Pillow:

```sh
python3 scripts/build-whale-tail.py /path/to/running-whale@2x.png \
  --output /tmp/dsh-whale-tail-constant.el
```

Replace the matching `defconst` in `dsh-emacs-modeline.el` with that output.
Without `--output`, the script prints the declaration to stdout. No separate
GIF is shipped; Emacs decodes the constant once, on first graphical use.

The converter preserves sixty 28×28 full frames, each lasting 50ms. Every
nonzero alpha pixel becomes foreground palette index 1; index 0 is transparent.
The two-entry global palette permits runtime tinting. Disposal mode 2 clears
the previous frame, preventing old tail positions from accumulating. The
converter checks every decoded mask and delay against its APNG input before
emitting the Elisp constant. Emacs displays the frames through explicit image
indices, using a centered 18×18 display box. GIF cannot
retain the APNG's partial edge transparency.

The upstream asset and static path are distributed under this license:

MIT License

Copyright (c) 2026 DeepSeek

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
