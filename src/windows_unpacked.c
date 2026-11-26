#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <GL/gl.h>
#include <stddef.h>

#include "shader_unpacked.h"

#define STATE_BYTES 0x30000
#define AUDIO_BUFFERS 4
#define AUDIO_SAMPLES 1024

#ifndef WAVE_FORMAT_IEEE_FLOAT
#define WAVE_FORMAT_IEEE_FLOAT 3
#endif
#ifndef GL_COMPUTE_SHADER
#define GL_COMPUTE_SHADER 0x91B9
#endif
#ifndef GL_FRAGMENT_SHADER
#define GL_FRAGMENT_SHADER 0x8B30
#endif
#ifndef GL_SHADER_STORAGE_BUFFER
#define GL_SHADER_STORAGE_BUFFER 0x90D2
#endif
#ifndef GL_DYNAMIC_DRAW
#define GL_DYNAMIC_DRAW 0x88E8
#endif
#ifndef GL_ALL_BARRIER_BITS
#define GL_ALL_BARRIER_BITS 0xFFFFFFFFu
#endif

typedef GLuint (APIENTRY *PFN_CreateShaderProgramv)(GLenum, GLsizei, const char *const *);
typedef void   (APIENTRY *PFN_UseProgram)(GLuint);
typedef void   (APIENTRY *PFN_BindBufferBase)(GLenum, GLuint, GLuint);
typedef void   (APIENTRY *PFN_BufferData)(GLenum, ptrdiff_t, const void *, GLenum);
typedef void   (APIENTRY *PFN_BufferSubData)(GLenum, ptrdiff_t, ptrdiff_t, const void *);
typedef void   (APIENTRY *PFN_GetBufferSubData)(GLenum, ptrdiff_t, ptrdiff_t, void *);
typedef void   (APIENTRY *PFN_DispatchCompute)(GLuint, GLuint, GLuint);
typedef void   (APIENTRY *PFN_MemoryBarrier)(GLbitfield);
typedef BOOL   (APIENTRY *PFN_SwapIntervalEXT)(int);

static const char *const game_sources[] = { "#version 430\n#define GAME\n", SHADER_PARTS_LIST };
static const char *const draw_sources[] = { "#version 430\n", SHADER_PARTS_LIST };

static char zero[STATE_BYTES];
static float audio[AUDIO_BUFFERS][AUDIO_SAMPLES * 2];
static float input[8];
static WAVEHDR headers[AUDIO_BUFFERS];

static int running = 1;
static int key_mask = 0;
static int wheel_event = 0;

static int key_bit(WPARAM wp, LPARAM lp) {
    unsigned int sc = (unsigned int)((lp >> 16) & 0xFF);
    if (sc == 0x11) return 1 << 0;
    if (sc == 0x1F) return 1 << 1;
    if (sc == 0x1E) return 1 << 2;
    if (sc == 0x20) return 1 << 3;
    switch (wp) {
        case VK_SPACE:  return 1 << 4;
        case VK_SHIFT:  return 1 << 6;
        case '1':       return 1 << 7;
        case '2':       return 1 << 8;
        case '3':       return 1 << 9;
        case '4':       return 1 << 10;
        case VK_ESCAPE: return 1 << 11;
        default:        return 0;
    }
}

static LRESULT CALLBACK wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_CLOSE:
        case WM_DESTROY:
            running = 0;
            return 0;
        case WM_SYSCOMMAND:
            if ((wp & 0xFFF0) == SC_CLOSE) {
                running = 0;
                return 0;
            }
            break;
        case WM_KEYDOWN:
        case WM_SYSKEYDOWN:
            key_mask |= key_bit(wp, lp);
            break;
        case WM_KEYUP:
        case WM_SYSKEYUP:
            key_mask &= ~key_bit(wp, lp);
            break;
        case WM_LBUTTONDOWN:
            key_mask |= 1 << 5;
            return 0;
        case WM_LBUTTONUP:
            key_mask &= ~(1 << 5);
            return 0;
        case WM_RBUTTONDOWN:
            key_mask |= 1 << 12;
            return 0;
        case WM_RBUTTONUP:
            key_mask &= ~(1 << 12);
            return 0;
        case WM_MOUSEWHEEL:
            wheel_event = (short)HIWORD(wp) < 0 ? 8192 : 16384;
            return 0;
        case WM_KILLFOCUS:
            key_mask = 0;
            break;
    }
    return DefWindowProcA(hwnd, msg, wp, lp);
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE prev, LPSTR cmd, int show) {
    (void)prev;
    (void)cmd;
    (void)show;

    SetProcessDPIAware();

    WNDCLASSA wc = { 0 };
    wc.style = CS_OWNDC;
    wc.lpfnWndProc = wnd_proc;
    wc.hInstance = instance;
    wc.hCursor = LoadCursorA(NULL, IDC_ARROW);
    wc.lpszClassName = "KilocryptWindow";
    RegisterClassA(&wc);

    int width = GetSystemMetrics(SM_CXSCREEN);
    int height = GetSystemMetrics(SM_CYSCREEN);
    HWND window = CreateWindowExA(0, wc.lpszClassName, "Kilocrypt", WS_POPUP | WS_VISIBLE,
                                  0, 0, width, height, NULL, NULL, instance, NULL);
    if (!window) return 1;

    HDC dc = GetDC(window);
    PIXELFORMATDESCRIPTOR pfd = { 0 };
    pfd.nSize = sizeof(pfd);
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    int pf = ChoosePixelFormat(dc, &pfd);
    SetPixelFormat(dc, pf, &pfd);
    HGLRC rc = wglCreateContext(dc);
    wglMakeCurrent(dc, rc);

    glClear(GL_COLOR_BUFFER_BIT);
    SwapBuffers(dc);
    ShowCursor(FALSE);
    timeBeginPeriod(1);

    PFN_CreateShaderProgramv pCreateShaderProgramv = (PFN_CreateShaderProgramv)(INT_PTR)wglGetProcAddress("glCreateShaderProgramv");
    PFN_UseProgram           pUseProgram           = (PFN_UseProgram)(INT_PTR)wglGetProcAddress("glUseProgram");
    PFN_BindBufferBase       pBindBufferBase       = (PFN_BindBufferBase)(INT_PTR)wglGetProcAddress("glBindBufferBase");
    PFN_BufferData           pBufferData           = (PFN_BufferData)(INT_PTR)wglGetProcAddress("glBufferData");
    PFN_BufferSubData        pBufferSubData        = (PFN_BufferSubData)(INT_PTR)wglGetProcAddress("glBufferSubData");
    PFN_GetBufferSubData     pGetBufferSubData     = (PFN_GetBufferSubData)(INT_PTR)wglGetProcAddress("glGetBufferSubData");
    PFN_DispatchCompute      pDispatchCompute      = (PFN_DispatchCompute)(INT_PTR)wglGetProcAddress("glDispatchCompute");
    PFN_MemoryBarrier        pMemoryBarrier        = (PFN_MemoryBarrier)(INT_PTR)wglGetProcAddress("glMemoryBarrier");
    PFN_SwapIntervalEXT      pSwapIntervalEXT      = (PFN_SwapIntervalEXT)(INT_PTR)wglGetProcAddress("wglSwapIntervalEXT");

    if (!pCreateShaderProgramv || !pUseProgram || !pBindBufferBase || !pBufferData ||
        !pBufferSubData || !pGetBufferSubData || !pDispatchCompute || !pMemoryBarrier) {
        goto broken;
    }
    if (pSwapIntervalEXT) pSwapIntervalEXT(1);

    GLuint game = pCreateShaderProgramv(GL_COMPUTE_SHADER, (GLsizei)(sizeof(game_sources) / sizeof(game_sources[0])), game_sources);
    GLuint draw = pCreateShaderProgramv(GL_FRAGMENT_SHADER, (GLsizei)(sizeof(draw_sources) / sizeof(draw_sources[0])), draw_sources);
    pUseProgram(game);
    pUseProgram(draw);
    if (!game || !draw || glGetError()) {
broken:
        ShowCursor(TRUE);
        MessageBoxA(window, "Needs OpenGL 4.3", "Kilocrypt", MB_ICONERROR);
        timeEndPeriod(1);
        if (rc) { wglMakeCurrent(NULL, NULL); wglDeleteContext(rc); }
        ReleaseDC(window, dc);
        DestroyWindow(window);
        return 1;
    }

    pBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, 1);
    pBufferData(GL_SHADER_STORAGE_BUFFER, STATE_BYTES, zero, GL_DYNAMIC_DRAW);

    STICKYKEYS sticky_keys = { sizeof(STICKYKEYS), 0 };
    STICKYKEYS no_sticky_shortcut = { sizeof(STICKYKEYS), 0 };
    int mouse_params[3] = { 0, 0, 0 };
    int no_mouse_accel[3] = { 0, 0, 0 };
    SystemParametersInfoA(SPI_GETSTICKYKEYS, sizeof(STICKYKEYS), &sticky_keys, 0);
    no_sticky_shortcut.dwFlags = (sticky_keys.dwFlags & SKF_STICKYKEYSON)
        ? sticky_keys.dwFlags
        : (sticky_keys.dwFlags & ~SKF_HOTKEYACTIVE);
    SystemParametersInfoA(SPI_GETMOUSE, 0, mouse_params, 0);

    WAVEFORMATEX wf = { 0 };
    wf.wFormatTag = WAVE_FORMAT_IEEE_FLOAT;
    wf.nChannels = 2;
    wf.nSamplesPerSec = 44100;
    wf.nAvgBytesPerSec = 44100 * 8;
    wf.nBlockAlign = 8;
    wf.wBitsPerSample = 32;

    HWAVEOUT wave = NULL;
    int audio_ok = waveOutOpen(&wave, WAVE_MAPPER, &wf, 0, 0, 0) == MMSYSERR_NOERROR;
    if (audio_ok) {
        for (int i = 0; i < AUDIO_BUFFERS; i++) {
            headers[i].lpData = (LPSTR)audio[i];
            headers[i].dwBufferLength = AUDIO_SAMPLES * 8;
            waveOutPrepareHeader(wave, &headers[i], sizeof(WAVEHDR));
            headers[i].dwFlags |= WHDR_DONE;
        }
    }

    input[5] = (float)width;
    input[6] = (float)height;

    int held = 0, paused = 0, focused = 0;
    DWORD last = timeGetTime();

    while (running && IsWindow(window)) {
        wheel_event = 0;
        MSG msg;
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageA(&msg);
        }
        if (!running || !IsWindow(window)) break;

        POINT mouse = { width / 2, height / 2 };
        int keys = 0, ready = 0, was = focused;
        if ((focused = (GetForegroundWindow() == window))) {
            if (!paused) {
                GetCursorPos(&mouse);
                SetCursorPos(width / 2, height / 2);
            }
            keys = key_mask | wheel_event;
        }
        if (focused > was) held = keys;
        int esc = keys & ~held & 2048;
        if (paused > 1 && esc) break;
        if (was != focused) {
            SystemParametersInfoA(SPI_SETSTICKYKEYS, sizeof(STICKYKEYS), focused ? &no_sticky_shortcut : &sticky_keys, 0);
            SystemParametersInfoA(SPI_SETMOUSE, 0, focused ? no_mouse_accel : mouse_params, 0);
        }
        if (esc || (focused && paused && (held & ~keys & 32))) {
            paused = paused ? 0 : 1 + !!esc;
            ShowCursor(paused != 0);
            SetCursorPos(width / 2, height / 2);
        } else if (was > focused && !paused) {
            paused = 1;
            ShowCursor(TRUE);
        }
        input[2] = (float)(keys & ~(held & 64));
        held = keys;

        if (!focused) {
            Sleep(100);
            continue;
        }

        if (audio_ok) {
            for (int i = 0; i < AUDIO_BUFFERS; i++)
                ready += (headers[i].dwFlags & WHDR_DONE) ? 1 : 0;
        }
        DWORD now = timeGetTime();
        input[0] = (float)(mouse.x - width / 2);
        input[1] = (float)(mouse.y - height / 2);
        input[3] = (now - last) * 0.001f;
        input[4] = (float)(ready * AUDIO_SAMPLES);
        input[7] = (float)paused;
        last = now;

        pBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, sizeof(input), input);
        if (!paused) {
            pUseProgram(game);
            pDispatchCompute(1, 1, 1);
            pMemoryBarrier(GL_ALL_BARRIER_BITS);
            pDispatchCompute(64, 1, 1);
            pMemoryBarrier(GL_ALL_BARRIER_BITS);
            if (audio_ok) {
                for (int i = 0, offset = 32; i < AUDIO_BUFFERS; i++) {
                    if ((headers[i].dwFlags & WHDR_DONE) && ready-- > 0) {
                        pGetBufferSubData(GL_SHADER_STORAGE_BUFFER, offset, AUDIO_SAMPLES * 8, audio[i]);
                        waveOutWrite(wave, &headers[i], sizeof(WAVEHDR));
                        offset += AUDIO_SAMPLES * 8;
                    }
                }
            }
        }
        pUseProgram(draw);
        glViewport(0, 0, width, height);
        glRects(-1, -1, 1, 1);
        SwapBuffers(dc);
    }

    SystemParametersInfoA(SPI_SETSTICKYKEYS, sizeof(STICKYKEYS), &sticky_keys, 0);
    SystemParametersInfoA(SPI_SETMOUSE, 0, mouse_params, 0);
    ShowCursor(TRUE);
    if (audio_ok) {
        waveOutReset(wave);
        for (int i = 0; i < AUDIO_BUFFERS; i++) waveOutUnprepareHeader(wave, &headers[i], sizeof(WAVEHDR));
        waveOutClose(wave);
    }
    timeEndPeriod(1);
    wglMakeCurrent(NULL, NULL);
    wglDeleteContext(rc);
    ReleaseDC(window, dc);
    DestroyWindow(window);
    return 0;
}
