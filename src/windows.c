#define API __declspec(dllimport) __stdcall
#define GLAPI __stdcall

API void ExitProcess(unsigned);
API void Sleep(unsigned);
API int IsWindow(void *);
API int SystemParametersInfoA(unsigned, unsigned, void *, unsigned);
API void *CreateWindowExA(unsigned, const char *, const char *, unsigned, int, int, int, int, void *, void *, void *, void *);
API void *GetDC(void *);
API int ShowCursor(int);
API int PeekMessageA(void *, void *, unsigned, unsigned, unsigned);
API short GetAsyncKeyState(int);
API unsigned MapVirtualKeyA(unsigned, unsigned);
API int GetCursorPos(int *);
API int SetCursorPos(int, int);
API int GetSystemMetrics(int);
API void *GetForegroundWindow(void);
API int ChoosePixelFormat(void *, const void *);
API int SetPixelFormat(void *, int, const void *);
API int SwapBuffers(void *);
API void *wglCreateContext(void *);
API int wglMakeCurrent(void *, void *);
API void *wglGetProcAddress(const char *);
API void glRects(short, short, short, short);
API void glClear(unsigned);
API unsigned glGetError(void);
API int MessageBoxA(void *, const char *, const char *, unsigned);
API unsigned waveOutOpen(void **, unsigned, const void *, void *, void *, unsigned);
API unsigned waveOutPrepareHeader(void *, void *, unsigned);
API unsigned waveOutWrite(void *, void *, unsigned);
API unsigned timeGetTime(void);
API unsigned timeBeginPeriod(unsigned);
#ifdef DEV
API void *CreateFileA(const char *, unsigned, unsigned, void *, unsigned, unsigned, void *);
API int WriteFile(void *, const void *, unsigned, unsigned *, void *);
API void glReadPixels(int, int, int, int, unsigned, unsigned, void *);
API unsigned waveOutSetVolume(void *, unsigned);
#endif
#ifdef DIAG
API void *CreateFileA(const char *, unsigned, unsigned, void *, unsigned, unsigned, void *);
API int WriteFile(void *, const void *, unsigned, unsigned *, void *);
API const char *glGetString(unsigned);
#endif

int _fltused;

#include "shader.h"

#define STATE_BYTES 0x30000
#define AUDIO_BUFFERS 4
#define AUDIO_SAMPLES 1024

typedef struct { float *data; unsigned length, recorded, user, flags, loops; void *next, *reserved; } WaveHeader;

static const struct { short size, version; unsigned flags; unsigned char type, bits, unused[30]; } pixel_format = { 40, 1, 0x25, 0, 32 };
static const struct { short tag, channels; unsigned rate, bytes_per_second; short align, bits, extra; } wave_format = {
    3, 2, 44100, 44100 * 8, 8, 32, 0
};
static const char gl_names[] = "glCreateShaderProgramv\0glUseProgram\0glBindBufferBase\0glBufferData\0glBufferSubData\0glGetBufferSubData\0glDispatchCompute\0glMemoryBarrier\0wglSwapIntervalEXT\0";
static const char *const game_sources[] = { "#version 430\n#define GAME\n", shader_source };
static const char *const draw_sources[] = { "#version 430\n", shader_source };
static void *gl[9];
static char zero[STATE_BYTES];
static float audio[AUDIO_BUFFERS][AUDIO_SAMPLES * 2], input[8];
static WaveHeader headers[AUDIO_BUFFERS];
static int message[7], held, paused, focused;
static unsigned sticky_keys[2] = { 8 }, no_sticky_shortcut[2] = { 8 };
static int mouse_params[3];

#define CreateShaderProgramv ((unsigned(GLAPI *)(unsigned, int, const char *const *))gl[0])
#define UseProgram ((void(GLAPI *)(unsigned))gl[1])
#define BindBufferBase ((void(GLAPI *)(unsigned, unsigned, unsigned))gl[2])
#define BufferData ((void(GLAPI *)(unsigned, long, const void *, unsigned))gl[3])
#define BufferSubData ((void(GLAPI *)(unsigned, long, long, const void *))gl[4])
#define GetBufferSubData ((void(GLAPI *)(unsigned, long, long, void *))gl[5])
#define DispatchCompute ((void(GLAPI *)(unsigned, unsigned, unsigned))gl[6])
#define MemoryBarrier ((void(GLAPI *)(unsigned))gl[7])

#ifdef DEV
static unsigned char pixels[960 * 540 * 3];
static unsigned char bitmap_header[54] = { 'B', 'M', 0, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0, 40, 0, 0, 0, 0xC0, 3, 0, 0, 0x1C, 2, 0, 0, 1, 0, 24 };

static void dev_dump(const char *name) {
    unsigned written;
    glReadPixels(0, 0, 960, 540, 0x80E0, 0x1401, pixels);
    void *file = CreateFileA(name, 0x40000000, 0, 0, 2, 0x80, 0);
    WriteFile(file, bitmap_header, 54, &written, 0);
    WriteFile(file, pixels, sizeof pixels, &written, 0);
}
#endif

#ifdef DIAG
static void *log_file;
static char log_text[65536];
static unsigned frames, report_second = 1, log_start;

static void log_put(const char *text) {
    unsigned length = 0, written;
    if (!text) text = "(null)";
    while (text[length]) length++;
    WriteFile(log_file, text, length, &written, 0);
}

static void log_number(const char *label, unsigned value) {
    char digits[12];
    int at = 11;
    digits[11] = 0;
    do digits[--at] = '0' + value % 10; while (value /= 10);
    log_put(label);
    log_put(digits + at);
}

static unsigned build_program(unsigned type, const char *const *sources, const char *label) {
    log_put(label);
    log_put(": compiling\r\n");
    unsigned start = timeGetTime(), program = CreateShaderProgramv(type, 2, sources);
    int linked = 0, length = 0;
    ((void(GLAPI *)(unsigned, unsigned, int *))wglGetProcAddress("glGetProgramiv"))(program, 0x8B82, &linked);
    ((void(GLAPI *)(unsigned, int, int *, char *))wglGetProcAddress("glGetProgramInfoLog"))(program, sizeof log_text - 1, &length, log_text);
    log_put(label);
    log_number(": linked ", linked);
    log_number(", ms ", timeGetTime() - start);
    log_put("\r\n");
    log_text[length > 0 ? length : 0] = 0;
    log_put(log_text);
    log_put("\r\n");
    return program;
}
#endif

void __stdcall entry(void) {
#ifdef DEV
    int width = 960, height = 540;
    void *window = CreateWindowExA(0, "edit", 0, 0x90000000, 0, 0, width, height, 0, 0, 0, 0);
#else
    int width = GetSystemMetrics(0), height = GetSystemMetrics(1);
    void *window = CreateWindowExA(0, "edit", 0, 0x91000000, 0, 0, width, height, 0, 0, 0, 0);
#endif
    void *dc = GetDC(window);
    SetPixelFormat(dc, ChoosePixelFormat(dc, &pixel_format), &pixel_format);
    wglMakeCurrent(dc, wglCreateContext(dc));
    glClear(0x4000);
    SwapBuffers(dc);
    ShowCursor(0);
    timeBeginPeriod(1);
#ifdef DIAG
    log_file = CreateFileA("kilocrypt-log.txt", 0x40000000, 1, 0, 2, 0x80, 0);
    log_number("screen ", width);
    log_number(" x ", height);
    log_put("\r\n");
    for (unsigned key = 0x1F00; key < 0x1F03; key++) {
        log_put(glGetString(key));
        log_put("\r\n");
    }
#endif

    const char *name = gl_names;
    for (int i = 0; i < 9; i++) {
        gl[i] = wglGetProcAddress(name);
#ifdef DIAG
        if (!gl[i]) {
            log_put("missing ");
            log_put(name);
            log_put("\r\n");
        }
#endif
        while (*name++) {}
    }
    if (!gl[6]) goto broken;
    if (gl[8]) ((int(GLAPI *)(int))gl[8])(1);
#ifdef DIAG
    unsigned game = build_program(0x91B9, game_sources, "game"), draw = build_program(0x8B30, draw_sources, "draw");
    log_start = timeGetTime();
#else
    unsigned game = CreateShaderProgramv(0x91B9, 2, game_sources), draw = CreateShaderProgramv(0x8B30, 2, draw_sources);
#endif
    UseProgram(game);
    UseProgram(draw);
    if (glGetError()) {
broken:
        MessageBoxA(window, "Needs OpenGL 4.3", 0, 0x10);
        ExitProcess(1);
    }
    BindBufferBase(0x90D2, 0, 1);
    BufferData(0x90D2, STATE_BYTES, zero, 0x88E8);
    SystemParametersInfoA(0x3A, 8, sticky_keys, 0);
    no_sticky_shortcut[1] = sticky_keys[1] & 1 ? sticky_keys[1] : sticky_keys[1] & ~4u;
    SystemParametersInfoA(3, 0, mouse_params, 0);

    void *wave;
    if (!waveOutOpen(&wave, -1, &wave_format, 0, 0, 0)) {
#ifdef DEV
        waveOutSetVolume(wave, 0);
#endif
        for (int i = 0; i < AUDIO_BUFFERS; i++) {
            headers[i].data = audio[i];
            headers[i].length = AUDIO_SAMPLES * 8;
            waveOutPrepareHeader(wave, &headers[i], sizeof(WaveHeader));
            headers[i].flags |= 1;
        }
    }

    input[5] = width;
    input[6] = height;
    unsigned last = timeGetTime();
#ifdef DEV
    for (int frame = 0; frame < 300; frame++) {
#else
    for (;;) {
#endif
        int wheel = 0;
        for (int n = 0; n < 16 && PeekMessageA(message, 0, 0, 0, 1); n++) {
            if (message[1] == 0x10 || message[1] == 0x112 && (message[2] & 0xFFF0) == 0xF060) goto quit;
            if (message[1] == 0x20A) wheel = message[2] < 0 ? 8192 : 16384;
        }
        if (!IsWindow(window)) break;
        int mouse[2] = { width / 2, height / 2 }, keys = 0, ready = 0, was = focused;
        if ((focused = GetForegroundWindow() == window)) {
#ifndef DEV
            if (GetAsyncKeyState(0x12) < 0 && GetAsyncKeyState(0x73) < 0) break;
            if (!paused) {
                GetCursorPos(mouse);
                SetCursorPos(width / 2, height / 2);
            }
#endif
            static const char codes[13] = { 0x11, 0x1F, 0x1E, 0x20, ' ', 1, 0x10, '1', '2', '3', '4', 0x1B, 2 };
            keys = wheel;
            for (int k = 0; k < 13; k++)
                if (GetAsyncKeyState(k < 4 ? MapVirtualKeyA(codes[k], 1) : codes[k]) < 0) keys |= 1 << k;
        }
        if (focused > was) held = keys;
        int esc = keys & ~held & 2048;
        if (paused > 1 && esc) break;
        if (was != focused) {
            SystemParametersInfoA(0x3B, 8, focused ? no_sticky_shortcut : sticky_keys, 0);
            SystemParametersInfoA(4, 0, focused ? (void *)zero : mouse_params, 0);
        }
        if (esc || focused && paused && held & ~keys & 32) {
            ShowCursor(paused = paused ? 0 : 1 + !!esc);
            SetCursorPos(width / 2, height / 2);
        } else if (was > focused && !paused)
            ShowCursor(paused = 1);
        input[2] = keys & ~(held & 64);
        held = keys;
#ifdef DIAG
        if (report_second <= 20 && timeGetTime() - log_start >= report_second * 1000) {
            log_number("second ", report_second++);
            log_number(": frames ", frames);
            log_number(", focused ", focused);
            log_number(", paused ", paused);
            log_number(", gl error ", glGetError());
            log_put("\r\n");
        }
#endif
#ifndef DEV
        if (!focused) {
            Sleep(100);
            continue;
        }
#else
        mouse[0] += 3;
        input[2] = 33;
#endif
        for (int i = 0; i < AUDIO_BUFFERS; i++) ready += headers[i].flags & 1;
        unsigned now = timeGetTime();
        input[0] = mouse[0] - width / 2;
        input[1] = mouse[1] - height / 2;
        input[3] = (now - last) * 0.001f;
        input[4] = ready * AUDIO_SAMPLES;
        input[7] = paused;
        last = now;
        BufferSubData(0x90D2, 0, sizeof input, input);
        if (!paused) {
            UseProgram(game);
            DispatchCompute(1, 1, 1);
            MemoryBarrier(-1);
            DispatchCompute(64, 1, 1);
            MemoryBarrier(-1);
            for (int i = 0, offset = 32; i < AUDIO_BUFFERS; i++) {
                if (headers[i].flags & 1 && ready-- > 0) {
                    GetBufferSubData(0x90D2, offset, AUDIO_SAMPLES * 8, audio[i]);
                    waveOutWrite(wave, &headers[i], sizeof(WaveHeader));
                    offset += AUDIO_SAMPLES * 8;
                }
            }
        }
        UseProgram(draw);
        glRects(-1, -1, 1, 1);
#ifdef DEV
        if (frame == 120) dev_dump("build/win-frame120.bmp");
        if (frame == 299) dev_dump("build/win-frame299.bmp");
#endif
#ifdef DIAG
        frames++;
#endif
        SwapBuffers(dc);
    }
quit:
    SystemParametersInfoA(0x3B, 8, sticky_keys, 0);
    SystemParametersInfoA(4, 0, mouse_params, 0);
    ExitProcess(0);
}
