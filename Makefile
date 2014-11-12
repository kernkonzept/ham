-include .ham.d

ham.pl: ham
	pp -vvv -c -n -d -P -o $@ $< | grep -E "adding\s+/" | cut -f 4 -d' ' | xargs echo $@: >.ham.d
