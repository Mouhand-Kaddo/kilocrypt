#include <SDL2/SDL.h>
#include "shader.h"

#ifdef DEV
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#endif

#define STATE_BYTES 0x30000
#define AUDIO_TARGET 2048

static const char gl_names[] = "glCreateShaderProgramv\0glUseProgram\0glBindBufferBase\0glBufferData\0glBufferSubData\0glGetBufferSubData\0glDispatchCompute\0glMemoryBarrier\0glRects\0glViewport\0glClear\0glGetError\0";
static void *gl[12];
static char zero[STATE_BYTES];
static float input[8], samples[8192];
static int held, paused, focused;

#define CreateShaderProgramv ((unsigned (*)(unsigned, int, const char *const *))gl[0])
#define UseProgram ((void (*)(unsigned))gl[1])
#define BindBufferBase ((void (*)(unsigned, unsigned, unsigned))gl[2])
#define BufferData ((void (*)(unsigned, long, const void *, unsigned))gl[3])
#define BufferSubData ((void (*)(unsigned, long, long, const void *))gl[4])
#define GetBufferSubData ((void (*)(unsigned, long, long, void *))gl[5])
#define DispatchCompute ((void (*)(unsigned, unsigned, unsigned))gl[6])
#define MemoryBarrier ((void (*)(unsigned))gl[7])
#define Rects ((void (*)(short, short, short, short))gl[8])
#define Viewport ((void (*)(int, int, int, int))gl[9])
#define Clear ((void (*)(unsigned))gl[10])
#define GetError ((unsigned (*)(void))gl[11])

#ifdef DEV
static char dev_defines[256];

static unsigned build(unsigned type, const char *const *sources, int count) {
    unsigned program = CreateShaderProgramv(type, count, sources);
    int ok, length;
    char log[8192];
    ((void (*)(unsigned, unsigned, int *))SDL_GL_GetProcAddress("glGetProgramiv"))(program, 0x8B82, &ok);
    if (!ok) {
        ((void (*)(unsigned, int, int *, char *))SDL_GL_GetProcAddress("glGetProgramInfoLog"))(program, sizeof log, &length, log);
        fprintf(stderr, "%s\n", log);
        exit(1);
    }
    return program;
}

static void dev_dump(int frame, int width, int height) {
    static unsigned char pixels[4096 * 4096 * 3];
    char name[64];
    void (*read)(int, int, int, int, unsigned, unsigned, void *) = SDL_GL_GetProcAddress("glReadPixels");
    read(0, 0, width, height, 0x1907, 0x1401, pixels);
    snprintf(name, sizeof name, "build/dev/frame%04d.ppm", frame);
    FILE *f = fopen(name, "wb");
    fprintf(f, "P6 %d %d 255\n", width, height);
    for (int y = height - 1; y >= 0; y--) fwrite(pixels + y * width * 3, 1, width * 3, f);
    fclose(f);
}
#endif

static void run(void) {
    SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO);
#ifdef DEV
    SDL_Window *window = SDL_CreateWindow("", 0, 0, 960, 540, SDL_WINDOW_OPENGL);
#else
    SDL_Window *window = SDL_CreateWindow("", SDL_WINDOWPOS_CENTERED_DISPLAY(0), SDL_WINDOWPOS_CENTERED_DISPLAY(0), 0, 0, SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN_DESKTOP);
#endif
    SDL_GL_CreateContext(window);
    SDL_GL_SetSwapInterval(1);
    static SDL_AudioSpec spec = { 44100, AUDIO_F32, 2, 0, 1024 };
    SDL_OpenAudio(&spec, 0);
    SDL_PauseAudio(0);

    const char *name = gl_names;
    for (int i = 0; i < 12; i++) {
        gl[i] = SDL_GL_GetProcAddress(name);
        while (*name++) {}
    }
    Clear(0x4000);
    SDL_GL_SwapWindow(window);
#ifdef DEV
    int used = snprintf(dev_defines, sizeof dev_defines, "#define BOT\n#define LEVEL %s.0\n", getenv("LEVEL") ? getenv("LEVEL") : "1");
    char macros[128] = "";
    if (getenv("DEFINES")) snprintf(macros, sizeof macros, "%s", getenv("DEFINES"));
    for (char *macro = strtok(macros, " "); macro; macro = strtok(0, " ")) used += snprintf(dev_defines + used, sizeof dev_defines - used, "#define %s\n", macro);
    const char *game_sources[] = { "#version 430\n#define GAME\n", dev_defines, shader_source };
    const char *draw_sources[] = { "#version 430\n", shader_source };
    unsigned game = build(0x91B9, game_sources, 3), draw = build(0x8B30, draw_sources, 2);
#else
    static const char *const game_sources[] = { "#version 430\n#define GAME\n", shader_source };
    static const char *const draw_sources[] = { "#version 430\n", shader_source };
    unsigned game = CreateShaderProgramv(0x91B9, 2, game_sources), draw = CreateShaderProgramv(0x8B30, 2, draw_sources);
#endif
    UseProgram(game);
    UseProgram(draw);
    if (!game || !draw || GetError()) {
        SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "", "Needs OpenGL 4.3", window);
        return;
    }
    BindBufferBase(0x90D2, 0, 1);
    BufferData(0x90D2, STATE_BYTES, zero, 0x88E8);

#ifdef DEV
    int frames = getenv("FRAMES") ? atoi(getenv("FRAMES")) : 900;
    for (int frame = 0; frame < frames; frame++) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {}
        input[3] = 1.0f / 60;
        focused = 1;
#else
    SDL_SetRelativeMouseMode(SDL_TRUE);
    unsigned last = SDL_GetTicks();
    for (;;) {
        SDL_Event event;
        int wheel = 0;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) return;
            if (event.type == SDL_MOUSEWHEEL) wheel += event.wheel.direction ? -event.wheel.y : event.wheel.y;
        }
        const Uint8 *key = SDL_GetKeyboardState(0);
        int mouse_x, mouse_y;
        int buttons = SDL_GetRelativeMouseState(&mouse_x, &mouse_y);
        unsigned now = SDL_GetTicks();
        input[0] = mouse_x;
        input[1] = mouse_y;
        static const unsigned char codes[12] = { SDL_SCANCODE_W, SDL_SCANCODE_S, SDL_SCANCODE_A, SDL_SCANCODE_D, SDL_SCANCODE_SPACE, 0, SDL_SCANCODE_LSHIFT, SDL_SCANCODE_1, SDL_SCANCODE_2, SDL_SCANCODE_3, SDL_SCANCODE_4, SDL_SCANCODE_ESCAPE };
        int keys = (buttons & 1) << 5 | (buttons & 4) << 10 | (wheel < 0) << 13 | (wheel > 0) << 14, was = focused;
        for (int k = 0; k < 12; k++) keys |= key[codes[k]] << k;
        focused = SDL_GetWindowFlags(window) & SDL_WINDOW_INPUT_FOCUS;
        if (focused > was) held = keys;
        if (paused > 1 && keys & ~held & 2048) return;
        if (keys & ~held & 2048 || focused && paused && held & ~keys & 32 || was > focused && !paused) SDL_SetRelativeMouseMode(!(paused = paused ? 0 : 1 + (keys & ~held & 2048) / 2048));
        input[2] = keys & ~(held & 64);
        held = keys;
        if (!focused) SDL_Delay(100);
        input[7] = paused;
        input[3] = (now - last) * 0.001f;
        last = now;
#endif
        int width, height, need = AUDIO_TARGET - (int)SDL_GetQueuedAudioSize(1) / 8;
        SDL_GL_GetDrawableSize(window, &width, &height);
        need = need < 0 ? 0 : need;
        input[4] = need;
        input[5] = width;
        input[6] = height;
        BufferSubData(0x90D2, 0, sizeof input, input);
        if (!paused && focused) {
            UseProgram(game);
            DispatchCompute(1, 1, 1);
            MemoryBarrier(-1);
            DispatchCompute(64, 1, 1);
            MemoryBarrier(-1);
            GetBufferSubData(0x90D2, 32, sizeof samples, samples);
            SDL_QueueAudio(1, samples, need * 8);
        }
        UseProgram(draw);
        Viewport(0, 0, width, height);
        Rects(-1, -1, 1, 1);
#ifdef DEV
        if (frame % 60 == 0)
            printf("frame %d level %.0f health %.2f left %.0f weapon %.0f dead %.1f boxes %.0f\n", frame, samples[8186], samples[8187], samples[8188], samples[8189],
                   samples[8190], samples[8191]);
        if (getenv("DUMP") && frame % atoi(getenv("DUMP")) == 0) dev_dump(frame, width, height);
        ((void (*)(void))SDL_GL_GetProcAddress("glFinish"))();
#endif
        SDL_GL_SwapWindow(window);
    }
}

#ifdef DEV
int main(void) {
    run();
    return 0;
}
#else
__attribute__((force_align_arg_pointer, noreturn)) void _start(void) {
    run();
    SDL_Quit();
    __asm__ volatile("syscall" : : "a"(231), "D"(0));
    __builtin_unreachable();
}
#endif
