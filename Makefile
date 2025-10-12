EXCLUDE_MODS := IO::Tty IO::Pty

HAM_PL  ?= ham.pl
SRC_DIR ?= .

all: $(HAM_PL)

clean:
	rm -f $(HAM_PL) .ham.d ham.par

ham.par: $(SRC_DIR)/ham
	pp -vvv $(addprefix-X ,$(EXCLUDE_MODS)) -M Hammer::Changes::Gerrit -p -o $@ $< | grep -E "adding\s+/" | cut -f 4 -d' ' | xargs echo $@: >.ham.d

$(HAM_PL): ham.par $(SRC_DIR)/par-archive
	$(SRC_DIR)/par-archive -b -O$@ $<

-include .ham.d
