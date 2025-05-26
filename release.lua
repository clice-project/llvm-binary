-- usage: xmake l release.lua
-- Add proxy: xmake g --proxy=ip:port

import("core.base.json")
import("core.base.global")

function _get_current_commit_hash()
    return os.iorunv("git rev-parse --short HEAD"):trim()
end

function _get_current_tag()
    return os.iorunv("git describe --tags --abbrev=0"):trim()
end

function main()
    local envs = {}
    if global.get("proxy") then
        envs.HTTPS_PROXY = global.get("proxy")
    end

    local tag = _get_current_tag()
    local current_commit = _get_current_commit_hash()

    print("current tag: ", tag)
    print("current commit: ", current_commit)

    local dir = path.join(os.scriptdir(), "artifacts", current_commit)
    os.mkdir(dir)

    -- Get latest workflow id
    for _, workflow in ipairs({"linux", "windows", "macos"}) do
        local result = json.decode(os.iorunv(format("gh run list --json databaseId --limit 1 --workflow=%s.yml", workflow)))
        for _, json in pairs(result) do
            -- float -> int
            local run_id = format("%d", json["databaseId"])
            -- download all artifacts
            os.execv("gh", {"run", "download", run_id, "--dir", dir}, {envs = envs})
        end
    end

    local binaries = {}
    table.join2(binaries, os.files(path.join(dir, "**.7z")))
    table.join2(binaries, os.files(path.join(dir, "**.tar.xz")))

    print(binaries)

    local release_message = {
        "Linux precompiled binary require glibc2.35 (build on ubuntu 22.04)",
        "sha256"
    }

    for _, binary in ipairs(binaries) do
        table.insert(release_message, format("%s: `%s`", path.filename(binary), hash.sha256(binary)))
    end

    release_message = table.concat(release_message, "\n")
    print(release_message)

    os.execv("gh", {"release", "create", tag, "--notes", release_message}, {envs = envs})
    -- clobber: overwrite
    for _, binary in ipairs(binaries) do
        os.execv("gh", {"release", "upload", tag, binary, "--clobber"}, {envs = envs})
    end
end
