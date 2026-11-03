# Spike 01: V4L2 stateful decoder client. Cross-builds a static arm64 binary for the Frame.
#   make                 aarch64-linux-gnu-gcc, static (runs on the read-only SteamOS as is)
#   make CC=gcc          host build, for a compile/warning check only
#   make deploy          scp the binary to the Frame (host 'frame', see ~/.ssh/config)

CC      ?= aarch64-linux-gnu-gcc
# make's built-in default for CC is 'cc'; treat that as "not set".
ifeq ($(origin CC),default)
CC      := aarch64-linux-gnu-gcc
endif
CFLAGS  ?= -O2 -g
CFLAGS  += -Wall -Wextra -std=gnu11 -pthread
LDFLAGS += -static -pthread
FRAME   ?= frame
BIN     := v4l2dec

all: $(BIN)

$(BIN): v4l2dec.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

deploy: $(BIN)
	scp $(BIN) $(FRAME):~/v4l2dec

clean:
	rm -f $(BIN)

.PHONY: all deploy clean
