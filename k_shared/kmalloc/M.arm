KERNEL_DIR ?= $(OUTDIR)
obj-m := ioremap_demo.o
CFLAG := -Wall -Wno-error 
modules:
	$(MAKE) $(CFLAG) -C $(KERNEL_DIR) M=$(PWD) modules 
clean: 
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean
install:         
	cp *.ko $(KERNEL_DIR)/kmodules


