# ============================================================
# XQuest 2 for Sega Genesis - SGDK 1.70 Makefile
# ============================================================
#
# Requirements:
#   - SGDK 1.70 installed, SGDK env var set: export SGDK=/opt/sgdk
#   - Java (for rescomp)
#   - m68k-elf-gcc toolchain
#
# Usage:
#   make          - build ROM
#   make clean    - clean build artifacts
#   make run      - build and launch in BlastEm emulator

# Path to SGDK installation
ifndef SGDK
  SGDK := /opt/sgdk
endif

# Project name
ROM_NAME := xquest2

# Source directories
SRC_DIR  := src
INC_DIR  := inc
RES_DIR  := res
OUT_DIR  := out

# SGDK tools
GDK      := $(SGDK)
GDK_LIB  := $(GDK)/lib
RESCOMP  := java -jar $(GDK)/bin/rescomp.jar

# Toolchain
CC       := m68k-elf-gcc
AS       := m68k-elf-as
LD       := m68k-elf-ld
OBJCOPY  := m68k-elf-objcopy
NM       := m68k-elf-nm

# Flags
CFLAGS   := -m68000 -Wall -Wextra -O2 \
            -fomit-frame-pointer -fno-builtin \
            -I$(GDK)/inc \
            -I$(INC_DIR) \
            -I$(OUT_DIR)

LDFLAGS  := -T $(GDK)/md.ld \
            -L$(GDK_LIB) \
            -lmd -lsgdk

# Source files
C_SRCS   := $(wildcard $(SRC_DIR)/*.c)
C_OBJS   := $(C_SRCS:$(SRC_DIR)/%.c=$(OUT_DIR)/%.o)

# Resource file
RES_FILE := $(RES_DIR)/resources.res
RES_OUT  := $(OUT_DIR)/resources.o
RES_H    := $(OUT_DIR)/resources.h

# ============================================================
.PHONY: all clean run

all: $(OUT_DIR)/$(ROM_NAME).bin

# Create output directory
$(OUT_DIR):
	mkdir -p $(OUT_DIR)

# Compile resources
$(RES_OUT) $(RES_H): $(RES_FILE) | $(OUT_DIR)
	$(RESCOMP) $(RES_FILE) $(RES_OUT) -dep $(OUT_DIR)/resources.d

# Compile C sources
$(OUT_DIR)/%.o: $(SRC_DIR)/%.c $(RES_H) | $(OUT_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

# Link
$(OUT_DIR)/$(ROM_NAME).elf: $(C_OBJS) $(RES_OUT)
	$(CC) $(CFLAGS) $^ $(LDFLAGS) -o $@

# Strip to binary ROM
$(OUT_DIR)/$(ROM_NAME).bin: $(OUT_DIR)/$(ROM_NAME).elf
	$(OBJCOPY) -O binary $< $@
	@echo ""
	@echo "=========================================="
	@echo " ROM built: $(OUT_DIR)/$(ROM_NAME).bin"
	@echo " Size: $$(du -h $(OUT_DIR)/$(ROM_NAME).bin | cut -f1)"
	@echo "=========================================="

# Run in emulator (BlastEm)
run: all
	blastem $(OUT_DIR)/$(ROM_NAME).bin

clean:
	rm -rf $(OUT_DIR)
