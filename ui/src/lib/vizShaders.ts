/**
 * The desktop visualizer's Ambient styles as WebGL fragment shaders (2.0.0-player.20) - the canvas
 * board DesktopVisualizer.dc.html's own GLSL, taken across unchanged (WebGL 1, GLSL ES 1.00). PURE:
 * strings, compiled by player/vizGl.ts. Each style reads its own previous frame (a ping-pong pair of
 * framebuffers) and writes the next one - that feedback is what makes the trails - and a composite
 * pass mixes the outgoing and incoming styles of a crossfade onto the screen. The spectrum goes in as
 * a 64x1 texture, the waveform as a 256x1 one, and a 64x64 texture keeps the spectrum's recent
 * history for the Waves landscape. Nothing in them is random: every "noise" is a hash of a position.
 */

const HEAD = 'precision highp float;\nvarying vec2 vUv;\n'

/** What every style shares: its size and clock, the music's bass and kick, its own last frame, the
 *  palette's six colours, and two ways of reading them. */
const COMMON = `
uniform vec2 uRes;
uniform float uTime;
uniform float uBass;
uniform float uKick;
uniform sampler2D uPrev;
uniform vec3 uPal[6];
const float PI = 3.14159265;
mat2 rot(float a) {
  float c = cos(a);
  float s = sin(a);
  return mat2(c, s, -s, c);
}
vec3 pal(float t) {
  float x = clamp(t, 0.0, 1.0) * 5.0;
  vec3 c = mix(uPal[0], uPal[1], clamp(x, 0.0, 1.0));
  c = mix(c, uPal[2], clamp(x - 1.0, 0.0, 1.0));
  c = mix(c, uPal[3], clamp(x - 2.0, 0.0, 1.0));
  c = mix(c, uPal[4], clamp(x - 3.0, 0.0, 1.0));
  c = mix(c, uPal[5], clamp(x - 4.0, 0.0, 1.0));
  return c;
}
vec3 palm(float t) {
  return pal(1.0 - abs(1.0 - 2.0 * fract(t)));
}
`

/** The one vertex shader: a triangle that covers the screen. */
export const VERTEX = `
attribute vec2 aPos;
varying vec2 vUv;
void main() {
  vUv = aPos * 0.5 + 0.5;
  gl_Position = vec4(aPos, 0.0, 1.0);
}
`

/**
 * Mandala, as a real kaleidoscope. The plane is folded into mirrored wedges - into a whole number of
 * them (uOuter), and each wedge folded again at the count as it swings (uFold.x). While a count holds
 * the second fold is exactly the first's count or a whole multiple of it; while it changes (by a fold:
 * twice or three times as many, or a half or a third, lib/visualizer.ts MIRROR_COUNTS) a new mirror
 * swings shut inside every wedge at once, or swings open. The second fold reads only the first one's
 * answer, so every wedge is like every other at every moment (2.0.0-player.34: a single fold at a count
 * between whole numbers left one wedge unlike the rest, a radial line shapes were born out of). The
 * angle is measured AFTER the spin and twist turn the plane, so atan's wrap lands on a mirror line
 * (2.0.0-player.20). Inside the wedge a source pattern drifts, turns and scales on its own path, like
 * the beads in a turned tube, so the figure keeps changing even with the mirrors still. The source is
 * made of distance fields, and it morphs by interpolating them, never by fading: a regular polygon of
 * any number of sides (3-8, any real number, so a square's corners bulge into a pentagon), which can
 * round into a circle or, now and then, pinch into a star; a flower of circles; and triangle, square
 * and hexagon lattices. On top of that the plane is turned inside out by blending in circle inversion,
 * wound and unwound by a polar twist, and flown slowly in and out through.
 *
 * ONE figure with room round it (2.0.0-player.34, James: "it just looks a bit busy"): it fills a disc
 * of the screen (wider for smooth music, tighter for aggressive), and beyond it the pattern carries on
 * only faintly, in the deep colour, and only some of the time; the echoes of its lines and the band of
 * cells each come and go too, so a few layers show at once rather than all of them; its lines are
 * thin and soft for smooth music and drawn wider, with less glow beside them, as the feel rises (harder,
 * never fainter), and a pile of glow is scaled down in all three channels together, so it keeps the
 * cover's colour instead of burning to white; the rings are drawn in the cover's colour alone,
 * without the rainbow fringe that split each into three; the trail behind the lines is about half as
 * long, so a line no longer drags a stack of echoes; and the flare across the middle is gone. Its
 * tiles and the band's cells are no longer cut off along their cells' straight edges: each is worked out
 * with its neighbours, so a corner or a spike carries on into the next cell instead of appearing out of
 * a straight line as the tiles turn. Where neither the figure nor the faint pattern shows, none of it is
 * worked out, which (with the rings in one colour) pays for the neighbours. Nothing follows the beat:
 * brightness and size are steady, and the music only sets how fast the numbers move (lib/visualizer.ts
 * mandalaFlow and mandalaMorph).
 */
export const MANDALA = HEAD + COMMON + `
uniform vec3 uCore;
uniform vec3 uBody;
uniform vec3 uBody2;
uniform vec3 uRing;
uniform vec3 uFlare;
uniform vec4 uFold;
uniform float uOuter;
uniform vec4 uInv;
uniform vec4 uSrc;
uniform vec4 uForm;
uniform vec4 uLat;
uniform vec4 uRingsQ;
uniform vec3 uFormW;
uniform vec3 uEdge;
uniform vec4 uRoom;
float tri(float x) {
  return abs(fract(x + 0.5) - 0.5);
}
// a regular polygon of any number of sides, its own two numbers made once a frame (k: the angle one side
// spans, and how far out a spike's tip reaches as a share of r) since every shape of the figure shares them
float sdPoly(vec2 p, float r, vec2 k, float star, float round) {
  float la = k.x * tri(atan(p.y, p.x) / k.x);
  float edge = r / cos(la);
  float spike = mix(r * 0.5, r * k.y, 2.0 * la / k.x);
  return length(p) - mix(mix(edge, spike, star), r * 1.08, round);
}
float latTri(vec2 s) {
  return min(tri(s.y), min(tri(dot(s, vec2(0.8660254, 0.5))), tri(dot(s, vec2(-0.8660254, 0.5)))));
}
float latSq(vec2 s) {
  return min(tri(s.x), tri(s.y));
}
float latHex(vec2 s) {
  vec2 k = vec2(1.0, 1.7320508);
  vec2 a = mod(s, k) - 0.5 * k;
  vec2 b = mod(s - 0.5 * k, k) - 0.5 * k;
  vec2 h = abs(dot(a, a) < dot(b, b) ? a : b);
  return 0.5 - max(dot(h, vec2(0.5, 0.8660254)), h.x);
}
float lattice(vec2 s, float kind) {
  float k = mod(kind, 3.0);
  float t3 = latTri(s);
  float d = mix(t3, latSq(s), smoothstep(0.0, 1.0, clamp(k, 0.0, 1.0)));
  d = mix(d, latHex(s), smoothstep(0.0, 1.0, clamp(k - 1.0, 0.0, 1.0)));
  return mix(d, t3, smoothstep(0.0, 1.0, clamp(k - 2.0, 0.0, 1.0)));
}
float glowLine(float d, float w, float tail) {
  return exp(-(d * d) / (w * w)) + tail * exp(-d / (3.0 * w));
}
float glowRing(float r, float R, float w) {
  float d = r - R;
  return exp(-d * d / (w * w)) + 0.12 * exp(-abs(d) / (w * 4.0));
}
void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * uRes) / uRes.y;
  float t = uTime;
  float r0 = length(p);
  // ONE figure with room round it: it fills a disc of the screen (uRoom.x of its height, or of its width
  // where that is the smaller), faded out before the screen's edge so it is never cut off by the top and
  // bottom, and beyond that the pattern carries on only faintly, in the deep colour, and only some of the
  // time (uRoom.y) - and where neither shows, the figure isn't worked out at all
  float reach = uRoom.x * min(1.0, uRes.x / uRes.y);
  float inside = 1.0 - smoothstep(reach * 0.9, reach * 1.15, r0);
  float faint = (1.0 - inside) * uRoom.y * 0.11;
  vec3 col = vec3(0.0);
  if (inside > 0.0 || faint > 0.0) {
    vec2 z = p * uFold.w;
    float k = uInv.y;
    float inv = uInv.x;
    float rz = max(length(z), 0.0005);
    float kr = (k * k) / (rz * rz);
    vec2 w = mix(z, z * kr, inv);
    float stretch = uFold.w * sqrt(abs(mix(1.0, -kr, inv)) * abs(mix(1.0, kr, inv)));
    float mag = clamp(stretch, 0.06, 6.0);
    float dense = 1.0 - smoothstep(2.5, 9.0, stretch);
    float r = length(w);
    // turned by the spin and the twist FIRST, then measured: atan's wrap at +-pi then falls where the even
    // fold meets itself, so it leaves no tear along the left horizontal (2.0.0-player.20)
    vec2 wt = rot(uFold.y + uFold.z * log(r + 0.02)) * w;
    float a = atan(wt.y, wt.x);
    // folded into uOuter wedges, then each wedge folded again at the count as it swings (uFold.x, a whole
    // multiple of uOuter while it holds): the second fold reads only the first's answer, so every wedge
    // is like every other at every moment, and a change of count is a mirror swinging inside each one
    float seg = 2.0 * PI / uOuter;
    float fa = seg * tri(a / seg);
    float sub = 2.0 * PI / uFold.x;
    fa = sub * tri(fa / sub);
    vec2 q = r * vec2(cos(fa), sin(fa));
    vec2 s = rot(uSrc.x) * (q - uInv.zw) / uSrc.y;
    float lw = 0.0038 * mag / uSrc.y * uEdge.y;
    float C = uLat.y;
    vec2 g = fract(s / C);
    float pSeg = 2.0 * PI / uSrc.z;
    vec2 pk = vec2(pSeg, 1.35 / cos(0.5 * pSeg));
    float dPoly = sdPoly(s, 0.42, pk, uSrc.w, uForm.y);
    // the polygon's own field, kept for its fill: the fill is the polygon's inside, so it fades in and out
    // only along the polygon's own outline (a drawn line), never along an edge drawn nowhere
    float dCore = dPoly;
    // the tiles: this cell's polygon and the three in the cells round the corner this point is nearest,
    // so a tile's corners and spikes carry on into the next cell instead of being cut off along its edge
    // (a straight line spikes appeared out of as the tiles turned)
    mat2 tr = rot(t * 0.07);
    vec2 h = (g - 0.5) * C;
    vec2 o = (step(0.5, g) * 2.0 - 1.0) * C;
    float dTile = min(min(sdPoly(tr * h, C * 0.32, pk, uSrc.w, uForm.y), sdPoly(tr * (h - vec2(o.x, 0.0)), C * 0.32, pk, uSrc.w, uForm.y)),
      min(sdPoly(tr * (h - vec2(0.0, o.y)), C * 0.32, pk, uSrc.w, uForm.y), sdPoly(tr * (h - o), C * 0.32, pk, uSrc.w, uForm.y)));
    dPoly = abs(dPoly) < abs(dTile) ? dPoly : dTile;
    float petals = min(min(abs(length(g) - 0.7), abs(length(g - vec2(1.0, 0.0)) - 0.7)), min(abs(length(g - vec2(0.0, 1.0)) - 0.7), abs(length(g - vec2(1.0, 1.0)) - 0.7)));
    float dFlower = min(abs(length(s) - 0.42), petals * C);
    float dLat = lattice(s / C, uLat.x) * C;
    float wsum = uFormW.x + uFormW.y + uFormW.z;
    float d = (uFormW.x * abs(dPoly) + uFormW.y * abs(dFlower) + uFormW.z * dLat) / wsum;
    col = (uBody * inside * 1.5 + uFlare * faint) * glowLine(d, lw, uEdge.x) * dense;
    float sp = uForm.z;
    float dn = abs(mod(d + 0.5 * sp + t * 0.012, sp) - 0.5 * sp);
    col += uBody2 * exp(-d / (uForm.w * 0.6)) * glowLine(dn, lw * 0.8, uEdge.x) * 0.6 * uRoom.z * dense * inside;
    float fill = uForm.x * (1.0 - smoothstep(-lw, lw, dCore)) * uFormW.x / wsum;
    col += mix(uBody, uBody2, 0.5) * fill * inside;
    float cw = uLat.w;
    vec2 cell = vec2((fract(fa * r / cw) - 0.5) * cw, r - uLat.z);
    // the band's cells: the cell's polygon and the next one along, the nearer - a corner crosses into the
    // next cell instead of being cut off at its edge
    mat2 br = rot(t * 0.1);
    float dCell = sdPoly(br * cell, cw * 0.3, pk, uSrc.w * 0.5, uForm.y * 0.5);
    float dNext = sdPoly(br * (cell - vec2(sign(cell.x) * cw, 0.0)), cw * 0.3, pk, uSrc.w * 0.5, uForm.y * 0.5);
    float band = glowLine(abs(min(dCell, dNext)), 0.003 * mag * uEdge.y, uEdge.x);
    col += uBody2 * band * (1.0 - smoothstep(cw * 0.35, cw * 0.55, abs(r - uLat.z))) * 0.6 * uRoom.w * dense * inside;
    // the rings in the cover's colour alone: the rainbow fringe they had split each into three
    float wob = 1.0 + uRingsQ.w * cos(uFold.x * fa);
    float split = uRingsQ.y * 0.02;
    float rw = 0.003 * mag;
    float rings = 0.0;
    for (int i = 0; i < 2; i++) {
      float R = (uRingsQ.z + float(i) * uRingsQ.x) * wob;
      rings += 0.5 * (glowRing(r, R - split, rw) + glowRing(r, R + split, rw));
    }
    col += rings * mix(uRing, uBody2, 0.4) * 0.8 * dense * inside;
  }
  col += uCore * (exp(-r0 * r0 / 0.0008) * 0.8 + 0.05 * exp(-r0 * 14.0));
  // brightness kept under white by scaling all three channels together, so a pile of glow stays the
  // cover's colour instead of burning to white
  float peak = max(col.r, max(col.g, col.b));
  col *= (1.0 - exp(-1.5 * peak)) / max(peak, 0.0001);
  vec2 asp = vec2(uRes.y / uRes.x, 1.0);
  vec2 fp = rot(0.0035 + 0.002 * sin(t * 0.13)) * p / 1.009;
  fp += 0.003 * vec2(sin(p.y * 9.0 + t), cos(p.x * 9.0 - t * 1.1));
  float cab = uEdge.z;
  vec3 prev = vec3(
    texture2D(uPrev, fp * (1.0 + cab) * asp + 0.5).r,
    texture2D(uPrev, fp * asp + 0.5).g,
    texture2D(uPrev, fp * (1.0 - cab) * asp + 0.5).b);
  vec3 fb = max(prev * 0.6 - 0.018, 0.0);
  gl_FragColor = vec4(max(col, fb) + col * 0.04, 1.0);
}
`

/**
 * Waves: flying around over a landscape of spectrum ridgelines. Each line is a row of the spectrum's
 * history: the newest rises out of the fog at the far end and they all come toward the camera, nearer
 * ridges hiding the ones behind them. The ridges lie across the landscape's own axis, and the camera's
 * heading swings away from that axis and back (lib/visualizer.ts wavesCamera), so the lines arrive
 * slanted, from a direction that keeps changing, with the horizon rolling into each turn. The last
 * frame, drawn a touch outward from where the flight is headed and faded, leaves each line a trail.
 */
export const WAVES = HEAD + COMMON + `
uniform sampler2D uHist;
uniform float uHead;
uniform float uPhase;
uniform float uHeading;
uniform float uRoll;
uniform float uCamH;
uniform float uHorizon;
uniform float uYaw;
uniform float uVanish;
float hist(float bx, float age) {
  float row = mod(uHead - age + 64.0, 64.0);
  return texture2D(uHist, vec2(bx * 0.984375 + 0.0078125, (row + 0.5) / 64.0)).r;
}
void main() {
  vec2 p0 = (gl_FragCoord.xy - 0.5 * uRes) / uRes.y;
  float cr = cos(uRoll);
  float sr = sin(uRoll);
  vec2 p = vec2(cr * p0.x - sr * p0.y, sr * p0.x + cr * p0.y);
  float ch = cos(uHeading);
  float sh = sin(uHeading);
  float den = max(ch - p.x * sh, 0.08);
  float dirx = p.x * ch + sh;
  const float zNear = 1.1;
  const float dz = 0.36;
  const int N = 48;
  float zFar = zNear + float(N) * dz;
  float px = 1.0 / uRes.y;
  vec3 col = vec3(0.0);
  float occ = -10.0;
  for (int i = 0; i < N; i++) {
    float age = float(N - 1 - i);
    float Z = zFar - (age + uPhase) * dz;
    float lam = Z / den;
    float X = lam * dirx - uYaw;
    float bx = abs(mod(X + 3.2, 6.4) - 3.2) / 3.2;
    float h = hist(bx, age);
    float ground = 0.03 * sin(X * 2.3 + age * 0.8) * sin(X * 0.9 - age * 0.37);
    float y = h * 0.65 + ground + uBass * 0.2 * (1.0 - 0.6 * bx);
    float sy = (y - uCamH) / lam + uHorizon;
    float d = p.y - sy;
    float w = px * (0.9 + 1.8 / lam);
    float line = exp(-d * d / (w * w)) + 0.2 * exp(-abs(d) / (w * 6.0));
    float vis = smoothstep(-w, w, p.y - occ);
    float fog = exp(-(lam - zNear) * 0.1);
    float alpha = clamp(age + uPhase, 0.0, 1.0) * clamp((Z - zNear) / dz, 0.0, 1.0);
    vec3 lc = pal(bx) * (0.35 + 1.1 * h) + vec3(0.08) * h;
    col += lc * line * vis * fog * alpha;
    occ = max(occ, sy);
  }
  float above = p.y - uHorizon;
  col += pal(0.15) * 0.1 * exp(-abs(above) * 14.0) * (0.6 + uBass);
  col += pal(0.05) * 0.16 * exp(-length(vec2(p.x - uVanish, above * 2.5)) * 7.0) * (0.4 + 0.8 * uKick);
  vec2 vq = vec2(cr * uVanish + sr * uHorizon, -sr * uVanish + cr * uHorizon);
  vec2 vp = vq * vec2(uRes.y / uRes.x, 1.0) + 0.5;
  vec3 prev = texture2D(uPrev, vp + (vUv - vp) * 0.988).rgb;
  gl_FragColor = vec4(max(col, prev * 0.9 - 0.003), 1.0);
}
`

/**
 * Liquid: domain-warped noise (noise pushed around by noise, twice) coloured through the palette like
 * ink, mixed a little at a time into the last frame, which is swirled round the centre and carried
 * along the flow - so the colour drifts and curls like ink in water. Its brightness is steady; the
 * music moves it instead (lib/visualizer.ts liquidFlow).
 */
export const LIQUID = HEAD + COMMON + `
uniform vec4 uFlow;
uniform vec4 uFlow2;
uniform vec2 uFlowStep;
uniform float uSurge;
float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
  float v = 0.0;
  float amp = 0.5;
  for (int i = 0; i < 4; i++) {
    v += amp * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p;
    amp *= 0.5;
  }
  return v;
}
void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * uRes) / uRes.y;
  float t = uFlow.z;
  vec2 b = p * 1.7 + uFlow.xy;
  vec2 q = vec2(fbm(b + vec2(0.0, t)), fbm(b + vec2(5.2, 1.3) - t * 0.8));
  float warp = uFlow.w;
  vec2 r = vec2(fbm(b + warp * q + vec2(1.7, 9.2) + t * 0.6), fbm(b + warp * q + vec2(8.3, 2.8) - t * 0.5));
  vec2 ripple = uFlow2.z * vec2(sin(p.y * 46.0 + t * 9.0 + q.x * 6.0), cos(p.x * 41.0 - t * 8.0 + q.y * 6.0));
  float f = fbm(b + warp * r + ripple);
  vec3 c = palm(f * 2.2 + q.x * 1.1 - r.y * 0.6 + uFlow2.w + dot(p, uFlow2.xy) * 0.6);
  float ink = smoothstep(0.3, 0.8, f);
  c *= ink * 1.2 * (0.8 + 0.8 * length(r - 0.5));
  c = max(mix(vec3(dot(c, vec3(0.3, 0.59, 0.11))), c, 1.35), 0.0);
  c += vec3(1.0) * ink * ink * ink * ink * 0.1;
  vec2 asp = vec2(uRes.y / uRes.x, 1.0);
  float rr = length(p);
  vec2 sp = rot(0.003 + (0.006 + 0.016 * uSurge) * exp(-rr * 2.5)) * p * 0.997 + (q - 0.5) * (0.004 + 0.008 * uSurge) + uFlowStep;
  vec3 prev = texture2D(uPrev, sp * asp + 0.5).rgb;
  gl_FragColor = vec4(mix(prev * 0.99, c, 0.13), 1.0);
}
`

/**
 * The Media Player family's one shader (Burst, Ribbons, Smoke, Rings, Embers - lib/visualizer.ts
 * FEEDBACK has each one's numbers). Every frame it (1) finds where each pixel's light was in the last
 * frame - zoomed, turned, swirled, drifted and jostled, the same for every pixel of a block when
 * blockiness is on - (2) fades that, (3) draws the live waveform or spectrum over it, and (4) colours
 * it. How bright each pixel is lives in the alpha channel, so the one-hue styles can be recoloured
 * whole as their hue moves on.
 */
export const FEEDBACK_SHADER = HEAD + COMMON + `
uniform sampler2D uSpec;
uniform sampler2D uWave;
uniform vec4 uWarp;
uniform vec4 uDrift;
uniform vec4 uFade;
uniform vec4 uLook;
uniform vec4 uRingP;
uniform vec3 uLineW;
uniform vec3 uLineAng;
uniform vec4 uLineP;
uniform vec4 uBarsP;
uniform vec4 uCoreP;
uniform vec3 uHueA;
uniform vec3 uHueB;
uniform vec3 uHueC;
float wv(float u) {
  return texture2D(uWave, vec2(clamp(u, 0.002, 0.998), 0.5)).r * 2.0 - 1.0;
}
float h1(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float onWave(float u, float du, float y, float amp, float w) {
  float a = wv(u - du) * amp;
  float b = wv(u) * amp;
  float c = wv(u + du) * amp;
  float dist = max(min(a, min(b, c)) - y, y - max(a, max(b, c)));
  return (1.0 - smoothstep(0.0, w, dist)) + uCoreP.w * exp(-max(dist, 0.0) / (w * 6.0));
}
float lineAt(vec2 p, float ang, float amp, float len, float w, float px) {
  float c = cos(ang);
  float s = sin(ang);
  vec2 q = vec2(c * p.x + s * p.y, -s * p.x + c * p.y);
  if (abs(q.x) > len) return 0.0;
  return onWave(q.x / (2.0 * len) + 0.5, 1.5 * px / (2.0 * len), q.y, amp, w);
}
float ringAt(vec2 p, float R, float amp, float w, float px) {
  float u = abs(atan(p.y, p.x)) / PI;
  return onWave(u, 1.5 * px / (PI * max(R, 0.02)), length(p) - R, amp, w);
}
void main() {
  vec2 asp = vec2(uRes.y / uRes.x, 1.0);
  vec2 p = (gl_FragCoord.xy - 0.5 * uRes) / uRes.y;
  float px = 1.0 / uRes.y;
  float t = uTime;
  float blk = uFade.w;
  vec2 pb = blk > 0.0 ? (floor(p / blk) + 0.5) * blk : p;
  vec2 ctr = uDrift.zw;
  vec2 q = pb - ctr;
  q = rot(uWarp.y + uWarp.z * exp(-length(q) * 2.0)) * q / (1.0 + uWarp.x);
  q += uWarp.w * vec2(sin(pb.y * 7.0 + t * 1.3) + sin(pb.y * 17.0 - t * 2.1), cos(pb.x * 6.0 - t * 1.1) + sin(pb.x * 15.0 + t * 1.7));
  vec2 suv = (p + (q + ctr - pb) - uDrift.xy) * asp + 0.5;
  vec4 prev = texture2D(uPrev, suv);
  if (uFade.z > 0.0) {
    vec2 o = uFade.z / uRes;
    prev = 0.4 * prev + 0.15 * (texture2D(uPrev, suv + vec2(o.x, 0.0)) + texture2D(uPrev, suv - vec2(o.x, 0.0)) + texture2D(uPrev, suv + vec2(0.0, o.y)) + texture2D(uPrev, suv - vec2(0.0, o.y)));
  }
  float inside = step(abs(suv.x - 0.5), 0.5) * step(abs(suv.y - 0.5), 0.5);
  float keptA = max(prev.a * uFade.x - uFade.y, 0.0) * inside;
  vec3 kept = max(prev.rgb * uFade.x - uFade.y, 0.0) * inside;
  float w = uLook.w * px;
  float grain = 1.0 - uLineP.w * h1(vec2(floor(atan(p.y, p.x) * 22.0), floor(t * 4.0)));
  float ring = 0.0;
  float ringW = uRingP.x + uRingP.w * smoothstep(0.45, 0.9, uKick);
  if (ringW > 0.0) ring = ringAt(p, uRingP.y, uRingP.z, w, px) * ringW * grain;
  vec2 pm = uLineP.z > 0.5 ? vec2(abs(p.x), p.y) : p;
  float l0 = 0.0;
  float l1 = 0.0;
  float l2 = 0.0;
  if (uLineW.x > 0.0) l0 = lineAt(pm, uLineAng.x, uLineP.x, uLineP.y, w, px) * uLineW.x * grain;
  if (uLineW.y > 0.0) l1 = lineAt(pm, uLineAng.y, uLineP.x, uLineP.y, w, px) * uLineW.y;
  if (uLineW.z > 0.0) l2 = lineAt(pm, uLineAng.z, uLineP.x, uLineP.y, w, px) * uLineW.z;
  float bars = 0.0;
  if (uBarsP.x > 0.0) {
    float n = uBarsP.z;
    float bxu = min(abs(p.x) / 0.8, 0.999) * n;
    float hgt = texture2D(uSpec, vec2((floor(bxu) + 0.5) / n, 0.5)).r * uBarsP.y;
    float fc = fract(bxu);
    float yb = p.y + 0.5;
    bars = step(0.14, fc) * step(fc, 0.86) * (1.0 - smoothstep(hgt - 2.0 * px, hgt, yb)) * uBarsP.x;
  }
  float rc = length(p - ctr);
  float core = exp(-rc * rc / (uCoreP.y * uCoreP.y)) * (uCoreP.x + uCoreP.z * uKick);
  float d = max(max(ring, core), max(bars, max(l0, max(l1, l2))));
  float a = max(keptA, min(d, 1.0));
  if (uBarsP.w > 0.0) a = min(max(d, keptA + d * uBarsP.w), 1.0);
  float hot = min(d, 1.0);
  vec3 drawn = uHueA * min(ring + bars + l0, 1.0) + uHueB * min(l1, 1.0) + uHueC * min(l2, 1.0) + vec3(1.0) * (core + 0.25 * hot * hot * hot * hot);
  vec3 baked = max(kept, min(drawn, 1.0));
  float x = a;
  if (uLook.y > 0.0) x = floor(x * uLook.y + 0.5) / uLook.y;
  vec3 mono = mix(uHueA * (uLook.z + (1.0 - uLook.z) * smoothstep(0.0, 0.55, x)), vec3(1.0), smoothstep(0.5, 1.0, x));
  gl_FragColor = vec4(mix(baked, mono, uLook.x), a);
}
`

/** The composite: the crossfade's two styles mixed, a soft vignette, and a dither against banding. */
export const COMPOSITE = HEAD + `
uniform sampler2D uA;
uniform sampler2D uB;
uniform float uMix;
uniform vec2 uRes;
void main() {
  vec3 c = mix(texture2D(uA, vUv).rgb, texture2D(uB, vUv).rgb, uMix);
  vec2 p = vUv - 0.5;
  p.x *= uRes.x / uRes.y;
  c *= 1.0 - 0.4 * smoothstep(0.4, 1.0, length(p));
  float n = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);
  gl_FragColor = vec4(c + (n - 0.5) / 255.0, 1.0);
}
`
