CC   := gcc
KDIR ?= /lib/modules/$(shell uname -r)/build

BIN    := bin
CFLAGS := -g -Wall -std=c11 -D_GNU_SOURCE

APP_SOURCES := $(wildcard app/conv/*.c) $(wildcard app/lib/*.c)
ALL_SOURCES := \
  $(wildcard app/conv/*.c) $(wildcard app/conv/*.h) \
  $(wildcard app/lib/*.c) $(wildcard app/lib/*.h) \
  $(wildcard include/*.h) "driver/gowin_pcie_drv.c"

.PHONY: all app module format lint clean

all: app module

app: $(BIN)/conv

$(BIN)/conv: $(APP_SOURCES)
	$(CC) $(CFLAGS) -o $@ $^

module:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/driver modules

format:
	clang-format --dry-run --verbose --Werror $(ALL_SOURCES)

lint:
	clang-tidy -checks='clang-analyzer-*' $(APP_SOURCES) -- $(CFLAGS)

clean:
	rm -f $(BIN)/conv
	-$(MAKE) -C $(KDIR) M=$(CURDIR)/driver clean
