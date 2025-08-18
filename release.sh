#!/bin/bash
# Espressif LLVM Cross-Platform Release Builder
# Usage: ./release.sh <platform>
# Based on the working Makefile and build script

set -e

# Configuration
TAG="${TAG:-19.1.2_20250312}"
VERSION_STRING="$TAG"
LLVM_PROJECTDIR="${LLVM_PROJECTDIR:-llvm-project}"
BUILD_DIR_BASE="${BUILD_DIR_BASE:-build}"

# Extract version from TAG to determine branch name
LLVM_VERSION_FROM_TAG="${TAG%%_*}"
LLVM_BRANCH="xtensa_release_${LLVM_VERSION_FROM_TAG}"

# Detect host system
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ -n "$WINDIR" ]]; then
    HOST_OS="Windows_NT"
    EXE=".exe"
else
    HOST_OS="$(uname -s)"
    EXE=""
fi

# Detect host architecture
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    x86_64|amd64)
        HOST_ARCH="x86_64"
        ;;
    aarch64|arm64)
        HOST_ARCH="aarch64"
        ;;
    armv7l)
        HOST_ARCH="arm"
        ;;
esac

echo "Host system: $HOST_OS $HOST_ARCH"

# Set macOS SDK root if on macOS
if [[ "$HOST_OS" == "Darwin" ]]; then
    if [[ -z "$SDKROOT" ]]; then
        export SDKROOT="$(xcrun --show-sdk-path)"
        echo "Setting SDKROOT to: $SDKROOT"
    fi
fi

# Supported build targets
VALID_TARGETS="aarch64-apple-darwin aarch64-linux-gnu arm-linux-gnueabihf x86_64-apple-darwin x86_64-linux-gnu x86_64-w64-mingw32"

# Function to show usage
show_usage() {
    echo "Espressif LLVM Cross-Platform Release Builder"
    echo ""
    echo "Usage: $0 <platform>"
    echo ""
    echo "Supported platforms:"
    for target in $VALID_TARGETS; do
        echo "  - $target"
    done
    echo ""
    echo "Environment variables:"
    echo "  TAG              - Version tag (default: $TAG)"
    echo "  LLVM_PROJECTDIR  - LLVM source directory (default: $LLVM_PROJECTDIR)"
    echo "  BUILD_DIR_BASE   - Build directory base (default: $BUILD_DIR_BASE)"
    echo "  LLVM_NATIVE_TOOL_DIR - Directory containing native tablegen tools"
    echo ""
}

# Function to check if we need cross-compilation
needs_cross_compilation() {
    local target="$1"

    case "$target" in
        aarch64-linux-gnu)
            [[ "$HOST_OS" == "Linux" && "$HOST_ARCH" != "aarch64" ]]
            ;;
        x86_64-linux-gnu)
            [[ "$HOST_OS" == "Linux" && "$HOST_ARCH" != "x86_64" ]]
            ;;
        arm-linux-gnueabihf)
            [[ "$HOST_OS" == "Linux" && "$HOST_ARCH" != "arm" ]]
            ;;
        aarch64-apple-darwin)
            [[ "$HOST_OS" == "Darwin" && "$HOST_ARCH" != "aarch64" ]]
            ;;
        x86_64-apple-darwin)
            [[ "$HOST_OS" == "Darwin" && "$HOST_ARCH" != "x86_64" ]]
            ;;
        x86_64-w64-mingw32)
            [[ "$HOST_OS" != "Windows_NT" ]]
            ;;
        *)
            false
            ;;
    esac
}

# Function to download LLVM source
download_llvm_source() {
    if [[ ! -d "$LLVM_PROJECTDIR" ]]; then
        echo "Cloning LLVM project branch $LLVM_BRANCH..."
        git clone -b "$LLVM_BRANCH" --depth=1 https://github.com/espressif/llvm-project "$LLVM_PROJECTDIR"
    else
        echo "LLVM project directory already exists."
    fi
}

# Function to build native tools for cross-compilation
build_native_tools() {
    local target="$1"
    local native_build_dir="$BUILD_DIR_BASE/native-tools-${target}"
    local native_install_dir="$PWD/install/native-tools-${target}"

    echo "Building native tools for ${target}..."

    mkdir -p "$native_build_dir" "$native_install_dir"

    cd "$native_build_dir"
    cmake "../../$LLVM_PROJECTDIR/llvm" \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_TARGETS_TO_BUILD="host" \
        -DLLVM_BUILD_TOOLS=ON \
        -DLLVM_BUILD_UTILS=ON \
        -DLLVM_INCLUDE_TESTS=OFF \
        -DLLVM_INCLUDE_EXAMPLES=OFF \
        -DLLVM_INCLUDE_BENCHMARKS=OFF \
        -DLLVM_INCLUDE_DOCS=OFF \
        -DCMAKE_INSTALL_PREFIX="$native_install_dir"

    # Build the tablegen tools
    ninja -j$(get_cpu_cores) llvm-min-tblgen llvm-tblgen

    # Manually copy the tools to install directory
    mkdir -p "$native_install_dir/bin"
    cp bin/llvm-min-tblgen "$native_install_dir/bin/"
    cp bin/llvm-tblgen "$native_install_dir/bin/"

    cd - > /dev/null

    export LLVM_NATIVE_TOOL_DIR="$native_install_dir/bin"
}

# Base CMake arguments (from working script)
get_base_cmake_args() {
    cat << 'EOF'
-G Ninja
-DCMAKE_BUILD_TYPE=Release
-DLLVM_TARGETS_TO_BUILD=X86;ARM;AArch64;AVR;Mips;RISCV;WebAssembly
-DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Xtensa
-DLLVM_ENABLE_PROJECTS=clang;lld
-DLLVM_ENABLE_RUNTIMES=compiler-rt;libcxx;libcxxabi;libunwind;pstl
-DLLVM_POLLY_LINK_INTO_TOOLS=ON
-DLLVM_BUILD_EXTERNAL_COMPILER_RT=ON
-DLLVM_ENABLE_EH=ON
-DLLVM_ENABLE_FFI=ON
-DLLVM_ENABLE_RTTI=ON
-DLLVM_INCLUDE_DOCS=OFF
-DLLVM_INCLUDE_TESTS=OFF
-DLLVM_INSTALL_UTILS=ON
-DLLVM_ENABLE_Z3_SOLVER=OFF
-DLLVM_OPTIMIZED_TABLEGEN=ON
-DLLVM_USE_RELATIVE_PATHS_IN_FILES=ON
-DLLVM_SOURCE_PREFIX=.
-DLIBCXX_INSTALL_MODULES=ON
-DCLANG_FORCE_MATCHING_LIBCLANG_SOVERSION=OFF
EOF
}

# macOS-specific CMake arguments (from working script)
get_macos_cmake_args() {
    local target="$1"
    local arch

    if [[ "$target" == "aarch64-apple-darwin" ]]; then
        arch="arm64"
    else
        arch="x86_64"
    fi

    cat << EOF
-DLLVM_BUILD_LLVM_C_DYLIB=ON
-DLLVM_ENABLE_LIBCXX=ON
-DLIBCXX_PSTL_BACKEND=libdispatch
-DCMAKE_OSX_SYSROOT=$SDKROOT
-DCMAKE_OSX_ARCHITECTURES=$arch
-DLIBCXXABI_USE_SYSTEM_LIBS=ON
EOF
}

# Linux-specific CMake arguments with cross-compilation support
get_linux_cmake_args() {
    local target="$1"
    local is_cross_compile="$2"

    local base_args
    base_args=$(cat << 'EOF'
-DLLVM_ENABLE_LIBXML2=OFF
-DLLVM_ENABLE_LIBCXX=OFF
-DCLANG_DEFAULT_CXX_STDLIB=libstdc++
-DCMAKE_POSITION_INDEPENDENT_CODE=ON
-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF
-DLLVM_BUILD_LLVM_DYLIB=ON
-DLLVM_LINK_LLVM_DYLIB=ON
-DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON
-DLIBCXX_STATICALLY_LINK_ABI_IN_SHARED_LIBRARY=OFF
-DLIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY=ON
-DLIBCXX_USE_COMPILER_RT=ON
-DLIBCXX_HAS_ATOMIC_LIB=OFF
-DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON
-DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_SHARED_LIBRARY=OFF
-DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_STATIC_LIBRARY=ON
-DLIBCXXABI_USE_COMPILER_RT=ON
-DLIBCXXABI_USE_LLVM_UNWINDER=ON
-DLIBUNWIND_USE_COMPILER_RT=ON
-DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON
-DCOMPILER_RT_USE_LLVM_UNWINDER=ON
-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON
-DSANITIZER_CXX_ABI=libc++
-DSANITIZER_TEST_CXX=libc++
EOF
)

    echo "$base_args"

    # Add cross-compilation specific arguments
    if [[ "$is_cross_compile" == "true" ]]; then
        case "$target" in
            aarch64-linux-gnu)
                cat << 'EOF'
-DCMAKE_SYSTEM_NAME=Linux
-DCMAKE_SYSTEM_PROCESSOR=aarch64
-DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc
-DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++
-DCMAKE_ASM_COMPILER=aarch64-linux-gnu-gcc
-DCMAKE_AR=aarch64-linux-gnu-ar
-DCMAKE_RANLIB=aarch64-linux-gnu-ranlib
-DCMAKE_STRIP=aarch64-linux-gnu-strip
-DCMAKE_FIND_ROOT_PATH=/usr/aarch64-linux-gnu
-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
-DLLVM_DEFAULT_TARGET_TRIPLE=aarch64-unknown-linux-gnu
-DLLVM_HOST_TRIPLE=aarch64-unknown-linux-gnu
-DLLVM_TARGET_ARCH=AArch64
EOF
                ;;
            arm-linux-gnueabihf)
                cat << 'EOF'
-DCMAKE_SYSTEM_NAME=Linux
-DCMAKE_SYSTEM_PROCESSOR=arm
-DCMAKE_C_COMPILER=arm-linux-gnueabihf-gcc
-DCMAKE_CXX_COMPILER=arm-linux-gnueabihf-g++
-DCMAKE_ASM_COMPILER=arm-linux-gnueabihf-gcc
-DCMAKE_AR=arm-linux-gnueabihf-ar
-DCMAKE_RANLIB=arm-linux-gnueabihf-ranlib
-DCMAKE_STRIP=arm-linux-gnueabihf-strip
-DCMAKE_FIND_ROOT_PATH=/usr/arm-linux-gnueabihf
-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
-DLLVM_DEFAULT_TARGET_TRIPLE=arm-unknown-linux-gnueabihf
-DLLVM_HOST_TRIPLE=arm-unknown-linux-gnueabihf
-DLLVM_TARGET_ARCH=ARM
EOF
                ;;
            x86_64-linux-gnu)
                # Cross-compile from ARM64 to x86_64
                if command -v x86_64-linux-gnu-gcc >/dev/null 2>&1; then
                    cat << 'EOF'
-DCMAKE_SYSTEM_NAME=Linux
-DCMAKE_SYSTEM_PROCESSOR=x86_64
-DCMAKE_C_COMPILER=x86_64-linux-gnu-gcc
-DCMAKE_CXX_COMPILER=x86_64-linux-gnu-g++
-DCMAKE_ASM_COMPILER=x86_64-linux-gnu-gcc
-DCMAKE_AR=x86_64-linux-gnu-ar
-DCMAKE_RANLIB=x86_64-linux-gnu-ranlib
-DCMAKE_STRIP=x86_64-linux-gnu-strip
-DCMAKE_FIND_ROOT_PATH=/usr/x86_64-linux-gnu
-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
-DLLVM_DEFAULT_TARGET_TRIPLE=x86_64-unknown-linux-gnu
-DLLVM_HOST_TRIPLE=x86_64-unknown-linux-gnu
-DLLVM_TARGET_ARCH=X86
EOF
                fi
                ;;
        esac

        # Add native tool directory if available
        if [[ -n "$LLVM_NATIVE_TOOL_DIR" ]]; then
            echo "-DLLVM_NATIVE_TOOL_DIR=$LLVM_NATIVE_TOOL_DIR"
        fi
    fi
}

# MinGW-specific CMake arguments (修复版本)
get_mingw_cmake_args() {
    if [[ "$HOST_OS" == "Windows_NT" ]]; then
        # Native Windows build with MinGW
        cat << 'EOF'
-DCMAKE_SYSTEM_NAME=Windows
-DLLVM_ENABLE_LIBXML2=OFF
-DLLVM_ENABLE_LIBCXX=OFF
-DCLANG_DEFAULT_CXX_STDLIB=libstdc++
-DCMAKE_POSITION_INDEPENDENT_CODE=ON
-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF
-DLLVM_DEFAULT_TARGET_TRIPLE=x86_64-w64-windows-gnu
-DLLVM_HOST_TRIPLE=x86_64-w64-windows-gnu
-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON
-DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON
-DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON
-DLIBCXX_STATICALLY_LINK_ABI_IN_SHARED_LIBRARY=OFF
-DLIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY=ON
-DLIBCXX_USE_COMPILER_RT=ON
-DLIBCXX_HAS_ATOMIC_LIB=OFF
-DLIBCXX_ENABLE_FILESYSTEM=ON
-DLIBCXX_HAS_WIN32_THREAD_API=ON
-DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON
-DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_SHARED_LIBRARY=OFF
-DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_STATIC_LIBRARY=ON
-DLIBCXXABI_USE_COMPILER_RT=ON
-DLIBCXXABI_USE_LLVM_UNWINDER=ON
-DLIBCXXABI_ENABLE_NEW_DELETE_DEFINITIONS=OFF
-DLIBUNWIND_USE_COMPILER_RT=ON
-DCOMPILER_RT_BUILD_SANITIZERS=OFF
-DCOMPILER_RT_BUILD_XRAY=OFF
-DCOMPILER_RT_BUILD_LIBFUZZER=OFF
-DCOMPILER_RT_BUILD_PROFILE=OFF
-DSANITIZER_CXX_ABI=libc++
-DSANITIZER_TEST_CXX=libc++
EOF
    else
        # Cross-compile from Linux
        cat << 'EOF'
-DCMAKE_SYSTEM_NAME=Windows
-DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc
-DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++
-DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres
-DCMAKE_FIND_ROOT_PATH=/usr/x86_64-w64-mingw32
-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF
-DLLVM_ENABLE_LIBXML2=OFF
-DLLVM_ENABLE_LIBCXX=OFF
-DCLANG_DEFAULT_CXX_STDLIB=libstdc++
-DCMAKE_POSITION_INDEPENDENT_CODE=ON
-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF
-DLLVM_DEFAULT_TARGET_TRIPLE=x86_64-w64-mingw32
-DLLVM_HOST_TRIPLE=x86_64-w64-mingw32
-DLLVM_TARGET_ARCH=x86_64
-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON
-DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON
-DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON
-DLIBCXX_STATICALLY_LINK_ABI_IN_SHARED_LIBRARY=OFF
-DLIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY=ON
-DLIBCXX_USE_COMPILER_RT=ON
-DLIBCXX_HAS_ATOMIC_LIB=OFF
-DLIBCXX_ENABLE_FILESYSTEM=ON
-DLIBCXX_HAS_WIN32_THREAD_API=ON
-DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON
-DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_SHARED_LIBRARY=OFF
-DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_STATIC_LIBRARY=ON
-DLIBCXXABI_USE_COMPILER_RT=ON
-DLIBCXXABI_USE_LLVM_UNWINDER=ON
-DLIBCXXABI_ENABLE_NEW_DELETE_DEFINITIONS=OFF
-DLIBUNWIND_USE_COMPILER_RT=ON
-DCOMPILER_RT_BUILD_SANITIZERS=OFF
-DCOMPILER_RT_BUILD_XRAY=OFF
-DCOMPILER_RT_BUILD_LIBFUZZER=OFF
-DCOMPILER_RT_BUILD_PROFILE=OFF
-DSANITIZER_CXX_ABI=libc++
-DSANITIZER_TEST_CXX=libc++
EOF
        # Add native tool directory if available
        if [[ -n "$LLVM_NATIVE_TOOL_DIR" ]]; then
            echo "-DLLVM_NATIVE_TOOL_DIR=$LLVM_NATIVE_TOOL_DIR"
        fi
    fi
}

# Function to get platform-specific CMake arguments
get_platform_cmake_args() {
    local target="$1"
    local is_cross_compile="$2"

    case "$target" in
        *-apple-darwin)
            get_macos_cmake_args "$target"
            ;;
        *-linux-gnu*)
            get_linux_cmake_args "$target" "$is_cross_compile"
            ;;
        *-mingw32)
            get_mingw_cmake_args
            ;;
        *)
            echo "Unknown target platform: $target" >&2
            return 1
            ;;
    esac
}

# Function to set up cross-compilation environment
setup_cross_compile_env() {
    local target="$1"

    case "$target" in
        aarch64-linux-gnu)
            if [[ "$HOST_OS" == "Linux" && "$HOST_ARCH" != "aarch64" ]]; then
                export CC=aarch64-linux-gnu-gcc
                export CXX=aarch64-linux-gnu-g++
                export AR=aarch64-linux-gnu-ar
                export RANLIB=aarch64-linux-gnu-ranlib
                export STRIP=aarch64-linux-gnu-strip
            fi
            ;;
        arm-linux-gnueabihf)
            if [[ "$HOST_OS" == "Linux" && "$HOST_ARCH" != "arm" ]]; then
                export CC=arm-linux-gnueabihf-gcc
                export CXX=arm-linux-gnueabihf-g++
                export AR=arm-linux-gnueabihf-ar
                export RANLIB=arm-linux-gnueabihf-ranlib
                export STRIP=arm-linux-gnueabihf-strip
            fi
            ;;
        x86_64-linux-gnu)
            if [[ "$HOST_OS" == "Linux" && "$HOST_ARCH" != "x86_64" ]]; then
                if command -v x86_64-linux-gnu-gcc >/dev/null 2>&1; then
                    export CC=x86_64-linux-gnu-gcc
                    export CXX=x86_64-linux-gnu-g++
                    export AR=x86_64-linux-gnu-ar
                    export RANLIB=x86_64-linux-gnu-ranlib
                    export STRIP=x86_64-linux-gnu-strip
                fi
            fi
            ;;
        x86_64-w64-mingw32)
            if [[ "$HOST_OS" == "Linux" ]]; then
                export CC=x86_64-w64-mingw32-gcc
                export CXX=x86_64-w64-mingw32-g++
                export AR=x86_64-w64-mingw32-ar
                export RANLIB=x86_64-w64-mingw32-ranlib
                export STRIP=x86_64-w64-mingw32-strip
            elif [[ "$HOST_OS" == "Windows_NT" ]]; then
                if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
                    export CC=x86_64-w64-mingw32-gcc
                    export CXX=x86_64-w64-mingw32-g++
                    export AR=x86_64-w64-mingw32-ar
                    export RANLIB=x86_64-w64-mingw32-ranlib
                    export STRIP=x86_64-w64-mingw32-strip
                elif [[ -d "/c/mingw64" ]]; then
                    export PATH="/c/mingw64/bin:$PATH"
                    export CC=gcc
                    export CXX=g++
                elif [[ -d "/mingw64" ]]; then
                    export PATH="/mingw64/bin:$PATH"
                    export CC=gcc
                    export CXX=g++
                fi
            fi
            ;;
    esac
}

# Function to get number of CPU cores
get_cpu_cores() {
    if [[ "$HOST_OS" == "Darwin" ]]; then
        sysctl -n hw.ncpu
    elif [[ "$HOST_OS" == "Linux" ]]; then
        nproc
    elif [[ "$HOST_OS" == "Windows_NT" ]]; then
        echo "${NUMBER_OF_PROCESSORS:-4}"
    else
        echo "4"
    fi
}

# Function to create release directory structure
create_release_structure() {
    local target="$1"
    local install_dir="$2"
    local release_dir="dist/${target}/esp-clang"

    echo "Creating release package for $target..."

    # Create release directory
    rm -rf "dist/${target}"
    mkdir -p "$release_dir"

    # Copy the installed files
    cp -r "$install_dir"/* "$release_dir"/

    # Create tarball
    mkdir -p dist
    cd "dist/${target}"
    tar -cJf "../clang-esp-${VERSION_STRING}-${target}.tar.xz" esp-clang/
    cd - > /dev/null

    echo "Package created: dist/clang-esp-${VERSION_STRING}-${target}.tar.xz ($(du -h "dist/clang-esp-${VERSION_STRING}-${target}.tar.xz" | cut -f1))"
}

# Function to build just LLVM/Clang without runtimes on first pass
build_stage1() {
    local target="$1"
    local build_dir="$2"
    local install_dir="$3"

    echo "Stage 1: Building LLVM/Clang core tools for $target..."

    # Create stage1 cmake args without runtimes
    local cmake_args_file=$(mktemp)
    {
        cat << 'EOF'
-G Ninja
-DCMAKE_BUILD_TYPE=Release
-DLLVM_TARGETS_TO_BUILD=X86;ARM;AArch64;AVR;Mips;RISCV;WebAssembly
-DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Xtensa
-DLLVM_ENABLE_PROJECTS=clang;lld
-DLLVM_POLLY_LINK_INTO_TOOLS=ON
-DLLVM_BUILD_EXTERNAL_COMPILER_RT=ON
-DLLVM_ENABLE_EH=ON
-DLLVM_ENABLE_FFI=ON
-DLLVM_ENABLE_RTTI=ON
-DLLVM_INCLUDE_DOCS=OFF
-DLLVM_INCLUDE_TESTS=OFF
-DLLVM_INSTALL_UTILS=ON
-DLLVM_ENABLE_Z3_SOLVER=OFF
-DLLVM_OPTIMIZED_TABLEGEN=ON
-DLLVM_USE_RELATIVE_PATHS_IN_FILES=ON
-DLLVM_SOURCE_PREFIX=.
-DCLANG_FORCE_MATCHING_LIBCLANG_SOVERSION=OFF
EOF
        get_platform_cmake_args "$target"
        echo "-DCMAKE_INSTALL_PREFIX=$install_dir"
    } > "$cmake_args_file"

    # Configure Stage 1
    cd "$build_dir"
    cmake "../../$LLVM_PROJECTDIR/llvm" $(cat "$cmake_args_file" | tr '\n' ' ')

    # Build Stage 1
    local cores=$(get_cpu_cores)
    echo "Building stage 1 with $cores CPU cores"
    ninja -j"$cores" clang lld

    # Install Stage 1
    ninja install-clang install-lld

    cd - > /dev/null
    rm -f "$cmake_args_file"

    echo "Stage 1 completed successfully!"
}

# Function to build with full runtimes using stage1 compiler
build_stage2() {
    local target="$1"
    local build_dir="$2"
    local install_dir="$3"

    echo "Stage 2: Building full LLVM with runtimes for $target..."

    # Create stage2 build directory
    local stage2_dir="${build_dir}-stage2"
    mkdir -p "$stage2_dir"

    # Prepare full CMake arguments with runtimes
    local cmake_args_file=$(mktemp)
    {
        get_base_cmake_args
        get_platform_cmake_args "$target"
        echo "-DCMAKE_INSTALL_PREFIX=$install_dir"

        # Use stage1 compiler for MinGW
        if [[ "$target" == *mingw32 && "$HOST_OS" == "Windows_NT" ]]; then
            echo "-DCMAKE_C_COMPILER=$install_dir/bin/clang.exe"
            echo "-DCMAKE_CXX_COMPILER=$install_dir/bin/clang++.exe"
        fi
    } > "$cmake_args_file"

    echo "Stage 2 CMake configuration:"
    cat "$cmake_args_file"
    echo ""

    # Configure Stage 2
    cd "$stage2_dir"
    cmake "../../$LLVM_PROJECTDIR/llvm" $(cat "$cmake_args_file" | tr '\n' ' ')

    # Build Stage 2
    local cores=$(get_cpu_cores)
    echo "Building stage 2 with $cores CPU cores"
    ninja -j"$cores"

    # Install Stage 2
    ninja install

    cd - > /dev/null
    rm -f "$cmake_args_file"

    echo "Stage 2 completed successfully!"
}

# Main build function
build_platform() {
    local target="$1"

    echo "Building LLVM $VERSION_STRING for $target..."

    # Check if we need cross-compilation
    local is_cross_compile="false"
    if needs_cross_compilation "$target"; then
        is_cross_compile="true"
        echo "Cross-compilation required"

        # Build native tools first
        if [[ "$HOST_OS" == "Linux" ]]; then
            build_native_tools "$target"
        fi
    fi

    # Create build and install directories
    local build_dir="$BUILD_DIR_BASE/$target"
    local install_dir="$PWD/install/$target"

    rm -rf "$build_dir" "$install_dir"
    mkdir -p "$build_dir" "$install_dir"

    # Set up cross-compilation environment
    setup_cross_compile_env "$target"

    # For MinGW, use two-stage build
    if [[ "$target" == *mingw32 ]]; then
        build_stage1 "$target" "$build_dir" "$install_dir"
        build_stage2 "$target" "$build_dir" "$install_dir"
    else
        # Single stage build
        local cmake_args_file=$(mktemp)
        {
            get_base_cmake_args
            get_platform_cmake_args "$target" "$is_cross_compile"
            echo "-DCMAKE_INSTALL_PREFIX=$install_dir"
        } > "$cmake_args_file"

        echo "Configuring..."
        cd "$build_dir"
        cmake "../../$LLVM_PROJECTDIR/llvm" $(cat "$cmake_args_file" | tr '\n' ' ')

        echo "Building..."
        ninja -j$(get_cpu_cores)

        echo "Installing..."
        ninja install

        cd - > /dev/null
        rm -f "$cmake_args_file"
    fi

    # Create release package
    create_release_structure "$target" "$install_dir"

    # Clean up build directory and native tools
    if [[ "${KEEP_BUILD_DIR:-false}" != "true" ]]; then
        rm -rf "$build_dir" "${build_dir}-stage2"
        if [[ "$is_cross_compile" == "true" ]]; then
            rm -rf "$BUILD_DIR_BASE/native-tools-${target}" "$PWD/install/native-tools-${target}"
        fi
    fi

    echo "Build completed for $target"
}

# Function to check for required cross-compilation tools
check_cross_compile_tools() {
    local target="$1"

    if ! needs_cross_compilation "$target"; then
        return 0
    fi

    case "$target" in
        aarch64-linux-gnu)
            if [[ "$HOST_OS" == "Linux" ]] && ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
                echo "Error: aarch64-linux-gnu cross-compilation tools not found"
                return 1
            fi
            ;;
        arm-linux-gnueabihf)
            if [[ "$HOST_OS" == "Linux" ]] && ! command -v arm-linux-gnueabihf-gcc >/dev/null 2>&1; then
                echo "Error: arm-linux-gnueabihf cross-compilation tools not found"
                return 1
            fi
            ;;
        x86_64-w64-mingw32)
            if [[ "$HOST_OS" == "Linux" ]] && ! command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
                echo "Error: x86_64-w64-mingw32 cross-compilation tools not found"
                return 1
            fi
            ;;
    esac

    return 0
}

# Main script logic
main() {
    if [[ $# -ne 1 ]]; then
        show_usage
        exit 1
    fi

    local target="$1"

    # Validate target
    local target_valid=0
    for valid_target in $VALID_TARGETS; do
        if [[ "$target" == "$valid_target" ]]; then
            target_valid=1
            break
        fi
    done

    if [[ $target_valid -eq 0 ]]; then
        echo "Error: Invalid target '$target'"
        echo ""
        show_usage
        exit 1
    fi

    # Check for required tools
    if ! command -v cmake >/dev/null 2>&1; then
        echo "Error: cmake is required but not installed"
        exit 1
    fi

    if ! command -v ninja >/dev/null 2>&1; then
        echo "Error: ninja is required but not installed"
        exit 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        echo "Error: git is required but not installed"
        exit 1
    fi

    # Check for cross-compilation tools if needed
    if ! check_cross_compile_tools "$target"; then
        exit 1
    fi

    # Download LLVM source
    download_llvm_source

    # Build the platform
    build_platform "$target"
}

# Run main function
main "$@"
