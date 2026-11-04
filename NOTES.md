# BandFix2 notes

Project history lives in this repository, so record findings here.

## The fault

A vertical strip of the built-in display, 864-1080 pt of 1728 (exactly 1/8 of
the panel, starting at its centre), emits less light than the rest. Confirmed
as hardware: it is visible before macOS loads and never appears in screenshots.
Band position is confirmed correct by eye; do not re-measure it.

## What was measured

Run with `tools/BandTest.html`, by eye, in Safari, with BandFix's correction
off. Values are Display P3 drive levels, close to what the panel receives.

| Content | Band last seen | Band gone by |
|---|---|---|
| Grey | 75% | 70% |
| Red, green or blue alone | 80% | 75% |
| Standard red | #E50000 (about 82% panel red) | #D90000 (about 78%) |

All 7 colours tested showed the band at full drive and none when capped at
70%: white, red, yellow, magenta, salmon, orange and sky.

The results looked the same at every brightness level tried. Full-screen 70%
grey was judged a comfortable white.

## Conclusion

The fault follows how hard each subpixel is driven, not how bright the content
looks. `#E50000` is about 17% luminance and shows the band, while 70% grey is
much brighter and does not. The likely cause is a source-driver fault, though
that remains an inference.

## Approach

BandFix looks at the screen and dims either side of the band. BandFix2 avoids
the faulty range instead: a display-wide transfer table scales every channel of
the built-in display, so the panel is never driven above the cap.

It scales rather than clips, which is what the test page's capped rows did and
keeps gradients and highlights distinct. Default cap: 70%, the highest level
confirmed for every colour. 71-74% has not been tested.

## Costs and unknowns

Update this table as things are checked.

| Question | Status |
|---|---|
| Does the real cap hide the band as the test page did? | Not yet checked by eye |
| Battery compared with BandFix at the same perceived brightness | Not measured |
| HDR video and photos: do they bypass the cap? | Not checked |
| Does the cap survive real sleep, wake and lock? | Not checked; see below |
| Do gradients show visible steps? | Not checked |
| Night Shift and True Tone interaction | Not checked |

## Verified by test (2026-11-04)

These read back the live table. None of them shows what the panel emits.

- Launching the app takes the live peak from 1.00 to 0.70.
- Another process overwriting the table is recaptured within about 5 seconds,
  without compounding. A real wake has not been tried.
- Quitting restores 1.00. So does `kill -9`: macOS undoes a process's table when
  it exits, so a crash cannot leave the screen stuck dim.
- `CGDisplayRestoreColorSyncSettings` from another process did not change the
  table this app had set.

## Safety properties

- The cap is limited to 50-100%, so a bad stored value cannot black out the screen.
- The cap only reapplies when the live table's peak exceeds the expected peak.
  It never re-caps a table that is already capped, so the dimming cannot compound.
- Only the built-in display is touched.
- BandFix's correction must be off while testing, or both apps dim the screen.

## Commands

    ./build.sh                  build and install to ~/Applications; does not launch
    bandfix2 --check            table arithmetic only; does not touch the display
    bandfix2 --read             print the live table's peak
    bandfix2 --selftest         apply, verify and restore; dims the screen briefly
    bandfix2 --apply-and-exit   apply and exit without restoring; dims until macOS restores
