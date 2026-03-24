# Makefile - Build DOOM for PicoRV32 FPGA SoC
#
# Reference: doomgeneric/Makefile (source file list, compiler flags)
# Reference: smunaut doom_riscv Makefile (RISC-V cross-compilation)

# Toolchain
CROSS = riscv-none-elf-
CC = $(CROSS)gcc
AS = $(CROSS)as
LD = $(CROSS)ld
OBJCOPY = $(CROSS)objcopy
SIZE = $(CROSS)size

# Architecture — PicoRV32 is RV32IM
ARCH = -march=rv32im -mabi=ilp32

# Doomgeneric source directory
DOOM_DIR = ../../doomgeneric/doomgeneric

# Compiler flags
# Reference: doomgeneric/Makefile -DNORMALUNIX -DLINUX flags
# CMAP256: use 8-bit palette-indexed framebuffer (matches our hardware)
# DOOMGENERIC_RESX/RESY: native 320x200 (hardware does the doubling)
CFLAGS = $(ARCH) -Os -g
CFLAGS += -ffunction-sections -fdata-sections
CFLAGS += -DCMAP256
CFLAGS += -DDOOMGENERIC_RESX=320 -DDOOMGENERIC_RESY=200
CFLAGS += -DNORMALUNIX -DLINUX -D_DEFAULT_SOURCE
CFLAGS += -I$(DOOM_DIR)
CFLAGS += -std=gnu99
CFLAGS += -Wall -Wno-unused-variable -Wno-unused-function

# Linker flags
# Reference: smunaut doom_riscv Makefile - nano.specs for newlib-nano malloc/realloc
LDFLAGS = $(ARCH) -T doom.ld -nostartfiles --specs=nano.specs
LDFLAGS += -Wl,--gc-sections
LDFLAGS += -lm -lc -lgcc

# OS detection - pick the right shell commands
ifeq ($(OS),Windows_NT)
    RMDIR   = cmd /c if exist "$(OBJDIR)" rmdir /s /q "$(OBJDIR)"
    RMFILES = cmd /c del /f /q 2>nul
    MKDIR   = cmd /c if not exist "$(OBJDIR)" mkdir "$(OBJDIR)"
else
    RMDIR   = rm -rf $(OBJDIR)
    RMFILES = rm -f
    MKDIR   = mkdir -p $(OBJDIR)
endif

# Output
OUTPUT = doom

# ---- Source files ----

# crt0 + platform files (our code)
PLATFORM_SRC = crt0.S syscalls.c main.c doomgeneric_riscv.c w_file_memory.c

# DOOM engine sources from doomgeneric
# Reference: doomgeneric/Makefile SRC_DOOM list
DOOM_SRC = \
	dummy.c am_map.c doomdef.c doomstat.c dstrings.c \
	d_event.c d_items.c d_iwad.c d_loop.c d_main.c d_mode.c d_net.c \
	f_finale.c f_wipe.c g_game.c hu_lib.c hu_stuff.c \
	info.c i_cdmus.c i_endoom.c i_joystick.c i_scale.c \
	i_sound.c i_system.c i_timer.c i_video.c i_input.c \
	memio.c m_argv.c m_bbox.c m_cheat.c m_config.c m_controls.c \
	m_fixed.c m_menu.c m_misc.c m_random.c mus2mid.c \
	p_ceilng.c p_doors.c p_enemy.c p_floor.c p_inter.c p_lights.c \
	p_map.c p_maputl.c p_mobj.c p_plats.c p_pspr.c p_saveg.c \
	p_setup.c p_sight.c p_spec.c p_switch.c p_telept.c p_tick.c p_user.c \
	r_bsp.c r_data.c r_draw.c r_main.c r_plane.c r_segs.c \
	r_sky.c r_things.c sha1.c sounds.c statdump.c \
	st_lib.c st_stuff.c s_sound.c tables.c v_video.c \
	wi_stuff.c w_checksum.c w_file.c w_main.c w_wad.c \
	z_zone.c doomgeneric.c \
	gusconf.c

# NOTE: w_file_stdc.c is intentionally excluded — replaced by w_file_memory.c
# NOTE: doomgeneric_xlib.c excluded — replaced by doomgeneric_riscv.c

# Object directory
OBJDIR = build

# Build object lists
PLATFORM_OBJS = $(addprefix $(OBJDIR)/, $(patsubst %.S,%.o,$(patsubst %.c,%.o,$(PLATFORM_SRC))))
DOOM_OBJS = $(addprefix $(OBJDIR)/, $(patsubst %.c,%.o,$(DOOM_SRC)))
OBJS = $(PLATFORM_OBJS) $(DOOM_OBJS)

# ---- Rules ----

all: $(OUTPUT).bin
	@echo "  DOOM binary: $(OUTPUT).bin"
	@$(SIZE) $(OUTPUT).elf

$(OUTPUT).bin: $(OUTPUT).elf
	$(OBJCOPY) -O binary $< $@

$(OUTPUT).elf: $(OBJS)
	@echo "[Linking $@]"
	$(CC) $(LDFLAGS) $(OBJS) -o $@

$(OBJS): | $(OBJDIR)

$(OBJDIR):
	$(MKDIR)

# Platform sources (in current directory)
$(OBJDIR)/%.o: %.c
	@echo "[CC] $<"
	@$(CC) $(CFLAGS) -c $< -o $@

$(OBJDIR)/%.o: %.S
	@echo "[AS] $<"
	@$(CC) $(ARCH) -c $< -o $@

# DOOM sources (in doomgeneric directory)
$(OBJDIR)/%.o: $(DOOM_DIR)/%.c
	@echo "[CC] $<"
	@$(CC) $(CFLAGS) -c $< -o $@

clean:
	$(RMDIR)
	$(RMFILES) $(OUTPUT).elf $(OUTPUT).bin

.PHONY: all clean