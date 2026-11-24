PREFIX?= /usr/local
BINDIR?= $(PREFIX)/bin
MANDIR?= $(PREFIX)/share/man/man8
DESTDIR?=

.PHONY: all install test clean

all:
	@printf '%s\n' 'Nothing to build; run sudo make install.'

install:
	install -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(MANDIR)
	install -m 0555 brcm-fbsd-configurator $(DESTDIR)$(BINDIR)/brcm-fbsd-configurator
	install -m 0444 brcm-fbsd-configurator.8 $(DESTDIR)$(MANDIR)/brcm-fbsd-configurator.8

test:
	sh tests/run.sh

clean:
	@printf '%s\n' 'No build artifacts to clean.'
