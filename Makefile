#~ Rust Project

.SILENT:
.NOTPARALLEL:
.ONESHELL:

all clean run debug release ~clean ~run ~debug ~release package publish &:
	./Make.sh $(MAKECMDGOALS)
