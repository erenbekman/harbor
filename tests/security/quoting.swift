import Foundation

let hostile = [
    "/tmp/a'; touch /tmp/harbor-pwned-1; echo '",
    "/tmp/a$(touch /tmp/harbor-pwned-2)b",
    "/tmp/a`touch /tmp/harbor-pwned-3`b",
    "/tmp/a; rm -rf /tmp/harbor-pwned-dir; echo x",
    "/tmp/a\"; touch /tmp/harbor-pwned-4; \"",
]

var failures = 0
for value in hostile {
    let result = Shell.run("/bin/zsh", ["-l", "-c", "printf '%s' \(Shell.quoted(value))"])
    if result.output != value {
        failures += 1
        print("FAIL  \(value)\n      got: \(result.output)")
    }
}

let marks = (1...4).map { "/tmp/harbor-pwned-\($0)" }.filter { FileManager.default.fileExists(atPath: $0) }
if !marks.isEmpty {
    failures += 1
    print("FAIL  injection created \(marks)")
}

print(failures == 0 ? "PASS  quoting: \(hostile.count) hostile strings stayed literal"
                    : "FAIL  quoting: \(failures) problem(s)")
exit(failures == 0 ? 0 : 1)
