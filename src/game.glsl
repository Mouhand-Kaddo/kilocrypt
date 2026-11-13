layout(std430) buffer State {
    vec4 controls, screen;
    float audio[8192];
    vec3 eye;
    float time, yaw, pitch, health, flash, hurt, left, weapon, kick, bob, level, exitOpen, dead, hitmark;
    int boxCount;
    vec3 exitPos;
    float fade;
    vec3 tracerEnd;
    float tracer;
    vec3 player;
    float intensity;
    vec3 velocity;
    float grounded;
    vec3 aim;
    float fireCooldown, dashCooldown, shake, punch, hitstop, firing, musicClock, frenzy, frenzyClock, alarm, alarmRoom, spin, whirl, notice, boosted, pulse, swap, shown, guardsDown, droneClock;
    uint seed;
    float musicStep;
    float sampleClock, fuses, arsenal, arsenalStart, runTime, deaths, kills, ending, banner, spawnClock, hum, bfsCell;
    vec4 ammo, ammoStart, upgrades, upgradesStart, cursor, beamHit, beamNormal, entity[112], motion[112], monster[16], brain[16], charge[16], pickup[16], boxes[640], boxHalf[640], voice[16];
    float echo[14000], field[6400], pan[16], threat[16];
    int queue[6400], roomStart[17], doors[16], kinds[16], decals, decalList[64];
#ifdef BOT
    vec4 links[16];
    float parent[16], spare;
#endif
};

int material, part, hitBox, dynamicZero = 0;
vec3 normal = vec3(0);
const float monsterStats[40] = float[](0.5, 0.5, 3.0, 10.0, 0.13, 0.0, 1.3, 1.8, 0.4, 1.0, 3.0, 7.5, 0.35, 0.0, 1.3, 2.2, 0.7, 1.0, 9.0, 3.5, 0.15, 1.0, 1.7, 2.5, 0.75, 1.6, 22.0, 4.5, 0.3, 0.0, 2.4, 3.1, 1.8, 2.6, 340.0, 1.6, 0.3, 1.0, 4.6, 6.0);

float stat(int i, int k) {
    return monsterStats[int(max(monster[i].x, 0.0)) * 8 + k];
}

float bossRage() {
    return monster[15].x > 3.0 ? 1.0 - brain[15].x / stat(15, 2) : 0.0;
}

float twist() {
    float stage = mod(level - 1.0, 6.0);
    return stage > 4.0 ? stage : mod(stage * (mod(floor((level - 1.0) / 6.0), 4.0) + 1.0), 5.0);
}

bool hunter(int i) {
    return i == 12 && twist() == 3.0;
}

bool armored(int i) {
    return hunter(i) && fuses < 3.0;
}

float barRoot(int beat) {
    return float[](0, 0, -4, -2, 0, 3, -5, -4)[beat / 16 % 4 + (int(level) + beat / 128) % 2 * 4] + step(0.5, bossRage()) + fuses;
}

mat2 rot(float a) {
    return mat2(cos(a), sin(a), -sin(a), cos(a));
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9, 78.2))) * 43758.5);
}

float ripple(vec3 p) {
    return sin(p.x * 1.7 + sin(p.z * 2.3)) * sin(p.y * 1.9 + sin(p.x * 1.3)) * sin(p.z * 2.1 + sin(p.y * 1.1));
}

float capsule(vec3 p, vec3 a, vec3 b, float r) {
    vec3 pa = p - a, ba = b - a;
    return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - r;
}

float box(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0);
    return min(a, b) - h * h * 0.25 / k;
}

void hitShape(int i, vec3 ro, vec3 rd, vec3 m, inout float far) {
    vec4 c = boxes[i], h = boxHalf[i];
    vec3 o = ro - c.xyz, k = abs(m) * h.xyz, t1 = -m * o - k, t2 = -m * o + k, face = -sign(rd) * step(t1.yzx, t1) * step(t1.zxy, t1);
    float t = max(max(t1.x, t1.y), t1.z), exit = min(min(t2.x, t2.y), t2.z);
    if (t >= exit || t >= far) return;
    if (h.w > 0.0) {
        vec3 a = h.w == 1.0 || (h.w == 2.0) != (h.x > h.z) ? vec3(1, 0, 0) : vec3(0, 0, 1), b = h.w == 1.0 ? vec3(0, 0, 1) : vec3(0, 1, 0);
        vec2 po = vec2(dot(o, a), dot(o, b) + (h.w == 3.0 ? h.y : 0.0)), pd = vec2(dot(rd, a), dot(rd, b));
        float radius = h.w == 3.0 ? max(h.x, h.z) : min(min(h.x, h.z), h.w == 1.0 ? 9.0 : h.y), qa = dot(pd, pd), qb = dot(po, pd), disc = qb * qb - qa * (dot(po, po) - radius * radius), c0 = (-qb - sqrt(disc)) / qa, c1 = (-qb + sqrt(disc)) / qa;
        if (h.w == 3.0) {
            if (disc > 0.0 && t > c0 && t < c1) {
                if (c1 >= exit) return;
                t = c1;
                face = -(a * (po.x + pd.x * t) + b * (po.y + pd.y * t)) / radius;
            }
        } else {
            if (disc <= 0.0 || c0 >= exit || c1 <= t) return;
            if (c0 > t) {
                t = c0;
                face = (a * (po.x + pd.x * t) + b * (po.y + pd.y * t)) / radius;
            }
        }
    }
    if (t <= 0.0 || t >= far) return;
    far = t;
    normal = face;
    material = int(c.w);
    hitBox = i;
}

float traceScene(vec3 ro, vec3 rd, float far) {
    vec3 m = 1.0 / rd, b = (step(0.0, rd) * vec3(80, 8, 80) - ro) * m;
    float t = min(min(b.x, b.y), b.z);
    hitBox = -1;
    if (t < far) {
        far = t;
        material = b.y == t ? (rd.y < 0.0 ? 7 : 8) : 0;
        normal = -sign(rd) * step(b, b.yzx) * step(b, b.zxy);
    }
    ivec2 cell = ivec2(clamp(ro.xz / 20.0, 0.0, 3.0)), dir = ivec2(sign(rd.xz));
    vec2 next = ((vec2(cell) + step(0.0, rd.xz)) * 20.0 - ro.xz) * m.xz, delta = abs(m.xz) * 20.0;
    for (int k = roomStart[16]; k > 0; k -= 8) {
        if (any(greaterThan(uvec2(cell), uvec2(3)))) break;
        int r = cell.y * 4 + cell.x;
        for (int i = roomStart[r]; i < roomStart[r + 1]; i++) hitShape(i, ro, rd, m, far);
        if (far <= min(next.x, next.y)) break;
        vec2 side = step(next, next.yx);
        cell += ivec2(side) * dir;
        next += side * delta;
    }
    hitShape(boxCount - 1, ro, rd, m, far);
    return max(far, 0.0);
}

float maw(vec3 m, float r, inout float d) {
    float k = floor(atan(m.x, m.y) * 2.23 + 0.5) / 2.23;
    d = max(d, r - length(m * vec3(1, 1, 0.5)));
    m.xy = rot(k) * m.xy;
    return capsule(m, vec3(0, r * 1.1, -0.01), vec3(0, r * (0.6 + fract(k * 7.3) * 0.25), 0.03), 0.008 + 0.008 * fract(k * 3.1));
}

float creature(vec3 p, vec4 info) {
    float type = info.x, phase = info.y, d, e, f = 9.0;
    p.y /= 1.0 - info.w * 0.6;
    p += sin(p.yzx * 5.0 + type) * 0.025;
    if (type == 2.0 || type == 4.0) {
        p.y += 1.0;
        vec3 b = p - vec3(0, 0.85, 0);
        d = length(b * vec3(0.8, 1.1, 0.8)) - 0.6 + ripple(p * 3.0 + phase) * 0.12;
        f = maw((b - vec3(0, 0.05, 0.62)) * vec3(1, 0.8, 1), 0.2 + 0.06 * sin(phase), d);
        e = length(b - vec3(0, 0.05, 0.5)) - 0.2;
        for (int i = 0; i < 8 + dynamicZero; i++) {
            float a = i * 0.785 + 0.4 + sin(i * 5.0) * 0.3, up = (i & 1);
            vec3 arm = vec3(sin(a), 0, cos(a)), mid = arm * 0.9 + vec3(sin(phase + i) * 0.15, 0.8 + up * 0.6 + sin(phase * 1.3 + i * 2.0) * 0.15, 0);
            d = smin(d, min(capsule(p, arm * 0.3 + vec3(0, 0.75, 0), mid, 0.12 * (0.7 + fract(i * 0.61) * 0.6)), capsule(p, mid, arm * (1.15 - up * 0.4) + vec3(sin(phase * 1.7 + i) * 0.2, up * (1.6 + sin(phase * 2.0 + i) * 0.3), 0), 0.04)), 0.15);
            e = min(e, length(b - normalize(vec3(sin(i * 2.4) * 0.8, cos(i * 1.7) * 0.6 + 0.2, 1)) * 0.7) - (0.05 + fract(i * 0.37) * 0.04) * step(-0.9, sin(phase * 0.4 + i * 2.0)));
        }
    } else if (type == 0.0) {
        p = (p + vec3(0, 0.5, 0)) / 1.3;
        float side = sign(p.x);
        vec3 q = vec3(abs(p.x), p.yz), head = vec3(sin(floor(phase * 6.0) * 7.3) * 0.05, 0.62, 0.6), h = p - head;
        d = smin(capsule(p, vec3(0, 0.55, -0.35), vec3(0, 0.7, 0.3), 0.19), capsule(p, vec3(0, 0.65, 0.35), head, 0.05), 0.06);
        for (int i = 0; i < 2 + dynamicZero; i++) {
            float lift = max(sin(phase * 2.0 + i * 3.1 + side * 1.6), 0.0) * 0.2;
            vec3 knee = i == 0 ? vec3(0.48, 0.75 + lift, -0.15) : vec3(0.5, 0.8 + lift, 0.5);
            d = smin(d, min(capsule(q, i == 0 ? vec3(0.14, 0.55, -0.35) : vec3(0.16, 0.7, 0.3), knee, 0.07 - i * 0.02), capsule(q, knee, i == 0 ? vec3(0.45, lift * 0.5, -0.7) : vec3(0.4, lift * 0.5, 0.85), 0.045)), 0.05);
        }
        d = smin(d, length(h) - 0.15, 0.04);
        f = maw(h - vec3(0, -0.03, 0.12), 0.07, d) * 1.3;
        d *= 1.3;
        e = min(length(vec3(abs(h.x) - 0.06, h.y - 0.07, h.z - 0.11)) - 0.03, length(h - vec3(0, 0.05, 0.08)) - 0.04) * 1.3;
    } else {
        float s = type > 2.0 ? 1.6 : 1.0, swing = sin(phase) * sign(p.x) * 0.45;
        p = p / s + vec3(0, 1, 0);
        vec3 q = vec3(abs(p.x), p.yz);
        vec3 knee = vec3(0.17, 0.55, 0.15 + swing * 0.5), elbow = vec3(0.42, 1.1, 0.4 - swing * 0.4), hand = vec3(0.3, 0.3, 0.7 + swing * 0.3), head = vec3(sin(floor(phase * 4.0) * 7.3) * 0.12, 1.5, 0.7);
        d = min(capsule(q, vec3(0.13, 1, 0), knee, 0.07), capsule(q, knee, vec3(0.15, 0.05, swing), 0.05));
        d = smin(d, capsule(p, vec3(0, 0.95, 0), vec3(0, 1.42, 0.5), 0.15), 0.1);
        d = smin(d, capsule(p, head, head - vec3(0, 0.22, -0.06), 0.13), 0.05);
        d = smin(d, min(capsule(q, vec3(0.2, 1.35, 0.45), elbow, 0.05), capsule(q, elbow, hand, 0.04)), 0.04);
        d = min(d, capsule(q, hand, hand + vec3(0.03, -0.4, 0.3), 0.015));
        f = maw((p - head - vec3(0, -0.15, 0.14)) * vec3(1.2, 0.6, 1), 0.09, d) * s;
        if (s > 1.0) d = min(d, min(capsule(q, vec3(0.1, 1.6, 0.7), vec3(0.38, 1.75, 0.6), 0.04), capsule(q, vec3(0.38, 1.75, 0.6), vec3(0.55, 1.85, 1.05), 0.012)));
        e = min(length(vec3(abs(p.x - head.x), p.yz) - head - vec3(0.06, 0.06, 0.12)) - 0.035, length(p - head - vec3(0, -0.07, 0.1)) - 0.045);
        if (s < 1.5) {
            vec3 belly = p - vec3(0, 1.05, 0.3);
            d = smin(d, length(belly) - 0.3, 0.1);
        }
        e *= s;
        d = d * s - s * 0.04 + 0.04;
    }
    d += ripple(p * 13.0) * 0.012;
    part = e < min(d, f) ? 1 : f < d ? 2 : 0;
    return min(min(d, e), f) * (1.0 - info.w * 0.6);
}

vec4 monsterFrame(int i) {
    vec4 m = entity[i];
    m.y -= (monster[i].w + clamp(motion[i].w, 0.0, 0.5) * 0.3) * stat(i, 1) * 0.8;
    return m;
}

float monsterAt(vec3 p, int i) {
    vec4 m = monsterFrame(i);
    p -= m.xyz;
    if (charge[i].y > 0.0) p.y = -p.y;
    p.xz *= rot(-m.w);
    p.z += monster[i].z * 0.15;
    float s = monster[i].x > 3.0 ? 2.6 : 1.0;
    return creature(p / s, monster[i]) * s;
}

float gun(vec3 p) {
    float w = shown, d, wood = 9.0, reload = sin(clamp(fireCooldown * (w == 0.0 ? 4.5 : 3.14), 0.0, 3.14));
    p -= vec3(0.29 + sin(bob) * 0.012, -0.26 - abs(cos(bob)) * 0.012 - float(w == 2.0) * reload * 0.2 - swap * 0.35, 0.68 - kick * 0.45);
    p.xy += sin(time * vec2(90, 70)) * flash * float(w == 1.0) * 0.03;
    p.yz *= rot(kick * 0.8 + reload * 0.15);
    vec3 q = vec3(abs(p.x), p.yz);
    part = 0;
    if (w == 0.0) {
        vec3 f = p - vec3(0, -0.045, 0.06 - reload * 0.1);
        wood = min(box(f, vec3(0.045, 0.028, 0.07)) + step(0.5, fract(f.z * 40.0)) * 0.002, box(p - vec3(0, -0.06, -0.38), vec3(0.034, 0.045, 0.09)));
        d = min(min(capsule(q, vec3(0.027, 0, -0.22), vec3(0.027, 0, 0.24), 0.026), box(p - vec3(0, -0.01, -0.25), vec3(0.046, 0.03, 0.039)) - 0.006), min(box(p - vec3(0, 0.026, 0.01), vec3(0.006, 0.006, 0.22)), capsule(q, vec3(0.02, 0.02, -0.27), vec3(0.02, 0.042, -0.255), 0.006)));
    } else if (w == 1.0) {
        vec3 b = p;
        b.xy *= rot(spin);
        b.xy *= rot(floor(atan(b.y, b.x) / 1.047 + 0.5) * 1.047);
        d = min(min(capsule(b, vec3(0.045, 0, -0.2), vec3(0.045, 0, 0.36), 0.016), capsule(p, vec3(0, 0, -0.38), vec3(0, 0, -0.2), 0.05)), max(length(p.xy) - 0.07, abs(abs(p.z - 0.15) - 0.12) - 0.012));
        part = int(p.z > 0.29);
    } else if (w == 2.0) {
        d = min(min(max(capsule(p, vec3(0, 0, -0.32), vec3(0, 0, 0.26), 0.072), 0.056 - length(p.xy)), max(abs(length(p.xy) - 0.078) - 0.01, abs(p.z - 0.23) - 0.025)), min(capsule(p, vec3(-0.08, 0.06, -0.22), vec3(-0.08, 0.06, -0.06), 0.02), box(p - vec3(-0.05, 0.045, -0.14), vec3(0.025, 0.008, 0.03))));
    } else {
        wood = max(box(p - vec3(0, 0.03, -0.1), vec3(0.052, 0.024, 0.2)), (q.x + p.y) * 0.7071 - 0.06) + step(0.5, fract(p.z * 70.0)) * 0.001;
        d = min(box(p - vec3(0, -0.03, -0.16), vec3(0.044, 0.036, 0.17)) - 0.005, capsule(q, vec3(0.022, 0, 0.06), vec3(0.022, 0, 0.24), 0.013));
        float rim = length(p.yz - vec2(-0.03, -0.1)), cell = max(rim - 0.036, q.x - 0.056);
        if (cell < d) part = int(rim < 0.027);
        d = min(d, cell);
    }
    if (wood < d) part = 2;
    return min(d, wood);
}

#ifdef GAME
layout(local_size_x = 64) in;
float noteOffset = 0.0, clanked = 0.0;

const float weaponStats[28] = float[](0.7, 10.0, 0.07, 1.5, 6.0, 0.22, 0.0, 0.09, 1.0, 0.015, 2.8, 1.5, 0.025, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.1, 2.0, 0.12, 0.0, 0.0, 0.0, 0.0, 0.03, 4.0);
const float furniture[192] = float[](
    0.0, 4.5, 4.0, 4.5, 0.6, 4.0, 0.6, 19.0,
    0.0, 4.5, 0.25, 4.5, 0.85, 0.25, 0.85, 3.0,
    0.0, 7.5, 0.45, 2.5, 1.1, 0.45, 0.5, 3.0,
    0.0, 7.5, 0.95, 2.5, 1.2, 0.07, 0.6, 3.0,
    1.0, 4.0, 1.0, 4.0, 1.0, 1.0, 1.0, 2.0,
    1.0, 7.5, 0.9, 6.0, 0.45, 0.05, 2.4, 6.0,
    1.0, 7.5, 1.9, 6.0, 0.45, 0.05, 2.4, 6.0,
    1.0, 7.5, 1.2, 3.6, 0.45, 1.2, 0.06, 6.0,
    1.0, 7.5, 1.2, 8.4, 0.45, 1.2, 0.06, 6.0,
    2.0, 3.0, 2.6, 3.0, 0.3, 0.9, 0.3, 20.0,
    2.0, 3.0, 5.7, 3.0, 0.03, 2.3, 0.03, 1.0,
    2.0, 7.0, 2.4, 3.0, 0.26, 0.8, 0.26, 20.0,
    2.0, 7.0, 5.6, 3.0, 0.03, 2.4, 0.03, 1.0,
    2.0, 5.0, 7.95, 3.0, 5.0, 0.08, 0.08, 33.0,
    3.0, 5.5, 2.5, 5.5, 1.8, 2.5, 1.8, 17.0,
    3.0, 5.5, 6.5, 5.5, 0.3, 1.5, 0.3, 17.0,
    3.0, 9.0, 6.0, 5.0, 0.2, 0.2, 5.0, 33.0,
    3.0, 5.5, 0.15, 5.5, 2.1, 0.15, 2.1, 3.0,
    4.0, 7.5, 1.4, 6.25, 2.5, 0.1, 3.25, 15.0,
    4.0, 5.2, 0.65, 4.0, 0.08, 0.65, 0.08, 17.0,
    4.0, 5.2, 0.65, 8.5, 0.08, 0.65, 0.08, 17.0,
    4.0, 5.1, 2.45, 6.25, 0.04, 0.04, 3.25, 33.0,
    4.0, 7.5, 0.5, 2.75, 2.5, 0.5, 0.25, 3.0,
    4.0, 7.5, 0.25, 2.25, 2.5, 0.25, 0.25, 3.0);
const float sounds[176] = float[](
    220.0, 45.0, 0.7, 0.18, 0.8, 0.5, 3.0, 0.0,
    650.0, 220.0, 0.6, 0.05, 0.6, 0.9, 2.5, 0.9,
    90.0, 420.0, 0.75, 0.55, 1.0, 0.12, 3.0, -1.5,
    110.0, 22.0, 0.9, 0.8, 1.0, 0.05, 4.0, 0.0,
    1500.0, 300.0, 0.25, 0.1, 0.3, 0.5, 2.5, 1.5,
    2400.0, 1200.0, 0.15, 0.04, 0.5, 0.8, 2.0, 0.6,
    210.0, 150.0, 0.35, 0.25, 0.9, 0.3, 400.0, 2000.0,
    380.0, 600.0, 0.3, 0.4, 0.65, 0.25, 1400.0, 2400.0,
    75.0, 50.0, 0.4, 0.7, 1.0, 0.03, 300.0, 900.0,
    100.0, 60.0, 0.4, 0.8, 0.85, 0.2, 650.0, 1100.0,
    300.0, 50.0, 0.55, 0.25, 0.8, 0.35, 3.0, 0.8,
    600.0, 1400.0, 0.6, 0.3, 0.5, 0.4, 2.0, 1.0,
    110.0, 60.0, 0.8, 0.05, 0.3, 0.25, 1.0, 0.0,
    52.0, 32.0, 0.35, 2.2, 1.25, 0.12, 520.0, 1400.0,
    100.0, 48.0, 0.25, 0.14, 0.6, 0.08, 4.0, -1.0,
    1.0, 1.0, 0.0, 2.5, 0.22, 0.0, 1.0, 0.7,
    180.0, 45.0, 0.08, 0.14, 1.25, 0.7, 2.5, 0.0,
    340.0, 280.0, 0.65, 0.13, 0.75, 0.5, 3.0, 3.0,
    4000.0, 4000.0, 1.0, 0.045, 1.0, 1.0, 1.5, 0.0,
    1.0, 1.0, 0.0, 0.11, 0.6, 0.0, 4.0, -3.0,
    1.0, 1.0, 0.0, 0.3, 0.75, 0.0, 1.8, -1.2,
    400.0, 80.0, 0.85, 0.18, 0.5, 0.25, 1.5, 0.0);

float noise(float i) {
    uint h = uint(i) * 1664525u + 1013904223u;
    return ((h ^ h >> 16) * 1664525u + 1013904223u >> 9) / 8388608.0;
}

float rnd() {
    seed = seed * 1664525u + 1013904223u;
    return (seed >> 9) / 8388608.0;
}

vec3 spread(float s) {
    return (vec3(rnd(), rnd(), rnd()) - 0.5) * s;
}

bool inside(vec3 p, vec3 c, vec3 h) {
    return all(lessThan(abs(p - c), h));
}

vec3 monsterHalf(int i) {
    return vec2(stat(i, 0), stat(i, 1)).xyx;
}

vec4 cues[32];
vec2 cueFrom[32];
int cueCount = 0;

void playAt(float sound, float semitones, float gain, vec3 at) {
    cueFrom[cueCount & 31] = at.xz - eye.xz;
    cues[cueCount++ & 31] = vec4(sound, exp2(semitones / 12.0), gain, sampleClock + noteOffset);
}

void playNote(float sound, float semitones, float gain) {
    playAt(sound, semitones, gain, eye);
}

int cellOf(vec3 p) {
    return int(clamp(p.z, 2.0, 77.0)) * 80 + int(clamp(p.x, 2.0, 77.0));
}

void chord(float root, int n) {
    noteOffset = 4725.0 - musicClock;
    for (int k = 0; k < n + dynamicZero; k++) {
        playNote(15.0, root + float(50992 >> k * 4 & 15), 1.0);
        noteOffset += 2362.5;
    }
    noteOffset = 0.0;
}

void growl(int i, float tone) {
    vec3 to = entity[i].xyz + vec3(0, stat(i, 1) * 0.8, 0) - eye;
    float d = length(to), wall = field[cellOf(entity[i].xyz)] > d * 1.5 + 2.0 && field[cellOf(entity[i].xyz)] < 1e8 ? 0.4 : 1.0, clear = (0.7 + 0.3 * dot(to, aim) / d) * wall * 11.0 / (12.0 + d);
    playAt((monster[i].x > 3.0 ? 14.0 : 7.0 + monster[i].x) - clear, 12.0 * log2(sqrt(tone) * (0.9 + rnd() * 0.2)), 20.0 / (8.0 + d) * wall, entity[i].xyz);
}

vec3 roomCenter(int r) {
    return vec3(r % 4 + 0.5, 0, r / 4 + 0.5) * 20.0;
}

int roomOf(vec3 p) {
    ivec2 g = ivec2(clamp(p.xz / 20.0, 0.0, 3.0));
    return g.y * 4 + g.x;
}

#ifdef BOT

void search(int from) {
    int todo[16], head = 0, tail = 1;
    for (int r = 0; r < 16 + dynamicZero; r++) parent[r] = -1.0;
    parent[from] = from;
    todo[0] = from;
    while (head < tail) {
        int r = todo[head++];
        for (int d = 0; d < 4 + dynamicZero; d++) {
            int n = r + int[](1, -1, 4, -4)[d];
            if (links[r][d] > 0.0 && parent[n] < 0.0) {
                parent[n] = r;
                todo[tail++] = n;
            }
        }
    }
}
#endif

bool blocked(vec3 c, vec3 h) {
    if (!inside(c, vec3(40, 4, 40), vec3(40, 4, 40) - h)) return true;
    int r = roomOf(c);
    for (int i = roomStart[r]; i < roomStart[r + 1]; i++)
        if ((boxHalf[i].w != 3.0 || abs(h.y - 1.1) > 0.9) && inside(c, boxes[i].xyz, h + boxHalf[i].xyz)) return true;
    return inside(c, boxes[boxCount - 1].xyz, h + boxHalf[boxCount - 1].xyz);
}

bool move(inout vec3 p, inout vec3 v, vec3 h, float dt, bool climb) {
    bool ground = false;
    for (int k = 0; k < 3 + dynamicZero; k++) {
        vec3 old = p;
        p[k] += v[k] * dt;
        if (blocked(p, h)) {
            if (climb && k != 1) {
                p.y += max(0.55, h.y * 0.6);
                if (!blocked(p, h)) continue;
            }
            p = old;
            ground = ground || k == 1 && v.y < 0.0;
            v[k] = 0.0;
        }
    }
    return ground;
}

void emit(float what, vec3 at, vec3 v, float duration) {
    int range = what < 3.0 ? 0 : what < 6.0 ? 1 : 2;
    int e = int[](16, 40, 104)[range] + int(cursor[range]++) % int[](24, 64, 8)[range];
    entity[e] = vec4(at, what);
    motion[e] = vec4(v, duration);
}

void hurtPlayer(float amount) {
    if (dead > 0.0 || dashCooldown > 0.75) return;
    frenzy = 0.0;
    if ((health -= amount * (0.9 + min(level, 8.0) * 0.1)) <= 0.0) dead = 0.01;
    hurt = 1.0;
    shake += 0.4;
    punch += 0.1;
    playNote(10.0, 0.0, 1.0);
}

void hurtMonster(int i, float damage, vec3 push, vec3 at) {
    if (monster[i].w > 0.0) return;
    float opening = motion[i].w > 0.0 || brain[i].w == 0.0 ? 1.0 : 0.0;
    damage *= (monster[i].x > 3.0 ? (fuses + 1.0) / 4.0 : 1.0) * (1.0 + opening) / (0.85 + min(level, 14.0) * 0.15) / (hunter(i) ? 5.0 : 1.0);
    if (armored(i)) {
        damage = 0.0;
        if (clanked++ < 4.0) emit(4, at, spread(5.0), 0.3);
        if (clanked == 1.0) playNote(5.0, -12.0, 0.6);
    } else {
        if (hitmark < 1.0) {
            playNote(5.0, opening * 12.0, 1.0);
            emit(3, at, push * 0.3 + spread(6.0) + vec3(0, 2, 0), 30.0);
        }
        monster[i].z = hitmark = 1.0;
    }
    motion[i].xyz += push / stat(i, 2) * 3.0;
    if (length(push) > 5.0) brain[i].yz = vec2(max(brain[i].y, 0.3), 0);
    if ((brain[i].x -= damage) <= 0.0) {
        monster[i].w = 0.01;
        left--;
        if (firing > 0.2 && dead == 0.0 && push != vec3(0)) {
            frenzy = min(frenzy + 1.0, 3.0);
            frenzyClock = 1.6;
            if (length(entity[i].xyz - player) < 4.0) health = min(1.0, health + 0.04 * frenzy);
        }
    }
}

void burst(vec3 at, float radius, float damage, float push, float stun) {
    for (int i = 0; i < 16 + dynamicZero; i++) {
        vec3 to = entity[i].xyz - at;
        float gap = length(max(abs(to) - monsterHalf(i) * float(stun != 0.0), 0.0));
        if (monster[i].x >= 0.0 && gap < radius) {
            hurtMonster(i, damage * (1.0 - gap / radius), normalize(to + 1e-4) * push, entity[i].xyz);
            if (monster[i].x < 4.0 && !armored(i)) motion[i].w = max(motion[i].w, stun);
        }
    }
}

int upgradeTarget() {
    int g = int(weapon);
    if (upgrades[g] > 1.0)
        for (int w = 0; w <= int(arsenal) + dynamicZero; w++)
            if (upgrades[w] < upgrades[g]) g = w;
    return g;
}

void killMonster(int i) {
    vec3 at = entity[i].xyz;
    kills++;
    for (int k = 0; k < 6 + dynamicZero; k++) emit(5, at + spread(1.0), motion[i].xyz * 0.5 + spread(10.0) + vec3(0, 5, 0), 30.0);
    emit(20, at, vec3(0), 0.6);
    shake += 0.3;
    if (monster[i].x == 1.0) emit(1, at, vec3(0), 0.0);
    if (hunter(i)) playNote(3.0, -12.0, 1.0);
    if (monster[i].x > 3.0) {
        playNote(3.0, -12.0, 1.0);
        playNote(13.0, 12.0, 1.0);
        hitstop = 0.25;
        exitPos.y = 0.0;
        boxes[boxCount - 1].y = 0.25;
    }
    float drop = rnd() < 0.15 ? 2.0 : 0.0, others = 0.0;
    if (i > 11 && i < 15) {
        for (int j = 12 + dynamicZero; j < 15; j++) others += float(monster[j].x >= 0.0 && monster[j].w <= 0.01);
        drop = guardsDown++ == 0.0 && arsenal < min(level - 1.0, 3.0) ? 3.0 : others > 1.0 ? 2.0 : upgrades[upgradeTarget()] < 2.0 ? 4.0 : 7.0;
    }
    if (drop > 0.0) {
        int slot;
        for (int t = 0; t < 8 + dynamicZero && pickup[slot = 8 + int(mod(cursor.w++, 8.0))].w > 2.0; t++);
        pickup[slot] = vec4(at.x, 0.3, at.z, drop);
    }
    growl(i, 0.6);
    playAt(12.0, 7.0, 2.5, at);
}

void addBox(vec3 c, vec3 h, float kind) {
    if (boxCount > 638) return;
    boxes[boxCount] = vec4(c, mod(kind, 16.0));
    boxHalf[boxCount++] = vec4(h, floor(kind / 16.0));
}

bool hall(int r) {
    return abs(r % 4 - 1.5) < 1.0 && abs(r / 4 - 1.5) < 1.0;
}

void spawnMonster(int i, vec3 at, float type, float awake, bool ceiling) {
    monster[i] = vec4(type, 0, 0, 0);
    entity[i].xyz = at + vec3(0, ceiling ? 7.95 - stat(i, 1) : stat(i, 1) + 0.05, 0);
    motion[i] = vec4(0);
    charge[i] = vec4(0, ceiling, 0, 0);
    brain[i] = vec4(stat(i, 2), 1, 0, awake);
    if (i < 15 && blocked(entity[i].xyz, monsterHalf(i))) monster[i].x = -1.0;
    else left++;
}

void spawn(vec3 at, float type, bool ceiling) {
    for (int j = 0; j < 12 + dynamicZero; j++)
        if (monster[j].x < 0.0) {
            spawnMonster(j, at, type, 1.0, ceiling);
            return;
        }
}

float guardType() {
    return float(1240 >> int(twist()) * 2 & 3);
}

float pickType() {
    return float(int(rnd() * min(level + 1.0, 4.0)));
}

void spawnLevel() {
    seed = uint(level) * 7919u + uint(deaths) * 104729u;
    float stage = twist();
    bool boss = stage > 4.0;
    boxCount = 0;
#ifdef BOT
    for (int r = 0; r < 16 + dynamicZero; r++) links[r] = vec4(0);
#endif
    for (int r = 0; r < 16 + dynamicZero; r++) {
        int x = r % 4, z = r / 4;
        threat[r] = 0.0;
        kinds[r] = int(mod(step(0.5, hash(vec2(r, level))) * (boss ? 2.0 : 1.0) + level * 2.0, 5.0));
        bool east = x < 3 && (z == 3 || rnd() < 0.5);
        float loops = float[](0.25, 0.1, 0.55, 0.0, 0.35, 0.25)[int(stage)];
        bool north = z < 3 && (!east || rnd() < loops);
        east = east || x < 3 && rnd() < loops;
        doors[r] = int(east) + int(north) * 2;
    }
    bool square = false;
    for (int m = boss ? 1 : int(rnd() * 3.0) + 2; m > 0; m--) {
        int r = boss ? 5 : int(rnd() * 3.0) + int(rnd() * 3.0) * 4;
        float shape = boss ? 1.0 : rnd();
        doors[r] |= shape < 0.35 ? 5 : shape < 0.7 ? 10 : 15;
        if (shape > 0.9 && !square) {
            doors[r + 1] |= 10;
            doors[r + 4] |= 5;
            square = true;
        }
    }
    for (int r = 0; r < 16 + dynamicZero; r++) {
        roomStart[r] = boxCount;
        if ((doors[r] & 4) > 0) kinds[r + 1] = kinds[r];
        if ((doors[r] & 8) > 0) kinds[r + 4] = kinds[r];
#ifdef BOT
        if ((doors[r] & 1) > 0) links[r].x = links[r + 1].y = 1.0;
        if ((doors[r] & 2) > 0) links[r].z = links[r + 4].w = 1.0;
#endif
        int x = r % 4, z = r / 4;
        vec3 c = roomCenter(r);
        for (int d = 0; d < 4 + dynamicZero; d++) {
            ivec2 o = ivec2[](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1))[d];
            int n = r + o.x + o.y * 4;
            if (any(greaterThan(uvec2(x + o.x, z + o.y), uvec2(3)))) continue;
            int door = doors[d % 2 > 0 ? n : r] >> d / 2;
            vec3 dir = vec3(o.x, 0, o.y), across = abs(dir), along = across.zyx, edge = c + dir * 10.0 + vec3(0, 4, 0), thin = across * 0.5 + vec3(0, 4, 0);
            if ((door & 4) > 0) {
                for (float side = -1.0; side < 2.0 + dynamicZero && !boss; side += 2.0) addBox(edge + along * side * 5.0, vec3(0.6, 4, 0.6), 19.0);
                addBox(edge + vec3(0, 3.6, 0), across * 0.3 + along * 10.0 + vec3(0, 0.4, 0), 6.0);
                continue;
            }
            if ((door & 1) == 0)
                addBox(edge, thin + along * 10.0, 0.0);
            else {
                if (hash(edge.xz + level) < 0.25) addBox(edge - vec3(0, 3.55, 0), across * 0.45 + along * 2.1 + vec3(0, 0.45, 0), 33.0);
                for (float side = -1.0; side < 2.0 + dynamicZero; side += 2.0) {
                    addBox(edge + along * side * 6.0, thin + along * 4.0, 0.0);
                    addBox(edge + along * side * 2.1 - vec3(0, 2.25, 0), across * 0.7 + along * 0.15 + vec3(0, 1.75, 0), 6.0);
                }
                addBox(edge + vec3(0, 1.75, 0), across * 0.7 + along * 2.25 + vec3(0, 2.25, 0), 54.0);
            }
        }
        addBox(c + vec3(0, 7, 0), vec3(0.03, 1, 0.03), 1.0);
        addBox(c + vec3(0, 5.85, 0), vec3(0.3, 0.18, 0.3), 30.0);
        addBox(c + vec3(0, 7.7, 5), vec3(10, 0.3, 0.25), 6.0);
        addBox(c + vec3(0, 7.7, -5), vec3(10, 0.3, 0.25), 6.0);
        float radius = 0.06 + hash(c.xz) * 0.14;
        if (((radius > 0.13 ? doors[r] : x > 0 ? doors[r - 1] : 0) & 4) == 0) addBox(c + vec3(radius > 0.13 ? 9.15 : -9.15, 6.6, 0), vec3(radius, radius, 9.5), 33.0);
        if (r == 0) continue;
        if (boss && hall(r)) {
            addBox(c * 0.6 + vec3(16, 4, 16), vec3(0.8, 4, 0.8), 17.0);
            continue;
        }
        float style = float(kinds[r]);
        for (int k = 0; k < 4 + dynamicZero; k++) {
            if (rnd() < 0.3) continue;
            float s = 0.5 + floor(rnd() * 4.0) * 0.25;
            vec3 jitter = spread(3.0) * vec3(1, 0, 1);
            for (int f = 0; f < 192 + dynamicZero; f += 8) {
                if (furniture[f] != style) continue;
                float loose = furniture[f + 7] == 2.0 ? 1.0 : 0.0;
                addBox(c + vec3((k & 1) > 0 ? furniture[f + 1] : -furniture[f + 1], furniture[f + 2] * mix(1.0, s, loose), (k & 2) > 0 ? furniture[f + 3] : -furniture[f + 3]) + jitter * loose, vec3(furniture[f + 4], furniture[f + 5], furniture[f + 6]) * mix(1.0, s, loose), furniture[f + 7]);
            }
        }
    }
    roomStart[16] = boxCount;
    for (int c = 0; c < 6400 + dynamicZero; c++) field[c] = blocked(vec3(c % 80, 1.675, c / 80) + 0.5, vec3(0.8, 1.125, 0.8)) ? 1e9 : 999.0;
    int perm[15], role = boss ? 1 : 0;
    for (int k = 0; k < 15 + dynamicZero; k++) perm[k] = k + 1;
    for (int k = 14 + dynamicZero; k > 0; k--) {
        int j = int(rnd() * (k + 1)), t = perm[k];
        perm[k] = perm[j];
        perm[j] = t;
    }
    exitPos = vec3(40, -9, 40);
    for (int i = 0; i < 16 + dynamicZero; i++) pickup[i] = vec4(0);
    for (int k = 0; k < 15 + dynamicZero; k++) {
        int r = perm[k];
        vec3 c = roomCenter(r), at = c;
        if (boss && hall(r)) continue;
        if (role == 0) {
            if (r % 4 + r / 4 > 3) {
                exitPos = c;
                role++;
            }
            continue;
        }
        for (int t = 0; t < 12 + dynamicZero; t++) {
            vec3 q = c + spread(12.0) * vec3(1, 0, 1);
            if (!blocked(q + vec3(0, 4, 0), vec3(0.8, 3.9, 0.8))) {
                at = q;
                break;
            }
        }
        if (role < 9) pickup[role - 1] = vec4(at, role < 4 ? 1.0 : role > 7 ? 7.0 : 2.0);
        role++;
    }
    if (boss) pickup[2].xz = vec2(27, 53);
    addBox(exitPos + vec3(0, 0.25, 0), vec3(2, 0.25, 2), 5.0);

    left = 0.0;
    for (int e = 16; e < 112 + dynamicZero; e++) entity[e].w = 0.0;
    for (int i = 0; i < 16 + dynamicZero; i++) {
        monster[i].x = -1.0;
        if (i < min(2.0 + stage * 1.2 + floor(level / 7.0) * 2.0, 9.0)) {
            vec3 at = roomCenter(1 + int(rnd() * 15.0)) + vec3(2.0 + rnd() * 5.0, 0, 0) * (rnd() < 0.5 ? -1.0 : 1.0);
            float type = pickType();
            spawnMonster(i, at, type, float(rnd() < stage * 0.1), type < 2.0 && rnd() < (stage == 2.0 ? 0.9 : 0.35));
        }
    }
    for (int g = 12; g < 15 + dynamicZero; g++) {
        float guard = guardType();
        spawnMonster(g, pickup[g - 12].xyz, guard, level > 6.0 || hunter(g) ? 1.0 : 0.0, guard < 2.0);
    }
    if (boss) spawnMonster(15, vec3(40, 0, 40), 4.0, 0.0, false);
    player = roomCenter(0) + vec3(0, 0.95, 0);
    velocity = vec3(0);
    health = 1.0;
    ammo = ammoStart;
    arsenal = arsenalStart;
    upgrades = upgradesStart;
    weapon = min(weapon, arsenal);
    yaw = pitch = dead = exitOpen = fade = intensity = hurt = shake = fuses = banner = frenzy = spawnClock = hitstop = alarm = whirl = notice = pulse = guardsDown = 0.0;
    bfsCell = -1.0;
    playNote(19.0, 74.4, 1.5);
    playNote(15.0, 86.4, 1.0);
}

void sequence(int count) {
    float k = dead > 0.0 ? 0.0 : max(intensity, alarm * 0.08), drums = smoothstep(0.3, 0.6, k) * 0.25;
    if ((musicClock += count) > 4725.0) {
        musicClock -= 4725.0;
        noteOffset = max(count - musicClock, 0.0);
        float rage = bossRage();
        int beat = int(musicStep++), step = beat % 16, old = (beat + 1) % 16, bar = beat / 16 % 4, phrase = rage > 0.0 ? 8 : beat / 64 % 2 * 8, odd = int(level) % 2, kicks = int[](2369, 18753, 1033, 17417)[phrase / 8 + odd * 2];
        float root = barRoot(beat), hook = float[](0, -99, 3, 1, 0, -99, -5, -99, -4, -5, -99, 3, 1, -99, 0, -99)[(step / 2 + bar % 2 * 8 + int(level) * 6) % 16];
        if (abs(mod(sampleClock - voice[old].w, 16758000.0) - 1.2e7) < 4e6) voice[old].z = 0.0;
        if (k > 0.15 && step % (k > 0.4 ? 4 : 8) < 2) playNote(14.0, 0.0, k * (1.0 - step % 2 * 0.4) * max(0.0, 1.0 - drums * 4.6));
        if (alarm > 6.0 && step % 4 == 0) playNote(20.0, 110.4 + root + float(step % 8 / 4 * 5), (alarm - 6.0) * 0.1);
        bool kickHit = (kicks >> step & 1) > 0 && beat % 128 < 112;
        if (drums > 0.0) {
            if (kickHit) playNote(16.0, 0.0, drums);
            if (step % (8 << odd) == 4 << odd || bar == 3 && step > 12) playNote(17.0, 0.0, drums * (step % (8 << odd) == 4 << odd ? 1.0 : 0.5));
            if (step % 2 == 0) playNote(19.0, 74.4 + root + float[](0, 0, 1, 0, 3, 0, 1, -2, 0, 12, 0, 10, 8, 3, -5, -2)[(step / 2 + int(level) * 6) % 8 + phrase], drums * (kickHit ? 0.25 : 1.0));
            if ((k > 0.55 || rage > 0.0) && (step % 2 == 1 || rage > 0.66 || frenzy > 1.0 || alarm > 0.0)) playNote(18.0, 0.0, drums * (step % 4 == 3 ? 1.0 : 0.5));
            if ((k > 0.6 || rage > 0.0) && (phrase > 0 || k > 0.8 && bar < 2) && step % (2 << odd) == 0 && hook > -50.0) playNote(20.0, 110.4 + root + hook, drums * 0.8);
        } else if (step % 4 == 0 && hook > -50.0 && (beat % 128 < 64 || ending + dead > 0.0))
            playNote(15.0, 110.4 + root + hook, 0.3);
    }
    for (int j = max(cueCount - 32, 0); j < cueCount; j++) {
        vec4 c = cues[j & 31];
        if (c.z == 0.0) continue;
        c.z *= 20.0 / (20.0 + length(cueFrom[j & 31]));
        int b = abs(c.x - 17.0) > 3.0 ? 8 : 0, v = b;
        float oldest = -1e9;
        for (int i = b; i < b + 8 + dynamicZero; i++) {
            float age = voice[i].z == 0.0 ? 1e9 : abs(mod(c.w - voice[i].w + 8e6, 16758000.0) - 8e6) / sounds[int(voice[i].x) * 8 + 3] - log(voice[i].z * sounds[int(voice[i].x) * 8 + 4]) * 44100.0;
            if (age > oldest) {
                oldest = age;
                v = i;
            }
        }
        voice[v] = c;
        pan[v] = (rot(yaw) * cueFrom[j & 31]).x / (length(cueFrom[j & 31]) + 1.0) + float(c.x == 15.0 || c.x == 18.0) * sin(c.w) * 0.3;
    }
    sampleClock = mod(sampleClock + count, 16758000.0);
    droneClock = mod(droneClock + count * exp2(fuses / 12.0), 882000.0);
}

void render(int n, int count) {
    if (n < count) {
        float k = intensity, w = mod(sampleClock + (n - count), 882000.0), t = (droneClock + (n - count) * exp2(fuses / 12.0)) * 1.425e-4, duck = 0.0;
        vec2 music = vec2(0), s = vec2(0) + (sin(t * 36.7) * 0.6 + sin(t * vec2(73.4, 73.85)) * 1.4 + sin(t * 110.1) * 0.5 + sin(t * 174.6) * 0.3 + (sin(t * 587.3) + sin(t * vec2(587.9, 586.6))) * 0.2 * (1.0 - k)) * 0.024 * (1.2 - k * 0.6) * (1.0 + sin(t * 0.1) * 0.4) + (sin(t * 220.0) + sin(t * 330.5) * 0.6 + sin(t * 441.0) * 0.3) * (0.6 + 0.4 * sin(t * 9.0)) * hum * 0.08;
        for (int j = 0; j < 16 + dynamicZero; j++) {
            vec4 v = voice[j];
            int p = int(v.x) * 8;
            float m = mod(sampleClock + (n - count) - v.w, 16758000.0), span = sounds[p + 3] * 44100.0, g = exp(-m / span), u = m * sounds[p + 5] * v.y + fract(v.w * 0.0137) * 1e4, x = 0.0;
            if (v.z == 0.0 || g < 1e-3) continue;
            float f = v.y * (sounds[p + 1] + (sounds[p] - sounds[p + 1]) * g), z = v.y * 1.425e-4 * (sounds[p + 1] * m + (sounds[p] - sounds[p + 1]) * (1.0 - g) * span), hiss = (mix(noise(u), noise(u + 1.0), fract(u)) * 2.0 - 1.0) * sqrt(sounds[p + 5]) * sounds[p + 2];
            bool voiced = sounds[p + 6] > 50.0;
            if (voiced) {
                float a = m * 0.0005 + v.y * 999.0;
                z += (mix(noise(a), noise(a + 1.0), fract(a)) * 3.0 + sin(m * 0.0007 + v.y * 999.0)) * f * 0.006;
                float c = 1.0 - fract(v.x);
                for (int h = 1; h < 40 + dynamicZero && h * f < 400.0 + 4600.0 * c; h++) {
                    vec2 d = (h * f / vec2(sounds[p + 6], sounds[p + 7]) / (0.75 + 0.35 * g) - 1.0) * vec2(2.5, 3);
                    x += sin(h * z + h * h) * (dot(exp(-d * d), vec2(1, 0.6)) + 0.4 / h);
                }
                x = (x * (0.6 + 0.4 * sin(z * 0.5)) * (1.0 - sounds[p + 2]) + hiss * (1.0 + sin(z)) * 4.0 * c) * 0.45;
            } else
                x = (sin(z + sin(z * (sounds[p + 7] < 0.0 ? 1.0 : 3.5)) * sounds[p + 7] * g) * (1.0 - sounds[p + 2]) + hiss) * sounds[p + 6];
            float e = g * (1.0 - exp(-m * (voiced ? 0.0003 : 0.005))) * v.z * sounds[p + 4];
            vec2 y = x / (1.0 + abs(x)) * e * normalize(1.0 + vec2(-0.9, 0.9) * pan[j]) * 1.41;
            if (j < 8 && v.z < 1.0) music += y;
            else s += y, duck += max(e - 0.3, 0.0);
        }
        int at = int(mod(w, 14000.0));
        float delayed = echo[at], early = echo[int(mod(w + 4410.0, 14000.0))];
        echo[at] = (s.x + s.y) * 0.5 + (delayed + echo[int(mod(w + 9000.0, 14000.0))]) * 0.3;
        s = tanh(clamp(s + music / (1.0 + duck * 2.0) + vec2(delayed, early) * 0.2 - vec2(early, delayed) * 0.08, -6.0, 6.0)) * 0.64;
        audio[n * 2] = s.x;
        audio[n * 2 + 1] = s.y;
    }
}

#ifdef BOT
void bot() {
    int target = -1, frame = int(spare++);
    float best = 1e9;
    for (int i = 0; i < 16 + dynamicZero; i++) {
        float d = length(entity[i].xyz - player);
        if (monster[i].x >= 0.0 && monster[i].w == 0.0 && d < best) {
            best = d;
            target = i;
        }
    }
    vec3 goal = exitPos;
    for (int i = 0; i < 16; i++)
        if (pickup[i].w > 0.0 && (i < 4 || pickup[i].w == 4.0 && distance(pickup[i].xyz, player) < 25.0)) goal = pickup[i].xyz;
    int here = roomOf(player);
    search(roomOf(goal));
    vec3 walk = here == roomOf(goal) ? goal : (roomCenter(here) + roomCenter(int(parent[here]))) * 0.5, look = target >= 0 ? entity[target].xyz + vec3(0, 0.3, 0) - eye : aim;
    bool visible = target >= 0 && best < 25.0 && traceScene(eye, normalize(look), length(look)) >= length(look) - 1.0;
    if (!visible) look = walk - player;
    float dy = clamp(mod(atan(look.x, look.z) - yaw + 3.1416, 6.2832) - 3.1416, -0.08, 0.08);
    float dp = clamp((visible ? atan(look.y, length(look.xz)) : 0.0) - pitch, -0.08, 0.08);
    vec3 toWalk = walk - player;
    float rel = atan(toWalk.x, toWalk.z) - yaw;
    int keys = (cos(rel) > 0.3 ? 1 : 0) | (cos(rel) < -0.3 ? 2 : 0) | (sin(rel) > 0.3 ? 8 : 0) | (sin(rel) < -0.3 ? 4 : 0);
    if (visible && best < 6.0) keys = 2;
    if (frame % 120 == 0) keys |= 16;
    if (length(velocity.xz) < 2.0) keys |= (frame / 40 % 2 > 0 ? 4 : 8) | 16;
    if (visible && abs(dy) < 0.06 && abs(dp) < 0.06 || dead > 2.5) keys |= 32;
    keys |= 128 << frame / 400 % 4;
    for (int i = 0; i < 16 + dynamicZero; i++) {
        float near = length(entity[i].xyz - player);
        if (monster[i].x >= 0.0 && monster[i].w == 0.0 && (charge[i].w > 0.0 && near < 20.0 || brain[i].z > 0.0 && near < 5.0)) keys = (keys & ~15) | (brain[i].z > 0.0 ? 2 : 0) | (frame / 90 % 2 > 0 ? 4 : 8) | 64;
    }
    controls.xyz = vec3(dy / 0.0013, -dp / 0.0013, keys);
#ifdef STAND
    controls.xyz = vec3(0);
#endif
#ifdef RESPAWN
    if (frame % 100 == 99) fade = -1.0;
#endif
#ifdef GUN
    arsenal = 3.0;
    ammo = vec4(99);
    weapon = GUN;
#endif
#ifdef TOUR
    controls.xyz = vec3(0);
    player = roomCenter(frame / 20 % 16) + vec3(0, 0.95, 0);
    velocity = vec3(0);
    yaw = 0.785;
    pitch = -0.1;
    fuses = 3.0;
    health = 1.0;
#endif
#ifdef ENDING
    ending = frame > 30 ? 3.0 : 0.0;
    runTime = 754.0;
    deaths = 7.0;
    kills = 123.0;
#endif
#ifdef SOUNDTEST
    for (int i = 0; i < 16 + dynamicZero; i++) monster[i].x = -1.0;
    controls.xyz = vec3(0);
    if (frame % 90 == 60 && frame < 1860) playNote(float(frame / 90), frame == 1410 ? 98.4 : frame == 1770 ? 74.4 : 0.0, 1.0);
    intensity = max(frame - 1800, 0) / 2400.0;
#endif
#ifdef SHOWCASE
    controls.xyz = vec3(0, 0, frame % 40 < 2 ? 32 : 0);
    for (int i = 0; i < 16 + dynamicZero; i++) {
        monster[i] = vec4(i < 4 ? i : -1, frame * 0.08, 0, 0);
        entity[i].xyz = roomCenter(0) + vec3(i * 2.2 - 3.3, monsterStats[i * 8 + 1], 6);
        brain[i] = vec4(99, 1, 0, 1);
    }
#ifdef CLOSE
    for (int i = 0; i < 16; i++) monster[i].x = i == 0 ? CLOSE : -1.0;
    entity[0].xyz = roomCenter(0) + vec3(0.3, stat(0, 1) + 0.05, 2.0 + stat(0, 1) * 1.5);
#endif
    left = 4.0;
    yaw = 0.0;
    pitch = 0.05;
#endif
    audio[8185] = 0.0;
    for (int i = 0; i < 16 + dynamicZero; i++) {
        bool hunting = monster[i].x >= 0.0 && monster[i].x < 4.0 && monster[i].w == 0.0 && brain[i].w > 0.0 && charge[i].y <= 0.0;
        float path = field[cellOf(entity[i].xyz)], reach = length((player - entity[i].xyz) * vec3(1, 0.3, 1));
        bool still = dead == 0.0 && hunting && path > 4.0 && path < 998.0 && reach > stat(i, 7) + 1.0 && length(motion[i].xz) < 0.5 && motion[i].w < 0.0 && brain[i].z <= 0.0 && charge[i].w <= 0.0;
        audio[8150 + i] = still ? audio[8150 + i] + controls.w : 0.0;
        audio[8184] += audio[8150 + i] > 2.0 ? controls.w : 0.0;
        audio[8185] += float(hunting);
    }
    audio[8186] = level;
    audio[8187] = health;
    audio[8188] = fuses * 100.0 + left;
    audio[8189] = weapon;
    audio[8190] = dead;
    audio[8191] = boxCount;
#ifdef GUARDKILL
    controls.xyz = vec3(0);
    if (frame == 60)
        for (int g = 12; g < 15 + dynamicZero; g++) hurtMonster(g, 1e4, vec3(0), entity[g].xyz);
    audio[8189] = 0.0;
    for (int i = 8; i < 16 + dynamicZero; i++) audio[8189] += float(pickup[i].w == 4.0) * 10.0 + float(pickup[i].w == 2.0);
#endif
#ifdef EXITTEST
    controls.xyz = vec3(0);
    fuses = 3.0;
    if (frame == 120) hurtMonster(12, 1e4, vec3(0), entity[12].xyz);
    if (frame < 120) audio[8148] = float(exitOpen > 0.0) * 10.0;
    audio[8189] = audio[8148] + float(exitOpen > 0.0);
#endif
#ifdef CHORDTEST
    controls.xyz = vec3(0);
    for (int i = 0; i < 16 + dynamicZero; i++) monster[i].x = -1.0;
    intensity = 1.0;
    if (frame % 120 == 60) chord(98.4, 3);
    if (frame % 120 == 80) {
        float notes = 0.0;
        for (int i = 0; i < 8 + dynamicZero; i++) notes += float(voice[i].x == 15.0 && voice[i].z == 1.0 && mod(sampleClock - voice[i].w, 16758000.0) < 22050.0);
        audio[8149] = frame < 120 ? notes : min(audio[8149], notes);
    }
    audio[8189] = audio[8149];
#endif
#ifdef PLASMATEST
    if (frame < 2) {
        arsenal = weapon = shown = 3.0;
        upgrades.w = 1.0;
        ammo.w = 90.0;
    }
    controls.xyz = vec3(0, 0, frame > 30 && frame < 140 ? 4128 : 0);
    audio[8189] = ammo.w;
#endif
#ifdef WHEELTEST
    if (frame < 2) audio[8148] = 0.0;
    arsenal = WHEELTEST;
    ammo = vec4(0, 0, 10, 10);
    controls.xyz = vec3(0, 0, frame % 30 == 10 ? 8192 : 0);
    audio[8148] = float(int(audio[8148]) | 1 << int(weapon));
    audio[8189] = audio[8148];
#endif
#ifdef STUNTEST
    audio[8189] = audio[8147];
#endif
#ifdef LUNGETEST
    controls.xyz = vec3(0);
    health = 1.0;
    if (frame == 30) {
        entity[12].xyz = player + vec3(2.5, 0, 0);
        brain[12].yw = vec2(0, 1);
    }
    if (brain[12].z > 0.2) dashCooldown = 0.85;
    audio[8189] = min(floor(audio[8146] * 10.0), 999.0);
#endif
}
#endif

void main() {
    dynamicZero = int(screen.w);
    if (gl_NumWorkGroups.x > 1u) {
        render(int(gl_GlobalInvocationID.x), int(screen.x));
        return;
    }
    if (gl_LocalInvocationIndex > 0u) return;
    if (level == 0.0 || fade < 0.0) {
        if (level == 0.0) {
            level = 1.0;
#ifdef LEVEL
            level = LEVEL;
            arsenalStart = min(level - 1.0, 3.0);
            upgradesStart = vec4(min(floor(level * 0.4), 2.0));
            ammoStart = vec4(0, 99, 9, 19);
#endif
        }
        spawnLevel();
    }
#ifdef BOT
    bot();
#endif
    float dt = clamp(controls.w, 1e-3, 0.05);
    time += dt;
    banner += dt;
    int k = int(controls.z);
    if (ending > 0.0) {
        if ((ending += dt) > 2.0 && (k & 32) > 0) {
            ending = 0.0;
            level++;
            fade = -1.0;
        }
    } else {
    runTime += dt;
    fade = min(1.0, fade + dt * 1.5);
    if ((frenzyClock -= dt) < 0.0) frenzy = max(frenzy - dt * 2.0, 0.0);
    if (hitstop > 0.0) {
        hitstop -= dt;
        dt *= 0.15;
    }
    float decay = 1.0 - min(dt * 10.0, 1.0);
    flash *= decay;
    tracer *= decay;
    hitmark *= decay;
    kick *= decay;
    punch *= decay;
    shake *= decay;
    firing *= 1.0 - dt;
    hurt *= 1.0 - dt * 2.0;
    dashCooldown -= dt;

    if (dead > 0.0) {
        if (dead == 0.01) {
            playNote(15.0, 97.4, 1.0);
            playNote(15.0, 98.4, 1.0);
            playNote(3.0, -12.0, 1.0);
        }
        if ((dead += dt) > 2.0 && (k & 32) > 0) {
            deaths++;
            fade = -1.0;
        }
    } else {
        yaw += controls.x * 0.0013;
        pitch = clamp(pitch - controls.y * 0.0013, -1.5, 1.5);
        for (int w = 0; w < 4 + dynamicZero; w++)
            if ((k & 128 << w) > 0 && w <= arsenal) weapon = w;
        int wheel = (k >> 13 & 1) - (k >> 14 & 1) + int(arsenal) + 1;
        for (int t = 0; t < 5 + dynamicZero; t++)
            if (t < 1 || weapon > 0.0 && ammo[int(weapon)] < 1.0) weapon = t > 3 ? 0.0 : float((int(weapon) + wheel) % (int(arsenal) + 1));
        vec3 forward = vec3(sin(yaw), 0, cos(yaw));
        vec3 wish = forward * ((k & 1) - (k >> 1 & 1)) + vec3(forward.z, 0, -forward.x) * ((k >> 3 & 1) - (k >> 2 & 1));
        if (dot(wish, wish) > 0.0) wish = normalize(wish) * 8.5;
        if ((k & 64) > 0 && dashCooldown <= 0.0 && dot(wish, wish) > 0.0) {
            velocity += wish * 2.5;
            dashCooldown = 0.9;
            playNote(21.0, 0.0, 1.0);
        }
        float control = min(dt * (grounded > 0.0 && dashCooldown < 0.7 ? 10.0 : 2.0), 1.0);
        velocity.xz += (wish.xz - velocity.xz) * control;
        velocity.y -= 22.0 * dt;
        if (grounded > 0.0 && (k & 16) > 0) velocity.y = 7.5;
        grounded = float(move(player, velocity, vec3(0.4, 0.9, 0.4), dt, true));
        float before = sin(bob);
        if (grounded > 0.0) bob += dt * length(velocity.xz) * 1.2;
        if ((before < 0.0) != (sin(bob) < 0.0)) playNote(12.0, 0.0, 1.0);

        fireCooldown = max(fireCooldown - dt, -0.05);
        notice -= dt;
        float u = upgrades[int(weapon)];
        bool alt = (k & 4096) > 0 && u > 0.0, wave = alt && weapon == 3.0;
        pulse = max(pulse - dt * 2.0, 0.0);
        whirl = clamp(whirl + dt * ((k & 4128) > 0 ? 3.0 : -1.5), 0.0, 1.0);
        spin += whirl * dt * 40.0;
        swap = clamp(swap + dt * (weapon != shown ? 8.0 : -8.0), 0.0, 1.0);
        if (swap == 1.0) shown = weapon;
        if (((k & 32) > 0 || alt) && fireCooldown <= 0.0 && weapon == shown && (weapon != 1.0 || whirl > 0.4 || u > 1.0)) {
            float shots = alt && weapon == 0.0 ? 2.0 : 1.0, fan = alt && weapon == 2.0 ? min(ammo.z, 3.0) : float(!wave);
            ammo[int(weapon)] -= wave ? min(ammo.w, 10.0) : fan;
            int w = int(weapon) * 7;
            fireCooldown += weaponStats[w] * (1.0 - frenzy * 0.12) * (weapon == 1.0 ? (u > 1.0 ? 0.67 : 2.0 - whirl) / (alt ? 2.0 : 1.0) : weapon == 3.0 ? (wave ? 8.0 : 1.0) * (u > 1.0 ? 0.5 : 1.0) : shots * 0.8 + 0.2);
            firing = 1.0;
            flash = weapon == 1.0 ? 0.5 + rnd() * 0.3 : weapon > 2.0 ? 0.3 : 1.0;
            if (wave) {
                pulse = 1.0;
                shake += 1.0;
                playNote(3.0, -12.0, 1.0);
                burst(player, 8.0, 10.0, 60.0, 2.0);
            }
            kick += weaponStats[w + 5] * shots;
            velocity -= aim * weaponStats[w + 5] * 20.0 * shots;
            punch += weaponStats[w + 5] * 0.4 * shots;
            shake += weaponStats[w + 5] * shots;
            playNote(weaponStats[w + 6], rnd() - 0.5 - shots * 2.0 + 2.0, shots * 0.4 + 0.6);
            for (float r = 0.0; r < fan && weapon > 1.0; r++) emit(weapon > 2.0 ? 0.3 : 1.0, eye + aim * 2.0, vec3(aim.xz * rot((r - fan * 0.5 + 0.5) * 0.17), aim.y).xzy * 30.0, 4.0);
            bool crit = false;
            for (float n = 0.0; n < weaponStats[w + 1] * (weapon == 0.0 && u > 1.0 ? 2.0 : 1.0) * shots; n++) {
                vec3 dir = normalize(aim + spread(weaponStats[w + 2] * (2.0 - frenzy * 0.3) * (shots * 0.5 + 0.5) * (weapon == 1.0 && alt ? 2.0 : weapon == 0.0 && u > 1.0 ? 0.6 : 1.0)));
                float far = traceScene(eye, dir, 200.0), best = far, hit = 0.0;
                int target = -1, struck = 0;
                for (int i = 0; i < 16 + dynamicZero; i++) {
                    if (monster[i].x < 0.0 || monster[i].w > 0.0) continue;
                    vec3 a = (entity[i].xyz - monsterHalf(i) - eye) / dir, b = (entity[i].xyz + monsterHalf(i) - eye) / dir, lo = min(a, b), hi = max(a, b);
                    float t = max(max(lo.x, lo.y), lo.z), exit = min(min(hi.x, hi.y), hi.z);
                    t = t < exit && exit > 0.0 ? max(t, 0.0) : 1e9;
                    if (t < far) {
                        float d = 1.0;
                        for (int k = 0; k < 24 + dynamicZero && t < exit && d > 0.02; k++) t += d = monsterAt(eye + dir * t, i);
                        if (d > 0.02 || t > far) continue;
                        if (t < best) {
                            best = t;
                            target = i;
                            hit = weaponStats[w + 3] * (part == 1 ? 2.5 : 1.0);
                            struck = part;
                        }
                    }
                }
                tracerEnd = eye + dir * best;
                if (target >= 0) {
                    hurtMonster(target, hit * (weapon == 0.0 ? min(1.0, (u > 1.0 ? 16.0 : 8.0) / abs(best)) : 1.0), dir * weaponStats[w + 4], tracerEnd);
                    crit = crit || struck == 1;
                }
                else if (n == 0.0)
                    emit(4, eye + dir * (far - 0.05), spread(5.0), 0.3);
            }
            if (crit && clanked < 1.0) playNote(5.0, 7.0, 1.0);
            tracer = float(weapon == 1.0) * 0.3;
        }
    }

    int head = 0, tail = 0, here = cellOf(player);
    if (bfsCell != here) {
        for (int c = 0; c < 6400 + dynamicZero; c++)
            if (field[c] < 1e8) field[c] = 999.0;
        for (int ring = 1; ring < 3 + dynamicZero && tail == 0; ring++)
            for (int d = 0; d < 25 + dynamicZero; d++) {
                int c = here + (d / 5 - 2) * 80 + d % 5 - 2;
                if (field[c] == 999.0 && (ring > 1 || d / 5 % 4 * (d % 5 % 4) > 0)) {
                    field[c] = 0.0;
                    queue[tail++] = c;
                }
            }
        bfsCell = here;
    }
    while (head < tail) {
        int c = queue[head++];
        float next = field[c] + 1.0;
        for (int d = 0; d < 4 + dynamicZero; d++) {
            int n = c + int[](1, -1, 80, -80)[d];
            if (field[n] == 999.0) {
                field[n] = next;
                queue[tail++] = n;
            }
        }
    }
    float chase = 0.0;
    for (int r = 0; r < 16 + dynamicZero; r++) threat[r] = max(threat[r] - dt, 0.0);
    for (int i = 0; i < 16 + dynamicZero; i++) {
        float type = monster[i].x, rage = type > 3.0 ? bossRage() : 0.0;
        if (type < 0.0) continue;
        monster[i].z *= decay;
        motion[i].w -= dt;
        vec3 p = entity[i].xyz, v = motion[i].xyz;
        if (monster[i].w > 0.0) {
            if (monster[i].w == 0.01) killMonster(i);
            v *= decay;
            move(p, v, monsterHalf(i), dt, false);
            entity[i].xyz = p;
            motion[i].xyz = v;
            if ((monster[i].w += dt) > 1.0) monster[i].x = -1.0;
            continue;
        }
        vec3 to = player - p, look = p + vec3(0, stat(i, 1) * 0.8, 0), dir = normalize(eye - look), want = to;
        float dist = length(to), reach = length(to * vec3(1, 0.3, 1));
        bool see = traceScene(look, dir, dist) >= dist - 0.5;
        if (charge[i].y > 0.0) {
            if (length(to.xz) > 3.0 + brain[i].w * 4.0 && (brain[i].w == 0.0 || monster[i].y < 12.0) && monster[i].z < 0.5 && exitOpen == 0.0) {
                monster[i].y += dt * 0.6;
                if (dist < 12.0 && rnd() < dt * 0.4) growl(i, 0.5);
                continue;
            }
            charge[i].y = 0.0;
            brain[i].w = 1.0;
            growl(i, 1.6);
        }
        if (see && dist < 10.0 + fuses * (twist() == 4.0 ? 0.0 : 6.0) || dist < (firing == 1.0 ? 30.0 : 6.0) || monster[i].z >= 0.5) {
            if (brain[i].w == 0.0) growl(i, 1.0);
            brain[i].w = 1.0;
        }
        monster[i].y += dt * (brain[i].w > 0.0 ? stat(i, 3) * 1.3 : 0.6);
        if (brain[i].w == 0.0) {
            if (dist < 20.0 && rnd() < dt * 0.04) growl(i, 0.6);
            continue;
        }
        if (rnd() < dt * (type == 1.0 ? 0.45 : 0.3)) growl(i, 1.0);
        threat[roomOf(p)] = 1.0;
        if (type > 3.0 && left < 15.0 && rnd() < dt * 0.1 * (fuses + 1.0)) {
            spawn(vec3(p.x, 0, p.z) + spread(5.0) * vec3(1, 0, 1), rage > 0.5 ? 1.0 : 0.0, false);
        }
        int c = cellOf(p);
        float f = min(field[c], 998.0);
        chase = max(chase, 3.0 / max(dist, field[c] > 1e8 ? 0.0 : f));
        vec2 grad = vec2(min(field[c - 1], f + 1.0) - min(field[c + 1], f + 1.0), min(field[c - 80], f + 1.0) - min(field[c + 80], f + 1.0));
        if (f > 2.0 && !(see && dist < 4.0) && type < 4.0 && grad != vec2(0)) want = floor(p) - p + sign(grad).xxy + 0.5;
        if (see && dist > 4.0 && type < 3.0) {
            float weave = sin(time * 2.7 + i * 2.3) * (dot(aim, dir) < -0.993 ? 0.9 : 0.45);
            want.xz *= rot(type == 2.0 ? (i % 2 == 0 ? 1.0 : -1.0) * (dist < 9.0 ? 2.3 : 1.2) : weave);
        }
        want = want / (length(want.xz) + 1e-4) * stat(i, 3) * (0.95 + min(level, 8.0) * 0.05 + float(alarm > 0.0) * 0.4 - float(armored(i)) * 0.35) * (reach > stat(i, 7) * 0.6 && motion[i].w < 0.0 ? 1.0 : 0.0);
        v.xz += (want.xz - v.xz) * min(dt * (brain[i].z > 0.0 ? 1.0 : 6.0), 1.0);
        if (charge[i].w > 0.0) {
            v.xz = motion[i].w > 0.0 ? vec2(0) : charge[i].xz;
            monster[i].y += dt * 10.0;
            if (motion[i].w < 0.0 && reach < stat(i, 0) + 1.2 && dashCooldown < 0.75) {
                velocity += charge[i].xyz + vec3(0, 6, 0);
                hurtPlayer(stat(i, 4));
                charge[i].w = 0.0;
            }
            charge[i].w -= dt;
        }
        v.y -= 22.0 * dt;
        for (int j = 0; j < 16 + dynamicZero; j++) {
            vec3 gap = (p - entity[j].xyz) * vec3(1, 0, 1);
            if (j != i && monster[j].x >= 0.0 && dot(gap, gap) < 1.5) v += gap * dt * 15.0;
        }
        if (dashCooldown > 0.7 && reach < stat(i, 0) + 1.2 && type < 4.0 && motion[i].w < 0.0) {
            motion[i].w = 0.8;
            brain[i].z = 0.0;
            v += velocity * 1.5 / stat(i, 2) + vec3(0, 5, 0);
            monster[i].z = 1.0;
            shake += 0.5;
            playNote(3.0, 7.0, 1.0);
        }
        bool ground = move(p, v, monsterHalf(i), dt, true);
        if (charge[i].w > 0.0 && motion[i].w < 0.0 && dot(v.xz, v.xz) < 60.0) {
            charge[i].w = 0.0;
            motion[i].w = 2.0;
            shake += 4.0 / (4.0 + dist);
            playAt(3.0, -5.0, 1.0, p);
        }
        if (ground && dot(v.xz, v.xz) < 0.5 && dot(want.xz, want.xz) > 1.0 && rnd() < dt * 5.0) v.y = 7.0;
        entity[i].xyz = p;
        motion[i].xyz = v;

        if (brain[i].z > 0.0) {
            monster[i].y += dt * 20.0;
            if (brain[i].z < 0.2 && see && reach < stat(i, 7) + 0.5) {
                if (dashCooldown < 0.75) velocity += to / dist * 9.0;
                hurtPlayer(stat(i, 4));
#ifdef BOT
                audio[8147] += float(motion[i].w > 0.0);
#endif
                brain[i].z = 0.0;
            }
            brain[i].z -= dt;
            continue;
        }
        if ((brain[i].y -= dt) > 0.0 || charge[i].w > 0.0 || motion[i].w > 0.0 || !see) continue;
        if (type == 1.0 && reach < stat(i, 7)) {
            hurtPlayer(0.2);
            hurtMonster(i, 1e3, vec3(0), look);
        }
        else if ((type == 3.0 || rage > 0.33 && rnd() < 0.5) && dist > 5.0 && dist < 18.0 + rage * 10.0) {
            charge[i] = vec4(normalize(to * vec3(1, 0, 1) + vec3(1e-4, 0, 0)) * 15.0, dist / 15.0 + 0.9);
            motion[i].w = 0.4;
            brain[i].y = 3.0;
            growl(i, 0.7);
        } else if (reach < stat(i, 7) || type == 0.0 && dist < 7.0) {
            brain[i].yz = vec2(hunter(i) || type > 3.0 ? 2.5 : 0.7, dist > 3.0 ? 0.6 : 0.45);
#ifdef BOT
            if (i == 12) {
                if (audio[8145] > 0.0) audio[8146] = min(audio[8146] > 0.0 ? audio[8146] : 99.0, time - audio[8145]);
                audio[8145] = time;
            }
#endif
            motion[i].xyz = vec3(0, 4, 0) + (dist > 3.0 ? to * 1.9 : motion[i].xyz + to / dist * 3.0);
            growl(i, 1.8);
        } else if (stat(i, 5) > 0.0 && dist < 40.0) {
            brain[i].y = type > 3.0 ? 1.6 : 1.5 + rnd();
            playAt(11.0, type > 3.0 ? -7.0 : 0.0, 1.0, p);
            for (int n = 0; n < (type > 3.0 ? 5 + 7 * int(rage > 0.66) : 2) + dynamicZero; n++) emit(2, look, normalize(n > 4 ? vec3(sin(n * 0.9 + time), dir.y, cos(n * 0.9 + time)) : dir + spread(n * 0.15 + 0.1)) * 18.0, 4.0);
        }
    }

    if (alarm > 0.0 && (alarm -= dt) <= 0.0 && dead == 0.0) {
        health = min(1.0, health + 0.15);
        chord(110.4 + barRoot(int(musicStep)), 3);
    }
    for (int e = 16; e < 112 + dynamicZero; e++) {
        float what = entity[e].w;
        if (what == 0.0) continue;
        bool expired = (motion[e].w -= dt) < 0.0;
        if (expired && what != 1.0) {
            entity[e].w = 0.0;
            continue;
        }
        vec3 p = entity[e].xyz += motion[e].xyz * dt;
        if (e >= 104) entity[e].w = (what > 15.0 ? 21.0 : what > 9.0 ? 11.0 : 7.0) - motion[e].w / 0.6;
        else if (what < 3.0) {
            bool hit = expired || blocked(p, vec3(0.1));
            for (int m = 0; m < 16 + dynamicZero; m++) hit = hit || what < 2.0 && monster[m].x >= 0.0 && monster[m].w == 0.0 && inside(p, entity[m].xyz, monsterHalf(m) + 0.3);
            if (what == 2.0 && inside(p, player, vec3(0.5, 1, 0.5))) {
                hurtPlayer(0.1);
                hit = true;
            }
            if (hit) {
                entity[e].w = 0.0;
                if (what < 2.0) {
                    vec3 at = p - motion[e].xyz * dt;
                    emit(what < 1.0 ? 7.0 : 10.0, at, vec3(0), 0.6);
                    playAt(3.0, 12.0 - what * 12.0, what, at);
                    shake += 0.6 * what;
                    float blast = what == 1.0 && upgrades.z > 1.0 ? 10.0 : 5.0 * what, scale = what * what;
                    burst(at, blast, 40.0 * scale, 25.0 * scale, what - 1.0);
                    vec3 to = player - at;
                    float d = length(to) + 1e-4;
                    if (what == 1.0) {
                        if (d < 4.0) {
                            velocity += to / d * (14.0 - d * 2.0);
                            hurtPlayer(min(0.3 - d * 0.07, 0.1));
                        }
                        for (int k = 0; k < 6 + dynamicZero; k++) emit(4, at, spread(14.0), 0.3);
                    }
                }
                else emit(20, p, vec3(0), 0.6);
            }
        } else {
            if (what == 5.0 && length(p - player) < 1.5) {
                health = min(1.0, health + 0.006);
                entity[e].w = 0.0;
                playNote(12.0, 0.0, 1.0);
            }
            if (motion[e].xyz != vec3(0)) {
                motion[e].y -= 18.0 * dt;
                if (p.y < 0.04 || blocked(p, vec3(0.05))) {
                    entity[e].y = max(p.y, 0.04);
                    motion[e].xyz = vec3(0);
                }
            }
        }
    }

    hum = 0.0;
    for (int i = 0; i < 16 + dynamicZero; i++) {
        vec4 q = pickup[i];
        if (q.w == 1.0) hum = max(hum, 300.0 / (300.0 + dot(q.xyz - player, q.xyz - player)));
        if (q.w > 0.0 && dead == 0.0 && (q.w != 7.0 || health < 1.0) && length((q.xyz - player) * vec3(1, 0.5, 1)) < 1.4) {
            pickup[i].w = 0.0;
            if (q.w == 1.0) {
                fuses++;
                if (alarm > 0.0) health = min(1.0, health + 0.15);
                alarm = 10.0;
                alarmRoom = float(roomOf(player));
                shake += 1.0;
                playNote(3.0, -7.0, 1.0);
                for (int m = 0; m < 16 + dynamicZero; m++)
                    if (field[cellOf(entity[m].xyz)] < fuses * 40.0) monster[m].z = 1.0;
                playNote(15.0, 98.4 + fuses, 1.2);
            } else {
                if (q.w == 3.0) weapon = arsenal = min(arsenal + 1.0, 3.0);
                if (q.w == 4.0) {
                    int g = upgradeTarget();
                    upgrades[g] = min(upgrades[g] + 1.0, 2.0);
                    weapon = boosted = float(g);
                    notice = 3.0;
                }
                if (q.w == 7.0) health = min(1.0, health + 0.3);
                ammo = min(ammo + vec4(0, 40, 4, 30) * (q.w == 3.0 ? 2.0 : 1.0), vec4(1e9, 150, 16, 90) * (1.0 + upgrades * 0.5));
                if (q.w > 2.0) {
                    playNote(12.0, -5.0, 3.0);
                    playNote(5.0, -24.0, 2.0);
                    chord(110.4 + barRoot(int(musicStep)), 3);
                } else playNote(5.0, 12.0, 1.0);
            }
        }
    }
    spawnClock = chase < 0.1 || exitOpen > 0.0 || spawnClock < 0.0 ? spawnClock + dt : 0.0;
    if ((spawnClock > 9.6 - min(level, 6.0) * 0.6 + float(abs(fuses - 1.5) > 1.0) * 4.0 || alarm == 10.0) && dead == 0.0) {
        spawnClock = 0.0;
        bool ambush = exitOpen == 0.0 && (twist() == 2.0 || fuses > 0.0 && rnd() < 0.4) && alarm < 10.0;
        float before = left, cap = min(8.0 + level, 14.0) - float(ambush) * 3.0;
        for (int t = 0; t < 16 + dynamicZero; t++) {
            vec3 at = clamp(player * vec3(1, 0, 1) + vec3(rnd() - 0.5, 0, rnd() - 0.5) * 60.0, 2.0, 78.0) * vec3(1, 0, 1);
            vec3 sight = at + vec3(0, ambush ? 7.0 : 1.0, 0) - eye;
            float path = field[cellOf(at)];
            if (left < cap && path > 14.0 && path < 36.0 && roomOf(at) != roomOf(player) && ((t > 3 || alarm == 10.0) && !ambush || dot(at - player, aim) > 0.0 == ambush) && traceScene(eye, normalize(sight), length(sight)) < length(sight) - 1.0) {
                for (int n = 0; n <= int(min(fuses, 2.0)) + int(fuses > 1.0 && exitOpen == 0.0) + int(twist() == 4.0) + dynamicZero; n++) {
                    vec3 q = at + spread(3.0) * vec3(1, 0, 1);
                    if (left < cap && roomOf(q) != roomOf(player)) spawn(q, n > 0 ? float(guardType() == 1.0 && !ambush) : ambush ? min(pickType(), 1.0) : rnd() < 0.5 ? guardType() : pickType(), ambush);
                }
                if (left > before && !ambush) {
                    spawnClock = -1.2;
                    if (rnd() < 0.3 + fuses * 0.25) {
                        playAt(3.0, -4.0 - rnd() * 4.0, 0.3, at);
                        playAt(7.8, -6.0 - rnd() * 3.0, 1.0, at);
                    }
                }
                break;
            }
        }
    }

    intensity += (min(1.0, chase + hurt * 0.4 + firing * 0.2) - intensity) * dt * 0.6;
    if (exitOpen > 0.0) exitOpen = min(1.0, exitOpen + dt * 0.5);
    if (fuses > 2.0 && exitPos.y == 0.0 && exitOpen == 0.0 && (monster[12].x < 0.0 || !hunter(12))) {
        exitOpen = 0.01;
        int r = roomOf(player);
        for (int n = 0; n < 3 + dynamicZero; n++) spawn(roomCenter((r % 4 < 2 ? 3 : 0) + (r / 4 < 2 ? 12 : 0)) + vec3((rnd() - 0.5) * 12.0, 0, 0), 1.0, false);
        for (int i = 0; i < 16 + dynamicZero; i++) brain[i].w = 1.0;
        float key = barRoot(int(musicStep));
        playNote(15.0, 98.4 + key, 1.0);
        playNote(15.0, 105.4 + key, 1.0);
        playNote(19.0, 74.4 + key, 1.0);
    }
    if (dead == 0.0 && exitOpen == 1.0 && inside(player, exitPos, vec3(2, 9, 2))) {
        ammoStart = ammo;
        arsenalStart = arsenal;
        upgradesStart = upgrades;
        if (mod(level, 6.0) == 0.0)
        {
            ending = 0.01;
            intensity = 0.0;
            chord(98.4, 4);
        }
        else {
            level++;
            fade = -1.0;
        }
    }
    eye = player + vec3(0, 0.65 + sin(bob * 2.0) * 0.05, 0) + spread(shake * 0.25);
    float tilt = clamp(pitch + punch + (rnd() - 0.5) * shake * 0.08, -1.55, 1.55);
    aim = vec3(0, sin(tilt), cos(tilt));
    aim.xz *= rot(yaw);
    for (int i = 0; i < 16 + dynamicZero; i++) entity[i].w = brain[i].w > 0.0 ? atan(eye.x - entity[i].x, eye.z - entity[i].z) : i * 2.4;
    float reach = traceScene(eye, aim + 1e-6, 1e3);
    beamHit = vec4(eye + aim * reach + normal * 0.05, min(0.3 + reach, 2.0) / (1.0 + reach * reach * 0.025));
    beamNormal.xyz = normal;
    decals = 0;
    vec3 rt = normalize(vec3(aim.z, 0, -aim.x)), up = cross(aim, rt);
    for (int e = 40 + dynamicZero; e < 104; e++) {
        vec3 v = entity[e].xyz - eye;
        float z = dot(v, aim) + 0.4;
        if (entity[e].w == 4.0 || entity[e].w > 0.0 && abs(dot(v, rt)) * 1.5 - 0.6 < z * screen.y / screen.z && abs(dot(v, up)) * 1.5 - 0.6 < z) decalList[decals++] = e;
    }
    }
    sequence(int(screen.x));
}
#else
out vec4 fragColor;

vec3 ray;
vec2 uv;
const int glyphs[36] = int[](0, 31599, 29850, 29671, 31143, 18925, 31183, 31695, 9511, 31727, 31215, 23530, 25166, 15211, 29391, 4815, 27470, 23533, 29847, 23277, 29257, 23549, 23403, 11114, 4843, 23275, 14478, 9367, 31597, 24557, 23213, 9389, 448, 4772, 1040, 8338);
const int messages[95] = int[](321987852, 476636736, 536978325, 3253120, 443361166, 218219999, 536925074, 206127872, 19, 0, 425555215, 0, 0, 0, 0, 392213405, 274841622, 221827801, 0, 0, 234939483, 285324446, 392169099, 103325, 0, 234997215, 241218330, 13, 0, 0, 3757211, 664414564, 0, 0, 0, 292336525, 665059354, 0, 0, 0, 321987852, 268531392, 238604311, 103320, 0, 439985935, 1186240, 0, 0, 0, 162408, 0, 0, 0, 0, 457507993, 206127872, 341426195, 221852439, 0, 251658240, 453039506, 1049489, 439985935, 0, 422396608, 306972309, 292291860, 273235982, 108241, 486539264, 4507339, 201385051, 373900430, 16, 392691712, 306557845, 474219542, 520201942, 1815, 452984832, 392168337, 302093213, 188272666, 13, 0, 439985935, 321709888, 457704846, 0, 441533587, 665223168, 0, 0, 0);

float print(vec2 at, float size, int msg, float value) {
    vec2 q = (uv - at) / size;
    int k = int(floor(q.x / 4.0)), x = int(floor(q.x)) - k * 4, y = 4 - int(floor(q.y));
    if (k < 0 || k > 24 || x > 2 || y < 0 || y > 4) return 0.0;
    int code = messages[msg * 5 + k / 5] >> k % 5 * 6 & 63;
    if (code > 35) {
        float d = float[](600, 60, 10, 1, 100, 10)[code - 36];
        code = code > 39 && value < d ? 0 : int(value / d) % int[](10, 10, 6, 10, 10, 10)[code - 36] + 1;
    }
    return float(glyphs[code] >> y * 3 + x & 1);
}

vec2 relief(vec2 st, vec2 size) {
    vec2 g = st / size;
    g.x += floor(g.y) * step(size.x, 0.95) * 0.5;
    vec2 e = (0.5 - abs(fract(g) - 0.5)) * size;
    return vec2(smoothstep(0.0, 0.035, min(e.x, e.y)), hash(floor(g)));
}

vec2 hull(vec3 ro, vec3 rd, int i) {
    vec3 oc = ro - monsterFrame(i).xyz;
    float r = stat(i, 6), b = dot(oc, rd), h = b * b - dot(oc, oc) + r * r;
    return monster[i].x < 0.0 || h < 0.0 ? vec2(0) : sqrt(h) * vec2(-1, 1) - b;
}

float shadow(vec3 p, vec3 n, vec3 rd, float far) {
    if (traceScene(p + n * 0.01, rd, far) + 0.01 < far) return 0.0;
    vec3 ro = p + n * 0.03;
    float lit = 1.0;
    int steps = 0;
    for (int i = 0; i < 16 + dynamicZero && steps < 16; i++) {
        if (monster[i].x < 0.0) continue;
        vec2 r = hull(ro, rd, i);
        for (float s = max(r.x, 0.05); s < min(r.y, far) && steps++ < 16;) {
            float d = monsterAt(ro + rd * s, i);
            lit = min(lit, 24.0 * d / s);
            if (lit < 0.05) return 0.0;
            s += max(d, 0.1);
        }
    }
    return clamp(lit, 0.0, 1.0);
}

vec3 lampAt(vec2 cell) {
    int cellIndex = int(cell.y * 4.0 + cell.x);
    if (alarm > 0.0 && float(cellIndex) == alarmRoom) return vec3(1.3, 0.05, 0.02);
    float h = hash(cell + level * 7.0), dark = max(cell.x + cell.y > 0.0 ? (twist() == 4.0 ? 1.0 : 0.6) - fuses * 0.2 + float(alarm > 0.0 && twist() == 1.0) : 0.0, step(hash(vec2(floor(time * 7.0), 3)), max(max(monster[15].w == 0.0 ? bossRage() * 1.5 - 0.5 : 0.0, -spawnClock * 0.6), threat[cellIndex] * 0.3 * float(cell != floor(clamp(eye.xz, 0.1, 79.9) / 20.0)))));
    return (h < dark ? vec3(0) : vec3[](vec3(0.55, 0.8, 0.7), vec3(0.7, 0.45, 0.15), vec3(0.7, 0.06, 0.02), vec3(0.4, 0.5, 0.2), vec3(0.3, 0.55, 0.6))[kinds[cellIndex]] * (0.7 + 0.6 * fract(h * 13.0))) * (1.0 - threat[cellIndex] * 0.4) * (h > 0.7 ? step(0.0, sin(time * (4.0 + h * 9.0)) + sin(time * 17.0) + 0.6) : 1.0) * (1.0 + 0.3 * cos(level * 2.4 + vec3(0, 2, 4)));
}

vec3 glow(float t, vec3 at, vec3 color, float size) {
    vec3 v = at - eye;
    v -= ray * clamp(dot(v, ray), 0.0, t);
    return color * size / (dot(v, v) + size * 0.3) * smoothstep(0.0, 1.0, dot(at - eye, ray));
}

void main() {
    dynamicZero = int(beamNormal.w);
    uv = (2.0 * gl_FragCoord.xy - screen.yz) / screen.z;
    vec3 rt = normalize(vec3(aim.z, 0, -aim.x)), up = cross(aim, rt);
    ray = normalize(aim * 1.5 + rt * uv.x + up * uv.y);

    float t = traceScene(eye, ray, 1e3);
    vec3 n = normal;
    int mat = material, hit = -1, steps = 0, solid = hitBox;
    for (int i = 0; i < 16 + dynamicZero; i++) {
        if (monster[i].x < 0.0) continue;
        vec2 r = hull(eye, ray, i);
        for (float s = max(r.x, 0.0); s < min(r.y, t) && steps++ < 96;) {
            float d = monsterAt(eye + ray * s, i);
            if (d < 0.002 * s) {
                t = s;
                hit = i;
                break;
            }
            s += d * 0.8;
        }
    }
    for (int i = 0; i < 16 + dynamicZero; i++) {
        vec4 q = pickup[i];
        vec3 k = abs(1.0 / ray) * (q.w == 2.0 ? vec3(0.35, 0.25, 0.25) : vec3(0.12, 0.25, 0.12)), c = (q.xyz + vec3(0, q.w == 2.0 ? 0.25 : 0.9 + sin(time * 2.0 + i) * 0.1, 0) - eye) / ray, t1 = c - k, t2 = c + k;
        float near = max(max(t1.x, t1.y), t1.z);
        if (q.w > 0.0 && near < min(min(t2.x, t2.y), t2.z) && near > 0.0 && near < t) {
            t = near;
            n = -sign(ray) * step(t1.yzx, t1) * step(t1.zxy, t1);
            mat = 9 + int(q.w);
            hit = solid = -1;
        }
    }
    vec3 p = eye + ray * t, albedo, glint, emission = vec3(0), sparks = vec3(0);
    float stain = 0.0, drop = -1.0, edge = ripple(p * 9.0) * 0.08;
    for (int j = 0; j < decals; j++) {
        vec4 q = entity[decalList[j]];
        vec3 oc = eye - q.xyz;
        float r = q.w > 4.0 ? 0.06 : 0.035, b = dot(oc, ray), k = b * b - dot(oc, oc) + r * r;
        if (q.w == 4.0) sparks += glow(t, q.xyz, vec3(1, 0.7, 0.3), 0.0004);
        else if (q.w > 0.0) {
            stain += smoothstep(0.3, 0.1, length(q.xyz - p) + edge);
            if (k > 0.0 && b < 0.0 && -b - sqrt(k) < t) {
                drop = 0.5 + 0.5 * normalize(oc + ray * (-b - sqrt(k))).y;
                sparks = vec3(0);
            }
        }
    }
    vec2 cell = floor(clamp(p.xz, 0.1, 79.9) / 20.0);
    int cellIndex = int(cell.y * 4.0 + cell.x);
    float grime = 0.0, wet = 0.0;
    float shine = 0.15;
    if (hit >= 0) {
        vec2 e = vec2(0.005, -0.005);
        n = normalize(e.xyy * monsterAt(p + e.xyy, hit) + e.yyx * monsterAt(p + e.yyx, hit) + e.yxy * monsterAt(p + e.yxy, hit) + e.xxx * monsterAt(p + e.xxx, hit));
        n = normalize(n + vec3(ripple(p * 23.0), ripple(p.zxy * 23.0), 0) * 0.3);
        vec4 info = monster[hit];
        float vein = smoothstep(0.035, 0.0, abs(ripple(p * (hunter(hit) ? 9.0 : 4.0) + ripple(p * 9.0) * 0.4))), cut = 0.92 - (1.0 - brain[hit].x / stat(hit, 2)) * 0.6, gash = smoothstep(cut, cut + 0.03, ripple(p * vec3(9, 2.5, 9) + float(hit)));
        albedo = (hunter(hit) ? vec3(0.05, 0.045, 0.04) : vec3[](vec3(0.12, 0.07, 0.06), vec3(0.17, 0.16, 0.15), vec3(0.06, 0.03, 0.07), vec3(0.07, 0.045, 0.035), vec3(0.16, 0.04, 0.04))[int(info.x)]) * (0.7 + 0.3 * ripple(p * 11.0)) * (1.0 - 0.7 * vein);
        glint = armored(hit) ? vec3(1) : vec3[](vec3(1, 0.12, 0.05), vec3(1, 0.45, 0.05), vec3(0.7, 1, 0.2), vec3(1, 0.12, 0.05), vec3(0.7, 1, 0.2))[int(info.x)];
        emission = float(part == 1) * 5.0 * pow(max(-dot(n, ray), 0.0), 60.0) * glint + vein * max(info.z * info.z, float(hunter(hit)) * (fuses > 2.0 ? 0.6 : 0.25)) * 0.25 * max(-dot(n, ray), 0.0) * vec3(1, 0.12, 0.05);
        shine = part == 1 ? 0.0 : max(0.9 * smoothstep(0.3, 0.7, ripple(p * 17.0)), gash);
        albedo = part > 1 ? vec3(0.3, 0.25, 0.15) : mix(albedo, vec3(0.05, 0.0, 0.0), gash) * float(part < 1);
        albedo *= 0.25 + 0.75 * clamp(monsterAt(p + n * 0.15, hit) / 0.15, 0.0, 1.0);
        mat = 9;
    } else {
        int kind = kinds[cellIndex];
        vec2 st = abs(n.y) > 0.5 ? p.xz : abs(n.x) > 0.5 ? p.zy : p.xy, size = (mat == 0 || mat == 3) && abs(n.y) > 0.5 ? vec2(0.6) : mat == 0 ? (p.y < 1.3 ? vec2(0.3) : kind == 0 ? vec2(0.3, 0.15) : kind > 2 ? vec2(2.5, 1.25) : vec2(0.9, 0.42)) : mat == 7 ? vec2(kind == 0 ? 0.3 : 1.0) : mat == 8 ? vec2(2.5) : mat == 3 ? vec2(0.6, 0.3) : vec2(0), bump = vec2(1, 0.5);
        if (size.x > 0.0) {
            bump = relief(st, size);
            n = normalize(n + ((abs(n.x) > 0.5 ? vec3(0, 0, 1) : vec3(1, 0, 0)) * (bump.x - relief(st + vec2(0.01, 0), size).x) + (abs(n.y) > 0.5 ? vec3(0, 0, 1) : vec3(0, 1, 0)) * (bump.x - relief(st + vec2(0, 0.01), size).x)) * 1.5);
        }
        if (solid >= 0 && boxHalf[solid].w == 0.0) {
            vec3 q = p - boxes[solid].xyz;
            n = normalize(n + sign(q) * smoothstep(0.06, 0.0, boxHalf[solid].xyz - abs(q)) * (1.0 - abs(normal)));
        }
        grime = ripple(p * vec3(3, 0.35, 3)) * 0.5 + ripple(p * 4.1) * 0.25;
        albedo = vec3[](vec3(0.16, 0.14, 0.12), vec3(0.19, 0.14, 0.09), vec3(0.18, 0.12, 0.1), vec3(0.12, 0.1, 0.08), vec3(0.13, 0.14, 0.11))[kind] * (0.75 + grime * 0.4) * (0.55 + 0.45 * bump.x) * (0.45 + 0.9 * bump.y * bump.y);
        if (mat == 1 || mat == 15) {
            float holes = mat > 1 && abs(n.y) > 0.5 ? step(0.3, fract(st.x * 6.0)) * step(0.3, fract(st.y * 6.0)) : 1.0;
            albedo = vec3(0.07, 0.075, 0.08) * (0.7 + 0.3 * step(0.08, fract(p.y * 1.5))) * (0.3 + 0.7 * holes);
            if (p.y < 1.0 && boxHalf[solid].w == 2.0) albedo = vec3(0.02) + vec3(0.3, 0.24, 0.03) * step(0.5, fract((p.x + p.z) * 2.5));
            shine = smoothstep(-0.4, 0.6, grime) * 0.4 * holes;
        }
        if (mat == 2 || mat == 6) albedo = vec3(0.3, 0.16, 0.08) * (mat > 2 ? 0.45 : 1.0) * (0.6 + grime * 0.5) * (0.7 + 0.3 * step(0.1, min(fract(st.x + 0.05), fract(st.y + 0.05)))) * (0.8 + 0.2 * ripple(vec3(st * vec2(1, 30), 0)));
        if (mat == 3) albedo *= 1.4;
        if (mat == 0 && p.y < 1.3) {
            albedo *= 1.5;
            shine = 0.5;
        }
        if (mat < 2 && abs(n.y) < 0.5) {
            if (mat == 0 && kind == 0 && p.y > 1.3) {
                albedo = vec3(0.3, 0.33, 0.3) * (0.4 + 0.6 * bump.x) * (0.85 + 0.3 * bump.y) * (0.7 + grime * 0.5);
                shine = 0.6 * bump.x;
            }
            float streak = smoothstep(0.3, 0.7, ripple(vec3(st.x * 6.0, p.y * 0.15, level))) * smoothstep(0.5, 6.0, p.y);
            albedo *= 1.0 - streak * 0.6;
            shine += streak * 0.4;
        }
        if (kind == 2) albedo *= 1.0 - 0.7 * smoothstep(2.0, 7.5, p.y) * (0.6 + grime);
        if (kind == 3 && mat == 0 && abs(n.y) < 0.5 && abs(p.y - 1.1) < 0.15) albedo = vec3(0.02) + vec3(0.3, 0.24, 0.03) * step(0.5, fract((st.x + p.y) * 2.5));
        if (kind == 4 && p.y < 0.45 && abs(n.y) < 0.5) albedo *= vec3(0.35, 0.45, 0.3);
        if (mat == 4 || mat == 0 && abs(n.y) < 0.5 && ripple(p * 0.4 + level) + ripple(p * 3.1) * 0.15 > 0.8 - min(level, 6.0) * 0.11) {
            albedo = mix(vec3(0.09, 0.008, 0.006) * (0.8 + grime), vec3(0.16, 0.1, 0.08), smoothstep(0.3, 0.6, ripple(p * vec3(6, 1, 6) + grime)));
            n = normalize(n + sin(p * vec3(31, 3, 37) + grime * 9.0 + time) * 0.3);
            shine = 0.6;
            if (mat == 4) albedo *= smoothstep(0.0, 0.7, boxHalf[solid].y - abs(p.y - boxes[solid].y)), shine *= albedo.r * 9.0;
        }
        if (mat == 5) emission = mix(vec3(0.5, 0, 0), vec3(0.5, 0.8, 1.5), exitOpen) * (pow(0.5 + 0.5 * sin(length(p.xz - exitPos.xz) * 4.0 - time * 4.0), 4.0) * 0.8 + 0.1) * (0.15 + 0.85 * max(n.y, 0.0));
        if (mat == 7) {
            wet = kind == 4 ? 1.0 : smoothstep(0.35, 0.42, ripple(p * 0.4 + level));
            n = normalize(mix(n, vec3(ripple(p * 5.0 + time) * 0.04, 1, ripple(p.zyx * 5.0 - time) * 0.04), wet));
            albedo *= 1.0 - wet * 0.6;
            shine = mix(smoothstep(0.2, 0.6, grime) * 0.9 * bump.x, 1.0, wet);
        }
        if (mat == 8 || mat == 14) albedo *= 0.25;
        if (mat == 10) emission = vec3(0.3, 0.6, 1.5) * (1.2 + sin(time * 6.0) * 0.4) * (0.15 + 0.85 * step(0.3, fract(p.y * 4.0 - time))) * (0.6 + 0.4 * abs(n.x));
        if (mat == 11) albedo = mix(vec3(0.05, 0.06, 0.03), vec3(0.3, 0.24, 0.03), step(abs(fract(p.y * 4.0 + 0.5) - 0.5), 0.1) * step(abs(n.y), 0.5));
        if (mat == 12 || mat == 13 || mat == 16) emission = mat > 15 ? vec3(0.3, 1.5, 0.4) : mat > 12 ? vec3(1.5, 0.1, 0.1) : vec3(1.5, 0.6, 0.1);
        float column = hash(vec2(floor(st.x * 3.0), level)), top = 2.0 + fract(column * 7.0) * 4.0, u = fract(st.x * 3.0) - 0.5;
        float blood = smoothstep(0.6, 0.65, ripple(p * 0.6) + edge) * (1.0 - smoothstep(0.0, 1.0, p.y)) + step(abs(n.y), 0.5) * float(mat == 0) * step(0.85, column) * max(smoothstep(0.25, 0.12, abs(u + sin(p.y * 6.0) * 0.04)) * smoothstep(top - 2.5 * fract(column * 13.0) - 0.3, top, p.y) * step(p.y, top), smoothstep(0.35, 0.2, length(vec2(u, (p.y - top) * 2.0))));
        blood = min(blood + stain, 1.0);
        shine = max(shine, blood);
        albedo *= 1.0 + ripple(p * 41.0) * ripple(p.zxy * 23.0) * 0.35 * smoothstep(4.0, 1.0, t);
        albedo = mix(albedo, vec3(0.04, 0, 0), blood * 0.9);
    }

    if (mat < 9) {
        float occ = 0.6;
        for (int i = roomStart[cellIndex]; i < roomStart[cellIndex + 1]; i++)
            if (boxHalf[i].w < 3.0) occ = min(occ, box(p + normal * 0.6 - boxes[i].xyz, boxHalf[i].xyz));
        albedo *= 0.25 + 1.25 * max(occ, 0.0);
    }
    vec2 room = 9.5 - abs(mod(p.xz, 20.0) - 10.0);
    room += step(room, vec2(0.0)) * 1.8;
    ivec2 seam = ivec2(floor(p.xz / 20.0 - 0.5));
    if (seam.x >= 0 && (doors[int(cell.y) * 4 + seam.x] & 4) > 0) room.x = 9.0;
    if (seam.y >= 0 && (doors[seam.y * 4 + int(cell.x)] & 8) > 0) room.y = 9.0;
    vec3 w = max(vec3(room.x, min(p.y, 8.0 - p.y), room.y), abs(n) * 9.0), tl = eye + rt * 0.3 - up * 0.25 - p;
    albedo *= (0.25 + 0.75 * smoothstep(0.0, 1.8, min(min(w.x, w.y), w.z))) * (0.6 + 0.4 * smoothstep(0.0, 1.2 + grime, p.y));
    float tn = length(tl);
    tl /= tn;
    float on = step(max(max(0.3 - health, intensity * 0.35 - 0.1), -spawnClock * 0.35), hash(vec2(floor(time * 15.0)))), axis = -dot(tl, aim), core = (smoothstep(0.9, 0.96, axis) * 0.8 + smoothstep(0.975, 1.0, axis) * 0.8) * on, cone = core + smoothstep(0.45, 0.92, axis) * 0.3 * on, lit = cone;
    if (core > 0.01) lit -= core * (1.0 - shadow(p, n, tl, tn));
    vec3 light = vec3(1, 0.88, 0.7) * (lit * min(0.3 + t, 2.0) / (1.0 + t * t * 0.015) + flash * 3.0 / (1.0 + t * t * 0.75) / (1.0 + t * t * 0.08));
    vec3 col = albedo * light * max(dot(n, tl), 0.0) + light * shine * pow(max(dot(n, normalize(tl - ray)), 0.0), mat == 9 ? 160.0 : 40.0) * lit * 0.5;
    if (mat == 9) col = col * (0.1 + 0.45 * pow(max(-dot(n, ray), 0.0), 2.0)) + albedo * light * vec3(0.6, 0.05, 0.03) * pow(max(1.0 - abs(dot(n, ray)), 0.0), 3.0) * 0.2;
    vec3 bounce = beamHit.xyz - p;
    float bounceSq = dot(bounce, bounce), fill;
    bounce *= inversesqrt(bounceSq);
    fill = on * 0.3 * beamHit.w * max(dot(n, bounce), 0.0) * max(-dot(beamNormal.xyz, bounce), 0.0) / (1.0 + bounceSq * 0.08) * (mat == 9 ? 0.4 : 1.0);
    if (fill > 0.004) fill *= shadow(p, n, bounce, sqrt(bounceSq) - 0.1);
    col += albedo * vec3(1, 0.88, 0.7) * fill;

    vec3 lamp = vec3(cell * 20.0 + 10.0, 5.6).xzy, toLamp = lamp - p, lampColor = lampAt(cell), cellLamp = lampColor;
    float dl = length(toLamp);
    toLamp /= dl;
    if (alarm > 0.0 && float(cellIndex) == alarmRoom) lampColor *= 0.25 + 3.0 * pow(0.5 + 0.5 * sin(atan(toLamp.z, toLamp.x) - time * 6.0), 8.0);
    if (hit >= 0) col += vec3(0.25, 0.012, 0.004) * (armored(hit) ? 0.1 : monster[hit].x > 0.0 ? 0.5 : 1.0) * clamp(1.0 + monsterAt(p - n * 0.12, hit) / 0.12, 0.0, 1.0) * (light * 0.12 + lampColor * 0.2 / (1.0 + dl * dl * 0.05)) + (lampColor * 0.15 / (1.0 + dl * dl * 0.05) + glint * 0.04 * smoothstep(30.0, 2.0, t)) * pow(max(1.0 - abs(dot(n, ray)), 0.0), 4.0);
    if (mat == 14) emission += (lampColor + dot(lampColor, vec3(0.25))) * 3.5 * step(0.04, fract(atan(toLamp.z, toLamp.x) * 1.2732)) * step(n.y, -0.5) + vec3(0.6, 0.02, 0) * step(lampColor.r, 0.0) * step(0.97, fract(time * 0.3 + cell.x * 0.37));
    if (lampColor.r > 0.0 && dot(n, toLamp) > 0.0 && (toLamp.y > 0.35 || toLamp.y < 0.0)) col += lampColor * (albedo * 12.0 * dot(n, toLamp) * max(smoothstep(0.35, 0.9, toLamp.y) * 3.0, -0.3 * toLamp.y)) / (1.0 + dl * dl * 0.2) * (mat == 9 ? 0.3 : shadow(p, n, normalize(lamp - p + (vec3(hash(uv + fract(time)), 0.5, hash(uv.yx + fract(time))) - 0.5) * 0.8), dl - 0.5)) * smoothstep(-0.5, 2.0, min(w.x, w.z));
    col += albedo * (mix(lampColor, vec3(dot(lampColor, vec3(0.33))), 0.15) * (1.0 + 0.6 * n.y) * smoothstep(0.0, 2.0, min(w.x, w.z)) / (1.0 + dl * dl * 0.25) + vec3(0.03, 0.035, 0.06)) * (mat == 9 ? 0.08 : 1.0);
    vec3 rl = reflect(ray, n), vl = lamp - p;
    vl -= rl * max(dot(vl, rl), 0.0);
    col += wet * lampColor * 0.03 / (dot(vl, vl) + 0.01);

    for (int i = 0; i < 8 + dynamicZero; i++) {
        vec4 b = entity[104 + i];
        vec3 l = b.xyz - p;
        if (b.w > 0.0 && b.w < 11.0) col += albedo * (b.w < 9.0 ? vec3(0.1, 0.25, 0.6) : vec3(1, 0.5, 0.15)) * pow(1.0 - fract(b.w), 2.0) * 12.0 * max(dot(n, normalize(l)), 0.0) / (1.0 + dot(l, l)) * (mat == 9 ? 0.3 : 1.0);
    }
    col += vec3(0.4, 0.9, 3) * pulse * exp(-abs(length(p.xz - eye.xz) - 8.0 + pulse * 8.0) * 3.0);
    for (int i = 0; i < 16 + dynamicZero; i++) {
        vec3 l = entity[i].xyz + vec3(0, 0.5, 0) - p;
        if (monster[i].x >= 0.0 && monster[i].w == 0.0 && brain[i].w > 0.0 && charge[i].y == 0.0 && i != hit) col += albedo * (armored(i) ? vec3(0.35, 0.4, 0.5) : vec3(1, 0.08, 0.02)) * 4.0 * max(dot(n, normalize(l)), 0.0) / (1.0 + dot(l, l) * 3.0);
    }
    for (int i = 0; i < 3 + dynamicZero; i++) {
        vec3 l = pickup[i].xyz + vec3(0, 0.9, 0) - p;
        if (pickup[i].w > 0.0) col += albedo * vec3(0.3, 0.6, 1.5) * max(dot(n, normalize(l)), 0.0) / (0.3 + dot(l, l)) * 1.5;
    }
    float fog = 0.04 + mod(level, 3.0) * 0.03 + intensity * 0.03, jitter = hash(gl_FragCoord.xy + fract(time));
    vec3 haze = vec3(0);
    vec2 home = floor(clamp(eye.xz, 0.1, 79.9) / 20.0);
    vec3 homeLamp = lampAt(home);
    for (int j = 0; j < 2 + dynamicZero; j++) {
        vec2 qc = j == 0 ? home : cell;
        vec3 lc = vec3(qc * 20.0 + 10.0, 5.6).xzy - eye, beam = (j == 0 ? homeLamp : cellLamp) * smoothstep(1.0, 4.0, length(lc.xz) + float(j) * 4.0);
        float a = dot(ray.xz, ray.xz) + 1e-5, b = dot(lc.xz, ray.xz), h = b * b - a * (dot(lc.xz, lc.xz) - 16.0);
        if (j == 1 && qc == home || beam.r == 0.0 || h < 0.0) continue;
        float s0 = max((b - sqrt(h)) / a, 0.0), ds = (min((b + sqrt(h)) / a, min(t, ray.y > 0.0 ? (5.6 - eye.y) / ray.y : t)) - s0) / 6.0;
        for (int i = 0; i < 6 + dynamicZero && ds > 0.0; i++) {
            float s = s0 + ds * (float(i) + jitter);
            vec3 ql = lc - ray * s;
            float d = length(ql);
            ql /= d;
            float spot = smoothstep(16.0, 9.0, dot(ql.xz * d, ql.xz * d)) * smoothstep(0.82, 0.98, ql.y) * (0.35 + 0.65 * smoothstep(0.03, 0.12, abs(fract(atan(ql.z, ql.x) * 1.2732 + 0.44) - 0.5))) * 1.5 / (1.0 + d * d * 0.15) * smoothstep(1.0, 6.0, s);
            if (spot > 0.003) haze += beam * spot * step(d - 0.05, traceScene(eye + ray * s, ql, d)) * exp(-fog * s) * ds;
        }
    }
    col = (col + emission) * exp(-t * fog) + haze * fog + vec3(1, 0.88, 0.7) * pow(smoothstep(0.85, 1.0, axis), 2.0) * on * fog * 0.04 * (1.0 - exp(-t * 0.25)) + (homeLamp + 0.4) * 0.004 * (1.0 - exp(-t * fog));

    if (drop >= 0.0) col = vec3(0.08, 0, 0) * (cone + 0.05) * drop;
    col += sparks;
    for (int i = 0; i < 16 + dynamicZero; i++) {
        vec4 q = pickup[i];
        if (q.w > 0.0 && q.w != 2.0) col += glow(t, q.xyz + vec3(0, 0.9, 0), q.w > 6.0 ? vec3(0.3, 1.5, 0.4) : q.w > 1.0 ? vec3(1, 0.4, 0.1) : vec3(0.3, 0.6, 1.5), 0.01);
    }
    for (int i = 0; i < 24 + dynamicZero; i++) {
        vec4 s = entity[16 + i];
        if (s.w > 0.0) col += glow(t, s.xyz, s.w > 1.0 ? vec3(0.6, 1, 0.2) : s.w < 1.0 ? vec3(0.4, 0.9, 3) : vec3(1, 0.6, 0.2), s.w < 1.0 ? 0.003 : 0.004) * exp(-fog * distance(s.xyz, eye));
    }
    for (int i = 0; i < 8 + dynamicZero; i++) {
        vec4 b = entity[104 + i];
        if (b.w == 0.0) continue;
        float age = fract(b.w), size = 0.5 + age * 2.5;
        vec3 v = b.xyz - eye;
        v -= ray * clamp(dot(v, ray), 0.0, t);
        float puff = (1.0 - age) * exp(-dot(v, v) / size) * min(distance(b.xyz, eye) * 0.5, 1.0) * smoothstep(-0.3, 0.6, dot(normalize(b.xyz - eye), ray));
        col = b.w > 15.0 ? mix(col, vec3(0.1, 0, 0), puff * 0.6) : col + (b.w < 9.0 ? vec3(0.1, 0.25, 0.6) : vec3(1, 0.45, 0.1)) * puff * (1.0 - age) * 0.5;
    }
    for (int i = 0; i < 16 + dynamicZero; i++) {
        vec4 m = monsterFrame(i), info = monster[i];
        vec2 f = vec2[](vec2(0.92, 0.4), vec2(0.7, 0.5), vec2(0.6, 0.0), vec2(1.3, 0.9), vec2(1.56, 0.0))[int(max(info.x, 0.0))];
        if (info.x >= 0.0 && info.w == 0.0) col += glow(t + 0.15, m.xyz + vec3(sin(m.w) * f.x, charge[i].y > 0.0 ? -f.y : f.y, cos(m.w) * f.x), (armored(i) ? vec3(0.35, 0.4, 0.5) : vec3(1.2, 0.12, 0)) * min(distance(m.xyz, eye) * 0.4, 1.0) * (brain[i].w * 0.7 + 0.3 + 3.0 * float(brain[i].z > 0.0 || charge[i].w > 0.0)), 0.001);
    }
    vec2 o = eye.xz - exitPos.xz, dd = ray.xz;
    float s = clamp(-dot(o, dd) / dot(dd, dd), 0.0, t);
    col += exitOpen * vec3(0.5, 0.7, 1) * 0.15 * min(dot(o, o), 1.0) / (dot(o + dd * s, o + dd * s) + 0.15);

    vec2 muzzle = vec2(0.29, -0.26 - float(shown == 2.0) * sin(clamp(fireCooldown * 3.14, 0.0, 3.14)) * 0.2 - swap * 0.35) / (0.95 - kick * 0.45) * 1.5;
    vec3 tv = tracerEnd - eye;
    vec2 end = vec2(dot(tv, rt), dot(tv, up)) / dot(tv, aim) * 1.5;
    float beam = capsule(vec3(uv, 0), vec3(muzzle, 0), vec3(end, 0), 0.0);
    if (tracer > 0.01 && dot(tv, aim) > 0.0) col += tracer * vec3(1, 0.7, 0.3) * 0.0001 / (beam * beam + 0.00004) * smoothstep(0.15, 0.0, beam);

    vec3 gd = normalize(vec3(uv, 1.5));
    float gt = 0.1;
    for (int i = 0; i < 40 + dynamicZero && uv.x > 0.1 && uv.y < -0.05; i++) {
        float d = gun(gd * gt);
        if (d < 0.0005) {
            vec2 e = vec2(0.001, 0);
            vec3 gn = normalize(vec3(gun(gd * gt + e.xyy), gun(gd * gt + e.yxy), gun(gd * gt + e.yyx)) - gun(gd * gt));
            float key = max(dot(gn, normalize(vec3(-0.5, 1, -0.6))), 0.0);
            col = (part == 2 ? (shown > 2.0 ? vec3(0.03, 0.027, 0.02) : vec3(0.06, 0.027, 0.011)) : shown == 2.0 ? vec3(0.024, 0.028, 0.014) : vec3(0.013, 0.014, 0.016)) * (1.0 + flash * vec3(3, 1.6, 0.6) * smoothstep(0.55, 0.95, gt)) * (key * 1.6 + 0.08 + homeLamp * 2.5 * max(gn.y, 0.0)) + vec3(0.25, 0.21, 0.17) * on * (part > 1 ? 0.3 : float(part < 1)) * pow(max(dot(reflect(gd, gn), normalize(vec3(-0.1, 0.5, 1))), 0.0), shown > 1.0 ? 90.0 : 40.0) + float(part == 1) * (shown == 1.0 ? vec3(1, 0.2, 0.03) * whirl * whirl * 0.5 : vec3(0.02, 0.2, 0.8) * (0.1 + max(0.0, 1.0 - fireCooldown * 2.0) * 0.4 + flash * 2.0)) + col * 0.25 * pow(max(1.0 + dot(gd, gn), 0.0), 5.0);
            break;
        }
        gt += d;
        if (gt > 1.5) break;
    }
    vec2 mz = uv - muzzle, barrel = normalize(muzzle);
    mz -= barrel * dot(mz, barrel) * 0.6;
    float spike = atan(mz.y, mz.x), shot = dot(tracerEnd, vec3(5)) + ammo.z;
    col += (shown > 2.0 ? vec3(0.3, 0.5, 1) : vec3(1, 0.55, 0.2)) * flash * flash * 0.0025 / (dot(mz, mz) + 0.0003) * (1.0 + (pow(abs(sin(spike * 2.5 + shot)), 4.0) + pow(abs(sin(spike * 3.5 + shot * 1.7)), 9.0)) * (1.0 - dot(normalize(mz), barrel)) * flash * (shown > 2.0 ? 1.2 : 2.5) * smoothstep(0.02, 0.0, dot(mz, mz)));

    vec2 c = abs(uv);
    if (max(c.x, c.y) < 0.012 && min(c.x, c.y) < 0.0015 || length(uv) < 0.003) col = vec3(0.9) - vec3(0, 0.25, 0.28) * frenzy;
    c = abs(uv * rot(0.785));
    if (max(c.x, c.y) < 0.04 && min(c.x, c.y) < 0.003 && max(c.x, c.y) > 0.015) col = mix(col, vec3(1, 0.1, 0), hitmark);

    col *= mix(vec3(1), vec3(0.9, 0.12, 0.08), clamp((hurt + frenzy * 0.08) * smoothstep(0.4, 2.0, dot(uv, uv)) + (1.0 - health + intensity * 0.5) * dot(uv, uv) * 0.16 * step(mod(musicStep + 3.0, 4.0), 1.0), 0.0, 0.85));
    for (int i = 0; i < 16 + dynamicZero; i++) {
        vec3 to = entity[i].xyz - eye;
        if (monster[i].x >= 0.0 && monster[i].w == 0.0 && brain[i].w > 0.0 && charge[i].y == 0.0) {
            float side = mod(atan(to.x, to.z) - yaw + 3.1416, 6.2832) - 3.1416;
            col +=vec3(0.08, 0.004, 0) * smoothstep(8.0, 2.5, length(to)) * smoothstep(0.7, 1.4, abs(side)) * smoothstep(0.6, 1.0, uv.x * sign(side) * screen.z / screen.y) * (0.7 + 4.0 * hurt);
        }
    }
    col *= fade * (1.0 - dot(uv, uv) * 0.12) * (1.0 - min(screen.w, 1.0) * 0.7);
    if (dead > 0.0) col = mix(col, vec3(dot(col, vec3(0.3))) * vec3(0.8, 0, 0), min(dead, 0.8));

    float aspect = screen.y / screen.z;
    if (abs(uv.y) > 0.8 && ending == 0.0) {
        vec2 bar = uv - vec2(-aspect + 0.1, -0.9);
        if (bar.x > 0.0 && bar.x < health * 0.5 && abs(bar.y) < 0.012) col = vec3(0.8, 0.05, 0.02);
        for (int k = 0; k < 4 + dynamicZero; k++) {
            vec2 q = abs(uv - vec2(aspect - 0.42 + k * 0.08, -0.9));
            if (max(q.x, q.y) < 0.025 && k <= arsenal) col = weapon == k ? vec3(0.9, 0.2, 0.1) : vec3(0.25);
            q = uv - vec2(aspect - 0.445 + k * 0.08, -0.95);
            if (abs(q.y) < 0.0075 && q.x > 0.0 && q.x < upgrades[k] * 0.016 && fract(q.x * 62.5) < 0.7 && (notice < 0.0 || k != int(boosted) || fract(time * 3.0) < 0.5)) col = vec3(0.9, 0.5, 0.1);
        }
    }

    if (ending > 0.0) {
        float rise = min(ending, 12.0) * 0.02, h = uv.y + 0.3 - 0.04 * sin(uv.x * 2.3 + 1.0) - 0.015 * sin(uv.x * 7.1);
        vec2 s = uv - vec2(0.9, rise - 0.32);
        col = step(0.0, h) * (mix(vec3(1, 0.4, 0.12) * rise * 6.0, vec3(0.01, 0.015, 0.04), sqrt(min(h * 2.0, 1.0))) + vec3(1, 0.6, 0.3) * 0.002 / (dot(s, s) + 0.002));
    }
    col = max(col, 0.0);
    col *= col / (col + 0.0015);
    vec3 g = sqrt(col / (col + 0.6667));
    g *= mix(vec3(0.8, 0.95, 1.2), vec3(1.1, 1.0, 0.85), smoothstep(0.05, 0.4, dot(g, vec3(0.3, 0.6, 0.1))));
    fragColor = vec4(g + (hash(uv + fract(time)) - 0.5) * 0.04 * min(g * 8.0 + 0.3, 1.0), 1.0);
    float stage = twist(), text = ending > 0.0 ? 0.0 : print(vec2(-aspect + 0.1, 0.84), 0.01, 9, fuses) + (weapon > 0.0 ? print(vec2(aspect - 0.62, -0.925), 0.01, 10, ammo[int(weapon)]) : 0.0);
    if (ending > 0.0)
        text += print(vec2(-0.55, 0.3), 0.025, 5, 0.0) + print(vec2(-0.264, 0.05), 0.012, 6, runTime) + print(vec2(-0.264, -0.08), 0.012, 7, deaths) + print(vec2(-0.264, -0.21), 0.012, 18, kills) + (ending > 2.0 ? print(vec2(-0.456, -0.62), 0.012, 8, 0.0) : 0.0);
    else if (screen.w > 0.0)
        text += print(vec2(screen.w * -0.3, 0.0), 0.012, 0, 0.0) * step(uv.x, screen.w - 0.66);
    else if (dead > 2.0)
        text += print(vec2(-0.476, -0.2), 0.014, 1, 0.0);
    else if (banner < 4.0)
        text += print(vec2(-0.35, 0.62), 0.025, 2, 0.0) + print(vec2(level < 10.0 ? 0.05 : 0.15, 0.62), 0.025, 10, level) + print(vec2(-0.6, 0.5), 0.012, int(stage) + 12, 0.0);
    else if (notice > 0.0)
        text += print(vec2(-0.36, 0.62), 0.012, 3, 0.0) + print(vec2(-0.504, 0.54), 0.012, 11, 0.0) * step(upgrades[int(boosted)], 1.0);
    else if (exitOpen > 0.0 && exitOpen < 1.0)
        text += print(vec2(-0.456, 0.62), 0.012, 4, 0.0);
    vec3 goal = hunter(12) && monster[12].x >= 0.0 ? entity[12].xyz : exitPos;
    float nearest = 1e9;
    for (int i = 0; i < 4 + dynamicZero; i++)
        if (exitOpen == 0.0 && pickup[i].w > 0.0 && pickup[i].w != 2.0 && distance(pickup[i].xyz, eye) < nearest) nearest = distance(pickup[i].xyz, eye), goal = pickup[i].xyz;
    float bearing = mod(atan(goal.x - eye.x, goal.z - eye.z) - yaw + 3.1416, 6.2832) - 3.1416;
    text += float(ending == 0.0 && dead == 0.0 && banner > 4.0) * step(abs(uv.x - clamp(bearing * 1.5, -1.2, 1.2)), 0.006) * step(abs(uv.y - 0.9), 0.02 + 0.015 * step(abs(bearing), 0.15));
    fragColor.rgb = mix(fragColor.rgb, vec3(0.9, 0.85, 0.8), min(text, 1.0));
}

#endif
