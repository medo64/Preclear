#~ Rust Project

.SILENT:
.NOTPARALLEL:
.ONESHELL:

all clean run debug release ~clean ~run ~debug ~release &:
	./Make.sh $(MAKECMDGOALS)
