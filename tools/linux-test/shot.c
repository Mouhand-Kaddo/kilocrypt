#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define STATE_BYTES 0x40000

static char zero[STATE_BYTES], source[262144], game_head[4096], text[65536];
static unsigned char pixels[3840 * 2160 * 3];
static int W = 960, H = 540;
static float input[8], samples[2048];

static unsigned (*CreateShaderProgramv)(unsigned, int, const char *const *);
static void (*GetProgramiv)(unsigned, unsigned, int *);
static void (*GetProgramInfoLog)(unsigned, int, int *, char *);
static void (*UseProgram)(unsigned);
static void (*BindBufferBase)(unsigned, unsigned, unsigned);
static void (*BufferData)(unsigned, long, const void *, unsigned);
static void (*BufferSubData)(unsigned, long, long, const void *);
static void (*GetBufferSubData)(unsigned, long, long, void *);
static void (*DispatchCompute)(unsigned, unsigned, unsigned);
static void (*MemoryBarrier)(unsigned);
static void (*GenFramebuffers)(int, unsigned *);
static void (*BindFramebuffer)(unsigned, unsigned);
static void (*GenRenderbuffers)(int, unsigned *);
static void (*BindRenderbuffer)(unsigned, unsigned);
static void (*RenderbufferStorage)(unsigned, unsigned, int, int);
static void (*FramebufferRenderbuffer)(unsigned, unsigned, unsigned, unsigned);
static void (*Rects)(short, short, short, short);
static void (*Finish)(void);
static void (*Viewport)(int, int, int, int);
static void (*ReadPixels)(int, int, int, int, unsigned, unsigned, void *);
static void (*PixelStorei)(unsigned, int);

static double now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1e3 + t.tv_nsec / 1e6;
}

static unsigned build(unsigned type, const char *const *sources, int count, const char *label) {
    double t0 = now_ms();
    unsigned program = CreateShaderProgramv(type, count, sources);
    int ok = 0, n = 0;
    GetProgramiv(program, 0x8B82, &ok);
    printf("%s ok=%d ms=%.0f\n", label, ok, now_ms() - t0);
    GetProgramInfoLog(program, sizeof text - 1, &n, text);
    if (n > 0) printf("%.*s\n", n, text);
    return ok ? program : 0;
}

static void dump(const char *dir, int frame) {
    char name[4096];
    ReadPixels(0, 0, W, H, 0x1907, 0x1401, pixels);
    snprintf(name, sizeof name, "%s/f%04d.ppm", dir, frame);
    FILE *f = fopen(name, "wb");
    if (!f) {
        perror(name);
        exit(1);
    }
    fprintf(f, "P6 %d %d 255\n", W, H);
    for (int y = H - 1; y >= 0; y--) fwrite(pixels + y * W * 3, 1, W * 3, f);
    fclose(f);
}

static void *proc(const char *name) {
    void *p = eglGetProcAddress(name);
    if (!p) {
        fprintf(stderr, "missing %s\n", name);
        exit(1);
    }
    return p;
}

int main(int argc, char **argv) {
    if (argc < 7) {
        fprintf(stderr, "usage: %s SHADER OUTDIR FRAMES EVERY FROM AUDIO [DEFINES]\n", argv[0]);
        return 1;
    }
    if (getenv("SIZE") && (sscanf(getenv("SIZE"), "%dx%d", &W, &H) != 2 || W < 1 || H < 1 || W > 3840 || H > 2160)) {
        fprintf(stderr, "SIZE must be WxH up to 3840x2160\n");
        return 1;
    }
    const char *dir = argv[2];
    int frames = atoi(argv[3]), every = atoi(argv[4]), from = atoi(argv[5]), audio = atoi(argv[6]);
    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        perror(argv[1]);
        return 1;
    }
    source[fread(source, 1, sizeof source - 1, f)] = 0;
    fclose(f);
    int used = snprintf(game_head, sizeof game_head, "#version 430\n#define GAME\n");
    if (argc > 7) {
        char macros[2048];
        snprintf(macros, sizeof macros, "%s", argv[7]);
        for (char *macro = strtok(macros, " "); macro; macro = strtok(0, " ")) {
            char *equals = strchr(macro, '=');
            if (equals) *equals = ' ';
            used += snprintf(game_head + used, sizeof game_head - used, "#define %s\n", macro);
        }
    }

    EGLDisplay display = eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, 0);
    if (!eglInitialize(display, 0, 0)) {
        PFNEGLQUERYDEVICESEXTPROC query_devices = (PFNEGLQUERYDEVICESEXTPROC)eglGetProcAddress("eglQueryDevicesEXT");
        EGLDeviceEXT device;
        EGLint devices = 0;
        if (query_devices && query_devices(1, &device, &devices) && devices > 0) display = eglGetPlatformDisplay(EGL_PLATFORM_DEVICE_EXT, device, 0);
    }
    if (!eglInitialize(display, 0, 0) || !eglBindAPI(EGL_OPENGL_API)) {
        fprintf(stderr, "no EGL display\n");
        return 1;
    }
    static const EGLint attributes[] = { EGL_CONTEXT_MAJOR_VERSION, 4, EGL_CONTEXT_MINOR_VERSION, 3, EGL_CONTEXT_OPENGL_PROFILE_MASK,
                                         EGL_CONTEXT_OPENGL_COMPATIBILITY_PROFILE_BIT, EGL_NONE };
    EGLContext context = eglCreateContext(display, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, attributes);
    if (context == EGL_NO_CONTEXT || !eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context)) {
        fprintf(stderr, "no GL 4.3 compatibility context\n");
        return 1;
    }
    CreateShaderProgramv = proc("glCreateShaderProgramv");
    GetProgramiv = proc("glGetProgramiv");
    GetProgramInfoLog = proc("glGetProgramInfoLog");
    UseProgram = proc("glUseProgram");
    BindBufferBase = proc("glBindBufferBase");
    BufferData = proc("glBufferData");
    BufferSubData = proc("glBufferSubData");
    GetBufferSubData = proc("glGetBufferSubData");
    DispatchCompute = proc("glDispatchCompute");
    MemoryBarrier = proc("glMemoryBarrier");
    GenFramebuffers = proc("glGenFramebuffers");
    BindFramebuffer = proc("glBindFramebuffer");
    GenRenderbuffers = proc("glGenRenderbuffers");
    BindRenderbuffer = proc("glBindRenderbuffer");
    RenderbufferStorage = proc("glRenderbufferStorage");
    FramebufferRenderbuffer = proc("glFramebufferRenderbuffer");
    Rects = proc("glRects");
    Finish = proc("glFinish");
    Viewport = proc("glViewport");
    ReadPixels = proc("glReadPixels");
    PixelStorei = proc("glPixelStorei");
    const char *(*get_string)(unsigned) = proc("glGetString");
    printf("gl %s | %s | %s\n", get_string(0x1F00), get_string(0x1F01), get_string(0x1F02));
    PixelStorei(0x0D05, 1);

    const char *game_sources[] = { game_head, source };
    const char *draw_sources[] = { "#version 430\n", source };
    unsigned game = build(0x91B9, game_sources, 2, "compute"), draw = build(0x8B30, draw_sources, 2, "fragment");
    if (!game || !draw) return 2;
    unsigned fbo, rbo;
    GenFramebuffers(1, &fbo);
    BindFramebuffer(0x8D40, fbo);
    GenRenderbuffers(1, &rbo);
    BindRenderbuffer(0x8D41, rbo);
    RenderbufferStorage(0x8D41, 0x8058, W, H);
    FramebufferRenderbuffer(0x8D40, 0x8CE0, 0x8D41, rbo);
    Viewport(0, 0, W, H);
    BindBufferBase(0x90D2, 0, 1);
    BufferData(0x90D2, STATE_BYTES, zero, 0x88E8);

    FILE *wav = 0;
    if (audio) {
        char name[4096];
        snprintf(name, sizeof name, "%s/audio.wav", dir);
        wav = fopen(name, "wb");
        if (!wav) {
            perror(name);
            return 1;
        }
        unsigned bytes = frames * 735 * 8, riff = bytes + 36, rate = 44100, byte_rate = rate * 8, fmt = 16;
        unsigned short tag = 3, channels = 2, align = 8, bits = 32;
        fwrite("RIFF", 1, 4, wav);
        fwrite(&riff, 4, 1, wav);
        fwrite("WAVEfmt ", 1, 8, wav);
        fwrite(&fmt, 4, 1, wav);
        fwrite(&tag, 2, 1, wav);
        fwrite(&channels, 2, 1, wav);
        fwrite(&rate, 4, 1, wav);
        fwrite(&byte_rate, 4, 1, wav);
        fwrite(&align, 2, 1, wav);
        fwrite(&bits, 2, 1, wav);
        fwrite("data", 1, 4, wav);
        fwrite(&bytes, 4, 1, wav);
    }
    input[3] = 1.0f / 60;
    input[4] = 735;
    input[5] = W;
    input[6] = H;
    int timing = getenv("TIMING") != 0;
    double game_total = 0, draw_total = 0;
    for (int frame = 0; frame < frames; frame++) {
        int saved = frame >= from && every && (frame - from) % every == 0;
        BufferSubData(0x90D2, 0, sizeof input, input);
        double t0 = now_ms();
        UseProgram(game);
        DispatchCompute(1, 1, 1);
        MemoryBarrier(-1);
        DispatchCompute(64, 1, 1);
        MemoryBarrier(-1);
        if (wav) {
            GetBufferSubData(0x90D2, 32, 735 * 8, samples);
            fwrite(samples, 4, 735 * 2, wav);
        }
        if (timing) Finish();
        double t1 = now_ms();
        if (timing || saved) {
            UseProgram(draw);
            Rects(-1, -1, 1, 1);
        }
        if (timing) Finish();
        double t2 = now_ms();
        game_total += t1 - t0;
        draw_total += t2 - t1;
        if (timing && (frame < 4 || t1 - t0 > 30)) printf("t %d game %.1f draw %.1f\n", frame, t1 - t0, t2 - t1);
        if (saved) dump(dir, frame);
        if (frame % 60 == 0) {
            GetBufferSubData(0x90D2, 32 + 8184 * 4, 32, samples);
            printf("frame %d level %.0f health100 %.0f left %.0f weapon %.0f dead10 %.0f boxes %.0f stuck %.1f awake %.0f\n", frame, samples[2],
                   samples[3] * 100, samples[4], samples[5], samples[6] * 10, samples[7], samples[0], samples[1]);
        }
    }
    if (timing) printf("avg game us %.0f draw us %.0f\n", game_total * 1000 / frames, draw_total * 1000 / frames);
    printf("done\n");
    if (wav) fclose(wav);
    return 0;
}
