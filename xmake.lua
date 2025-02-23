set_policy("compatibility.version", "3.0")

add_requires("llvm", {
    system = false,
    configs = {
        debug = is_mode("debug"),
        shared = is_mode("debug") and not is_plat("windows"),
    },
})

local sparse_checkout_list = {
    "cmake",
    "llvm",
    "clang",
    "clang-tools-extra",
}

if is_mode("debug") then
    table.insert(sparse_checkout_list, "runtimes")
    table.insert(sparse_checkout_list, "clang-tools-extra")
end

package("llvm")
    -- Use tarball when llvm 20 release
    set_urls("https://github.com/llvm/llvm-project.git", {includes = sparse_checkout_list})

    add_versions("20.0.0", "fac46469977da9c4e9c6eeaac21103c971190577") -- 2025.01.04

    if is_plat("windows") then
        add_configs("debug", {description = "Enable debug symbols.", default = false, type = "boolean", readonly = true})
    end

    add_deps("cmake", "ninja", "python 3.x", {kind = "binary"})

    if is_plat("windows", "mingw") then
        add_syslinks("version", "ntdll")
    end

    on_install(function (package)
        if not package:config("shared") then
            package:add("defines", "CLANG_BUILD_STATIC")
        end

        local configs = {
            "-DLLVM_INCLUDE_DOCS=OFF",
            "-DLLVM_INCLUDE_TESTS=OFF",
            "-DLLVM_INCLUDE_EXAMPLES=OFF",
            "-DLLVM_INCLUDE_BENCHMARKS=OFF",

            -- "-DCLANG_BUILD_TOOLS=OFF",
            "-DLLVM_BUILD_TOOLS=OFF",
            "-DLLVM_BUILD_UTILS=OFF",

            "-DLLVM_ENABLE_ZLIB=OFF",
            "-DLLVM_ENABLE_ZSTD=OFF",
            "-DLLVM_ENABLE_LIBXML2=OFF",

            "-DLLVM_LINK_LLVM_DYLIB=OFF",
            "-DLLVM_ENABLE_RTTI=OFF",

            -- "-DLLVM_ENABLE_PROJECTS=clang",
            "-DLLVM_TARGETS_TO_BUILD=X86",
        }
        table.insert(configs, "-DCMAKE_BUILD_TYPE=" .. (package:is_debug() and "Debug" or "Release"))
        table.insert(configs, "-DLLVM_USE_SANITIZER=" .. (package:is_debug() and "Address" or ""))
        table.insert(configs, "-DBUILD_SHARED_LIBS=" .. (package:config("shared") and "ON" or "OFF"))
        table.insert(configs, "-DLLVM_ENABLE_LTO=" .. (package:config("lto") and "ON" or "OFF"))
        if package:is_plat("windows") then
            table.insert(configs, "-DCMAKE_C_COMPILER=clang-cl")
            table.insert(configs, "-DCMAKE_CXX_COMPILER=clang-cl")
        end
        if package:is_debug() then
            table.insert(configs, "-DLLVM_ENABLE_PROJECTS=clang;clang-tools-extra")
            table.insert(configs, "-DLLVM_ENABLE_RUNTIMES=compiler-rt")
        else
            table.insert(configs, "-DLLVM_ENABLE_PROJECTS=clang;clang-tools-extra")
        end

        local opt = {}
        opt.buildir = path.join(package:sourcedir(), "build")
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
            "clangTidy",
            "clangTidyUtils",
        }

        os.cd("llvm")
        import("package.tools.cmake").install(package, configs, opt)

        if package:is_plat("windows") then
            for _, file in ipairs(os.files(package:installdir("bin/*"))) do
                if not file:endswith(".dll") then
                    os.rm(file)
                end
            end
        elseif package:is_plat("linux") then
            os.rm(package:installdir("bin/*"))
        end

        local clang_include_dir = "../clang/lib/Sema"
        local install_clang_include_dir = package:installdir("include/clang/Sema")
        os.vcp(path.join(clang_include_dir, "CoroutineStmtBuilder.h"), install_clang_include_dir)
        os.vcp(path.join(clang_include_dir, "TypeLocBuilder.h"), install_clang_include_dir)
        os.vcp(path.join(clang_include_dir, "TreeTransform.h"), install_clang_include_dir)

        local abi
        local format
        if package:is_plat("windows") then
            abi = "msvc"
            format = ".7z"
        elseif package:is_plat("linux") then
            abi = "gnu"
            format = ".tar.xz"
        end
        -- arch-plat-abi-mode
        local archive_name = table.concat({
            package:arch(),
            package:plat(),
            abi,
            package:is_debug() and "debug" or "release",
        }, "-")

        if package:config("lto") then
            archive_name = "-lto"
        end

        local archive_file = path.join(os.scriptdir(), "build/package", archive_name .. format)

        local opt = {}
        opt.recurse = true
        opt.compress = "best"
        opt.curdir = package:installdir()

        local archive_dirs
        if package:is_plat("windows") then
            archive_dirs = "*"
        elseif package:is_plat("linux") then
            -- workaround for tar
            archive_dirs = {}
            for _, dir in ipairs(os.dirs(path.join(opt.curdir, "*"))) do
                table.insert(archive_dirs, path.filename(dir))
            end
        end
        import("utils.archive").archive(archive_file, archive_dirs, opt)

        local checksum = hash.sha256(archive_file)
        print(checksum)
        io.writefile("build/package/" .. archive_name .. ".txt", checksum)
    end)
