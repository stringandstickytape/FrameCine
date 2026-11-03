# Spike 04: the Q10C probe. Builds in WSL:
#   make              q10c-probe (aarch64, for the headset; dynamic glibc, dlopen()s libvulkan.so.1)
#   make host         q10c-probe-x86_64 (for the self-test with lavapipe on the PC)
#   make shader       convert.spv.h from convert.comp (needs glslangValidator; the header is committed)
# The Vulkan headers come from the engine fork's thirdparty copy (VULKAN_INCLUDE).

CROSS_CC      ?= aarch64-linux-gnu-gcc
HOST_CC       ?= gcc
VULKAN_INCLUDE ?= $(HOME)/src/godot-player/thirdparty/vulkan/include
GLSLANG       ?= $(shell command -v glslangValidator || echo $(HOME)/.local/glslang-pkg/root/usr/bin/glslangValidator)
CFLAGS        ?= -O2 -g
CFLAGS        += -Wall -Wextra -Wno-unused-parameter -std=gnu11 -I$(VULKAN_INCLUDE) -I.
LDLIBS        += -ldl -lm

all: q10c-probe

q10c-probe: q10c_probe.c convert.spv.h
	$(CROSS_CC) $(CFLAGS) -o $@ q10c_probe.c $(LDLIBS)

host: q10c-probe-x86_64

q10c-probe-x86_64: q10c_probe.c convert.spv.h
	$(HOST_CC) $(CFLAGS) -o $@ q10c_probe.c $(LDLIBS)

shader: convert.spv.h

convert.spv.h: convert.comp
	$(GLSLANG) -V --target-env vulkan1.1 --vn convert_spv -o $@ convert.comp

clean:
	rm -f q10c-probe q10c-probe-x86_64

.PHONY: all host shader clean
