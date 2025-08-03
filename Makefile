# Espressif LLVM Cross-Platform Build Makefile
# Based on TinyGo's GNUmakefile but focused on Espressif LLVM toolchain

# Version and tag configuration
# TAG can be passed as parameter: make TAG=19.1.2_20250312
TAG ?= 19.1.2_20250312
VERSION_STRING = esp-$(TAG)

# Default build and source directories
LLVM_BUILDDIR ?= llvm-build
LLVM_PROJECTDIR ?= llvm-project
CLANG_SRC ?= $(LLVM_PROJECTDIR)/clang
LLD_SRC ?= $(LLVM_PROJECTDIR)/lld

# Detect host system
ifeq ($(OS),Windows_NT)
    uname := Windows_NT
    EXE = .exe
else
    uname := $(shell uname -s)
    EXE =
endif

# Build targets configuration
BUILD_TARGETS = \
	aarch64-apple-darwin \
	aarch64-linux-gnu \
	arm-linux-gnueabihf \
	x86_64-apple-darwin \
	x86_64-linux-gnu \
	x86_64-w64-mingw32

# LLVM components to build
LLVM_COMPONENTS = all-targets analysis asmparser asmprinter bitreader bitwriter codegen core coroutines coverage debuginfodwarf debuginfopdb executionengine frontenddriver frontendhlsl frontendopenmp instrumentation interpreter ipo irreader libdriver linker lto mc mcjit objcarcopts option profiledata scalaropts support target windowsdriver windowsmanifest

# Library names for clang and LLD
CLANG_LIB_NAMES = clangAnalysis clangAPINotes clangAST clangASTMatchers clangBasic clangCodeGen clangCrossTU clangDriver clangDynamicASTMatchers clangEdit clangExtractAPI clangFormat clangFrontend clangFrontendTool clangHandleCXX clangHandleLLVM clangIndex clangInstallAPI clangLex clangParse clangRewrite clangRewriteFrontend clangSema clangSerialization clangSupport clangTooling clangToolingASTDiff clangToolingCore clangToolingInclusions
LLD_LIB_NAMES = lldCOFF lldCommon lldELF lldMachO lldMinGW lldWasm
EXTRA_LIB_NAMES = LLVMInterpreter LLVMMCA LLVMRISCVTargetMCA LLVMX86TargetMCA
LIB_NAMES = clang $(CLANG_LIB_NAMES) $(LLD_LIB_NAMES) $(EXTRA_LIB_NAMES)

# Build targets for ninja
NINJA_BUILD_TARGETS = clang llvm-config llvm-ar llvm-nm lld $(addprefix lib/lib,$(addsuffix .a,$(LIB_NAMES)))

.PHONY: all clean llvm-source help
.PHONY: $(BUILD_TARGETS)
.PHONY: $(addprefix clang-,$(BUILD_TARGETS))
.PHONY: $(addprefix libs-clang-,$(BUILD_TARGETS))

# Default target
all: help

# Help target
help: ## Show this help message
	@echo "Espressif LLVM Cross-Platform Build System"
	@echo ""
	@echo "Available targets:"
	@echo "  all-clang          - Build clang packages for all targets"
	@echo "  all-libs           - Build libs packages for all targets"
	@echo "  all-packages       - Build both clang and libs packages for all targets"
	@echo ""
	@echo "Individual targets:"
	@for target in $(BUILD_TARGETS); do \
		echo "  clang-$$target     - Build clang package for $$target"; \
		echo "  libs-clang-$$target - Build libs package for $$target"; \
	done
	@echo ""
	@echo "Utility targets:"
	@echo "  llvm-source        - Download LLVM source"
	@echo "  clean              - Clean build directory"
	@echo ""
	@echo "Configuration:"
	@echo "  LLVM_VERSION=$(LLVM_VERSION)"
	@echo "  DATE_SUFFIX=$(DATE_SUFFIX)"
	@echo "  VERSION_STRING=$(VERSION_STRING)"

# Meta targets
all-clang: $(addprefix clang-,$(BUILD_TARGETS)) ## Build clang packages for all targets
all-libs: $(addprefix libs-clang-,$(BUILD_TARGETS)) ## Build libs packages for all targets
all-packages: all-clang all-libs ## Build both clang and libs packages for all targets

# Extract version from TAG to determine branch name
# TAG format: 19.1.2_20250312 -> branch: xtensa_release_19.1.2
LLVM_VERSION_FROM_TAG = $(firstword $(subst _, ,$(TAG)))
LLVM_BRANCH = xtensa_release_$(LLVM_VERSION_FROM_TAG)

# Download LLVM source with branch detection
.PHONY: llvm-source
llvm-source: ## Download LLVM source (skip if directory exists with correct branch)
	@echo "Target branch: $(LLVM_BRANCH)"
	@if [ -d "$(LLVM_PROJECTDIR)/.git" ]; then \
		echo "LLVM project directory exists, checking branch..."; \
		cd $(LLVM_PROJECTDIR) && \
		current_branch=$$(git rev-parse --abbrev-ref HEAD 2>/dev/null || git describe --tags --exact-match 2>/dev/null || echo "unknown"); \
		if [ "$$current_branch" = "$(LLVM_BRANCH)" ]; then \
			echo "Already on correct branch: $$current_branch"; \
		else \
			echo "Current branch: $$current_branch, expected: $(LLVM_BRANCH)"; \
			echo "Removing existing directory and re-cloning..."; \
			cd .. && rm -rf $(LLVM_PROJECTDIR) && \
			git clone -b $(LLVM_BRANCH) --depth=1 https://github.com/espressif/llvm-project $(LLVM_PROJECTDIR); \
		fi \
	else \
		echo "Cloning LLVM project branch $(LLVM_BRANCH)..."; \
		git clone -b $(LLVM_BRANCH) --depth=1 https://github.com/espressif/llvm-project $(LLVM_PROJECTDIR); \
	fi

# Clean target
clean: ## Remove build directory
	@rm -rf build llvm-build

# Build configuration function
define get_cmake_flags
$(if $(findstring darwin,$(1)),$(if $(findstring aarch64,$(1)),-DCMAKE_OSX_ARCHITECTURES=arm64 -DBOOTSTRAP_BOOTSTRAP_COMPILER_RT_ENABLE_IOS=OFF -DBOOTSTRAP_BOOTSTRAP_DARWIN_osx_ARCHS=arm64 -DBOOTSTRAP_BOOTSTRAP_DARWIN_osx_BUILTIN_ARCHS=arm64,-DCMAKE_OSX_ARCHITECTURES=x86_64 -DBOOTSTRAP_BOOTSTRAP_COMPILER_RT_ENABLE_IOS=OFF -DBOOTSTRAP_BOOTSTRAP_DARWIN_osx_ARCHS=x86_64 -DBOOTSTRAP_BOOTSTRAP_DARWIN_osx_BUILTIN_ARCHS=x86_64),\
$(if $(findstring mingw32,$(1)),$(if $(findstring Windows_NT,$(uname)),-DCMAKE_SYSTEM_NAME=Windows,-DCMAKE_SYSTEM_NAME=Windows -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ -DLLVM_ENABLE_PIC=OFF -DLLVM_ENABLE_THREADS=OFF -DLLVM_TOOLCHAIN_CROSS_BUILD_MINGW=ON -DCMAKE_CXX_FLAGS="-fpermissive -Wno-error -std=gnu++17"),\
$(if $(findstring linux-gnu,$(1)),-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_C_COMPILER=$(1)-gcc -DCMAKE_CXX_COMPILER=$(1)-g++,\
$(if $(findstring gnueabihf,$(1)),-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_C_COMPILER=$(1)-gcc -DCMAKE_CXX_COMPILER=$(1)-g++,))))
endef

# LLVM build directory for each target
define get_build_dir
llvm-build-$(1)
endef

# Configure LLVM for specific target
define configure_llvm
mkdir -p $(call get_build_dir,$(1)) && \
cd $(call get_build_dir,$(1)) && \
cmake -G Ninja ../$(LLVM_PROJECTDIR)/llvm \
	"-DLLVM_TARGETS_TO_BUILD=X86;ARM;AArch64;AVR;Mips;RISCV;WebAssembly" \
	"-DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Xtensa" \
	-DCMAKE_BUILD_TYPE=Release \
	-DLIBCLANG_BUILD_STATIC=ON \
	-DLLVM_ENABLE_TERMINFO=OFF \
	-DLLVM_ENABLE_ZLIB=OFF \
	-DLLVM_ENABLE_ZSTD=OFF \
	-DLLVM_ENABLE_LIBEDIT=OFF \
	-DLLVM_ENABLE_Z3_SOLVER=OFF \
	-DLLVM_ENABLE_OCAMLDOC=OFF \
	-DLLVM_ENABLE_LIBXML2=OFF \
	-DLLVM_ENABLE_PROJECTS="clang;lld" \
	-DLLVM_TOOL_CLANG_TOOLS_EXTRA_BUILD=OFF \
	-DCLANG_ENABLE_STATIC_ANALYZER=OFF \
	-DCLANG_ENABLE_ARCMT=OFF \
	-DCMAKE_INSTALL_PREFIX=../build/install-$(1) \
	$(call get_cmake_flags,$(1))
endef

# Build LLVM for specific target
define build_llvm
cd $(call get_build_dir,$(1)) && ninja $(NINJA_BUILD_TARGETS) && ninja install
endef

# Create clang package
define create_clang_package
mkdir -p build/clang-$(1) && \
cp -r build/install-$(1)/bin build/clang-$(1)/ && \
cp -r build/install-$(1)/include build/clang-$(1)/ && \
cp -r build/install-$(1)/share build/clang-$(1)/ && \
cd build && \
tar -cJf clang-$(VERSION_STRING)-$(1).tar.xz clang-$(1)/
endef

# Create libs package
define create_libs_package
mkdir -p build/libs-clang-$(1) && \
cp -r build/install-$(1)/lib build/libs-clang-$(1)/ && \
cd build && \
tar -cJf libs-clang-$(VERSION_STRING)-$(1).tar.xz libs-clang-$(1)/
endef

# Individual target rules
define make_target_rules
$(1): clang-$(1) libs-clang-$(1)

clang-$(1): llvm-source $(if $(findstring linux-gnu,$(1)),check-$(1),) $(if $(findstring gnueabihf,$(1)),check-$(1),) $(if $(findstring mingw32,$(1)),check-$(1),) ## Build clang package for $(1)
	@echo "Building clang for $(1)..."
	$(call configure_llvm,$(1))
	$(call build_llvm,$(1))
	$(call create_clang_package,$(1))
	@echo "Created: build/clang-$(VERSION_STRING)-$(1).tar.xz"

libs-clang-$(1): clang-$(1) ## Build libs package for $(1) (reuses clang build)
	@echo "Building libs for $(1)..."
	$(call create_libs_package,$(1))
	@echo "Created: build/libs-clang-$(VERSION_STRING)-$(1).tar.xz"
endef

# Cross-compilation dependency checks
.PHONY: check-aarch64-linux-gnu check-arm-linux-gnueabihf check-x86_64-w64-mingw32 check-x86_64-linux-gnu

check-aarch64-linux-gnu:
	@command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 || { echo "Error: aarch64-linux-gnu-gcc not found. Install with: sudo apt-get install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu"; exit 1; }

check-arm-linux-gnueabihf:
	@command -v arm-linux-gnueabihf-gcc >/dev/null 2>&1 || { echo "Error: arm-linux-gnueabihf-gcc not found. Install with: sudo apt-get install gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf"; exit 1; }

check-x86_64-w64-mingw32:
	@command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1 || { echo "Error: x86_64-w64-mingw32-gcc not found. Install with: sudo apt-get install gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64"; exit 1; }

check-x86_64-linux-gnu:
	@command -v gcc >/dev/null 2>&1 || { echo "Error: gcc not found. Install with: sudo apt-get install build-essential"; exit 1; }

# Generate rules for each target
$(foreach target,$(BUILD_TARGETS),$(eval $(call make_target_rules,$(target))))

# Debug target to show configuration
debug: ## Show build configuration
	@echo "Build configuration:"
	@echo "TAG: $(TAG)"
	@echo "VERSION_STRING: $(VERSION_STRING)"
	@echo "LLVM_VERSION_FROM_TAG: $(LLVM_VERSION_FROM_TAG)"
	@echo "LLVM_BRANCH: $(LLVM_BRANCH)"
	@echo "BUILD_TARGETS: $(BUILD_TARGETS)"
	@echo "LLVM_PROJECTDIR: $(LLVM_PROJECTDIR)"
	@echo "LLVM_BUILDDIR: $(LLVM_BUILDDIR)"
	@echo ""
	@echo "Example package names:"
	@for target in $(BUILD_TARGETS); do \
		echo "  clang-$(VERSION_STRING)-$$target.tar.xz"; \
		echo "  libs-clang-$(VERSION_STRING)-$$target.tar.xz"; \
	done
