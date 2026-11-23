BUILDROOT_DIR ?= $(CURDIR)/../keystone/buildroot
BUILDROOT_REV := c92cc8796ed951f0604e9272677a9cdfcd93680f
BUILD_DIR ?= $(CURDIR)/build
OUT_DIR ?= $(BUILD_DIR)/buildroot
OVERLAY_DIR ?= $(BUILD_DIR)/overlay
SDK_WORK ?= $(BUILD_DIR)/sdk
DRV_WORK ?= $(BUILD_DIR)/penglai-enclave-driver
QEMU_DIR ?= $(BUILD_DIR)/qemu
QEMU_SRC := $(CURDIR)/riscv-qemu
QEMU_BIN := $(QEMU_DIR)/riscv64-softmmu/qemu-system-riscv64
LINUX_SRC := $(CURDIR)/linux
OPENSBI_SRC := $(CURDIR)/opensbi
SDK_SRC := $(CURDIR)/sdk
DRV_SRC := $(CURDIR)/penglai-enclave-driver
LINUX_DIR := $(OUT_DIR)/build/linux-custom
TARGET_CROSS := $(OUT_DIR)/host/bin/riscv64-buildroot-linux-gnu-
TARGET_CC := $(TARGET_CROSS)gcc
TARGET_AR := $(TARGET_CROSS)ar
EAPP_CFLAGS = -nostdinc -march=rv64imac -mabi=lp64 \
	-isystem $$(riscv64-unknown-elf-gcc -print-file-name=include) \
	-I$(SDK_WORK)/musl/arch/riscv64 -I$(SDK_WORK)/musl/arch/generic \
	-I$(SDK_WORK)/musl/obj/include -I$(SDK_WORK)/musl/include \
	-I$(SDK_WORK)/lib/app/include -Wall -g
JOBS ?= $(shell nproc)
export FORCE_UNSAFE_CONFIGURE=1

.PHONY: all build config sdk qemu-build run-qemu

all: build

$(BUILD_DIR)/local.mk: Makefile
	mkdir -p "$(BUILD_DIR)"
	printf 'LINUX_OVERRIDE_SRCDIR = %s\nOPENSBI_OVERRIDE_SRCDIR = %s\n' "$(LINUX_SRC)" "$(OPENSBI_SRC)" > "$@"

$(OUT_DIR)/.config: $(CURDIR)/configs/spmp_defconfig $(CURDIR)/configs/linux_defconfig $(BUILD_DIR)/local.mk
	@test "$$(git -c safe.directory="$(abspath $(BUILDROOT_DIR))" -C "$(BUILDROOT_DIR)" rev-parse HEAD)" = "$(BUILDROOT_REV)" || { echo "Buildroot must be initialized at $(BUILDROOT_REV)" >&2; exit 1; }
	@git -c safe.directory="$(abspath $(BUILDROOT_DIR))" -C "$(BUILDROOT_DIR)" diff --quiet HEAD -- . || { echo "Pinned Buildroot source has tracked local changes." >&2; exit 1; }
	mkdir -p "$(OVERLAY_DIR)"
	$(MAKE) -C "$(BUILDROOT_DIR)" O="$(OUT_DIR)" BR2_DEFCONFIG="$(CURDIR)/configs/spmp_defconfig" defconfig
	"$(BUILDROOT_DIR)/utils/config" --file "$(OUT_DIR)/.config" \
		--set-str BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE "$(CURDIR)/configs/linux_defconfig" \
		--set-str BR2_PACKAGE_OVERRIDE_FILE "$(BUILD_DIR)/local.mk" \
		--set-str BR2_ROOTFS_OVERLAY "$(OVERLAY_DIR)"
	$(MAKE) -C "$(BUILDROOT_DIR)" O="$(OUT_DIR)" olddefconfig

config: $(OUT_DIR)/.config

$(BUILD_DIR)/.base.stamp: $(OUT_DIR)/.config
	$(MAKE) -C "$(BUILDROOT_DIR)" O="$(OUT_DIR)" -j$(JOBS) toolchain linux opensbi
	touch "$@"

$(BUILD_DIR)/.sdk.stamp: $(BUILD_DIR)/.base.stamp
	mkdir -p "$(SDK_WORK)" "$(DRV_WORK)"
	rsync -a --delete --exclude=.git "$(SDK_SRC)/" "$(SDK_WORK)/"
	rsync -a --delete --exclude=.git "$(DRV_SRC)/" "$(DRV_WORK)/"
	find "$(SDK_WORK)" "$(DRV_WORK)" -type f \( -name '*.o' -o -name '*.a' -o -name '*.ko' \) -delete
	PATH="$(OUT_DIR)/host/bin:$$PATH" $(MAKE) -C "$(LINUX_DIR)" ARCH=riscv CROSS_COMPILE="$(TARGET_CROSS)" M="$(DRV_WORK)" -j$(JOBS) modules
	cd "$(SDK_WORK)/musl" && CC=riscv64-unknown-elf-gcc CFLAGS="-march=rv64imac -mabi=lp64" ./configure --disable-shared --target=riscv64
	PENGLAI_SDK="$(SDK_WORK)" $(MAKE) -C "$(SDK_WORK)/musl" -j$(JOBS) CC=riscv64-unknown-elf-gcc CROSS_COMPILE=riscv64-unknown-elf- AR=riscv64-unknown-elf-ar RANLIB=riscv64-unknown-elf-ranlib CFLAGS="-march=rv64imac -mabi=lp64"
	PENGLAI_SDK="$(SDK_WORK)" $(MAKE) -C "$(SDK_WORK)/lib/app" -j$(JOBS) CC=riscv64-unknown-elf-gcc AR=riscv64-unknown-elf-ar GCC=riscv64-unknown-elf-gcc CFLAGS="$(EAPP_CFLAGS)"
	PENGLAI_SDK="$(SDK_WORK)" $(MAKE) -C "$(SDK_WORK)/lib/host" -j$(JOBS) GCC="$(TARGET_CC)" ARC="$(TARGET_AR)" GCCFLAGS="-Wall -Werror -shared -fPIC -I include/"
	PENGLAI_SDK="$(SDK_WORK)" $(MAKE) -C "$(SDK_WORK)/demo/prime" -j$(JOBS) CC=riscv64-unknown-elf-gcc LINK=riscv64-unknown-elf-ld AR=riscv64-unknown-elf-ar CFLAGS="$(EAPP_CFLAGS)"
	PENGLAI_SDK="$(SDK_WORK)" $(MAKE) -C "$(SDK_WORK)/demo/host" -j$(JOBS) CC="$(TARGET_CC)"
	KVER="$$(PATH="$(OUT_DIR)/host/bin:$$PATH" $(MAKE) -s -C "$(LINUX_DIR)" ARCH=riscv CROSS_COMPILE="$(TARGET_CROSS)" kernelrelease)"; \
	install -D -m 0644 "$(DRV_WORK)/penglai.ko" "$(OVERLAY_DIR)/lib/modules/$$KVER/extra/penglai.ko"; \
	install -D -m 0644 "$(DRV_WORK)/penglai.ko" "$(OUT_DIR)/target/lib/modules/$$KVER/extra/penglai.ko"
	install -D -m 0755 "$(SDK_WORK)/demo/host/host" "$(OVERLAY_DIR)/usr/share/penglai/spmp/host"
	install -D -m 0644 "$(SDK_WORK)/demo/prime/prime" "$(OVERLAY_DIR)/usr/share/penglai/spmp/prime"
	touch "$@"

sdk: $(BUILD_DIR)/.sdk.stamp

$(OUT_DIR)/images/rootfs.ext2: $(BUILD_DIR)/.sdk.stamp
	$(MAKE) -C "$(BUILDROOT_DIR)" O="$(OUT_DIR)" -j$(JOBS)

$(QEMU_DIR)/config-host.mak:
	mkdir -p "$(QEMU_DIR)"
	cd "$(QEMU_DIR)" && "$(QEMU_SRC)/configure" --target-list=riscv64-softmmu \
		--disable-werror --disable-docs --disable-capstone --disable-git-update \
		--disable-gtk --disable-sdl

$(QEMU_BIN): $(QEMU_DIR)/config-host.mak
	$(MAKE) -C "$(QEMU_DIR)" -j$(JOBS) riscv64-softmmu/all

qemu-build: $(QEMU_BIN)

build: $(OUT_DIR)/images/rootfs.ext2 $(QEMU_BIN)

run-qemu: build
	"$(QEMU_BIN)" -nographic -M virt -m "$(or $(MEMORY),2G)" -smp "$(or $(CPUS),1)" \
		-bios "$(OUT_DIR)/images/fw_jump.bin" -kernel "$(OUT_DIR)/images/Image" \
		-drive file="$(OUT_DIR)/images/rootfs.ext2",format=raw,id=hd0 -device virtio-blk-device,drive=hd0 \
		-netdev user,id=net0 -device virtio-net-device,netdev=net0 \
		-append "root=/dev/vda rw console=ttyS0"
