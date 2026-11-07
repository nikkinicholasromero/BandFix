# BandFix notes

Project history lives in this repository, so record findings here.

## The fault

A vertical strip of the built-in display, 864-1080 pt of 1728 (exactly 1/8 of
the panel, starting at its centre), emits less light than the rest. Confirmed
as hardware: it is visible before macOS loads and never appears in screenshots.
Band position is confirmed correct by eye; do not re-measure it.

## What was measured

Run with `tools/BandTest.html`, by eye, in Safari, with no correction running.
Values are Display P3 drive levels, close to what the panel receives.

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

An earlier app with this name watched the screen and dimmed either side of the
band. It missed saturated colours and busy screens, and was removed.

This app avoids the faulty range instead: a display-wide transfer table scales
every channel of the built-in display, so the panel is never driven above the
cap. It needs no screen capture, Screen Recording permission or overlays.

It scales rather than clips, which is what the test page's capped rows did and
keeps gradients and highlights distinct. Default cap: 70%, the highest level
confirmed for every colour. 71-74% has not been tested.

## Costs and unknowns

Update this table as things are checked.

| Question | Status |
|---|---|
| Does the real cap hide the band as the test page did? | Yes, judged by eye: "looks perfect" |
| Does it work again after a restart, with Open at Login on? | Yes, judged by eye |
| Battery compared with the earlier app at the same perceived brightness | Not measured |
| HDR video and photos: do they bypass the cap? | No: HDR white up to 3.0x showed no band and no extra brightness with the cap on (2026-11-07) |
| Does the cap survive real sleep, wake and lock? | Not reported; see below |
| Do gradients show visible steps? | Not reported |
| Night Shift and True Tone interaction | Not checked |

Costs that follow from the method: maximum brightness falls to about 225 nits
from about 500, and raising the slider to compensate uses more backlight power.
The test page cannot be used while the cap is on, because the cap also lowers
its values. Quit the app first.

## Verified by test (2026-11-04)

These read back the live table. None of them shows what the panel emits.

- Launching the app takes the live peak from 1.00 to 0.70.
- Another process overwriting the table is recaptured within about 5 seconds,
  without compounding. A real wake has not been tried.
- Quitting restores 1.00. So does `kill -9`: macOS undoes a process's table when
  it exits, so a crash cannot leave the screen stuck dim.
- `CGDisplayRestoreColorSyncSettings` from another process did not change the
  table this app had set.

## Tried and ruled out: brightness from the HDR backlight (2026-11-07)

Idea: keep the pixels under the cap and get brightness back from the XDR
backlight, which can exceed the 500-nit SDR limit while HDR headroom is active.
Display: 16" MacBook Pro, M2 Max (Mac14,6), Liquid Retina XDR, potential
headroom 16x, 3.2x at full brightness.

Tested by eye with a scratch test app (not kept in the repo), BandFix off,
headroom confirmed at 3.2x by the app:

- A small HDR patch, so ordinary white was on screen while headroom was active:
  band visible on the white. Turning HDR on does not lower the drive of
  ordinary white, likely because the backlight zones are dimmed separately.
- The full screen filled with HDR white at 1.0x to 3.0x of ordinary white:
  band visible at every level.
- The same full-screen test with BandFix on at 70%: no band at any level, but
  also no visible change in brightness between levels. The cap holds HDR
  content back too, so the extra backlight never reaches the screen.

Conclusion: without the cap, brighter content drives the pixels into the faulty
range; with the cap, it gets no brighter. The backlight cannot be used to win
brightness back, so about 225 nits at a 70% cap is the practical limit. Note that
headroom winds down over several seconds after HDR content disappears, so a
quick on/off comparison stays in HDR mode the whole time.

## Tried and ruled out: keeping darker shades at full level (2026-11-07)

Idea: leave levels up to 50% unchanged and squeeze only 50-100% into 50-70%,
so dark and middle shades look as they would without the cap.

Tried as a menu option and judged by eye: everything looked washed out, and
borders and lines lost contrast. Darks stay put while white is still held at
70%, so the gap between them shrinks, and light greys (about 66.5% for an 80%
input) nearly merge with white. Scaling every level evenly keeps the
proportions, so a dimmer but crisp picture beats a brighter, flat one. The
option was removed.

## Safety properties

- The cap is limited to 50-100%, so a bad stored value cannot black out the screen.
- The cap only reapplies when the live table's peak exceeds the expected peak.
  It never re-caps a table that is already capped, so the dimming cannot compound.
- Only the built-in display is touched.

## Commands

    ./build.sh                 build, install to ~/Applications and launch
    bandfix --check            table arithmetic only; does not touch the display
    bandfix --read             print the live table's peak
    bandfix --selftest         apply, verify and restore; dims the screen briefly
    bandfix --apply-and-exit   apply and exit without restoring; macOS undoes it on exit
