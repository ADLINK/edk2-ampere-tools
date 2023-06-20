# @file
#
# Copyright (c) 2020-2021, Ampere Computing LLC.
#
# SPDX-License-Identifier: ISC
#
# EDK2 Makefile
#
SHELL := /bin/bash

# Default Input variables
ATF_TBB ?= 1
BUILD_LINUXBOOT ?= 0

BOARD_NAME ?= jade
BOARD_NAME_SRC := Jade
BOARD_NAME_UPPER := $(shell echo $(BOARD_NAME) | tr a-z A-Z)
BOARD_NAME_UFL := $(shell echo $(BOARD_NAME) | sed 's/.*/\u&/')

# Directory variables
CUR_DIR := $(PWD)
SCRIPTS_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
ROOT_DIR := $(shell dirname $(SCRIPTS_DIR))

EDK2_SRC_DIR := $(ROOT_DIR)/edk2
EDK2_NON_OSI_SRC_DIR := $(ROOT_DIR)/edk2-non-osi
EDK2_PLATFORMS_SRC_DIR := $(ROOT_DIR)/edk2-platforms
EDK2_FEATURES_INTEL_DIR := $(EDK2_PLATFORMS_SRC_DIR)/Features/Intel
EDK2_PLATFORMS_PKG_DIR := $(EDK2_PLATFORMS_SRC_DIR)/Platform/Ampere/$(BOARD_NAME_UFL)Pkg
REQUIRE_EDK2_SRC := $(EDK2_SRC_DIR) $(EDK2_PLATFORMS_SRC_DIR)$(if $(wildcard $(EDK2_NON_OSI_SRC_DIR)), $(EDK2_NON_OSI_SRC_DIR),) $(EDK2_FEATURES_INTEL_DIR)
WORK_LINUXBOOT_BIN := $(EDK2_PLATFORMS_SRC_DIR)/Platform/Ampere/LinuxBootPkg/AArch64/flashkernel
ATF_TOOLS_DIR := $(SCRIPTS_DIR)/toolchain/atf-tools
IASL_DIR := $(SCRIPTS_DIR)/toolchain/iasl
EFI_TOOLS_DIR := $(SCRIPTS_DIR)/toolchain/efitools
COMPILER_DIR := $(SCRIPTS_DIR)/toolchain/ampere
AARCH64_TOOLS_DIR := $(COMPILER_DIR)/bin

# Compiler variables
EDK2_GCC_TAG := GCC5
AMPERE_COMPILER_PREFIX := aarch64-ampere-linux-gnu-
ifneq ($(or $(shell $(CROSS_COMPILE)gcc -dumpmachine 2>/dev/null | grep -v ampere | grep aarch64), \
           $(shell $(CROSS_COMPILE)gcc --version 2>/dev/null | grep Ampere | grep dynamic-nosysroot)),)
	COMPILER := $(CROSS_COMPILE)
else
	COMPILER := $(AARCH64_TOOLS_DIR)/$(AMPERE_COMPILER_PREFIX)
endif


NUM_THREADS := $(shell echo $$(( $(shell getconf _NPROCESSORS_ONLN) + $(shell getconf _NPROCESSORS_ONLN))))

# Tools variables
IASL := iasl
FIPTOOL := fiptool
CERTTOOL := cert_create
CERT_TO_EFI_SIG_LIST:=cert-to-efi-sig-list
SIGN_EFI_SIG_LIST:=sign-efi-sig-list
NVGENCMD := python $(SCRIPTS_DIR)/nvparam.py
EXECUTABLES := openssl git cut sed awk wget tar flex bison gcc g++ python3

PARSE_PLATFORMS_TOOL := $(SCRIPTS_DIR)/parse-platforms.py
PLATFORMS_CONFIG := $(SCRIPTS_DIR)/edk2-platforms.config

# Build variant variables
BUILD_VARIANT := $(if $(shell echo $(DEBUG) | grep -w 1),DEBUG,RELEASE)
BUILD_VARIANT_LOWER := $(shell echo $(BUILD_VARIANT) | tr A-Z a-z)
BUILD_VARIANT_UFL := $(shell echo $(BUILD_VARIANT_LOWER) | sed 's/.*/\u&/')

GIT_VER := $(shell cd $(EDK2_PLATFORMS_SRC_DIR) 2>/dev/null && \
			git describe --tags --dirty --long --always | grep ampere | grep -v dirty | cut -d \- -f 1 | cut -d \v -f 2)
# Input VER
VER ?= $(shell echo $(GIT_VER) | cut -d \. -f 1,2)
VER := $(if $(VER),$(VER),0.00)
MAJOR_VER := $(shell echo $(VER) | cut -d \. -f 1 )
MINOR_VER := $(shell echo $(VER) | cut -d \. -f 2 )

# Input BUILD
BUILD ?= $(shell echo $(GIT_VER) | cut -d \. -f 3)
BUILD := $(if $(BUILD),$(BUILD),100)
$(eval BUILD_COM := $(subst .A1,,$(BUILD)))

# iASL version
VER_GT_104 := $(shell [ $(MAJOR_VER)$(MINOR_VER) -gt 104 ] && echo true)
DEFAULT_IASL_VER := $(shell $(PARSE_PLATFORMS_TOOL) -c $(PLATFORMS_CONFIG) -p $(BOARD_NAME_UFL) get -o IASL_VER)
IASL_VER ?= $(if $(VER_GT_104),$(DEFAULT_IASL_VER),20200110)

# efitools version
EFITOOLS_VER := 1.8.1

# File path variables
LINUXBOOT_FMT := $(if $(shell echo $(BUILD_LINUXBOOT) | grep -w 1),_linuxboot,)
OUTPUT_VARIANT := $(if $(shell echo $(DEBUG) | grep -w 1),_debug,)
OUTPUT_BASENAME = $(BOARD_NAME)_tianocore_atf$(LINUXBOOT_FMT)$(OUTPUT_VARIANT)_$(VER).$(BUILD)
$(eval RELEASE_SUBDIR_ := $(subst .A1,,$(OUTPUT_BASENAME)))
$(eval RELEASE_SUBDIR := $(subst _tianocore_atf,,$(RELEASE_SUBDIR_)))

OUTPUT_BIN_DIR := $(if $(DEST_DIR),$(DEST_DIR),$(CUR_DIR)/BUILDS/$(OUTPUT_BASENAME))

OUTPUT_IMAGE := $(OUTPUT_BIN_DIR)/$(OUTPUT_BASENAME).img
OUTPUT_RAW_IMAGE := $(OUTPUT_BIN_DIR)/$(OUTPUT_BASENAME).img.raw
OUTPUT_FD_IMAGE := $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_tianocore$(LINUXBOOT_FMT)$(OUTPUT_VARIANT)_$(VER).$(BUILD).fd
OUTPUT_BOARD_SETTING_BIN := $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_board_setting.bin

BOARD_SETTING_FILES := $(EDK2_PLATFORMS_PKG_DIR)/$(BOARD_NAME)_board_setting.txt $(EDK2_PLATFORMS_PKG_DIR)/$(BOARD_NAME_UFL)BoardSetting.cfg
BOARD_SETTING ?= $(word 1,$(foreach iter,$(BOARD_SETTING_FILES), $(if $(wildcard $(iter)),$(iter),)))

ATF_MAJOR = $(shell grep -aPo AMPC31.\{0,14\} $(ATF_SLIM) 2>/dev/null | tr -d '\0' | cut -c7 )
ATF_MINOR = $(shell grep -aPo AMPC31.\{0,14\} $(ATF_SLIM) 2>/dev/null | tr -d '\0' | cut -c8-9 )
ATF_BUILD = $(shell grep -aPo AMPC31.\{0,14\} $(ATF_SLIM) 2>/dev/null | tr -d '\0' | cut -c10-17 )
FIRMWARE_VER="$(MAJOR_VER).$(MINOR_VER).$(BUILD) Build $(shell date '+%Y%m%d') ATF $(ATF_MAJOR).$(ATF_MINOR)"

LINUXBOOT_BIN := $(OEM_COMMON_DIR)/tools/flashkernel
PROGRAMMER_TOOL := $(OEM_COMMON_DIR)/tools/dpcmd
POWER_SCRIPT := $(OEM_COMMON_DIR)/tools/target_power.sh
CHECKSUM_TOOL := $(OEM_COMMON_DIR)/tools/checksum

# function to copy output file to virtual machine shared folder
define copy2release
	@mkdir -p $(RELEASE_DIR)/$(RELEASE_SUBDIR)
	$(eval RELEASE_FILE := $(RELEASE_DIR)/$(RELEASE_SUBDIR)/$(notdir $(1)))
	@if [[ -f $(1) ]]; then \
		echo copy to: $(RELEASE_FILE) ; \
		cp -f $(1) $(RELEASE_FILE); \
	fi
	@if [[ "$(RELEASE_FILE)" = *".img" || "$(RELEASE_FILE)" = *".bin" ]]; then \
		$(CHECKSUM_TOOL) $(RELEASE_FILE); \
	fi
endef

define copyNrelease
	$(call copy2release, $(1))
	$(eval INFO_TXT := $(RELEASE_DIR)/$(RELEASE_SUBDIR)/$(notdir $(1)).txt)
	@if [[ ! -z "$(CHECKSUM_TOOL)" ]]; then \
		echo "BIOS BIN FIle : "$(notdir $(1)) > $(INFO_TXT); \
		echo "Release Date  : $(shell date '+%Y/%m/%d')" >> $(INFO_TXT); \
		echo "Release Time  : $(shell date '+%T')" >> $(INFO_TXT); \
		echo "CheckSum      : "$(shell $(CHECKSUM_TOOL) $(RELEASE_FILE) | cut -d ' ' -f 1) >> $(INFO_TXT); \
		echo "POST Message  : "$(FIRMWARE_VER) >> $(INFO_TXT); \
		echo "Size          : 32MB" >> $(INFO_TXT); \
		echo "===============================================================================" >> $(INFO_TXT); \
		cat $(EDK2_PLATFORMS_PKG_DIR)/taglog.txt >> $(INFO_TXT); \
		echo "" >> $(INFO_TXT); \
		echo "===============================================================================" >> $(INFO_TXT); \
	fi
endef

# Targets
define HELP_MSG
Ampere EDK2 Tools
============================================================
Usage: make <Targets> [Options]
Options:
	SCP_SLIM=<Path>         : Path to scp.slim image
	ATF_SLIM=<Path>         : Path to atf.slim image
	LINUXBOOT_BIN=<Path>    : Path to linuxboot binary (flashkernel)
	BOARD_SETTING=<Path>    : Path to board_setting.[txt/bin]
	                          - Default: $(BOARD_NAME)_board_setting.txt
	BUILD=<Build>           : Specify image build id
	                          - Default: 100
	DEST_DIR=<Path>         : Path to output directory
	                          - Default: $(CUR_DIR)/BUILDS
	DEBUG=[0,1]             : Enable debug build
	                          - Default: 0
	VER=<Major.Minor>       : Specify image version
	                          - Default: 0.0
	IASL_VER=<Version>      : Specify iASL compiler version
	                          - Default: $(IASL_VER)
Target:
endef
export HELP_MSG

## help			: Print this help
.PHONY: help
help:
	@echo "$$HELP_MSG"
	@sed -ne '/@sed/!s/## /	/p' $(MAKEFILE_LIST)

## all			: Build all
.PHONY: all
all: tianocore_capsule linuxboot_img

## clean			: Clean basetool and tianocore build
.PHONY: clean
clean:
	@echo "Tianocore clean BaseTools..."
	$(MAKE) -C $(EDK2_SRC_DIR)/BaseTools clean

	@echo "Tianocore clean $(CUR_DIR)/Build..."
	@rm -fr $(CUR_DIR)/Build

	@echo "Ampere Tools clean $(CUR_DIR)/edk2-ampere-tools/toolchain..."
	@rm -fr $(CUR_DIR)/edk2-ampere-tools/toolchain

## linuxboot_img		: Linuxboot image
.PHONY: linuxboot_img
linuxboot_img: _check_linuxboot_bin
	@$(MAKE) -C $(SCRIPTS_DIR) tianocore_img BUILD_LINUXBOOT=1 CUR_DIR=$(CUR_DIR)

_check_source:
	@echo "Checking source...OK"
	$(foreach iter,$(REQUIRE_EDK2_SRC),\
		$(if $(wildcard $(iter)),,$(error "$(iter) not found")))

_check_tools:
	@echo "Checking tools...OK"
	$(foreach iter,$(EXECUTABLES),\
		$(if $(shell which $(iter) 2>/dev/null),,$(error "No $(iter) in PATH")))

_check_compiler:
	@echo "Checking compiler...OK"
# Changes of commit "Remove auto downloading Ampere toolchain b6f7e223" >>>
#ifeq ("$(shell uname -m)", "x86_64")
#	$(if $(shell $(CROSS_COMPILE)gcc -dumpmachine | grep aarch64),,$(error "CROSS_COMPILE is invalid"))
#endif

#	@echo "---> $$($(CROSS_COMPILE)gcc -dumpmachine) $$($(CROSS_COMPILE)gcc -dumpversion)";
# Changes of commit "Remove auto downloading Ampere toolchain b6f7e223" <<<

#Keep the original auto-downloading mechanism >>>
	$(eval COMPILER_NAME := ampere-8.3.0-20191025-dynamic-nosysroot-crosstools.tar.xz)
	$(eval COMPILER_URL := https://cdn.amperecomputing.com/tools/compilers/cross/8.3.0/$(COMPILER_NAME))

	@if [[ "$(COMPILER)" != $(AARCH64_TOOLS_DIR)*  || -f $(AARCH64_TOOLS_DIR)/$(AMPERE_COMPILER_PREFIX)gcc ]]; then \
		echo $$($(COMPILER)gcc -dumpmachine) $$($(COMPILER)gcc -dumpversion); \
	else \
		echo -e "Not Found\nDownloading and setting Ampere compiler..."; \
		rm -rf $(COMPILER_DIR) && mkdir -p $(COMPILER_DIR); \
		wget -O - -q $(COMPILER_URL) --no-check-certificate | tar xJf - -C $(COMPILER_DIR) --strip-components=1 --checkpoint=.100; \
	fi
#Keep the original auto-downloading mechanism <<<
_check_atf_tools:
	@echo -n "Checking ATF Tools..."
	$(eval ATF_REPO_URL := https://github.com/ARM-software/arm-trusted-firmware.git)
	$(eval export ATF_TOOLS_LIST := include/tools_share \nmake_helpers \ntools/cert_create \ntools/fiptool)
	$(eval export PATH := $(ATF_TOOLS_DIR):$(PATH))
#	$(eval ATF_TOOL_TAG := v2.6)

#
# ATF_REPO_URL cause CERTTOOL building error at commit 9bc52d330fccb0e4df22006630350a42457d3306
# so replace "--track origin/master" with previous commit "b1470ccc928c45d4ee53f384d8c2d5d39b31b5e1"
#
# cd $(SCRIPTS_DIR)/AtfTools && git -C . checkout tags/$(ATF_TOOL_TAG) -b $(ATF_TOOL_TAG); 

	@if which $(CERTTOOL) &>/dev/null && which $(FIPTOOL) &>/dev/null; then \
		echo "OK"; \
	else \
		echo -e "Not Found\nDownloading and building atf tools..."; \
		rm -rf $(SCRIPTS_DIR)/AtfTools && mkdir -p $(SCRIPTS_DIR)/AtfTools; \
		rm -rf $(ATF_TOOLS_DIR) && mkdir -p $(ATF_TOOLS_DIR); \
		cd $(SCRIPTS_DIR)/AtfTools && git init && git remote add origin -f $(ATF_REPO_URL) && git config core.sparseCheckout true; \
		echo -e $$ATF_TOOLS_LIST > $(SCRIPTS_DIR)/AtfTools/.git/info/sparse-checkout; \
		cd $(SCRIPTS_DIR)/AtfTools && git -C . checkout b1470ccc928c45d4ee53f384d8c2d5d39b31b5e1; \
		cd $(SCRIPTS_DIR)/AtfTools/tools/cert_create && $(MAKE) CRTTOOL=cert_create; \
		cd $(SCRIPTS_DIR)/AtfTools/tools/fiptool && $(MAKE) FIPTOOL=fiptool; \
		cp $(SCRIPTS_DIR)/AtfTools/tools/cert_create/cert_create $(ATF_TOOLS_DIR)/$(CERTTOOL); \
		cp $(SCRIPTS_DIR)/AtfTools/tools/fiptool/fiptool $(ATF_TOOLS_DIR)/$(FIPTOOL); \
		rm -fr $(SCRIPTS_DIR)/AtfTools; \
	fi

_check_iasl:
	@echo -n "Checking iasl..."
	$(eval IASL_NAME := acpica-unix2-$(IASL_VER))
	$(eval IASL_URL := "https://acpica.org/sites/acpica/files/$(IASL_NAME).tar.gz")
ifneq ($(shell $(IASL) -v 2>/dev/null | grep $(IASL_VER)),)
# iASL compiler is already available in the system.
	@echo "OK"
else
# iASL compiler not found or its version is not compatible.
	$(eval export PATH := $(IASL_DIR):$(PATH))

	@if $(IASL) -v 2>/dev/null | grep $(IASL_VER); then \
		echo "OK"; \
	else \
		echo -e "Not Found\nDownloadcleaning and building iasl..."; \
		rm -rf $(IASL_DIR) && mkdir -p $(IASL_DIR); \
		wget -O - -q $(IASL_URL) | tar xzf - -C $(SCRIPTS_DIR) --checkpoint=.100; \
		$(MAKE) -C $(SCRIPTS_DIR)/$(IASL_NAME) -j $(NUM_THREADS) HOST=_CYGWIN; \
		cp $(SCRIPTS_DIR)/$(IASL_NAME)/generate/unix/bin/iasl $(IASL_DIR)/$(IASL); \
		rm -fr $(SCRIPTS_DIR)/$(IASL_NAME); \
	fi
endif

_check_efitools:
	@echo -n "Checking efitools..."
	$(eval EFITOOLS_REPO_URL := https://github.com/vathpela/efitools.git)
	$(eval export PATH := $(EFI_TOOLS_DIR):$(PATH))

	@if which $(CERT_TO_EFI_SIG_LIST) &>/dev/null && which $(SIGN_EFI_SIG_LIST) &>/dev/null && $(CERT_TO_EFI_SIG_LIST) --version 2>/dev/null | grep $(EFITOOLS_VER); then \
		echo "OK"; \
	else \
		echo -e "Not Found\nDownloading and building efitools..."; \
		rm -rf $(SCRIPTS_DIR)/efitools && mkdir -p $(SCRIPTS_DIR)/efitools; \
		rm -rf $(EFI_TOOLS_DIR) && mkdir -p $(EFI_TOOLS_DIR); \
		cd $(SCRIPTS_DIR)/efitools && git init && git remote add origin -f $(EFITOOLS_REPO_URL) && git config core.sparseCheckout true; \
		cd $(SCRIPTS_DIR)/efitools && git -C . checkout --track origin/master && git -C . checkout v$(EFITOOLS_VER); \
		cd $(SCRIPTS_DIR)/efitools && $(MAKE) cert-to-efi-sig-list sign-efi-sig-list; \
		cp $(SCRIPTS_DIR)/efitools/cert-to-efi-sig-list $(EFI_TOOLS_DIR)/$(CERT_TO_EFI_SIG_LIST); \
		cp $(SCRIPTS_DIR)/efitools/sign-efi-sig-list $(EFI_TOOLS_DIR)/$(SIGN_EFI_SIG_LIST); \
		rm -fr $(SCRIPTS_DIR)/efitools; \
	fi

_check_atf_slim:
	@echo "Checking ATF_SLIM...OK"
	$(if $(wildcard $(ATF_SLIM)),,$(error "ATF_SLIM invalid"))

_check_linuxboot_bin:
	@echo "Checking LINUXBOOT_BIN...OK"
	$(if $(wildcard $(LINUXBOOT_BIN)),,$(error "LINUXBOOT_BIN invalid"))

_check_board_setting:
	@echo "Checking BOARD_SETTING...OK"
	$(if $(wildcard $(BOARD_SETTING)),,$(error "BOARD_SETTING invalid"))
	$(eval OUTPUT_BOARD_SETTING_TXT := $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_board_setting.txt)
	@mkdir -p $(OUTPUT_BIN_DIR)

	@if [[ "$(BOARD_SETTING)" = *.bin ]]; then \
		cp $(BOARD_SETTING) $(OUTPUT_BOARD_SETTING_BIN); \
	else \
		cp $(BOARD_SETTING) $(OUTPUT_BOARD_SETTING_TXT); \
		$(NVGENCMD) -f $(OUTPUT_BOARD_SETTING_TXT) -o $(OUTPUT_BOARD_SETTING_BIN); \
		rm -r $(OUTPUT_BOARD_SETTING_BIN).padded; \
	fi

_tianocore_prepare: _check_source _check_tools _check_compiler _check_iasl
	$(if $(wildcard $(EDK2_SRC_DIR)/BaseTools/Source/C/bin),,$(MAKE) -C $(EDK2_SRC_DIR)/BaseTools -j $(NUM_THREADS))
	$(eval export WORKSPACE := $(CUR_DIR))
	$(eval export PACKAGES_PATH := $(shell echo $(REQUIRE_EDK2_SRC) | sed 's/ /:/g'))
	$(eval export $(EDK2_GCC_TAG)_AARCH64_PREFIX := $(CROSS_COMPILE))
	$(eval EDK2_FV_DIR := $(WORKSPACE)/Build/$(BOARD_NAME_UFL)/$(BUILD_VARIANT)_$(EDK2_GCC_TAG)/FV)

_tianocore_sign_fd: _check_atf_tools _check_efitools
	@echo "Creating certitficate for $(OUTPUT_FD_IMAGE)"
	$(eval DBB_KEY := $(EDK2_PLATFORMS_SRC_DIR)/Platform/Ampere/$(BOARD_NAME_SRC)Pkg/TestKeys/Dbb_AmpereTest.priv.pem)
	@$(CERTTOOL) -n --ntfw-nvctr 0 --key-alg rsa --nt-fw-key $(DBB_KEY) --nt-fw-cert $(OUTPUT_FD_IMAGE).crt --nt-fw $(OUTPUT_FD_IMAGE)
	@$(FIPTOOL) create --nt-fw-cert $(OUTPUT_FD_IMAGE).crt --nt-fw $(OUTPUT_FD_IMAGE) $(OUTPUT_FD_IMAGE).signed
	@rm -fr $(OUTPUT_FD_IMAGE).crt

.PHONY: dbukeys_auth
dbukeys_auth: _check_efitools
	$(eval DBUAUTH:=$(OUTPUT_BIN_DIR)/dbukey.auth)
	$(eval DELDBUAUTH:=$(OUTPUT_BIN_DIR)/del_dbukey.auth)
	$(eval DBUGUID:=$(OUTPUT_BIN_DIR)/dbu_guid.txt)
	$(eval DBUKEY:=$(EDK2_PLATFORMS_SRC_DIR)/Platform/Ampere/$(BOARD_NAME_SRC)Pkg/TestKeys/Dbu_AmpereTest.priv.pem)
	$(eval DBUCER:=$(EDK2_PLATFORMS_SRC_DIR)/Platform/Ampere/$(BOARD_NAME_SRC)Pkg/TestKeys/Dbu_AmpereTest.cer.pem)
	$(eval DBUDIR:=$(OUTPUT_BIN_DIR)/dbukeys)
	$(eval FWUGUID:=$(shell python3 -c 'import uuid; print(str(uuid.uuid1()))'))

	@if [ $(MAJOR_VER)$(MINOR_VER) -gt 202 ]; then \
		mkdir -p $(DBUDIR); \
		echo FWU_GUID=$(FWUGUID); \
		echo $(FWUGUID) > $(DBUDIR)/dbu_guid.txt; \
		cd $(DBUDIR); \
		$(CERT_TO_EFI_SIG_LIST) -g $(FWUGUID) $(DBUCER) dbu.esl; \
		$(SIGN_EFI_SIG_LIST) -g $(FWUGUID) -t "$(date --date='1 second' +'%Y-%m-%d %H:%M:%S')" \
						-k $(DBUKEY) -c $(DBUCER) dbu dbu.esl dbukey.auth; \
		$(SIGN_EFI_SIG_LIST) -g $(FWUGUID) -t "$(date --date='1 second' +'%Y-%m-%d %H:%M:%S')" \
						-k $(DBUKEY) -c $(DBUCER) dbu /dev/null del_dbukey.auth; \
		cp -f $(DBUDIR)/dbukey.auth $(DBUAUTH); \
		cp -f $(DBUDIR)/del_dbukey.auth $(DELDBUAUTH); \
		rm -r $(DBUDIR); \
	fi

## tianocore_fd		: Tianocore FD image
.PHONY: tianocore_fd
tianocore_fd: _tianocore_prepare
	@echo "Build Tianocore $(BUILD_VARIANT_UFL) FD..."
	$(eval DSC_FILE := $(word 1,$(wildcard $(if $(shell echo $(BUILD_LINUXBOOT) | grep -w 1) \
									,$(EDK2_PLATFORMS_PKG_DIR)/$(BOARD_NAME_UFL)Linux*.dsc \
									,$(EDK2_PLATFORMS_PKG_DIR)/$(BOARD_NAME_UFL).dsc))))
	$(if $(DSC_FILE),,$(error "DSC not found"))
	$(eval EDK2_FD_IMAGE := $(EDK2_FV_DIR)/BL33_$(BOARD_NAME_UPPER)_UEFI.fd)

	@if [ $(BUILD_LINUXBOOT) -eq 1 ]; then \
		cp $(LINUXBOOT_BIN) $(WORK_LINUXBOOT_BIN); \
	fi

	. $(EDK2_SRC_DIR)/edksetup.sh && build -a AARCH64 -t $(EDK2_GCC_TAG) -b $(BUILD_VARIANT) -n $(NUM_THREADS) \
		-D DEVEL_MODE=$(DEVEL_MODE) \
		-D FIRMWARE_VER=$(FIRMWARE_VER) \
		-D MAJOR_VER=$(MAJOR_VER) -D MINOR_VER=$(MINOR_VER) -D SECURE_BOOT_ENABLE \
		-p $(DSC_FILE)
	@mkdir -p $(OUTPUT_BIN_DIR)
	@cp -f $(EDK2_FD_IMAGE) $(OUTPUT_FD_IMAGE)

	@if [ $(BUILD_LINUXBOOT) -eq 1 ]; then \
		rm -f $(WORK_LINUXBOOT_BIN); \
	fi

## Release		: Extra copy to workaround ubuntu file cached problem
.PHONY: Release
Release:
#	@echo "Extra copy action to workaround Ubuntu file cached causing checksum error."
ifneq ($(SPI_SIZE_MB),)
	$(eval OUTPUT_IMAGE_BIN  := $(basename $(OUTPUT_IMAGE)).bin)
ifneq ($(wildcard $(RELEASE_DIR)),)
ifneq ($(SPI_SIZE_MB),)
	$(call copyNrelease, $(OUTPUT_IMAGE_BIN))
endif	
endif	
endif	

## tianocore_img		: Tianocore Integrated image
.PHONY: tianocore_img
tianocore_img: _check_atf_tools _check_atf_slim _check_board_setting tianocore_fd
	@echo "Build Tianocore $(BUILD_VARIANT_UFL) Image - ATF VERSION: $(ATF_MAJOR).$(ATF_MINOR).$(ATF_BUILD)..."
	$(eval DBB_KEY := $(EDK2_PLATFORMS_SRC_DIR)/Platform/Ampere/$(BOARD_NAME_SRC)Pkg/TestKeys/Dbb_AmpereTest.priv.pem)
	@dd bs=1024 count=2048 if=/dev/zero | tr "\000" "\377" > $(OUTPUT_RAW_IMAGE)
	@dd bs=1 seek=0 conv=notrunc if=$(ATF_SLIM) of=$(OUTPUT_RAW_IMAGE)
	@if [ $(MAJOR_VER)$(MINOR_VER) -gt 202 ]; then \
		$(CERTTOOL) -n --ntfw-nvctr 0 --key-alg rsa --hash-alg sha384 --nt-fw-key $(DBB_KEY) --nt-fw-cert ${ATF_SLIM}.crt --nt-fw ${ATF_SLIM}; \
		dd bs=1 seek=1572864 conv=notrunc if=${ATF_SLIM}.crt of=${OUTPUT_RAW_IMAGE}; \
		rm -f ${ATF_SLIM}.crt; \
	fi
	@dd bs=1 seek=2031616 conv=notrunc if=$(OUTPUT_BOARD_SETTING_BIN) of=$(OUTPUT_RAW_IMAGE)

	@if [ $(ATF_TBB) -eq 1 ]; then \
		$(MAKE) -C $(SCRIPTS_DIR) _tianocore_sign_fd; \
		dd bs=1024 seek=2048 if=$(OUTPUT_FD_IMAGE).signed of=$(OUTPUT_RAW_IMAGE); \
		rm -f $(OUTPUT_FD_IMAGE).signed; \
	else \
		dd bs=1024 seek=2048 if=$(OUTPUT_FD_IMAGE) of=$(OUTPUT_RAW_IMAGE); \
	fi

# For Ampere ATF version 1.03 and 2.01, the following supports adding 4MB padding to the final image for
# compatibility with the support of firmware update utility.
	@if [ $(ATF_MAJOR)$(ATF_MINOR) -eq 103 ] || [ $(ATF_MAJOR)$(ATF_MINOR) -eq 201 ]; then \
		dd if=/dev/zero bs=1024 count=4096 | tr "\000" "\377" > $(OUTPUT_IMAGE); \
		dd bs=1 seek=4194304 conv=notrunc if=$(OUTPUT_RAW_IMAGE) of=$(OUTPUT_IMAGE); \
	else \
		cp $(OUTPUT_RAW_IMAGE) $(OUTPUT_IMAGE); \
	fi
ifneq ($(SPI_SIZE_MB),)
	$(eval OUTPUT_IMAGE_BIN  := $(basename $(OUTPUT_IMAGE)).bin)
	@dd bs=1M count=$(SPI_SIZE_MB) if=/dev/zero | tr "\000" "\377" > $(OUTPUT_IMAGE_BIN)
ifeq ($(FAILSAFE_WORKAROUND),1)
# 	override 0x114070 as a failsafe function workaround 
	@echo -en "\x01\x00\x00\x00\xff\xff\x13\xc3" | dd bs=1 seek=1130608 conv=notrunc of=$(OUTPUT_IMAGE_BIN)
endif
# insert tiano image to a SPI ROM image	starte at offset 8x512KB=4MB
	@dd conv=notrunc bs=8 seek=524288 if=$(OUTPUT_IMAGE) of=$(OUTPUT_IMAGE_BIN)
endif	
ifneq ($(wildcard $(PROGRAMMER_TOOL)),)
ifneq ($(shell lsusb | grep 0483:),)
	. $(POWER_SCRIPT) OFF
	$(PROGRAMMER_TOOL) -u $(OUTPUT_IMAGE) -a 0x400000 -v
	. $(POWER_SCRIPT) ON
endif	
endif	
ifneq ($(wildcard $(RELEASE_DIR)),)
	$(call copy2release, $(OUTPUT_IMAGE))
ifneq ($(SPI_SIZE_MB),)
	$(call copy2release, $(OUTPUT_IMAGE_BIN))
endif	
endif
	@echo "Checksum of FD: for binary modification check, use this value to check if any object binary were modified"	
	@$(CHECKSUM_TOOL) $(OUTPUT_FD_IMAGE)

## tianocore_capsule	: Tianocore Capsule image
.PHONY: tianocore_capsule
tianocore_capsule: tianocore_img dbukeys_auth
	@echo "Build Tianocore $(BUILD_VARIANT_UFL) Capsule..."
	$(eval DBU_KEY := $(EDK2_PLATFORMS_SRC_DIR)/Platform/Ampere/$(BOARD_NAME_SRC)Pkg/TestKeys/Dbu_AmpereTest.priv.pem)
# *atfedk2.img.signed was chosen to be backward compatible with release 1.01
	$(eval TIANOCORE_ATF_IMAGE := $(WORKSPACE)/Build/$(BOARD_NAME_UFL)/$(BOARD_NAME)_atfedk2.img.signed)
	$(eval OUTPUT_UEFI_ATF_CAPSULE := $(OUTPUT_BIN_DIR)/$(OUTPUT_BASENAME).cap)
	$(eval OUTPUT_UEFI_ATF_DBU_IMG := $(OUTPUT_BIN_DIR)/$(OUTPUT_BASENAME).dbu.sig.img)
	$(eval SCP_IMAGE := $(WORKSPACE)/Build/$(BOARD_NAME_UFL)/$(BOARD_NAME)_scp.slim)
	$(eval OUTPUT_SCP_CAPSULE := $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_scp$(OUTPUT_VARIANT)_$(VER).$(BUILD).cap)
	$(eval OUTPUT_SCP_DBU_IMG := $(OUTPUT_BIN_DIR)/$(BOARD_NAME)_scp$(OUTPUT_VARIANT)_$(VER).$(BUILD).dbu.sig.img)
	$(eval EDK2_AARCH64_DIR := $(WORKSPACE)/Build/$(BOARD_NAME_UFL)/$(BUILD_VARIANT)_$(EDK2_GCC_TAG)/AARCH64)
	$(eval OUTPUT_CAPSULE_APP := $(OUTPUT_BIN_DIR)/CapsuleApp.efi)
	$(eval OUTPUT_BOARDVERSION_APP := $(OUTPUT_BIN_DIR)/BoardVersion.efi)
	$(eval OUTPUT_FWUI_APP := $(OUTPUT_BIN_DIR)/FwUi.efi)
	$(eval CAPSULE_SCRIPT := $(OEM_COMMON_DIR)/Release/Capsule.nsh)
	$(eval RELEASE_README := $(OEM_COMMON_DIR)/Release/readme.txt)
	$(eval RELEASE_NOTE := $(EDK2_PLATFORMS_PKG_DIR)/ReleaseNote.txt)

	@if [ -f "$(SCP_SLIM)" ]; then \
		if [ $(MAJOR_VER)$(MINOR_VER) -le 202 ]; then \
			ln -sf $(realpath $(SCP_SLIM)) $(SCP_IMAGE); \
		else \
			echo "Append dummy data to origin SCP image"; \
			dd bs=1 count=261632 if=/dev/zero | tr "\000" "\377" > $(SCP_IMAGE).append; \
			dd bs=1 seek=0 conv=notrunc if=$(SCP_SLIM) of=$(SCP_IMAGE).append; \
			openssl dgst -sha384 -sign $(DBU_KEY) -out $(SCP_IMAGE).sig $(SCP_IMAGE).append; \
			cat $(SCP_IMAGE).sig $(SCP_IMAGE).append > $(SCP_IMAGE).signed; \
			cp -r $(SCP_IMAGE).signed $(SCP_IMAGE); \
			cp -r $(SCP_IMAGE).signed $(OUTPUT_SCP_DBU_IMG); \
		fi; \
	else \
		echo "********WARNING*******"; \
		echo " SCP firmware image is not valid to build capsule image."; \
		echo " It should be provided via the make build option, SCP_SLIM=/path/to/the/SCP/firmware/image."; \
		echo " Creating a fake image to pass the build..."; \
		echo "**********************"; \
		touch $(SCP_IMAGE); \
	fi

	@if [ $(MAJOR_VER)$(MINOR_VER) -le 105 ]; then \
		echo "Sign Tianocore Image"; \
		openssl dgst -sha256 -sign $(DBU_KEY) -out $(OUTPUT_RAW_IMAGE).sig $(OUTPUT_RAW_IMAGE); \
		cat $(OUTPUT_RAW_IMAGE).sig $(OUTPUT_RAW_IMAGE) > $(OUTPUT_RAW_IMAGE).signed; \
		ln -sf $(OUTPUT_RAW_IMAGE).signed $(TIANOCORE_ATF_IMAGE); \
	elif [ $(MAJOR_VER)$(MINOR_VER) -le 202 ]; then \
		ln -sf $(OUTPUT_IMAGE) $(TIANOCORE_ATF_IMAGE); \
	else \
		echo "Sign Tianocore Image"; \
		echo "Append to dummy byte to UEFI image"; \
		dd bs=1 count=13630976 if=/dev/zero | tr "\000" "\377" > $(OUTPUT_RAW_IMAGE).append; \
		dd bs=1 seek=0 conv=notrunc if=$(OUTPUT_RAW_IMAGE) of=$(OUTPUT_RAW_IMAGE).append; \
		openssl dgst -sha384 -sign $(DBU_KEY) -out $(OUTPUT_RAW_IMAGE).sig $(OUTPUT_RAW_IMAGE).append; \
		cat $(OUTPUT_RAW_IMAGE).sig $(OUTPUT_RAW_IMAGE).append > $(OUTPUT_RAW_IMAGE).signed; \
		ln -sf $(OUTPUT_RAW_IMAGE).signed $(TIANOCORE_ATF_IMAGE); \
		cp -f $(OUTPUT_RAW_IMAGE).signed $(OUTPUT_UEFI_ATF_DBU_IMG); \
	fi

	. $(EDK2_SRC_DIR)/edksetup.sh && build -a AARCH64 -t $(EDK2_GCC_TAG) -b $(BUILD_VARIANT) \
		-D UEFI_ATF_IMAGE=$(TIANOCORE_ATF_IMAGE) \
		-D SCP_IMAGE=$(SCP_IMAGE) \
		-p Platform/Ampere/$(BOARD_NAME_UFL)Pkg/$(BOARD_NAME_UFL)Capsule.dsc
	@cp -f $(EDK2_FV_DIR)/$(BOARD_NAME_UPPER)UEFIATFFIRMWAREUPDATECAPSULEFMPPKCS7.Cap $(OUTPUT_UEFI_ATF_CAPSULE)
	@cp -f $(EDK2_FV_DIR)/JADESCPFIRMWAREUPDATECAPSULEFMPPKCS7.Cap $(OUTPUT_SCP_CAPSULE)
	@cp -f $(EDK2_AARCH64_DIR)/CapsuleApp.efi $(OUTPUT_CAPSULE_APP)
	@if [[ -f $(EDK2_AARCH64_DIR)/BoardVersion.efi ]]; then \
		cp -f $(EDK2_AARCH64_DIR)/BoardVersion.efi $(OUTPUT_BOARDVERSION_APP); \
	fi
	@if [[ -f $(EDK2_AARCH64_DIR)/FwUi.efi ]]; then \
		cp -f $(EDK2_AARCH64_DIR)/FwUi.efi $(OUTPUT_FWUI_APP); \
	fi
	@rm -f $(OUTPUT_RAW_IMAGE).sig $(OUTPUT_RAW_IMAGE).signed $(OUTPUT_RAW_IMAGE) $(OUTPUT_RAW_IMAGE).append \
			$(SCP_IMAGE).append

ifneq ($(wildcard $(RELEASE_DIR)),)
	$(call copy2release, $(OUTPUT_UEFI_ATF_CAPSULE))
	$(call copy2release, $(OUTPUT_SCP_CAPSULE))
	$(call copy2release, $(OUTPUT_CAPSULE_APP))
	$(call copy2release, $(OUTPUT_BOARDVERSION_APP))
	$(call copy2release, $(OUTPUT_FWUI_APP))
	$(call copy2release, $(RELEASE_NOTE))
	$(call copy2release, $(RELEASE_README))
	$(call copy2release, $(CAPSULE_SCRIPT))
	@sed -i 's/%VER%.%BUILD%.*/$(VER).$(BUILD_COM)/' $(RELEASE_FILE)
endif	

# end of makefile
