CC = clang
BUILD = build
CFLAGS_COMMON = -Isrc -I$(BUILD) -ffast-math -fno-math-errno -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-ident -fomit-frame-pointer -fno-strict-aliasing -Wno-incompatible-function-pointer-types -Wno-int-conversion
LINUX_CFLAGS = $(CFLAGS_COMMON) -Oz -fno-pic -fno-plt -ffunction-sections -fdata-sections -fno-builtin
LINUX_LDFLAGS = -no-pie -nostartfiles -nostdlib -Wl,--gc-sections,-z,norelro,--hash-style=gnu,--build-id=none,-z,noseparate-code,--no-eh-frame-hdr -lSDL2

SHADER = src/game.glsl

.PHONY: all linux dev clean check size-fast

all: linux windows

$(BUILD)/shader.h: $(SHADER) tools/minify_glsl.py
	@mkdir -p $(BUILD)
	python3 tools/minify_glsl.py $< $@ $(BUILD)/shader.min.glsl --release
	printf '#version 430\n#define GAME\n' | cat - $(BUILD)/shader.min.glsl > $(BUILD)/check.comp
	printf '#version 430\n' | cat - $(BUILD)/shader.min.glsl > $(BUILD)/check.frag
	glslangValidator $(BUILD)/check.comp $(BUILD)/check.frag > /dev/null

$(BUILD)/game.elf: src/linux.c $(BUILD)/shader.h
	$(CC) $(LINUX_CFLAGS) $< -o $@ $(LINUX_LDFLAGS)
	strip -s -R .comment -R .note.gnu.property -R .gnu.version $@

$(BUILD)/kilocrypt: $(BUILD)/game.elf tools/pack_linux.py tools/unpack.S
	python3 tools/pack_linux.py $< $@ $(PACK_FLAGS)

linux: $(BUILD)/kilocrypt
	@ls -l $(BUILD)/game.elf $(BUILD)/kilocrypt

$(BUILD)/dev/shader.h: src/game.glsl tools/minify_glsl.py
	@mkdir -p $(BUILD)/dev
	python3 tools/minify_glsl.py $< $@

dev: src/linux.c $(BUILD)/dev/shader.h
	$(CC) -DDEV -O2 -g -Isrc -I$(BUILD)/dev -ffast-math -Wno-incompatible-function-pointer-types $< -o $(BUILD)/dev-game -lSDL2 -lm

clean:
	rm -rf $(BUILD)

check: linux windows
	tools/check.sh $(BUILD)

size-fast:
	@mkdir -p $(BUILD)/fast
	@$(MAKE) --no-print-directory BUILD=$(BUILD)/fast PACK_FLAGS="--search 0" CRINKLE_MODE=/COMPMODE:FAST linux windows > $(BUILD)/fast/make.log 2>&1 || { tail -20 $(BUILD)/fast/make.log; exit 1; }
	@stat -c "%n %s" $(BUILD)/fast/kilocrypt $(BUILD)/fast/kilocrypt.exe

WIN_CFLAGS = --target=i686-pc-windows-msvc $(CFLAGS_COMMON) -Oz -msse4.2 -mno-stack-arg-probe -ffunction-sections -fdata-sections -fno-builtin
WIN_LIBS = kernel32 user32 gdi32 opengl32 winmm
CRINKLER = WINE_CPU_TOPOLOGY=4:0,1,2,3 wine tools/crinkler/Crinkler.exe
CRINKLER_TOPOLOGIES = 4:0,1,2,3 16:0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15 8:0,1,2,3,4,5,6,7 6:0,1,2,3,4,5 12:0,1,2,3,4,5,6,7,8,9,10,11
CRINKLE_MODE = /COMPMODE:VERYSLOW /ORDERTRIES:300 /SATURATE /REUSE:tools/crinkler.reuse /REUSEMODE:MODELS
CRINKLE = /ENTRY:entry /SUBSYSTEM:WINDOWS /LARGEADDRESSAWARE $(CRINKLE_MODE) /HASHTRIES:0 /UNSAFEIMPORT /TINYIMPORT
CRINKLER_FLAGS = $(CRINKLE) /REPORT:$(BUILD)/crinkler-report.html /LIBPATH:$(BUILD)
WINHOST ?=

.PHONY: windows windows-dev windows-diag windows-remote

$(BUILD)/windows-dev.obj: src/windows.c $(BUILD)/shader.h
	$(CC) $(WIN_CFLAGS) -DDEV -c $< -o $@

windows-dev: $(BUILD)/windows-dev.obj $(WIN_LIBS:%=$(BUILD)/%.lib) tools/crinkler/Crinkler.exe
	$(CRINKLER) /ENTRY:entry /SUBSYSTEM:WINDOWS /LARGEADDRESSAWARE /COMPMODE:INSTANT /LIBPATH:$(BUILD) /OUT:$(BUILD)/windows-dev.exe $< $(WIN_LIBS:%=%.lib)

$(BUILD)/windows-diag.obj: src/windows.c $(BUILD)/shader.h
	$(CC) $(WIN_CFLAGS) -DDIAG -c $< -o $@

windows-diag: $(BUILD)/windows-diag.obj $(WIN_LIBS:%=$(BUILD)/%.lib) tools/crinkler/Crinkler.exe
	$(CRINKLER) /ENTRY:entry /SUBSYSTEM:WINDOWS /LARGEADDRESSAWARE /COMPMODE:INSTANT /LIBPATH:$(BUILD) /OUT:$(BUILD)/kilocrypt-diag.exe $< $(WIN_LIBS:%=%.lib)

$(BUILD)/%.lib: tools/winlibs/%.def
	@mkdir -p $(BUILD)
	llvm-dlltool -m i386 -k -d $< -l $@

$(BUILD)/windows.obj: src/windows.c $(BUILD)/shader.h
	$(CC) $(WIN_CFLAGS) -c $< -o $@

tools/crinkler/Crinkler.exe:
	tools/fetch_crinkler.sh

$(BUILD)/kilocrypt.exe: $(BUILD)/windows.obj $(WIN_LIBS:%=$(BUILD)/%.lib) tools/crinkler/Crinkler.exe Makefile $(wildcard tools/crinkler.reuse)
	for topology in $(CRINKLER_TOPOLOGIES); do WINE_CPU_TOPOLOGY=$$topology wine tools/crinkler/Crinkler.exe $(CRINKLER_FLAGS) /OUT:$@ $< $(WIN_LIBS:%=%.lib) && test -s $@ && break; rm -f dump*_mini.dmp dump*_full.dmp $@; done; test -s $@

windows: $(BUILD)/kilocrypt.exe
	@ls -l $<

windows-remote: $(BUILD)/windows.obj $(WIN_LIBS:%=$(BUILD)/%.lib) tools/crinkler/Crinkler.exe
	@test -n "$(WINHOST)" || { echo "set WINHOST=user@host (a Windows machine with OpenSSH)"; exit 1; }
	ssh $(WINHOST) "if not exist kilocrypt-build mkdir kilocrypt-build"
	scp -q tools/crinkler/Crinkler.exe $(BUILD)/windows.obj $(WIN_LIBS:%=$(BUILD)/%.lib) $(WINHOST):kilocrypt-build/
	ssh $(WINHOST) "cd kilocrypt-build && start \"\" /low /b /wait Crinkler.exe $(CRINKLE) /LIBPATH:. /OUT:kilocrypt.exe windows.obj $(WIN_LIBS:%=%.lib)"
	scp -q $(WINHOST):kilocrypt-build/kilocrypt.exe $(BUILD)/kilocrypt.exe
	@ls -l $(BUILD)/kilocrypt.exe
