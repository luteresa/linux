make -C ../../../out/ M=$PWD modules
make -C ../../../out/ M=$PWD clean
aarch64-linux-gnu-gcc -O2 -Wall -static -o cma_demo_test cma_demo_test.c
