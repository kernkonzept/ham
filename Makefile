EXCLUDE_MODS := IO::Tty IO::Pty

all: ham.pl

ham.par: ham
	pp -vvv $(addprefix-X ,$(EXCLUDE_MODS)) -p -o $@ $< | grep -E "adding\s+/" | cut -f 4 -d' ' | xargs echo $@: >.ham.d

ham.pl: ham.par par-archive
	./par-archive -b -O$@ $<

-include .ham.d
