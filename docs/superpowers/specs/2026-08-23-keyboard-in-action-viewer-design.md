# Keyboard in Action Viewer — Design

## Goal

Give the owner of an iPhone 15 running iOS 18.5 a touch-friendly, single-file reference for discovering the characters and system shortcuts available from a typical US-QWERTY external keyboard, including Option/Alt Lock.

## Scope

Create `files/keyboard-in-action-viewer.html`. The existing Rack application already exposes files in `files/` at `/files/<name>`, so no Ruby or server change is needed.

The page will:

- render a visual ANSI US-QWERTY keyboard;
- provide toggle buttons for Control, Option, Command, Shift, and Alt Lock;
- evaluate all 32 modifier states, with Alt Lock behaving as a persistent Option state;
- update each printable key to show its US-layout character for the selected state;
- label Command and Control combinations as system/app shortcuts rather than pretending they reliably insert text on iOS;
- include a compact programmer-symbol table for punctuation, brackets, braces, pipes, backticks, tildes, and common Option characters;
- listen for real external-keyboard events where the browser receives them, so the page can display the actual `key` value from the user’s keyboard/input source.

## Interaction and presentation

The default view is an iPhone-width, high-contrast technical reference. Modifier controls are large enough to tap. A selected modifier visibly changes the keyboard immediately; Alt Lock stays highlighted after selection and behaves like Option until turned off. A reset control returns to the normal layout.

The page will say that the built-in character map is a US English reference and that browser, iOS version, app, and keyboard layout can reserve Command/Control combinations or produce a different glyph. This prevents the page from claiming unsupported iOS behavior as fact.

## Implementation

Use semantic HTML, embedded CSS, and plain browser JavaScript only—no library, server route, or build step. Keep the modifier state and US key map in the page script. Use `KeyboardEvent` capture as an observational aid, not as the source of the reference map, because iOS may intercept system shortcuts before the page receives them.

## Verification

Add one small Ruby assertion test that reads the static file and confirms the required modifier controls, Alt Lock behavior marker, keyboard container, and event listener are present. Run the existing Ruby tests plus the new test. Open the page through the local Rack app and perform a browser smoke check of modifier toggling and the responsive layout.

## Non-goals

- Exact per-app iOS shortcut documentation.
- Support for every physical keyboard layout or international input source.
- A separate CSS/JS asset pipeline or a new dependency.
