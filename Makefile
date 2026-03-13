# Makefile — Install OKnav SSH orchestration system
# BCS1212 compliant

PREFIX   ?= /usr/local
BINDIR   ?= $(PREFIX)/bin
SHAREDIR ?= $(PREFIX)/share/oknav
MANDIR   ?= $(PREFIX)/share/man/man1
COMPDIR  ?= /etc/bash_completion.d
CONFDIR  ?= /etc/oknav
DESTDIR  ?=

VERSION := $(shell grep '^declare -r VERSION=' common.inc.sh | cut -d= -f2)
SCRIPTS := oknav ok_master
SOURCES := $(SCRIPTS) common.inc.sh

.PHONY: all install uninstall check test lint help

all: help

install:
	install -d $(DESTDIR)$(SHAREDIR)
	install -m 755 oknav $(DESTDIR)$(SHAREDIR)/oknav
	install -m 755 ok_master $(DESTDIR)$(SHAREDIR)/ok_master
	install -m 644 common.inc.sh $(DESTDIR)$(SHAREDIR)/common.inc.sh
	printf '%s\n' '$(VERSION)' > $(DESTDIR)$(SHAREDIR)/VERSION
	install -d $(DESTDIR)$(BINDIR)
	ln -sf $(SHAREDIR)/oknav $(DESTDIR)$(BINDIR)/oknav
	ln -sf $(SHAREDIR)/ok_master $(DESTDIR)$(BINDIR)/ok_master
	install -d $(DESTDIR)$(CONFDIR)
	@if [ ! -f $(DESTDIR)$(CONFDIR)/hosts.conf ]; then \
	  install -m 644 hosts.conf.example $(DESTDIR)$(CONFDIR)/hosts.conf; \
	fi
	install -d $(DESTDIR)$(MANDIR)
	install -m 644 oknav.1 $(DESTDIR)$(MANDIR)/oknav.1
	@if [ -d $(DESTDIR)$(COMPDIR) ]; then \
	  install -m 644 oknav.bash_completion $(DESTDIR)$(COMPDIR)/oknav; \
	fi
	@if [ -z "$(DESTDIR)" ] && [ -f $(CONFDIR)/hosts.conf ]; then \
	  $(BINDIR)/oknav install 2>/dev/null || true; \
	fi
	@if [ -z "$(DESTDIR)" ]; then $(MAKE) --no-print-directory check; fi

uninstall:
	@for link in $(DESTDIR)$(BINDIR)/*; do \
	  [ -L "$$link" ] || continue; \
	  case $$(readlink "$$link") in \
	    $(SHAREDIR)/ok_master) rm -f "$$link" ;; \
	  esac; \
	done
	rm -f $(DESTDIR)$(BINDIR)/oknav
	rm -f $(DESTDIR)$(BINDIR)/ok_master
	rm -f $(DESTDIR)$(MANDIR)/oknav.1
	rm -f $(DESTDIR)$(COMPDIR)/oknav
	rm -rf $(DESTDIR)$(SHAREDIR)

check:
	@command -v oknav >/dev/null 2>&1 \
	  && echo 'oknav: OK' \
	  || echo 'oknav: NOT FOUND (check PATH)'
	@command -v ok_master >/dev/null 2>&1 \
	  && echo 'ok_master: OK' \
	  || echo 'ok_master: NOT FOUND (check PATH)'

test:
	bats tests/

lint:
	shellcheck -x $(SOURCES)

help:
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@echo '  install     Install to $(PREFIX)'
	@echo '  uninstall   Remove installed files'
	@echo '  check       Verify installation'
	@echo '  test        Run test suite'
	@echo '  lint        Run shellcheck'
	@echo '  help        Show this message'
	@echo ''
	@echo 'Variables:'
	@echo '  PREFIX=$(PREFIX)  DESTDIR=$(DESTDIR)'
