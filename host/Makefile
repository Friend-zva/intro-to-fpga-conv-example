CC   := gcc
KDIR ?= /lib/modules/$(shell uname -r)/build

BIN    := bin
CFLAGS := -g -Wall -std=c11 -D_GNU_SOURCE

.PHONY: all app module clean

all: app module

app: $(BIN)/conv

$(BIN)/conv: $(wildcard app/conv/*.c) $(wildcard app/lib/*.c)
	$(CC) $(CFLAGS) -o $@ $^

module:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/driver modules

clean:
	rm -f $(BIN)/conv
	-$(MAKE) -C $(KDIR) M=$(CURDIR)/driver clean
