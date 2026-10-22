# 146 — Keep user-message text free of prompt decoration

## Background

The uncommitted rail design in [145](145-light-conversation-markers.md),
based on `1dcdb5d`, retained a hidden `❯ ` in each historical user message.
Empty display replacement disrupted C-a; replacing it with a zero-width
space restored navigation but still let copy-line expose the hidden prompt.
The renderer owned the defect: decoration had been stored as message text.

## Decision

Remove the synthetic prompt from historical messages. Keep the rail in
display prefixes and use the existing user-message property for navigation.
Imenu reads authored text without stripping a leading `❯ `. A native
`yank-handler` inserts copied user text without display or identity properties.

## Why

Filtering one copy command would leave other paths inconsistent. In particular,
the installed Xah copy-line command uses normal region copying initially but
direct buffer substrings when appending subsequent lines. Plain underlying
text gives both paths correct clipboard content; native yank handling keeps
their display properties from leaking into another buffer. No global advice
or private third-party integration is needed.

## Consequence

Copied user text contains exactly what the user wrote, including literal
prompt characters. C-a reaches the first real character. Regression tests
cover native copying, direct substrings, plain-text yanking and Imenu labels.
The [changelog](../CHANGELOG.md) records this uncommitted change on `1dcdb5d`.

## Known limitations

Existing rendered buffers need reloading and reopening, and old kill-ring
entries must be copied again. Code that explicitly uses raw `insert` rather
than Emacs yanking retains the properties of its input string as usual.
