PREFIX?=/usr/local
BINDIR?=$(PREFIX)/bin
MANDIR?=$(PREFIX)/share/man
C3C?=c3c
SCDOC?=scdoc
.DEFAULT_GOAL=all

all: build/c3f

build/c3f: project.json c3l.lock $(wildcard src/*/*.c3) $(wildcard lib/*.c3l)
	$(C3C) build c3f $(C3FLAGS)

# c3f.1 is committed, so that installing needs no scdoc
c3f.1: c3f.1.scd
	$(SCDOC) < $< > $@

doc: c3f.1

test:
	$(C3C) test $(C3FLAGS)

check: build/c3f
	build/c3f --check src test tools

gitconfig:
	ln -s ../../contrib/pre-commit .git/hooks/pre-commit

clean:
	rm -rf build

install: all
	mkdir -p $(DESTDIR)$(BINDIR) $(DESTDIR)$(MANDIR)/man1
	install -m755 build/c3f $(DESTDIR)$(BINDIR)/c3f
	install -m644 c3f.1 $(DESTDIR)$(MANDIR)/man1/c3f.1

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/c3f $(DESTDIR)$(MANDIR)/man1/c3f.1

.PHONY: all doc test check gitconfig clean install uninstall
