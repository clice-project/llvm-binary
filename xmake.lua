set_policy("compatibility.version", "3.0")

add_requires("llvm", {
    system = false,
    configs = {
        asan = is_mode("debug"),
        shared = is_mode("debug") and not is_plat("windows"),
    },
})

package("llvm")
    -- switch to tarball when llvm 20 release
    set_urls("https://github.com/llvm/llvm-project.git")

    add_versions("20.0.0", "fac46469977da9c4e9c6eeaac21103c971190577") -- 2025.01.04

    if is_plat("windows") then
        add_configs("runtimes", {description = "Set compiler runtimes.", default = "MD", readonly = true})
    end

    add_deps("cmake", "ninja", "python 3.x", {kind = "binary"})

    if is_plat("windows", "mingw") then
        add_syslinks("version", "ntdll")
    end

    on_load(function (package)
        package:set("installdir", path.join(os.scriptdir(), "build/package"))
    end)

    on_install(function (package)
        -- Some tool can't disable by `CLANG_BUILD_TOOLS`
        io.replace("clang/CMakeLists.txt", "add_subdirectory(tools)", "", {plain = true})

        local configs = {
            "-DLLVM_INCLUDE_DOCS=OFF",
            "-DLLVM_INCLUDE_TESTS=OFF",
            "-DLLVM_INCLUDE_EXAMPLES=OFF",
            "-DLLVM_INCLUDE_BENCHMARKS=OFF",

            "-DCLANG_BUILD_TOOLS=OFF",
            "-DLLVM_BUILD_TOOLS=OFF",
            "-DLLVM_BUILD_UTILS=OFF",

            "-DLLVM_ENABLE_ZLIB=OFF",
            "-DLLVM_ENABLE_ZSTD=OFF",

            "-DLLVM_LINK_LLVM_DYLIB=OFF",
            "-DLLVM_ENABLE_RTTI=OFF",

            "-DLLVM_ENABLE_PROJECTS=clang",
            "-DLLVM_TARGETS_TO_BUILD=X86",
        }
        table.insert(configs, "-DCMAKE_BUILD_TYPE=" .. (package:is_debug() and "Debug" or "Release"))
        table.insert(configs, "-DBUILD_SHARED_LIBS=" .. (package:config("shared") and "ON" or "OFF"))
        if package:is_plat("windows") then
            table.insert(configs, "-DCMAKE_C_COMPILER=clang")
            table.insert(configs, "-DCMAKE_CXX_COMPILER=clang++")
        end

        local opt = {}
        opt.target = {
            "LLVMSupport",
            "LLVMFrontendOpenMP",
            "clangAST",
            "clangASTMatchers",
            "clangBasic",
            "clangDependencyScanning",
            "clangDriver",
            "clangFormat",
            "clangFrontend",
            "clangIndex",
            "clangLex",
            "clangSema",
            "clangSerialization",
            "clangTooling",
            "clangToolingCore",
            "clangToolingInclusions",
            "clangToolingInclusionsStdlib",
            "clangToolingSyntax",
        }

        os.cd("llvm")
        import("package.tools.cmake").install(package, configs, opt)

        os.tryrm(package:installdir("bin"))

        os.vcp("../clang/lib/Headers", package:installdir("include"))

        local clang_include_dir = "../clang/lib/Sema"
        local install_clang_include_dir = package:installdir("include/clang/Sema")
        os.vcp(path.join(clang_include_dir, "CoroutineStmtBuilder.h"), install_clang_include_dir)
        os.vcp(path.join(clang_include_dir, "TypeLocBuilder.h"), install_clang_include_dir)
        os.vcp(path.join(clang_include_dir, "TreeTransform.h"), install_clang_include_dir)
    end)