#!/usr/bin/env python3
"""The iPhone EQ's fixtures (notes/ios-specs/eq.md, 5.1): what DeadwaxCore's EQ tests are held to.

    python -I ios/scripts/make-eq-fixtures.py [--out DIR]

Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/eq/ (or DIR - tests/test_ios_eq_fixtures.py writes a
temporary one and compares it with what is committed). Needs numpy and scipy; nothing else, and nothing from
deadwax: every rule here is written out again from the spec and from Equalizer APO's source as the spec describes
it (0.3, 1.3), independently of the Swift, so the Swift is held to a second reading rather than to itself.

    apo/*.txt        hand-made Equalizer APO files, one or more for each case of 3.9 - written by this script
                     (APO_FILES below), so they are made, never edited. UTF-16 and oversized files are not
                     committed (a UTF-16 file holds NUL bytes, which tests/test_source_bytes.py forbids): apo.json
                     names them as a committed file and a transform, and both readers make the bytes the same way.
    apo.json         what this script's reader of APO's rules reads from each: the filters, the preamp's parts,
                     the GraphicEQ lines and their conversion (3.10), the notes and the refusal, with their words.
    filters.json     the cookbook and APO's filter rules (1.3) at eight rates from 44.1 to 384 kHz: each filter's
                     f0 and five coefficients (as Python's repr, exact), its response on 1.4's 1/48-octave grid by
                     scipy.signal.freqz, and the first 128 samples of its impulse response through this script's
                     own Direct Form I in Python floats - 1.5's order of operations, the bit-exact reference.
                     scipy.signal.lfilter (transposed direct form II, another rounding) is run beside it as a
                     cross-check only.
    profiles.json    real AutoEq ParametricEQ.txt files (autoeq/, MIT, at AutoEq's 7ae0f56 - see its README),
                     read by this reader, and their curve by AutoEq's own biquads (peq.py's three functions,
                     copied below with their MIT notice) at 44.1 and 48 kHz.
    graphic.json     3.10's fit over AutoEq's two GraphicEQ.txt files, run in NumPy: the target, its median, the
                     gains before and after rounding, and the fit's numbers.
    preamp.json      3.6's presets (their tops, lowest points and automatic preamps) and 1.4's close pairs with
                     their true tops from a 4-million-point search.
    render.json      banks run over noise by this script's Direct Form I: input and Float32 output, bit for bit.

Inputs it reads and never writes: autoeq/ (fetched from AutoEq, see autoeq/README.md).

Exact numbers are written as Python's repr (shortest round trip) in strings, which Swift's Double(String) reads back
to the same bits; arrays as base64 of little-endian float32 ("_f4") or float64 ("_f8").
"""

import argparse
import base64
import json
import math
import re
import sys
from pathlib import Path

import numpy as np
from scipy import signal

IOS = Path(__file__).resolve().parents[1]
EQ = IOS / "DeadwaxKit" / "Tests" / "DeadwaxCoreTests" / "Fixtures" / "eq"

RATES = [44100.0, 48000.0, 88200.0, 96000.0, 176400.0, 192000.0, 352800.0, 384000.0]
NBSP = chr(0xA0)
ELLIPSIS = chr(0x2026)
REPLACEMENT = chr(0xFFFD)


# ------------------------------------------------------------------------------------------------ numbers

def r(x):
    """A Double as text that reads back to the same bits."""
    return repr(float(x))


def b64(values, dtype):
    return base64.b64encode(np.asarray(values, dtype="<" + dtype).tobytes()).decode("ascii")


def round_away(y):
    """Half away from zero, exactly (Swift's .rounded()): the fraction of a Double is exact."""
    a = abs(y)
    whole = math.floor(a)
    k = whole + 1.0 if a - whole >= 0.5 else whole
    return math.copysign(k, y)


def num(x):
    """A number in the reader's words: the shortest form that reads back, without a trailing ".0"."""
    text = repr(float(x))
    return text[:-2] if text.endswith(".0") else text


def bytes_words(count):
    """Core's Bytes.words, again: whole MB under 1 GB, at least "1 MB"."""
    megabytes = round_away(count / 1_000_000)
    if megabytes < 1000:
        return "%d MB" % max(int(megabytes), 1)
    raise ValueError("not needed here")


# ------------------------------------------------------------------------------------------------ the cookbook (1.3)

TYPES = {"PK": "peak", "PEQ": "peak", "Modal": "peak", "LP": "lowPass", "LPQ": "lowPass", "HP": "highPass",
         "HPQ": "highPass", "BP": "bandPass", "LS": "lowShelf", "HS": "highShelf", "LSC": "lowShelf",
         "HSC": "highShelf", "NO": "notch", "AP": "allPass"}
SHELVES = ("lowShelf", "highShelf")
GAINED = ("peak", "lowShelf", "highShelf")
SQRT1_2 = math.sqrt(0.5)
LN2 = math.log(2.0)


def width_rule(f):
    """APO's bandwidthOrQOrS and isBandwidthOrS for a filter as kept (BiQuadFilterFactory.cpp), or None when a
    peak or an all pass has no width. A shelf's S is returned as S (a slope already divided by 12)."""
    kind, width = f["kind"], f["width"]
    value, is_bws = 0.0, False
    if width is not None:
        wk, wv = width
        if wk == "q":
            value, is_bws = wv, False
        elif wk == "bandwidth" and kind not in SHELVES:
            value, is_bws = wv, True
        elif wk == "slope" and kind in SHELVES:
            value, is_bws = wv, True
    if value == 0:
        if kind in ("peak", "allPass"):
            return None
        if kind in ("lowPass", "highPass", "bandPass"):
            return SQRT1_2, is_bws, False
        if kind in SHELVES:
            return 0.9, True, False
        return 30.0, is_bws, False
    if kind in SHELVES and is_bws:
        value = value / 12.0
    return value, is_bws, True


def shelf_radicand(gain, s):
    a = 10 ** (gain / 40)
    return (a + 1 / a) * (1 / s - 1) + 2


def f0_of(f, value, is_bws, given):
    """A shelf read by its corner moved to the cookbook's f0 (BiQuadFilter.cpp); every other filter's f0 is Fc."""
    fc, gain = f["fc"], f["gain"]
    if f["corner"] and f["kind"] in SHELVES and given:
        s = value
        if not is_bws:
            q = value
            a = 10 ** (gain / 40)
            s = 1.0 / ((1.0 / (q * q) - 2.0) / (a + 1.0 / a) + 1.0)
        factor = 10.0 ** (abs(gain) / 80.0 / s)
        return fc * factor if f["kind"] == "lowShelf" else fc / factor
    return fc


def cookbook(kind, gain, f0, rate, value, is_bws):
    """BiQuad.cpp's five normalised coefficients (b0, b1, b2, a1, a2), in its order of operations."""
    big_a = 10 ** (gain / 40) if kind in GAINED else 1.0
    omega = 2 * math.pi * f0 / rate
    sn = math.sin(omega)
    cs = math.cos(omega)
    if not is_bws:
        alpha = sn / (2 * value)
    elif kind in SHELVES:
        alpha = sn / 2 * math.sqrt((big_a + 1 / big_a) * (1 / value - 1) + 2)
    else:
        alpha = sn * math.sinh(LN2 / 2 * value * omega / sn)
    beta = 2 * math.sqrt(big_a) * alpha
    if kind == "lowPass":
        b0, b1, b2, a0, a1, a2 = (1 - cs) / 2, 1 - cs, (1 - cs) / 2, 1 + alpha, -2 * cs, 1 - alpha
    elif kind == "highPass":
        b0, b1, b2, a0, a1, a2 = (1 + cs) / 2, -(1 + cs), (1 + cs) / 2, 1 + alpha, -2 * cs, 1 - alpha
    elif kind == "bandPass":
        b0, b1, b2, a0, a1, a2 = alpha, 0.0, -alpha, 1 + alpha, -2 * cs, 1 - alpha
    elif kind == "notch":
        b0, b1, b2, a0, a1, a2 = 1.0, -2 * cs, 1.0, 1 + alpha, -2 * cs, 1 - alpha
    elif kind == "allPass":
        b0, b1, b2, a0, a1, a2 = 1 - alpha, -2 * cs, 1 + alpha, 1 + alpha, -2 * cs, 1 - alpha
    elif kind == "peak":
        b0 = 1 + (alpha * big_a)
        b1 = -2 * cs
        b2 = 1 - (alpha * big_a)
        a0 = 1 + (alpha / big_a)
        a1 = -2 * cs
        a2 = 1 - (alpha / big_a)
    elif kind == "lowShelf":
        b0 = big_a * ((big_a + 1) - (big_a - 1) * cs + beta)
        b1 = 2 * big_a * ((big_a - 1) - (big_a + 1) * cs)
        b2 = big_a * ((big_a + 1) - (big_a - 1) * cs - beta)
        a0 = (big_a + 1) + (big_a - 1) * cs + beta
        a1 = -2 * ((big_a - 1) + (big_a + 1) * cs)
        a2 = (big_a + 1) + (big_a - 1) * cs - beta
    else:
        b0 = big_a * ((big_a + 1) + (big_a - 1) * cs + beta)
        b1 = -2 * big_a * ((big_a - 1) + (big_a + 1) * cs)
        b2 = big_a * ((big_a + 1) + (big_a - 1) * cs - beta)
        a0 = (big_a + 1) - (big_a - 1) * cs + beta
        a1 = 2 * ((big_a - 1) - (big_a + 1) * cs)
        a2 = (big_a + 1) - (big_a - 1) * cs - beta
    return (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)


def section(f, rate):
    """How deadwax plays a filter at a rate: (outcome, f0, coefficients). The outcome is "plays", or why it
    doesn't: "off", "noWidth", "tooSteep", "flat" (a peak or shelf at exactly 0 dB) or "above" (f0 at or above
    0.49 x the rate)."""
    if not f["on"]:
        return "off", None, None
    rule = width_rule(f)
    if rule is None:
        return "noWidth", None, None
    value, is_bws, given = rule
    if f["kind"] in SHELVES and is_bws and shelf_radicand(f["gain"], value) <= 0:
        return "tooSteep", None, None
    f0 = f0_of(f, value, is_bws, given)
    if f["kind"] in GAINED and f["gain"] == 0:
        return "flat", f0, None
    if f0 >= 0.49 * rate:
        return "above", f0, None
    return "plays", f0, cookbook(f["kind"], f["gain"], f0, rate, value, is_bws)


def section_db(coefficients, trig):
    """One section's dB, 1.4's formula: |b0 + b1 z^-1 + b2 z^-2| / |1 + a1 z^-1 + a2 z^-2| at z = e^jw, from
    trig = (cos w, sin w, cos 2w, sin 2w), as 10 log10 of each squared magnitude (a numerator of 0: -inf dB).
    (peq.py's form through 4 sin^2(w/2) loses up to 0.007 dB at 20 Hz, Q 100 and 384 kHz; this is within 4e-7 dB
    of 50-digit arithmetic over every case of filters.json.)"""
    b0, b1, b2, a1, a2 = coefficients
    c1, s1, c2, s2 = trig
    nr = b0 + b1 * c1 + b2 * c2
    ni = b1 * s1 + b2 * s2
    dr = 1 + a1 * c1 + a2 * c2
    di = a1 * s1 + a2 * s2
    with np.errstate(divide="ignore"):
        return 10 * np.log10(nr * nr + ni * ni) - 10 * np.log10(dr * dr + di * di)


def trig_of(frequencies, rate):
    """cos w, sin w, cos 2w and sin 2w at each frequency, w = 2 pi f / rate - by libm, one at a time."""
    ws = [2 * math.pi * f / rate for f in frequencies]
    return (np.array([math.cos(w) for w in ws]), np.array([math.sin(w) for w in ws]),
            np.array([math.cos(2 * w) for w in ws]), np.array([math.sin(2 * w) for w in ws]))


def response_grid(rate):
    """1.4's grid without its ends: every 1/48 octave from 10 Hz to just below Nyquist."""
    out, k = [], 0
    while True:
        f = 10 * 2 ** (k / 48)
        if f >= rate / 2:
            return out
        out.append(f)
        k += 1


def df1(coefficients, xs, state=None):
    """Direct Form I in Python floats, in 1.5's order: y = b0 x + b1 x1 + b2 x2 - a1 y1 - a2 y2, left to right."""
    b0, b1, b2, a1, a2 = coefficients
    x1, x2, y1, y2 = state or (0.0, 0.0, 0.0, 0.0)
    out = []
    for x in xs:
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, x
        y2, y1 = y1, y
        out.append(y)
    return out


# ------------------------------------------------------------------------------------------------ AutoEq's biquads
#
# Copied from AutoEq (github.com/jaakkopasanen/AutoEq, autoeq/peq.py at 7ae0f56: Peaking, HighShelf and LowShelf's
# biquad_coefficients, lines 236-250, 351-365, 404-418, and the frequency response at 110-128), each method's body
# made a function of its parameters. Their licence:
#
# MIT License
#
# Copyright (c) 2018-2022 Jaakko Pasanen
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

def peq_peaking(fc, q, gain, fs):
    """Calculates 2nd order biquad filter coefficients"""
    a = 10 ** (gain / 40)
    w0 = 2 * np.pi * fc / fs
    alpha = np.sin(w0) / (2 * q)

    a0 = 1 + alpha / a
    a1 = -(-2 * np.cos(w0)) / a0
    a2 = -(1 - alpha / a) / a0

    b0 = (1 + alpha * a) / a0
    b1 = (-2 * np.cos(w0)) / a0
    b2 = (1 - alpha * a) / a0

    return 1.0, a1, a2, b0, b1, b2


def peq_high_shelf(fc, q, gain, fs):
    """Calculates 2nd order biquad filter coefficients"""
    a = 10 ** (gain / 40)
    w0 = 2 * np.pi * fc / fs
    alpha = np.sin(w0) / (2 * q)

    a0 = (a + 1) - (a - 1) * np.cos(w0) + 2 * np.sqrt(a) * alpha
    a1 = -(2 * ((a - 1) - (a + 1) * np.cos(w0))) / a0
    a2 = -((a + 1) - (a - 1) * np.cos(w0) - 2 * np.sqrt(a) * alpha) / a0

    b0 = (a * ((a + 1) + (a - 1) * np.cos(w0) + 2 * np.sqrt(a) * alpha)) / a0
    b1 = (-2 * a * ((a - 1) + (a + 1) * np.cos(w0))) / a0
    b2 = (a * ((a + 1) + (a - 1) * np.cos(w0) - 2 * np.sqrt(a) * alpha)) / a0

    return 1.0, a1, a2, b0, b1, b2


def peq_low_shelf(fc, q, gain, fs):
    """Calculates 2nd order biquad filter coefficients"""
    a = 10 ** (gain / 40)
    w0 = 2 * np.pi * fc / fs
    alpha = np.sin(w0) / (2 * q)

    a0 = (a + 1) + (a - 1) * np.cos(w0) + 2 * np.sqrt(a) * alpha
    a1 = -(-2 * ((a - 1) + (a + 1) * np.cos(w0))) / a0
    a2 = -((a + 1) + (a - 1) * np.cos(w0) - 2 * np.sqrt(a) * alpha) / a0

    b0 = (a * ((a + 1) - (a - 1) * np.cos(w0) + 2 * np.sqrt(a) * alpha)) / a0
    b1 = (2 * a * ((a - 1) - (a + 1) * np.cos(w0))) / a0
    b2 = (a * ((a + 1) - (a - 1) * np.cos(w0) - 2 * np.sqrt(a) * alpha)) / a0

    return 1.0, a1, a2, b0, b1, b2


def peq_fr(f, fs, coefficients):
    """Calculates frequency response"""
    w = 2 * np.pi * f / fs
    phi = 4 * np.sin(w / 2) ** 2

    a0, a1, a2, b0, b1, b2 = coefficients

    a1 *= -1
    a2 *= -1

    return 10 * np.log10(
        (b0 + b1 + b2) ** 2 + (b0 * b2 * phi - (b1 * (b0 + b2) + 4 * b0 * b2)) * phi
    ) - 10 * np.log10(
        (a0 + a1 + a2) ** 2 + (a0 * a2 * phi - (a1 * (a0 + a2) + 4 * a0 * a2)) * phi
    )

# (end of what is copied from AutoEq)


# ------------------------------------------------------------------------------------------------ the reader (3.9)
#
# APO's rules as 0.3 sets them down from its source: lines split at LF with one CR dropped, each decoded as UTF-8
# or, failing that, Windows-1252; the command before the first ":", trimmed, matched with its case; a filter's
# parameters searched for by keyword, with its case, after commas become points; numbers by wcstod's prefix.

WS = "[ \t\n\r\f\v]"
WS_CHARS = " \t\n\r\f\v"
RUN = "[-+0-9.eE]+"
FC_RUN = "[-+0-9.eE" + NBSP + "]+"
DECIMAL = re.compile(r"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?")
CI = re.IGNORECASE | re.ASCII

RE_ON = re.compile("^" + WS + "*ON" + WS + "+([A-Za-z]+)")
RE_OFF = re.compile("^" + WS + "*OFF" + WS + "+([A-Za-z]+)")
RE_FC = re.compile(WS + "+Fc" + WS + "*(" + FC_RUN + ")" + WS + "*H" + WS + "*z")
RE_GAIN = re.compile(WS + "+Gain" + WS + "*(" + RUN + ")" + WS + "*dB")
RE_Q = re.compile(WS + "+Q" + WS + "*(" + RUN + ")")
RE_BW = re.compile(WS + "+BW" + WS + "+Oct" + WS + "*(" + RUN + ")")
RE_SLOPE = re.compile("^" + WS + "*(" + RUN + ")" + WS + "*dB")
RE_PREAMP = re.compile("^" + WS + "*(" + DECIMAL.pattern + ")")

RE_FC_CI = re.compile(WS + "+fc" + WS + "*(" + FC_RUN + ")" + WS + "*h" + WS + "*z", CI)
RE_FC_NO_HZ = re.compile(WS + "+Fc" + WS + "*(" + FC_RUN + ")")
RE_FC_NO_HZ_CI = re.compile(WS + "+fc" + WS + "*(" + FC_RUN + ")", CI)
RE_GAIN_CI = re.compile(WS + "+gain" + WS + "*(" + RUN + ")(?:" + WS + "*db)?", CI)
RE_Q_CI = re.compile(WS + "+q" + WS + "*(" + RUN + ")", CI)
RE_BW_CI = re.compile(WS + "+bw" + WS + "+oct" + WS + "*(" + RUN + ")", CI)
RE_ON_OFF_CI = re.compile("^" + WS + "*(on|off)" + WS + "+[A-Za-z]", CI)

REFUSED_COMMANDS = ["Include", "Convolution", "Delay", "Copy", "Eval", "If", "ElseIf", "Else", "EndIf", "Stage",
                    "VSTPlugin", "LoudnessCorrection"]
KNOWN_COMMANDS = ["Preamp", "Channel", "GraphicEQ", "Device"] + REFUSED_COMMANDS
TYPE_PHRASE = {"peak": "a peak filter", "lowShelf": "a low-shelf filter", "highShelf": "a high-shelf filter",
               "lowPass": "a low-pass filter", "highPass": "a high-pass filter", "bandPass": "a band-pass filter",
               "notch": "a notch filter", "allPass": "an all-pass filter"}
MAX_BYTES = 256 * 1024
MOST_FILTERS = 64

CP1252 = {0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021,
          0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018,
          0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC,
          0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178}


class Refused(Exception):
    def __init__(self, kind, line, text):
        super().__init__(text)
        self.kind, self.line, self.text = kind, line, text


def ascii_lower(text):
    return "".join(chr(ord(c) + 32) if "A" <= c <= "Z" else c for c in text)


def wcstod(text):
    match = DECIMAL.match(text)
    return float(match.group(0)) if match else 0.0


def get_freq(run):
    """BiQuadFilterFactory::getFreq: the non-breaking spaces dropped; no number is -1; five or more characters, no
    exponent, a point fourth from the end, is thousands (REW's "1.000")."""
    s = run.replace(NBSP, "")
    match = DECIMAL.match(s)
    if not match:
        return -1.0
    result = float(match.group(0))
    if len(s) >= 5 and "e" not in s and "E" not in s and s[len(s) - 4] == ".":
        result *= 1000.0
    return result


def cut(line):
    text = line.strip(WS_CHARS)
    if len(text) > 40:
        text = text[:40].rstrip(WS_CHARS) + ELLIPSIS
    return text


def unknown_note(n, line, hint):
    text = "Line %d isn't something Equalizer APO plays either (%s)" % (n, cut(line))
    if hint:
        text += ' - it reads "%s" only as written, capital and all' % hint
    return {"kind": "unknown", "first": n, "last": n, "text": text + "."}


def case_hint(key):
    lowered = ascii_lower(key)
    for known in KNOWN_COMMANDS:
        if lowered == ascii_lower(known):
            return known
    if lowered.startswith("filter"):
        return "Filter"
    return None


def positions(words):
    """The positions a phone doesn't have, in words: 'the centre channel (C)', 'the rear channels (RL, RR)'..."""
    groups, order = {}, []
    for word in words:
        if word == "C":
            key = "centre"
        elif word in ("LFE", "SUB"):
            key = "sub"
        elif word in ("RL", "RR"):
            key = "rear"
        elif word == "RC":
            key = "rearCentre"
        elif word in ("SL", "SR"):
            key = "side"
        else:
            key = "other"
        if key not in groups:
            groups[key] = []
            order.append(key)
        if word not in groups[key]:
            groups[key].append(word)
    phrases = []
    for key in order:
        ws = groups[key]
        listed = ", ".join(ws)
        if key == "centre":
            phrases.append("the centre channel (%s)" % listed)
        elif key == "sub":
            phrases.append("the subwoofer channel (%s)" % listed)
        elif key == "rear":
            phrases.append("the rear channel%s (%s)" % ("s" if len(ws) > 1 else "", listed))
        elif key == "rearCentre":
            phrases.append("the rear centre channel (%s)" % listed)
        elif key == "side":
            phrases.append("the side channel%s (%s)" % ("s" if len(ws) > 1 else "", listed))
        else:
            phrases.append(("channel " if len(ws) == 1 else "channels ") + and_list(ws))
    return and_list(phrases)


def and_list(items):
    if len(items) == 1:
        return items[0]
    return ", ".join(items[:-1]) + " and " + items[-1]


def channel_note(first, last, words):
    one = first == last
    where = "Line %d is" % first if one else "Lines %d-%d are" % (first, last)
    if not words:
        text = "%s for no channel: the Channel line before %s names none." % (where, "it" if one else "them")
    else:
        text = "%s for %s, which a phone doesn't have." % (where, positions(words))
    return {"kind": "channels", "first": first, "last": last, "text": text}


def channel_words(value):
    """ChannelFilterFactory: split at spaces only, upper-cased."""
    return [word for word in ascii_upper(value).split(" ") if word]


def ascii_upper(text):
    return "".join(chr(ord(c) - 32) if "a" <= c <= "z" else c for c in text)


def selection(words):
    """Which of a phone's two channels a Channel line selects, as APO selects on a stereo device."""
    chosen = set()
    for word in words:
        if word == "ALL":
            chosen |= {"L", "R"}
        elif word[0].isdigit() and word[0] in "0123456789":
            digits = re.match("[0-9]+", word).group(0)
            index = int(digits)
            if index == 1:
                chosen.add("L")
            elif index == 2:
                chosen.add("R")
        elif word in ("L", "R"):
            chosen.add(word)
    return chosen


def left_out(n, kind, reason, near, type_name=None):
    who = "Line %d (%s)" % (n, TYPE_PHRASE[kind]) if kind else "Line %d" % n
    why = {"frequency": "it has no frequency", "gain": "it has no gain",
           "width": "it has no width (a Q or a BW Oct; 0 counts as none, as in APO)",
           "onOff": "it has no ON or OFF"}.get(reason) or 'it has an unknown type ("%s")' % type_name
    text = "%s is left out, as Equalizer APO leaves it out: %s" % (who, why)
    if near:
        text += " - " + near
    return {"kind": "leftOut", "first": n, "last": n, "text": text + "."}


def says(match, reads):
    return 'it says "%s", and Equalizer APO reads only "%s"' % (match.group(0).lstrip(WS_CHARS), reads)


def parse_filter(n, value, channel):
    """One Filter line: (filter or None, note or None). Raises Refused."""
    v = value.replace(",", ".")
    on = True
    m = RE_ON.match(v)
    if not m:
        on = False
        m = RE_OFF.match(v)
    if not m:
        near = None
        miss = RE_ON_OFF_CI.match(v)
        if miss:
            near = 'it says "%s", and Equalizer APO reads only "%s"' % (miss.group(1), ascii_upper(miss.group(1)))
        return None, left_out(n, None, "onOff", near)
    written = m.group(1)
    rest = v[m.end():]
    if written == "None":
        return None, None
    if written == "IIR":
        raise Refused("iir", n, "Line %d gives a filter as raw coefficients, made for one sample rate - deadwax "
                                "plays at several, so it can't play it." % n)
    kind = TYPES.get(written)
    if kind is None:
        near = None
        for known in TYPES:
            if ascii_lower(known) == ascii_lower(written):
                near = 'Equalizer APO knows the type as "%s"' % known
        return None, left_out(n, None, "type", near, written)

    errors = []
    fc = None
    m = RE_FC.search(rest)
    if m:
        fc = get_freq(m.group(1))
    else:
        miss = RE_FC_CI.search(rest)
        if miss:
            near = says(miss, "Fc %s Hz" % miss.group(1))
        elif RE_FC_NO_HZ.search(rest):
            near = 'its frequency has no "Hz" after it, which Equalizer APO needs'
        else:
            miss = RE_FC_NO_HZ_CI.search(rest)
            near = says(miss, "Fc %s Hz" % miss.group(1)) if miss else None
        errors.append(("frequency", near))
    gain = 0.0
    m = RE_GAIN.search(rest)
    if m:
        if kind not in ("lowPass", "highPass", "notch", "allPass"):
            gain = wcstod(m.group(1))
    elif kind in GAINED:
        miss = RE_GAIN_CI.search(rest)
        errors.append(("gain", says(miss, "Gain %s dB" % miss.group(1)) if miss else None))
    width = None
    m = RE_Q.search(rest)
    if m:
        width = ("q", wcstod(m.group(1)))
    m = RE_BW.search(rest)
    if m and kind not in SHELVES:
        width = ("bandwidth", wcstod(m.group(1)))
    m = RE_SLOPE.search(rest)
    if m and kind in SHELVES:
        width = ("slope", wcstod(m.group(1)))
    if kind in ("peak", "allPass") and (width is None or width[1] == 0):
        near = None
        if not RE_Q.search(rest) and RE_Q_CI.search(rest):
            miss = RE_Q_CI.search(rest)
            near = says(miss, "Q %s" % miss.group(1))
        elif not RE_BW.search(rest) and RE_BW_CI.search(rest):
            miss = RE_BW_CI.search(rest)
            near = says(miss, "BW Oct %s" % miss.group(1))
        errors.append(("width", near))
    if errors:
        reason, near = errors[0]
        return None, left_out(n, kind, reason, near)

    if fc < 1:
        raise Refused("frequencyLow", n, "Line %d: a filter's frequency must be at least 1 Hz." % n)
    if fc > 22000:
        raise Refused("frequencyHigh", n, "Line %d: %s Hz is higher than this phone plays - the highest a filter "
                                          "can be is 22000 Hz." % (n, num(fc)))
    if kind in GAINED and not -30 <= gain <= 30:
        raise Refused("gain", n, "Line %d: a gain of %s dB is more than deadwax plays - at most 30 dB either way."
                      % (n, num(gain)))
    if width is not None:
        wk, wv = width
        if wk == "q" and wv != 0 and not 0.01 <= wv <= 100:
            raise Refused("q", n, "Line %d: Q %s won't make a filter - it must be between 0.01 and 100, or left out."
                          % (n, num(wv)))
        if wk == "bandwidth" and wv != 0 and not 0.01 <= wv <= 10:
            raise Refused("width", n, "Line %d: a width of %s octaves won't make a filter - it must be between 0.01 "
                                      "and 10, or left out." % (n, num(wv)))
        if wk == "slope" and wv < 0:
            raise Refused("slope", n, "Line %d: a slope of %s dB won't make a filter - it must be above 0."
                          % (n, num(wv)))
        if wk == "slope" and wv > 0 and shelf_radicand(gain, wv / 12.0) <= 0:
            raise Refused("tooSteep", n, "Line %d: %s this steep (%s dB an octave) can't have %s dB of gain - "
                                         "Equalizer APO can't play it either."
                          % (n, TYPE_PHRASE[kind], num(wv), num(gain)))
    corner = (kind in SHELVES and not written.endswith("C") and width is not None and width[0] in ("q", "slope")
              and width[1] != 0)
    return {"kind": kind, "written": written, "fc": fc, "gain": gain, "width": width, "corner": corner,
            "channel": channel, "on": on}, None


def decode_lines(data):
    """(lines, utf16). Raises Refused for UTF-16 that doesn't decode, and for lines that end in a CR alone."""
    cr_only = ("This file's lines end the old Mac way, which Equalizer APO reads as one long line. Save it again "
               "from a text editor and import that.")
    if data[:2] in (b"\xff\xfe", b"\xfe\xff"):
        encoding = "utf-16-le" if data[:2] == b"\xff\xfe" else "utf-16-be"
        try:
            text = data[2:].decode(encoding)
        except UnicodeDecodeError:
            raise Refused("unreadable", None, "deadwax couldn't read this file.")
        if "\n" not in text and "\r" in text[:-1]:
            raise Refused("crOnly", None, cr_only)
        return [line[:-1] if line.endswith("\r") else line for line in text.split("\n")], True
    if data[:3] == b"\xef\xbb\xbf":
        data = data[3:]
    if b"\n" not in data and b"\r" in data[:-1]:
        raise Refused("crOnly", None, cr_only)
    lines = []
    for raw in data.split(b"\n"):
        if raw.endswith(b"\r"):
            raw = raw[:-1]
        line = raw.decode("utf-8", errors="replace")
        if REPLACEMENT in line:
            line = "".join(chr(CP1252.get(byte, byte)) for byte in raw)
        lines.append(line)
    return lines, False


def read_apo(data, pasted=False):
    try:
        return read_apo_or_refuse(data, pasted)
    except Refused as refusal:
        return {"refused": {"kind": refusal.kind, "line": refusal.line, "text": refusal.text}}


def read_apo_or_refuse(data, pasted):
    if len(data) > MAX_BYTES:
        raise Refused("tooBig", None, "This file is too big to be an EQ file (%s)." % bytes_words(len(data)))
    lines, utf16 = decode_lines(data)
    notes = []
    filters, graphic = [], []
    preamp = {"all": 0.0, "left": 0.0, "right": 0.0}
    read_preamp = False
    chosen = {"L", "R"}
    group = None
    playing_seen = False
    devices = 0

    def close_group():
        if group is not None and group[1] is not None:
            notes.append(channel_note(group[1], group[2], group[0]))

    for n, line in enumerate(lines, 1):
        if ":" not in line:
            text = line.strip(WS_CHARS)
            if text and not text.startswith("#"):
                notes.append(unknown_note(n, line, None))
            continue
        key, value = line.split(":", 1)
        key = key.strip(WS_CHARS)
        if key.startswith("#"):
            continue
        if key == "Device":
            if devices or playing_seen:
                raise Refused("devices", n, "This file has settings for more than one device (line %d). deadwax "
                                            "keeps a setting for each output itself - import the part for these "
                                            "headphones as a file of its own." % n)
            devices += 1
            notes.append({"kind": "device", "first": n, "last": n,
                          "text": "Line %d (%s) chooses a device in Equalizer APO - deadwax keeps a setting for each "
                                  "output itself." % (n, cut(line))})
            continue
        if key == "Include":
            raise Refused("include", n, "Line %d includes another file (%s). Import that file itself."
                          % (n, value.strip(WS_CHARS)))
        if key in REFUSED_COMMANDS:
            raise Refused("unsupported", n, "Line %d uses %s, which deadwax can't play." % (n, key))
        if not (key in ("Preamp", "Channel", "GraphicEQ") or key.startswith("Filter")):
            notes.append(unknown_note(n, line, case_hint(key)))
            continue
        playing_seen = True
        if key == "Channel":
            close_group()
            words = channel_words(value)
            chosen = selection(words)
            group = None if chosen else [words, None, None]
            continue
        if not chosen:
            group[1] = group[1] or n
            group[2] = n
            continue
        channel = "all" if chosen == {"L", "R"} else ("left" if chosen == {"L"} else "right")
        if key == "Preamp":
            m = RE_PREAMP.match(value.replace(",", "."))
            if not m:
                notes.append(unknown_note(n, line, None))
                continue
            amount = float(m.group(1))
            if not -30 <= amount <= 30:
                raise Refused("preamp", n, "Line %d: a preamp of %s dB is more than deadwax plays - at most 30 dB "
                                           "either way." % (n, num(amount)))
            preamp[channel] += amount
            read_preamp = True
        elif key == "GraphicEQ":
            v = value if "." in value else value.replace(",", ".")
            numbers = [wcstod(run) for run in re.findall(RUN, v)]
            pairs = list(zip(numbers[0::2], numbers[1::2]))
            if not pairs:
                raise Refused("graphicEmpty", n, "Line %d: a GraphicEQ line needs at least one frequency and its "
                                                 "gain." % n)
            for f, _ in pairs:
                if not f > 0:
                    raise Refused("graphicZero", n, "Line %d: a GraphicEQ's frequencies must be above 0 Hz (%s is "
                                                    "there)." % (n, num(f)))
            for _, g in pairs:
                if not -30 <= g <= 30:
                    raise Refused("gain", n, "Line %d: a gain of %s dB is more than deadwax plays - at most 30 dB "
                                             "either way." % (n, num(g)))
            graphic.append({"channel": channel, "line": n, "points": sorted(pairs, key=lambda p: p[0])})
        else:
            made, note = parse_filter(n, value, channel)
            if note:
                notes.append(note)
            if made:
                made["id"] = len(filters) + 1
                filters.append(made)
    close_group()

    fits = []
    if graphic:
        ears = ["left", "right"] if any(g["channel"] != "all" for g in graphic) else ["all"]
        for ear in ears:
            lines_for = [g["points"] for g in graphic if g["channel"] in ("all", ear)]
            fit = fit_graphic(lines_for)
            for centre, gain in zip(fit["centres"], fit["rounded"]):
                if gain != 0:
                    filters.append({"id": len(filters) + 1, "kind": "peak", "written": "PK", "fc": centre,
                                    "gain": gain, "width": ("q", GRAPHIC_Q), "corner": False, "channel": ear,
                                    "on": True})
            preamp[ear] += fit["median"]
            fits.append({"ear": ear, "filters": fit["kept"], "median": r(fit["median"]), "rounds": fit["rounds"],
                         "mean": r(fit["stats48"]["mean"]), "largest": r(fit["stats48"]["largest"]),
                         "above": r(fit["stats48"]["above"]), "aboveAt": r(fit["stats48"]["aboveAt"])})

    for ear in ("left", "right"):
        count = sum(1 for f in filters if f["channel"] in ("all", ear))
        if count > MOST_FILTERS:
            raise Refused("tooMany", None, "This file has %d filters for one ear - deadwax plays up to 64." % count)
    if not read_preamp and not filters and not graphic:
        raise Refused("nothing", None, "There's no EQ in %s: no Preamp, Filter or GraphicEQ lines."
                      % ("what you pasted" if pasted else "this file"))

    extra = max(preamp["left"], preamp["right"])
    parts = {"all": preamp["all"] + extra, "left": preamp["left"] - extra, "right": preamp["right"] - extra}
    notes.sort(key=lambda note: note["first"])
    if utf16:
        notes.insert(0, {"kind": "utf16", "first": None, "last": None,
                         "text": "This file is saved as UTF-16, which Equalizer APO doesn't read - deadwax read it "
                                 "anyway."})
    return {"refused": None, "filters": filters, "preamp": parts, "graphic": graphic, "fits": fits, "notes": notes}


def filter_json(f):
    width = None if f["width"] is None else {f["width"][0]: r(f["width"][1])}
    return {"id": f.get("id", 0), "kind": f["kind"], "written": f["written"], "fc": r(f["fc"]), "gain": r(f["gain"]),
            "width": width, "corner": f["corner"], "channel": f["channel"], "on": f["on"]}


def reading_json(reading):
    if reading.get("refused"):
        return {"refused": reading["refused"]}
    return {"refused": None,
            "filters": [filter_json(f) for f in reading["filters"]],
            "preamp": {k: r(v) for k, v in reading["preamp"].items()},
            "graphic": [{"channel": g["channel"], "line": g["line"], "points": [[r(f), r(g_)] for f, g_ in g["points"]]}
                        for g in reading["graphic"]],
            "fits": reading["fits"],
            "notes": reading["notes"]}


# ------------------------------------------------------------------------------------------------ GraphicEQ (3.10)

GRAPHIC_Q = 4.32
GRAPHIC_RATE = 48000.0
GRAPHIC_LAMBDA = 1e-4
GRAPHIC_STEP = 1e-3


def graphic_grid():
    out, k = [], 0
    while 20 * 2 ** (k / 48) <= 21000:
        out.append(20 * 2 ** (k / 48))
        k += 1
    return out


def graphic_target(lines, frequencies):
    """Each line's points linear on log frequency between them, flat outside (GainIterator.cpp), summed."""
    out = []
    for f in frequencies:
        total = 0.0
        for points in lines:
            freqs = [p[0] for p in points]
            j = 0
            while j < len(freqs) and freqs[j] < f:
                j += 1
            if j == 0:
                total += points[0][1]
            elif j == len(freqs):
                total += points[-1][1]
            else:
                (fl, gl), (fr, gr) = points[j - 1], points[j]
                if gl == gr:
                    total += gl
                else:
                    log_left = math.log(fl)
                    t = (math.log(f) - log_left) / (math.log(fr) - log_left)
                    total += gl + t * (gr - gl)
        out.append(total)
    return out


def median(values):
    ordered = sorted(values)
    n = len(ordered)
    return ordered[n // 2] if n % 2 else (ordered[n // 2 - 1] + ordered[n // 2]) / 2


def graphic_centres():
    return [round_away(1000 * 2 ** (k / 6)) for k in range(-34, 27)]


def peak_db(fc, gain, trig, rate=GRAPHIC_RATE):
    return section_db(cookbook("peak", gain, fc, rate, GRAPHIC_Q, False), trig)


def fit_graphic(lines):
    grid = graphic_grid()
    trig = trig_of(grid, GRAPHIC_RATE)
    level = median(graphic_target(lines, [f for f in grid if f <= 20000]))
    target = np.array(graphic_target(lines, grid)) - level
    centres = graphic_centres()
    gains = np.zeros(len(centres))
    n = len(grid)
    rounds = 0
    for rounds in range(1, 51):
        model = sum(peak_db(c, g, trig) for c, g in zip(centres, gains))
        residual = model - target
        jacobian = np.array([(peak_db(c, g + GRAPHIC_STEP, trig) - peak_db(c, g - GRAPHIC_STEP, trig))
                             / (2 * GRAPHIC_STEP) for c, g in zip(centres, gains)]).T
        normal = jacobian.T @ jacobian / n + GRAPHIC_LAMBDA * np.eye(len(gains))
        rhs = -(jacobian.T @ residual / n + GRAPHIC_LAMBDA * gains)
        step = np.linalg.solve(normal, rhs)
        moved_to = np.clip(gains + step, -30, 30)
        moved = float(np.max(np.abs(moved_to - gains)))
        gains = moved_to
        if moved <= 0.001:
            break
    rounded = [round_away(g * 10) / 10 for g in gains]
    kept = [(c, g) for c, g in zip(centres, rounded) if g != 0]

    def stats(rate):
        p = trig_of(grid, rate)
        model = sum((section_db(cookbook("peak", g, c, rate, GRAPHIC_Q, False), p) for c, g in kept),
                    np.zeros(n))
        diff = np.abs(model - target)
        low = np.array(grid) <= 16000
        above = diff[~low]
        at = int(np.argmax(above))
        return {"mean": float(np.mean(diff[low])), "rms": float(math.sqrt(np.mean(diff[low] ** 2))),
                "largest": float(np.max(diff[low])), "above": float(above[at]),
                "aboveAt": float(np.array(grid)[~low][at])}
    return {"centres": centres, "median": level, "target": target, "unrounded": [float(g) for g in gains],
            "rounded": rounded, "kept": len(kept), "rounds": rounds, "stats48": stats(48000.0),
            "stats44": stats(44100.0)}


# ------------------------------------------------------------------------------------------------ the preamp (1.4)

def curve_db(sections, frequencies, rate, offset=0.0):
    trig = trig_of(frequencies, rate)
    total = np.full(len(frequencies), offset)
    for _, coefficients in sections:
        total = total + section_db(coefficients, trig)
    return total


GOLDEN = (math.sqrt(5) - 1) / 2


def refine(sections, rate, offset, lo, hi):
    """The largest of the curve between two frequencies: 80 rounds of golden-section search on log frequency."""
    def at(u):
        return float(curve_db(sections, [math.exp(u)], rate, offset)[0])
    a, b = math.log(lo), math.log(hi)
    c = b - GOLDEN * (b - a)
    d = a + GOLDEN * (b - a)
    fc, fd = at(c), at(d)
    best = max(fc, fd)
    for _ in range(80):
        if fc >= fd:
            b, d, fd = d, c, fc
            c = b - GOLDEN * (b - a)
            fc = at(c)
        else:
            a, c, fc = c, d, fd
            d = a + GOLDEN * (b - a)
            fd = at(d)
        best = max(best, fc, fd)
    return best


def top_of(ears, rate, refined=True):
    """The curve's top over every ear: (sections, offset dB) each. DC, every 1/48 octave from 10 Hz to below
    Nyquist, each f0, and Nyquist; each local maximum refined between its neighbours (a neighbour at DC: an
    octave below the point)."""
    points = {0.0, rate / 2}
    points.update(response_grid(rate))
    for sections, _ in ears:
        points.update(f0 for f0, _ in sections if 0 < f0 < rate / 2)
    points = sorted(points)
    best, best_at = -math.inf, 0.0
    for sections, offset in ears:
        values = curve_db(sections, points, rate, offset)
        for i, v in enumerate(values):
            if (i > 0 and v < values[i - 1]) or (i + 1 < len(values) and v < values[i + 1]):
                continue
            here = float(v)
            if refined and 0 < i < len(points) - 1:
                lo = points[i - 1] if points[i - 1] > 0 else points[i] / 2
                here = max(here, refine(sections, rate, offset, lo, points[i + 1]))
            if here > best:
                best, best_at = here, points[i]
    return best, best_at


def automatic_preamp(top):
    """-ceil(top x 10) / 10 above 0 dB, else 0 - never a boost. A top within 1e-9 dB of a tenth counts as on it."""
    if top <= 1e-9:
        return 0.0
    return -(math.ceil((top - 1e-9) * 10) / 10)


# ------------------------------------------------------------------------------------------------ the presets (3.5, 3.6)

BANDS = [1000.0 * 2.0 ** k for k in range(-5, 5)]
BAND_Q = 1.41
PRESETS = [
    ("flat", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    ("bassBoost", [5, 4.5, 3, 1, 0, 0, 0, 0, 0, 0]),
    ("bassReduce", [-5, -4.5, -3, -1, 0, 0, 0, 0, 0, 0]),
    ("trebleBoost", [0, 0, 0, 0, 0, 0, 1, 2.5, 3.5, 4.5]),
    ("trebleReduce", [0, 0, 0, 0, 0, 0, -1, -2.5, -3.5, -4.5]),
    ("vocal", [-2, -1.5, -1, 0, 1, 2, 2.5, 2, 0.5, 0]),
    ("loudness", [5, 4, 2, 0.5, 0, 0, 0, 1, 2.5, 3]),
    ("smallSpeakers", [-4, -1, 2.5, 2.5, 1, 0, 0, 1, 1.5, 0]),
    ("spokenWord", [-6, -4.5, -2.5, -1, 0, 1, 2.5, 3, 1.5, -1]),
]


def band_sections(gains, rate):
    out = []
    for fc, gain in zip(BANDS, gains):
        if gain != 0:
            out.append((fc, cookbook("peak", float(gain), fc, rate, BAND_Q, False)))
    return out


def lowest_of(sections, rate):
    """The curve's lowest point, on a 1/480-octave grid from 10 Hz (for the table; nothing is held to it)."""
    dense = [10 * 2 ** (k / 480) for k in range(0, 480 * 15) if 10 * 2 ** (k / 480) < rate / 2]
    values = curve_db(sections, dense, rate)
    i = int(np.argmin(values))
    return float(values[i]), dense[i]


# ------------------------------------------------------------------------------------------------ the hand-made APO files

def apo_files():
    plain = ["Preamp: -6.0 dB",
             "Filter 1: ON LSC Fc 105 Hz Gain 2.6 dB Q 0.70",
             "Filter 2: ON PK Fc 514 Hz Gain -4.4 dB Q 0.68",
             "Filter 3: ON HSC Fc 10000 Hz Gain -0.5 dB Q 0.70"]

    def text(lines, ending="\n"):
        return (ending.join(lines) + ending).encode("utf-8")

    files = {}
    files["a01-plain.txt"] = text(plain)
    files["a02-utf8-bom.txt"] = b"\xef\xbb\xbf" + text(plain)
    files["a03-notepad-unicode.txt"] = text(["# Notepad's Unicode"] + plain, "\r\n")
    files["a05-cp1252.txt"] = (b"# R\xe9glage pour casque \x80 \x81\r\n" + "\r\n".join(plain).encode("ascii")
                               + b"\r\n")
    files["a06-crlf.txt"] = text(plain, "\r\n")
    files["a07-cr-only.txt"] = "\r".join(plain).encode("ascii") + b"\r"
    files["a08-comments.txt"] = text([
        "# A comment",
        "#Preamp: -3 dB",
        "",
        "   ",
        "Filter 1: ON PK Fc 100 Hz Gain 3 dB Q 1 # Gain 9 dB Fc 200 Hz",
        "this line has no colon",
        "   # an indented comment",
        "Preamp: -2 dB # headroom",
    ])
    files["a09-case.txt"] = text([
        "preamp: -6 dB",
        "filter 1: ON PK Fc 100 Hz Gain 3 dB Q 1",
        "Channel: l r",
        "Filter: ON pk Fc 200 Hz Gain 2 dB Q 1",
        "Filter: on PK Fc 300 Hz Gain 2 dB Q 1",
        "Filter: ON PK fc 400 Hz Gain 2 dB Q 1",
        "Filter: ON PK Fc 500 Hz gain 2 dB Q 1",
        "Filter: ON PK Fc 600 Hz Gain 2 dB q 1",
        "Filter: ON PK Fc 700 Hz Gain 2 dB Q 1",
        "Filter: ON NO Fc 800 hz",
        "Filter: ON PK Fc 900 Hz Gain 2 dB bw oct 1",
        "PREAMP: -1 dB",
        "graphiceq: 20 0; 20000 0",
    ])
    files["a10-units.txt"] = text([
        "Filter: ON PK Fc 100 Gain 3 dB Q 1",
        "Filter: ON PK Fc 200 Hz Gain 3 Q 1",
        "Filter: ON PK Fc 300 H z Gain 3 dB Q 1",
        "Filter: ON PK Fc 400Hz Gain 3dB Q1",
        "Filter: ON PK Fc  500  Hz  Gain  -3  dB  Q  2",
        "Filter: ON PK Fc\t600\tHz\tGain\t-3\tdB\tQ\t2",
    ])
    files["a11-commas.txt"] = text([
        "Preamp: -6,5 dB",
        "Filter: ON PK Fc 1000 Hz Gain 6,5 dB Q 1,41",
        "Filter: ON LSC Fc 105,5 Hz Gain -2,5 dB Q 0,7",
    ])
    files["a12-thousands.txt"] = text([
        "Filter: ON PK Fc 1.000 Hz Gain 1 dB Q 1",
        "Filter: ON PK Fc 12.345 Hz Gain 1 dB Q 1",
        "Filter: ON PK Fc 10.000 Hz Gain 1 dB Q 1",
        "Filter: ON PK Fc 1,000 Hz Gain 1 dB Q 1",
        "Filter: ON PK Fc 1.5e3 Hz Gain 1 dB Q 1",
        "Filter: ON PK Fc 100.0 Hz Gain 1 dB Q 1",
        "Filter: ON PK Fc 1000.5 Hz Gain 1 dB Q 1",
        "Filter: ON PK Fc 2.0000 Hz Gain 1 dB Q 1",
        "Filter: ON PK Fc 22.000 Hz Gain 1 dB Q 1",
        "Filter: ON PK Fc 1" + NBSP + "500 Hz Gain 1 dB Q 1",
        "Filter: ON PK Fc 12.3450 Hz Gain 1 dB Q 1",
    ])
    files["a13-numbers.txt"] = text([
        "Filter: ON PK Fc 100 Hz Gain 6.5.1 dB Q 1",
        "Filter: ON PK Fc 200 Hz Gain 1 dB Q 1e0",
        "Filter: ON PK Fc 1e3 Hz Gain 1 dB Q 1",
        "Filter: ON PK Fc 300 Hz Gain -.5 dB Q .7",
        "Filter: ON PK Fc 400 Hz Gain +3 dB Q 1.",
        "Filter: ON PK Fc 500 Hz Gain 1e dB Q 1",
        "Filter: ON PK Fc 600 Hz Gain - dB Q 1",
        "Filter: ON PK Fc 700 Hz Gain 2 dB Q 2.5e-1",
    ])
    files["a14-off.txt"] = text([
        "Filter 1: OFF PK Fc 100 Hz Gain 3 dB Q 1",
        "Filter 2: PK Fc 200 Hz Gain 3 dB Q 1",
        "Filter 3: ON None",
        "Filter 4: ON PK Fc 300 Hz Gain 3 dB Q 1",
        "Filter 5: OFF LS 6dB Fc 80 Hz Gain 4 dB",
        "Filter 6:",
    ])
    files["a15-order.txt"] = text([
        "Filter: ON PK Q 2 Gain -3 dB Fc 250 Hz",
        "Filter: ON LSC Gain 4 dB Fc 80 Hz Q 0.7",
        "Filter: ON PK Gain 1 dB Q 3 Fc 5000 Hz Gain 9 dB Fc 6000 Hz Q 9",
        "Filter: ON PK Fc 100 Gain 2 dB Fc 7000 Hz Q 1",
    ])
    files["a16-preamps.txt"] = text([
        "Preamp: -3 dB",
        "Preamp: -1.5",
        "Channel: L",
        "Preamp: -1 dB",
        "Channel: R",
        "Preamp: 0.5 dB foo",
        "Channel: L R",
        "Preamp: -0.25 dB",
        "Channel: all",
        "Filter: ON PK Fc 1000 Hz Gain 3 dB Q 1",
        "Preamp:   -2dB",
    ])
    files["a17-ears.txt"] = text([
        "Filter: ON PK Fc 100 Hz Gain 1 dB Q 1",
        "Channel: L",
        "Filter: ON PK Fc 200 Hz Gain 2 dB Q 1",
        "Channel: 2",
        "Filter: ON PK Fc 300 Hz Gain 3 dB Q 1",
        "Channel: 1 2",
        "Filter: ON PK Fc 400 Hz Gain 4 dB Q 1",
        "Channel: R",
        "Filter: ON PK Fc 500 Hz Gain 5 dB Q 1",
        "Channel: ALL",
        "Filter: ON PK Fc 600 Hz Gain 6 dB Q 1",
        "Channel: L C",
        "Filter: ON PK Fc 700 Hz Gain 7 dB Q 1",
        "Channel: 1",
        "Filter: ON PK Fc 800 Hz Gain 8 dB Q 1",
    ])
    files["a18-positions.txt"] = text([
        "Filter: ON PK Fc 100 Hz Gain 1 dB Q 1",
        "Channel: C",
        "Preamp: -3 dB",
        "Filter: ON PK Fc 200 Hz Gain 2 dB Q 1",
        "# a comment between",
        "Filter: ON PK Fc 300 Hz Gain 3 dB Q 1",
        "Channel: LFE",
        "Filter: ON LP Fc 80 Hz",
        "Channel: RL RR",
        "Filter: ON PK Fc 400 Hz Gain 4 dB Q 1",
        "Filter: ON PK Fc 500 Hz Gain 5 dB Q 1",
        "Channel: SL SR",
        "Filter: ON PK Fc 600 Hz Gain 6 dB Q 1",
        "Channel: RC",
        "GraphicEQ: 20 1; 20000 1",
        "Channel: 3",
        "Filter: ON PK Fc 700 Hz Gain 7 dB Q 1",
        "Channel: SUB",
        "Filter: ON PK Fc 800 Hz Gain 8 dB Q 1",
        "Channel: C LFE",
        "Filter: ON PK Fc 900 Hz Gain 9 dB Q 1",
        "Channel: C",
        "Channel: L",
        "Filter: ON PK Fc 1000 Hz Gain 1 dB Q 1",
        "Channel: XYZ 4",
        "Filter: ON PK Fc 1100 Hz Gain 1 dB Q 1",
        "Channel: RR",
        "Filter: ON PK Fc 1200 Hz Gain 1 dB Q 1",
    ])
    files["a19-device.txt"] = text([
        "# for the laptop",
        "Device: Realtek High Definition Audio Speakers; Headphones",
        "Preamp: -3 dB",
        "Filter: ON PK Fc 1000 Hz Gain 3 dB Q 1",
    ])
    files["a20-devices.txt"] = text([
        "Device: Speakers",
        "Filter: ON PK Fc 1000 Hz Gain 3 dB Q 1",
        "Device: Headphones",
        "Filter: ON PK Fc 2000 Hz Gain -3 dB Q 1",
    ])
    files["a21-device-late.txt"] = text(["Preamp: -3 dB", "Device: Headphones",
                                         "Filter: ON PK Fc 2000 Hz Gain -3 dB Q 1"])
    files["a22-include.txt"] = text(["Preamp: -3 dB", "Filter: ON PK Fc 2000 Hz Gain -3 dB Q 1", "Include: bass.txt"])
    files["a23-convolution.txt"] = text(["Preamp: -3 dB", "Convolution: room.wav"])
    files["a24-if.txt"] = text(["Filter: ON PK Fc 2000 Hz Gain -3 dB Q 1", "If: sampleRate > 48000", "EndIf:"])
    files["a25-iir.txt"] = text(["Preamp: -1 dB", "Filter: ON IIR Order 2 Coefficients 1 0 0 1 0 0"])
    files["a26-high.txt"] = text(["Filter: ON PK Fc 1000 Hz Gain 1 dB Q 1", "Filter: ON PK Fc 30000 Hz Gain 1 dB Q 1"])
    files["a27-low.txt"] = text(["Filter: ON HP Fc 0.5 Hz"])
    files["a28-gain.txt"] = text(["Filter: ON PK Fc 1000 Hz Gain 45 dB Q 1"])
    files["a29-q.txt"] = text(["Filter: ON PK Fc 1000 Hz Gain 3 dB Q -2"])
    files["a30-bw.txt"] = text(["Filter: ON PK Fc 1000 Hz Gain 3 dB BW Oct 12"])
    files["a31-slope.txt"] = text(["Filter: ON LSC -6 dB Fc 100 Hz Gain 3 dB"])
    files["a32-steep.txt"] = text(["Filter: ON HS 12dB Fc 8000 Hz Gain 3 dB",
                                   "Filter: ON LSC 24 dB Fc 100 Hz Gain 23 dB"])
    files["a33-preamp-range.txt"] = text(["Preamp: 45 dB"])
    files["a34-too-many.txt"] = text(["Preamp: -3 dB"] + [
        "Filter %d: ON PK Fc %d Hz Gain %.1f dB Q 1.41" % (i + 1, 20 + 200 * i, (i % 7) - 3) for i in range(90)])
    files["a35-graphic-empty.txt"] = text(["Preamp: -2 dB", "GraphicEQ: "])
    files["a36-graphic-zero.txt"] = text(["GraphicEQ: 0 -3; 20 -3; 20000 -1"])
    files["a37-graphic-comma.txt"] = text(["GraphicEQ: 1000 -3,5; 20 -3,4; 200 1,5; 10000 2"])
    files["a38-graphic-point.txt"] = text(["GraphicEQ: 20 -3.5; 1000 2,5"])
    files["a39-nothing.txt"] = text(["# nothing here plays", "Volume: 5", "preamp: -3 dB",
                                     "Filter: ON PK Fc 1000 Hz Gain 3 dB"])
    files["a40-unknown.txt"] = text([
        "Volume: 5",
        "Preamp: abc",
        ": nothing before the colon",
        "Loudness Correction: on and on and on, a line longer than forty characters",
        "convolution: room.wav",
        "Filter: ON PK Fc 1000 Hz Gain 3 dB Q 1",
        "Filter: ON XYZ Fc 2000 Hz Gain 3 dB Q 1",
        "Filter: ON Peq Fc 3000 Hz Gain 3 dB Q 1",
        "Filter: ON PK Fc 4000 Hz Gain 6 Q 1",
    ])
    files["a41-forms.txt"] = text([
        "Filter: ON PK Fc 1000 Hz Gain 3 dB Q 1.41",
        "Filter: ON PEQ Fc 2000 Hz Gain -2 dB Q 2",
        "Filter: ON Modal Fc 60 Hz Gain -6 dB Q 5 T60 target 300 ms",
        "Filter: ON PK Fc 3000 Hz Gain 2 dB BW Oct 1",
        "Filter: ON PK Fc 3500 Hz Gain 2 dB Q 2 BW Oct 0.5",
        "Filter: ON LSC Fc 105 Hz Gain 2.6 dB Q 0.7",
        "Filter: ON LSC 12 dB Fc 120 Hz Gain 4 dB",
        "Filter: ON LSC Fc 90 Hz Gain 3 dB",
        "Filter: ON HSC Fc 10000 Hz Gain -0.5 dB Q 0.7",
        "Filter: ON HSC 6 dB Fc 8000 Hz Gain 2 dB",
        "Filter: ON LS Fc 100 Hz Gain 5 dB Q 0.7",
        "Filter: ON LS 6dB Fc 100 Hz Gain 5 dB",
        "Filter: ON LS 12dB Fc 200 Hz Gain -4 dB",
        "Filter: ON LS Fc 80 Hz Gain 4 dB",
        "Filter: ON HS Fc 6000 Hz Gain 3 dB Q 0.7",
        "Filter: ON HS 12dB Fc 6000 Hz Gain -3 dB",
        "Filter: ON HS Fc 9000 Hz Gain 2 dB",
        "Filter: ON LS Fc 100 Hz Gain 5 dB BW Oct 2",
        "Filter: ON LS 12dB Fc 100 Hz Gain 5 dB Q 0.7",
        "Filter: ON LP Fc 18000 Hz Q 0.7",
        "Filter: ON LPQ Fc 15000 Hz",
        "Filter: ON LP Fc 16000 Hz BW Oct 0",
        "Filter: ON LP 12dB Fc 17000 Hz",
        "Filter: ON HP Fc 20 Hz Q 0.5",
        "Filter: ON HPQ Fc 25 Hz BW Oct 2",
        "Filter: ON HP Fc 30 Hz Gain 6 dB",
        "Filter: ON BP Fc 1000 Hz Q 2",
        "Filter: ON BP Fc 1500 Hz Gain 6 dB",
        "Filter: ON NO Fc 50 Hz Q 10",
        "Filter: ON NO Fc 60 Hz",
        "Filter: ON NO Fc 70 Hz BW Oct 0",
        "Filter: ON AP Fc 500 Hz Q 0.7",
        "Filter: ON AP Fc 600 Hz BW Oct 1",
        "Filter: ON AP Fc 700 Hz",
        "Filter: ON PK Fc 800 Hz Gain 3 dB",
        "Filter: ON PK Fc 900 Hz Gain 3 dB Q 0",
        "Filter: ON LSC Fc 100 Hz Gain 3 dB Q 0",
        "Filter: ON LSC 0 dB Fc 100 Hz Gain 3 dB Q 0.7",
        "Filter: ON HP Fc 40 Hz Q 0",
        "Filter: ON PK Fc 1000 Hz Gain 0 dB Q 1",
        "Filter: ON HP Fc 50 Hz Q 2 BW Oct 0",
        "Filter: ON PK Fc 1100 Hz Gain 2 dB BW Oct 0 Q 3",
        "Filter: ON PK 6 dB Fc 1200 Hz Gain 2 dB Q 3",
    ])
    files["a42-filter-commands.txt"] = text([
        "Filter3: ON PK Fc 100 Hz Gain 1 dB Q 1",
        "Filter: ON PK Fc 200 Hz Gain 2 dB Q 1",
        "Filters: ON PK Fc 300 Hz Gain 3 dB Q 1",
        "  Filter 2 : ON PK Fc 400 Hz Gain 4 dB Q 1",
        "Filter 1:ON PK Fc 500 Hz Gain 5 dB Q 1",
        "\tPreamp:\t-1 dB",
    ])
    files["a43-channel-empty.txt"] = text([
        "Filter: ON PK Fc 100 Hz Gain 1 dB Q 1",
        "Channel:",
        "Filter: ON PK Fc 200 Hz Gain 2 dB Q 1",
        "Preamp: -2 dB",
        "Channel: all",
        "Filter: ON PK Fc 300 Hz Gain 3 dB Q 1",
    ])
    files["a44-graphic-ears.txt"] = text(["Channel: L", "GraphicEQ: 20 -2; 1000 0; 20000 3",
                                          "Channel: R", "GraphicEQ: 20 1; 1000 0; 20000 -2"])
    files["a45-graphic-add.txt"] = text(["Preamp: -1 dB", "GraphicEQ: 20 -2; 20000 -2",
                                         "GraphicEQ: 100 0; 1000 3; 10000 0",
                                         "Filter: ON PK Fc 50 Hz Gain -3 dB Q 2"])
    files["a46-graphic-odd.txt"] = text(["GraphicEQ: 20"])
    files["a47-stray-cr.txt"] = text(["Filter: ON PK Fc 100 Hz\rGain 3 dB Q 1", "Preamp: -1 dB"])
    files["a48-one-line-cr.txt"] = b"Preamp: -3 dB\r"
    files["a49-bad-numbers.txt"] = text([
        "Filter: ON PK Fc - Hz Gain 1 dB Q 1",
    ])
    files["a50-per-ear-preamps.txt"] = text([
        "Channel: L",
        "Preamp: -6 dB",
        "Filter: ON PK Fc 1000 Hz Gain 3 dB Q 1",
        "Channel: R",
        "Preamp: -6 dB",
        "Filter: ON PK Fc 2000 Hz Gain 2 dB Q 1",
    ])
    files["a51-export-shapes.txt"] = text([
        "Preamp: -7.1 dB",
        "Filter 1: ON PK Fc 31.25 Hz Gain 5.0 dB Q 1.41",
        "Filter 2: ON PK Fc 12.3450 Hz Gain 1.0 dB Q 0.70",
        "Filter 3: ON LS 12 dB Fc 80 Hz Gain 4.0 dB",
        "Filter 4: OFF HSC Fc 9000 Hz Gain -2.0 dB Q 0.71",
        "Filter 5: ON NO Fc 60 Hz BW Oct 0",
        "Filter 6: ON BP Fc 1500 Hz Gain 6.0 dB",
    ])
    # a GraphicEQ gain is held to a filter's +-30 dB (beyond it the fit's sums overflow to NaN)
    files["a52-graphic-gain.txt"] = text(["GraphicEQ: 20 0; 1000 -45; 20000 0"])
    # wcstod's overflow is HUGE_VAL, Python's float() and Swift's Double() inf - refused by the range, never read as 0
    files["a53-overflow.txt"] = text(["Filter: ON PK Fc 1e999 Hz Gain 1 dB Q 1"])
    return files


# Readings made from a committed file by a transform, so the bytes that can't be committed (NULs) never are:
# (name, the file, the transform, pasted).
TRANSFORMED = [
    ("a03-notepad-unicode utf16le", "a03-notepad-unicode.txt", "utf16le", False),
    ("a06-crlf utf16be", "a06-crlf.txt", "utf16be", False),
    ("a01-plain utf16le, a lone surrogate", "a01-plain.txt", "utf16leBroken", False),
    ("a01-plain padded past 256 KB", "a01-plain.txt", "big", False),
    ("a39-nothing pasted", "a39-nothing.txt", "none", True),
]


def transform(data, how):
    """Both readers' tests make these bytes the same way (APOReaderTests.transformed)."""
    if how == "none":
        return data
    if how == "utf16le":
        return b"\xff\xfe" + data.decode("utf-8").encode("utf-16-le")
    if how == "utf16be":
        return b"\xfe\xff" + data.decode("utf-8").encode("utf-16-be")
    if how == "utf16leBroken":
        return b"\xff\xfe" + data.decode("utf-8").encode("utf-16-le") + b"\x00\xd8"
    if how == "big":
        return data + b" " * (MAX_BYTES + 1 - len(data))
    raise ValueError(how)


# ------------------------------------------------------------------------------------------------ the fixtures

def filter_cases(rate):
    out = []

    def add(name, written, fc, gain=0.0, width=None, corner=False, on=True):
        out.append((name, {"id": len(out) + 1, "kind": TYPES[written], "written": written, "fc": float(fc),
                           "gain": float(gain), "width": width, "corner": corner, "channel": "all", "on": on}))

    rr = rate
    add("peak at 1 Hz", "PK", 1, 6, ("q", 0.7))
    add("peak at 0.45 x the rate", "PK", 0.45 * rr, -12, ("q", 2.0))
    add("peak just under 0.49 x the rate", "PK", 0.4899 * rr, 3, ("q", 1.0))
    add("peak at 0.49 x the rate, left out", "PK", 0.49 * rr, 3, ("q", 1.0))
    add("peak just over 0.49 x the rate, left out", "PK", 0.4901 * rr, 3, ("q", 1.0))
    add("peak, BW 0.1 octaves", "PK", 100, 3, ("bandwidth", 0.1))
    add("peak, BW 4 octaves", "PK", 3000, -6, ("bandwidth", 4.0))
    add("LSC, Q 2, at 20 Hz", "LSC", 20, -12, ("q", 2.0))
    add("HSC, Q 0.7, at 0.45 x the rate", "HSC", 0.45 * rr, 12, ("q", 0.7))
    add("LS 6dB, by its corner", "LS", 100, 5, ("slope", 6.0), corner=True)
    add("HS with a Q, by its corner", "HS", 6000, 3, ("q", 0.7), corner=True)
    add("LP, no width (Q 1/sqrt 2), at 0.3 x the rate", "LP", 0.3 * rr)
    add("HP, Q 0.5, at 1 Hz", "HP", 1, 0, ("q", 0.5))
    add("NO, BW Oct 0 (30 octaves)", "NO", 70, 0, ("bandwidth", 0.0))
    add("LSC +30 dB, Q 0.5, at 1 Hz", "LSC", 1, 30, ("q", 0.5))
    add("peak -30 dB, Q 100, at 20 Hz", "PK", 20, -30, ("q", 100.0))
    if rate == 48000.0:
        add("peak +0.1 dB, Q 1.41", "PK", 1000, 0.1, ("q", 1.41))
        add("peak -0.1 dB, Q 0.01", "PK", 1000, -0.1, ("q", 0.01))
        add("peak +30 dB, Q 4.32", "PK", 10000, 30, ("q", 4.32))
        add("PEQ", "PEQ", 2000, -2, ("q", 2.0))
        add("Modal", "Modal", 60, -6, ("q", 5.0))
        add("peak, BW 1 octave", "PK", 500, 6, ("bandwidth", 1.0))
        add("peak at 0 dB, left out (flat)", "PK", 1000, 0, ("q", 1.0))
        add("peak with no width, left out", "PK", 1000, 3)
        add("peak, Q 0, left out", "PK", 1000, 3, ("q", 0.0))
        add("peak, off", "PK", 1000, 3, ("q", 1.0), on=False)
        add("LSC, Q 0.7 (AutoEq's)", "LSC", 105, 2.6, ("q", 0.7))
        add("HSC, Q 0.7 (AutoEq's)", "HSC", 10000, -0.5, ("q", 0.7))
        add("HSC -30 dB", "HSC", 3000, -30, ("q", 0.5))
        add("LSC 3 dB slope", "LSC", 300, -3, ("slope", 3.0))
        add("LSC 12 dB slope (S 1)", "LSC", 100, 6, ("slope", 12.0))
        add("HSC 24 dB slope", "HSC", 8000, 4, ("slope", 24.0))
        add("LSC, no width (S 0.9)", "LSC", 90, 3)
        add("LSC, Q 0 (S 0.9)", "LSC", 100, 3, ("q", 0.0))
        add("LSC, slope 0 (S 0.9)", "LSC", 100, 3, ("slope", 0.0))
        add("LS, no width (S 0.9, f0 = Fc)", "LS", 80, 4)
        add("HS, no width (S 0.9, f0 = Fc)", "HS", 9000, 2)
        add("LS 12dB, by its corner", "LS", 200, -4, ("slope", 12.0), corner=True)
        add("LS with a Q, by its corner", "LS", 100, 5, ("q", 0.7), corner=True)
        add("HS 6dB, by its corner", "HS", 8000, 2, ("slope", 6.0), corner=True)
        add("HS 12dB, by its corner", "HS", 6000, -3, ("slope", 12.0), corner=True)
        add("LS 24dB at 23 dB: too steep", "LSC", 100, 23, ("slope", 24.0))
        add("LSC at 0 dB, left out (flat)", "LSC", 100, 0, ("q", 0.7))
        add("LP, Q 0.7", "LP", 18000, 0, ("q", 0.7))
        add("LP, Q 0 (Q 1/sqrt 2)", "LP", 16000, 0, ("q", 0.0))
        add("LP, BW Oct 0 (BW 1/sqrt 2 octaves)", "LP", 16000, 0, ("bandwidth", 0.0))
        add("LPQ, BW 2", "LPQ", 5000, 0, ("bandwidth", 2.0))
        add("HP, no width", "HP", 30)
        add("HPQ, BW 0.1", "HPQ", 25, 0, ("bandwidth", 0.1))
        add("BP, Q 2", "BP", 1000, 0, ("q", 2.0))
        add("BP, no width, a gain it ignores", "BP", 1500, 6)
        add("BP, BW 1", "BP", 1000, 0, ("bandwidth", 1.0))
        add("BP, BW Oct 0", "BP", 1000, 0, ("bandwidth", 0.0))
        add("NO, Q 10", "NO", 50, 0, ("q", 10.0))
        add("NO, no width (Q 30)", "NO", 60)
        add("NO, BW 0.5", "NO", 1000, 0, ("bandwidth", 0.5))
        add("AP, Q 0.7", "AP", 500, 0, ("q", 0.7))
        add("AP, BW 1", "AP", 600, 0, ("bandwidth", 1.0))
        add("AP, no width, left out", "AP", 700)
    return out


def make_filters():
    cases = []
    for rate in RATES:
        grid = response_grid(rate)
        for name, f in filter_cases(rate):
            outcome, f0, coefficients = section(f, rate)
            case = {"name": name, "rate": r(rate), "filter": filter_json(f), "outcome": outcome,
                    "f0": None if f0 is None else r(f0), "coefficients": None, "response_f4": None,
                    "impulse_f8": None}
            if coefficients:
                b0, b1, b2, a1, a2 = coefficients
                case["coefficients"] = [r(c) for c in coefficients]
                _, h = signal.freqz([b0, b1, b2], [1.0, a1, a2], worN=np.array(grid), fs=rate)
                with np.errstate(divide="ignore"):
                    db = 20 * np.log10(np.abs(h))
                mine = section_db(coefficients, trig_of(grid, rate))
                both = (db > -200) | (mine > -200)
                worst = float(np.max(np.abs(db[both] - mine[both]))) if both.any() else 0.0
                assert worst < 0.001, (name, rate, worst)
                case["response_f4"] = b64(db, "f4")
                impulse = df1(coefficients, [1.0] + [0.0] * 127)
                cross = signal.lfilter([b0, b1, b2], [1.0, a1, a2], [1.0] + [0.0] * 127)
                peak = max(abs(x) for x in impulse)
                assert float(np.max(np.abs(np.array(impulse) - cross))) <= 1e-9 * peak, (name, rate)
                case["impulse_f8"] = b64(impulse, "f8")
            cases.append(case)
    return {"about": "1.3's filters at eight rates: f0, the five coefficients (repr), the response on 1.4's "
                     "1/48-octave grid from 10 Hz to below Nyquist (freqz, dB, float32) and 128 samples of the "
                     "impulse response through Direct Form I in Python floats (float64, bit-exact).",
            "rates": [r(x) for x in RATES], "cases": cases}


AUTOEQ_PROFILES = [
    ("crinacle", "711", "in-ear", "results/crinacle/711 in-ear/Apple AirPods Pro/Apple AirPods Pro ParametricEQ.txt", None),
    ("crinacle", "711", "in-ear", "results/crinacle/711 in-ear/Apple AirPods Pro 2 (ANC mode)/Apple AirPods Pro 2 (ANC mode) ParametricEQ.txt", None),
    ("oratory1990", None, "over-ear", "results/oratory1990/over-ear/Sennheiser HD 650/Sennheiser HD 650 ParametricEQ.txt",
     "results/oratory1990/over-ear/Sennheiser HD 650/Sennheiser HD 650.csv"),
    ("oratory1990", None, "over-ear", "results/oratory1990/over-ear/Sennheiser HD 650/Sennheiser HD 650 FixedBandEQ.txt", None),
    ("Super Review", None, "in-ear", "results/Super Review/in-ear/Apple AirPods Pro/Apple AirPods Pro ParametricEQ.txt", None),
    ("HypetheSonics", "Bruel & Kjaer 5128", "in-ear", "results/HypetheSonics/Bruel & Kjaer 5128 in-ear/Apple AirPods Pro/Apple AirPods Pro ParametricEQ.txt", None),
    ("Rtings", "HMS II.3", "in-ear", "results/Rtings/HMS II.3 in-ear/Apple AirPods Pro/Apple AirPods Pro ParametricEQ.txt", None),
    ("oratory1990", None, "over-ear", "results/oratory1990/over-ear/Apple AirPods Max/Apple AirPods Max ParametricEQ.txt",
     "results/oratory1990/over-ear/Apple AirPods Max/Apple AirPods Max.csv"),
    ("crinacle", "GRAS 43AG-7", "over-ear", "results/crinacle/GRAS 43AG-7 over-ear/Sennheiser HD 650/Sennheiser HD 650 ParametricEQ.txt", None),
    ("Innerfidelity", None, "over-ear", "results/Innerfidelity/over-ear/Sennheiser HD 650/Sennheiser HD 650 ParametricEQ.txt", None),
    ("oratory1990", None, "in-ear", "results/oratory1990/in-ear/Etymotic ER2XR/Etymotic ER2XR ParametricEQ.txt", None),
    ("Rtings", "Bruel & Kjaer 5128", "over-ear", "results/Rtings/Bruel & Kjaer 5128 over-ear/Beyerdynamic DT 770 Pro/Beyerdynamic DT 770 Pro ParametricEQ.txt", None),
    ("Headphone.com Legacy", None, "over-ear", "results/Headphone.com Legacy/over-ear/Sennheiser HD 650/Sennheiser HD 650 ParametricEQ.txt", None),
    ("Kuulokenurkka", None, "over-ear", "results/Kuulokenurkka/over-ear/Sennheiser HD 6XX/Sennheiser HD 6XX ParametricEQ.txt", None),
]


def profile_grid():
    out, k = [], 0
    while 20 * 2 ** (k / 48) <= 20000:
        out.append(20 * 2 ** (k / 48))
        k += 1
    return out


def make_profiles(source):
    grid = np.array(profile_grid())
    out = []
    for measurer, rig, form, path, csv in AUTOEQ_PROFILES:
        data = (source / "autoeq" / path).read_bytes()
        reading = read_apo(data)
        assert not reading.get("refused") and not reading["notes"], (path, reading)
        file_preamp = float(re.match(r"Preamp: (\S+) dB", data.decode("ascii")).group(1))
        responses = {}
        for rate in (44100.0, 48000.0):
            total = np.zeros(len(grid))
            for f in reading["filters"]:
                make = {"peak": peq_peaking, "lowShelf": peq_low_shelf, "highShelf": peq_high_shelf}[f["kind"]]
                total = total + peq_fr(grid, rate, make(f["fc"], f["width"][1], f["gain"], rate))
            responses[rate] = total
        ears = [([section(f, 48000.0)[1:] for f in reading["filters"] if section(f, 48000.0)[0] == "plays"], 0.0)]
        top, at = top_of(ears, 48000.0)
        mine = automatic_preamp(top)
        assert abs(mine - file_preamp) <= 0.5, (path, mine, file_preamp)
        out.append({"path": "autoeq/" + path, "measurer": measurer, "rig": rig, "form": form,
                    "csv": None if csv is None else "autoeq/" + csv, "filePreamp": r(file_preamp),
                    "filters": [filter_json(f) for f in reading["filters"]],
                    "peq44100_f4": b64(responses[44100.0], "f4"), "peq48000_f4": b64(responses[48000.0], "f4"),
                    "top48000": r(top), "topAt48000": r(at), "automaticPreamp48000": r(mine)})
        print("  %-28s %-60s file %5.1f  deadwax %5.1f (top %.3f dB at %.0f Hz)"
              % (measurer, path.split("/")[-1], file_preamp, mine, top, at))
    return {"about": "AutoEq's ParametricEQ.txt files (autoeq/, MIT, AutoEq at 7ae0f56): the filters this "
                     "script's reader reads, and their curve by AutoEq's own peq.py on the 1/48-octave grid from 20 Hz "
                     "to 20 kHz (dB, float32), at 44.1 and 48 kHz.",
            "gridCount": len(grid), "profiles": out}


GRAPHIC_FILES = [
    "results/oratory1990/over-ear/Sennheiser HD 650/Sennheiser HD 650 GraphicEQ.txt",
    "results/crinacle/711 in-ear/Apple AirPods Pro/Apple AirPods Pro GraphicEQ.txt",
]


def make_graphic(source):
    out = []
    for path in GRAPHIC_FILES:
        reading = read_apo((source / "autoeq" / path).read_bytes())
        assert not reading.get("refused"), path
        lines = [g["points"] for g in reading["graphic"]]
        fit = fit_graphic(lines)
        print("  %-55s median %.3f, %d rounds, %d filters; to 16 kHz mean %.4f rms %.4f max %.3f; above %.2f at %.0f"
              " (48 kHz); 44.1 kHz above %.2f" % (path.split("/")[-1], fit["median"], fit["rounds"], fit["kept"],
                                                   fit["stats48"]["mean"], fit["stats48"]["rms"],
                                                   fit["stats48"]["largest"], fit["stats48"]["above"],
                                                   fit["stats48"]["aboveAt"], fit["stats44"]["above"]))
        near = [g for g in fit["unrounded"] if abs(abs(g * 10) % 1 - 0.5) < 1e-5]
        assert not near, (path, near)
        out.append({"path": "autoeq/" + path, "points": len(lines[0]), "median": r(fit["median"]),
                    "target_f8": b64(fit["target"], "f8"), "unrounded": [r(g) for g in fit["unrounded"]],
                    "rounded": [r(g) for g in fit["rounded"]], "kept": fit["kept"], "rounds": fit["rounds"],
                    "stats48000": {k: r(v) for k, v in fit["stats48"].items()},
                    "stats44100": {k: r(v) for k, v in fit["stats44"].items()}})
    return {"about": "3.10's fit, in NumPy, over AutoEq's GraphicEQ.txt for the HD 650 (oratory1990) and the "
                     "AirPods Pro (crinacle): the target on the 1/48-octave grid from 20 Hz to 21 kHz less its "
                     "median (float64), the 61 gains before and after rounding, and the fit after rounding.",
            "centres": [r(c) for c in graphic_centres()], "q": r(GRAPHIC_Q), "gridCount": len(graphic_grid()),
            "fits": out}


CLOSE_PAIRS = [
    ("two Q 30 peaks 1/30 octave apart", 30.0, 1000.0, 1000.0 * 2 ** (1 / 30), 6.0),
    ("two Q 10 peaks 1/8 octave apart", 10.0, 2000.0, 2000.0 * 2 ** (1 / 8), 6.0),
    ("two Q 100 peaks 1/100 octave apart", 100.0, 5000.0, 5000.0 * 2 ** (1 / 100), 6.0),
]


def make_preamp():
    presets = []
    for preset_id, gains in PRESETS:
        row = {"id": preset_id, "gains": [r(g) for g in gains]}
        for rate in (48000.0, 44100.0):
            sections = band_sections(gains, rate)
            top, at = top_of([(sections, 0.0)], rate)
            lowest, lowest_at = lowest_of(sections, rate)
            row["rate%d" % rate] = {"top": r(top), "topAt": r(at), "lowest": r(lowest), "lowestAt": r(lowest_at),
                                    "preamp": r(automatic_preamp(top))}
        print("  %-14s top %+.2f dB at %.0f Hz, lowest %+.2f at %.0f, preamp %.1f (48 kHz)"
              % (preset_id, float(row["rate48000"]["top"]), float(row["rate48000"]["topAt"]),
                 float(row["rate48000"]["lowest"]), float(row["rate48000"]["lowestAt"]),
                 float(row["rate48000"]["preamp"])))
        presets.append(row)
    pairs = []
    rate = 48000.0
    for name, q, fa, fb, gain in CLOSE_PAIRS:
        sections = [(f, cookbook("peak", gain, f, rate, q, False)) for f in (fa, fb)]
        dense = np.exp(np.linspace(math.log(fa / 2 ** 0.5), math.log(fb * 2 ** 0.5), 4_000_000))
        w = 2 * np.pi * dense / rate
        trig = (np.cos(w), np.sin(w), np.cos(2 * w), np.sin(2 * w))
        true = float(np.max(section_db(sections[0][1], trig) + section_db(sections[1][1], trig)))
        grid_only, _ = top_of([(sections, 0.0)], rate, refined=False)
        refined, _ = top_of([(sections, 0.0)], rate)
        print("  %-36s true %.6f, grid and f0s %.6f (short %.3f), refined %.6f (off %.1e)"
              % (name, true, grid_only, true - grid_only, refined, abs(refined - true)))
        assert abs(refined - true) < 1e-5 and true - grid_only > 0.02, name
        pairs.append({"name": name, "rate": r(rate), "filters": [
            filter_json({"id": i + 1, "kind": "peak", "written": "PK", "fc": f, "gain": gain, "width": ("q", q),
                         "corner": False, "channel": "all", "on": True}) for i, f in enumerate((fa, fb))],
            "trueTop": r(true), "gridTop": r(grid_only)})
    return {"about": "3.6's presets at 48 and 44.1 kHz (top and lowest of the curve, the automatic preamp), and "
                     "1.4's close pairs with their true tops from a 4,000,000-point search.",
            "bandQ": r(BAND_Q), "presets": presets, "closePairs": pairs}


def render_lists(rate):
    """Three lists (left, right, shared) of a stereo correction with per-ear filters, and Bass Boost's bands."""
    def sec(sid, kind, written, fc, gain, q):
        outcome, f0, coefficients = section({"kind": kind, "written": written, "fc": fc, "gain": gain,
                                             "width": ("q", q), "corner": False, "on": True}, rate)
        assert outcome == "plays"
        return {"id": sid, "kind": kind, "coefficients": coefficients}
    shared = [sec("filter:1", "lowShelf", "LSC", 105.0, 2.6, 0.7), sec("filter:2", "peak", "PK", 514.0, -4.4, 0.68),
              sec("filter:3", "highShelf", "HSC", 10000.0, -0.5, 0.7), sec("filter:6", "peak", "PK", 8903.0, 6.0, 1.66)]
    bands = [sec("band:%d" % i, "peak", "PK", BANDS[i], g, BAND_Q) for i, g in enumerate([5, 4.5, 3, 1]) if g]
    left = shared + [sec("filter:4", "peak", "PK", 2000.0, 3.0, 2.0)] + bands
    right = shared + [sec("filter:5", "peak", "PK", 3000.0, -2.0, 1.0)] + bands
    return [left, right, shared + bands]


def render(lists, levels, channels):
    """Each channel's list section by section over the whole signal (1.5: channel 0 the left's, 1 the right's, the
    rest the shared list; one channel plays the left's), then the level, then Float32."""
    out = []
    for c, xs in enumerate(channels):
        which = 0 if c == 0 else (1 if c == 1 else 2)
        signal_ = [float(x) for x in xs]
        for s in lists[which]:
            signal_ = df1(s["coefficients"], signal_)
        level = levels[which]
        out.append(np.array([y * level for y in signal_]).astype(np.float32))
    return out


def make_render():
    rng = np.random.default_rng(20261112)
    scenarios = []
    rate = 48000.0
    lists = render_lists(rate)
    levels = [10 ** (-6.1 / 20), 10 ** (-6.4 / 20), 10 ** (-6.1 / 20)]
    for name, count, frames in (("stereo", 2, 5000), ("eight channels", 8, 1500), ("one channel", 1, 1500)):
        channels = [(rng.uniform(-1.0, 1.0, frames) * 0.9).astype(np.float32) for _ in range(count)]
        for ch in channels:
            ch[100] = 1.0
            ch[101] = -1.0
        outs = render(lists, levels, channels)
        overs = sum(int(np.sum(np.abs(o) > 1.0)) for o in outs)
        largest = max(float(np.max(np.abs(o))) for o in outs)
        scenarios.append({"name": name, "frames": frames, "channels": count,
                          "input_f4": [b64(c, "f4") for c in channels], "output_f4": [b64(o, "f4") for o in outs],
                          "overs": overs, "largest": r(largest)})
    return {"about": "Banks run by this script's Direct Form I, section-major, in Python floats: Float32 in, the "
                     "level after the sections, Float32 out (1.5) - bit for bit.",
            "rate": r(rate), "levels": [r(x) for x in levels],
            "lists": [[{"id": s["id"], "kind": s["kind"], "coefficients": [r(c) for c in s["coefficients"]]}
                       for s in lst] for lst in lists],
            "scenarios": scenarios}


def make_apo(out):
    files = apo_files()
    folder = out / "apo"
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("*.txt"):
        old.unlink()
    readings = []
    for name, data in sorted(files.items()):
        (folder / name).write_bytes(data)
        readings.append({"name": name, "file": "apo/" + name, "transform": "none", "pasted": False,
                         "reading": reading_json(read_apo(data))})
    for name, source, how, pasted in TRANSFORMED:
        readings.append({"name": name, "file": "apo/" + source, "transform": how, "pasted": pasted,
                         "reading": reading_json(read_apo(transform(files[source], how), pasted))})
    return {"about": "This script's reader of APO's rules (0.3, 3.9) over apo/: the filters (exact, as repr), the "
                     "preamp's shared and per-ear parts, the GraphicEQ lines and their conversion, the notes and the "
                     "refusal, with their words.", "readings": readings}


def dump(path, value):
    """One case a line, so a change shows as a change to that case."""
    lines = ["{"]
    keys = list(value)
    for i, key in enumerate(keys):
        item = value[key]
        tail = "," if i + 1 < len(keys) else ""
        if isinstance(item, list) and item and isinstance(item[0], dict):
            lines.append("  %s: [" % json.dumps(key))
            for j, element in enumerate(item):
                lines.append("    " + json.dumps(element, ensure_ascii=False) + ("," if j + 1 < len(item) else ""))
            lines.append("  ]" + tail)
        else:
            lines.append("  %s: %s%s" % (json.dumps(key), json.dumps(item, ensure_ascii=False), tail))
    lines.append("}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", type=Path, default=EQ, help="where to write (default: the committed folder)")
    args = parser.parse_args(argv)
    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    print("apo.json")
    dump(out / "apo.json", make_apo(out))
    print("filters.json")
    dump(out / "filters.json", make_filters())
    print("profiles.json")
    dump(out / "profiles.json", make_profiles(EQ))
    print("graphic.json")
    dump(out / "graphic.json", make_graphic(EQ))
    print("preamp.json")
    dump(out / "preamp.json", make_preamp())
    print("render.json")
    dump(out / "render.json", make_render())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
