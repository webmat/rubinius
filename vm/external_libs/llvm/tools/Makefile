##===- tools/Makefile --------------------------------------*- Makefile -*-===##
# 
#                     The LLVM Compiler Infrastructure
#
# This file is distributed under the University of Illinois Open Source
# License. See LICENSE.TXT for details.
# 
##===----------------------------------------------------------------------===##

LEVEL := ..
# NOTE: The tools are organized into five groups of four consisting of one 
# large and three small executables. This is done to minimize memory load 
# in parallel builds.  Please retain this ordering.
PARALLEL_DIRS := llvm-config  \
                 opt llvm-as llvm-dis \
                 llc llvm-ranlib llvm-ar llvm-nm \
                 llvm-ld llvm-prof llvm-link \
		 lli gccas gccld llvm-extract llvm-db \
		 bugpoint llvm-bcanalyzer llvm-stub llvmc2


include $(LEVEL)/Makefile.config

# Disable liblto as it is going away
#PARALLEL_DIRS += lto

# only build new lto project on Darwin for now
ifeq ($(OS),Darwin)
PARALLEL_DIRS += lto2
endif

include $(LEVEL)/Makefile.common
