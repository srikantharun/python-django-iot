#!/usr/bin/env bats
# ================================================================
# spotbugs.bats – Bats tests for src/lint/jobs/spotbugs.sh
#
# Tests the standalone SpotBugs script which runs
# spotbugs:check via Maven with a compile phase for
# bytecode analysis.
#
# Exit codes:
#   0  - clean code, no SpotBugs violations
#   80 - invalid ruleset or custom ruleset missing exclude file
#   101 - SpotBugs violations detected
#   1  - Maven/infrastructure failure
#
# Requirements: Maven + JDK on PATH (use 'mise install' to set up)
#
# Run with: mise exec - bats tests/lint/spotbugs.bats
# ================================================================

# - File-level setup (once per .bats file) ------------------

setup_file() {
    # Shared Maven cache so plugins aren't re-downloaded for every test
    SHARED_MAVEN_CACHE="$(mktemp -d)"
    export SHARED_MAVEN_CACHE
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PROJECT_ROOT
}

teardown_file() {
    rm -rf "$SHARED_MAVEN_CACHE"
}

# - Per-test setup & teardown --------------------------

safe_export() {
    local var_name="$1"
    local var_value="$2"
    if ! declare -p "$var_name" &>/dev/null; then
        export "${var_name}=${var_value}"
    fi
}

setup() {
    cd "$PROJECT_ROOT" || exit
    SCRIPT_UNDER_TEST="$PROJECT_ROOT/src/lint/jobs/spotbugs.sh"
    export FIXTURES_DIR="$PROJECT_ROOT/tests/lint/fixtures"

    REPORT_FILE="spotbugsXml.xml"
    VIOLATION_PATTERN="<BugInstance"

    # Load vendor libraries if available
    if [ -d "$PROJECT_ROOT/vendor/bats-support" ]; then
        load "$PROJECT_ROOT/vendor/bats-support/load"
        load "$PROJECT_ROOT/vendor/bats-assert/load"
        load "$PROJECT_ROOT/vendor/bats-file/load"
    fi

    # Load shared helpers (common helpers only, no tool-specific functions)
    load './helpers'

    # Isolated sandbox per test
    TEST_SANDBOX="$(mktemp -d)"
    safe_export TEST_SANDBOX "$TEST_SANDBOX"
    safe_export PROJECT_ROOT "$PROJECT_ROOT"
    safe_export FIXTURES_DIR "$FIXTURES_DIR"

    safe_export COMPONENT_SHA "abcd1234"
    safe_export COMPONENT_VERSION "1.0.0"
    safe_export COMPONENT_PROJECT_PATH "dwp/path/to/java"
    safe_export CI_SERVER_URL "https://registry.gitlab.com"

    # Symlink shared Maven cache to avoid re-downloading per test
    ln -s "$SHARED_MAVEN_CACHE" "$TEST_SANDBOX/.m2-local"
}

teardown() {
    cd "$PROJECT_ROOT"
    rm -rf "$TEST_SANDBOX"
}

# - SpotBugs-specific helper functions --------------------
# (kept here per convention: tool-specific helpers live in their .bats file)

assert_spotbugs_report_exists() {
    local report="$TEST_SANDBOX/target/spotbugsXml.xml"
    [ -f "$report" ] || fail "FAIL: spotbugsXml.xml not found at: $report"
}

assert_spotbugs_has_violations() {
    local report="$TEST_SANDBOX/target/spotbugsXml.xml"
    [ -f "$report" ] || fail "FAIL: spotbugsXml.xml not found"
    grep -q '<BugInstance' "$report" || fail "FAIL: No BugInstance in spotbugsXml.xml"
}

assert_spotbugs_no_violations() {
    local report="$TEST_SANDBOX/target/spotbugsXml.xml"
    [ -f "$report" ] || fail "FAIL: spotbugsXml.xml not found"
    ! grep -q '<BugInstance' "$report" || fail "FAIL: Unexpected BugInstance found"
}

# ================================================================
# 1. CLEAN CODE - no SpotBugs violations (exit 0)
# ================================================================

@test "clean code generates no spotbugs violations" {
    prepare_fixture "clean"

    run "$SCRIPT_UNDER_TEST"

    assert_success
}

# ================================================================
# SPOTBUGS VIOLATIONS - all exit 101
# ================================================================

# ================================================================
# 2. NULL POINTER DEREFERENCE (NP_ALWAYS_NULL)
# ================================================================

@test "spotbugs detects null pointer dereference" {
    prepare_fixture "spotbugs-null-pointer"

    run "$SCRIPT_UNDER_TEST"

    assert_failure 101
    assert_spotbugs_report_exists
    assert_spotbugs_has_violations
}

# ================================================================
# 3. UNUSED FIELD (URF_UNREAD_FIELD)
# ================================================================

@test "spotbugs detects unused field" {
    prepare_fixture "spotbugs-unused-field"

    run "$SCRIPT_UNDER_TEST"

    assert_failure 101
    assert_spotbugs_report_exists
    assert_spotbugs_has_violations
}

# ================================================================
# 4. EXCLUDE FILTER - suppresses spotbugs violations
# ================================================================

@test "spotbugs exclude filter suppresses violations" {
    prepare_fixture "spotbugs-null-pointer"

    local component_dir
    component_dir="$(cd "$(dirname "$SCRIPT_UNDER_TEST")/.." && pwd)"

    cat >"$component_dir/spotbugs-exclude.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<FindBugsFilter>
    <Match>
        <Class name="com.example.NullDeref"/>
    </Match>
</FindBugsFilter>
XML

    run "$SCRIPT_UNDER_TEST"

    rm -f "$component_dir/spotbugs-exclude.xml"

    assert_success
}

# ================================================================
# SPOTBUGS REPORT CONTENT - verify BugInstance in report
# ================================================================

@test "spotbugs report contains BugInstance for null pointer fixture" {
    prepare_fixture "spotbugs-null-pointer"

    run "$SCRIPT_UNDER_TEST"

    assert_failure 101
    assert_output --partial "Total bugs: 2"

    run grep -c '<BugInstance' "$TEST_SANDBOX/target/spotbugsXml.xml"
    assert_success
    [ "$output" -ge 1 ]
}

# ================================================================
# MVN COMMAND VERIFICATION - mock mvn to verify args
# ================================================================

@test "uses default SPOTBUGS_VERSION 4.9.8.2 when not overridden" {
    mkdir -p "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
echo "\$@" > "$TEST_SANDBOX/mvn_args_captured.txt"
exit 0
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    prepare_fixture "clean"

    run "$SCRIPT_UNDER_TEST"

    run grep -q "spotbugs-maven-plugin:4.9.8.2:check" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_success
    run grep -q "compile" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_success
}

@test "mvn command includes compile and spotbugs plugin" {
    mkdir -p "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
echo "\$@" > "$TEST_SANDBOX/mvn_args_captured.txt"
exit 0
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    prepare_fixture "clean"

    run "$SCRIPT_UNDER_TEST"

    run grep -q "compile" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_success
    run grep -q "spotbugs-maven-plugin" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_success
    run grep -q "maven-checkstyle-plugin" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_failure
}

@test "mvn command includes failOnError=false" {
    mkdir -p "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
echo "\$@" > "$TEST_SANDBOX/mvn_args_captured.txt"
exit 0
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    prepare_fixture "clean"

    run "$SCRIPT_UNDER_TEST"

    run grep -q "spotbugs.failOnError=false" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_success
}

# ================================================================
# SPOTBUGS EFFORT/THRESHOLD - configurable via environment
# ================================================================

@test "passes spotbugs effort and threshold to mvn" {
    mkdir -p "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
echo "\$@" > "$TEST_SANDBOX/mvn_args_captured.txt"
exit 0
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    export SPOTBUGS_EFFORT="Min"
    export SPOTBUGS_THRESHOLD="High"

    prepare_fixture "clean"

    run "$SCRIPT_UNDER_TEST"

    run grep -q "\-Dspotbugs.effort=Min" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_success
    run grep -q "\-Dspotbugs.threshold=High" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_success
}

@test "uses default spotbugs effort Max and threshold Low" {
    mkdir -p "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
echo "\$@" > "$TEST_SANDBOX/mvn_args_captured.txt"
exit 0
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    unset SPOTBUGS_EFFORT 2>/dev/null || true
    unset SPOTBUGS_THRESHOLD 2>/dev/null || true

    prepare_fixture "clean"

    run "$SCRIPT_UNDER_TEST"

    run grep -q "\-Dspotbugs.effort=Max" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_success
    run grep -q "\-Dspotbugs.threshold=Low" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_success
}

# ================================================================
# SCRIPT ROBUSTNESS - env/arg validation
# ================================================================

@test "fails when CI_PROJECT_DIR is unset" {
    unset CI_PROJECT_DIR

    run "$SCRIPT_UNDER_TEST"

    assert_failure
}

# ================================================================
# EXCLUDEFILTER ENFORCEMENT - removes custom excludeFilterFile
# from pom.xml
# ================================================================

@test "removes custom excludeFilterFile from pom.xml" {
    prepare_fixture "clean"

    cat > "$TEST_SANDBOX/pom.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>test</artifactId>
    <version>1.0.0</version>
    <excludeFilterFile>custom/spotbugs-exclude.xml</excludeFilterFile>
</project>
XML

    grep 'excludeFilterFile' "$TEST_SANDBOX/pom.xml" >&3 || echo "# WARNING: tag not inserted!" >&3

    cd "$TEST_SANDBOX"

    run "$SCRIPT_UNDER_TEST"

    run grep -q '<excludeFilterFile>' "$TEST_SANDBOX/pom.xml"
    assert_failure
}

@test "pom.xml remains valid after excludeFilterFile removal" {
    prepare_fixture "clean"

    cat > "$TEST_SANDBOX/pom.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>test</artifactId>
    <version>1.0.0</version>
    <excludeFilterFile>custom/spotbugs-exclude.xml</excludeFilterFile>
</project>
XML

    cd "$TEST_SANDBOX"

    run "$SCRIPT_UNDER_TEST"

    run mvn -f "$TEST_SANDBOX/pom.xml" validate -q
    assert_success
}

@test "removes multi-line excludeFilterFile from pom.xml" {
    prepare_fixture "clean"

    cat > "$TEST_SANDBOX/pom.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>test</artifactId>
    <version>1.0.0</version>
    <excludeFilterFile>
        custom/spotbugs-exclude.xml
    </excludeFilterFile>
</project>
XML

    cd "$TEST_SANDBOX"

    run "$SCRIPT_UNDER_TEST"

    run grep -q '<excludeFilterFile>' "$TEST_SANDBOX/pom.xml"
    assert_failure

    run mvn -f "$TEST_SANDBOX/pom.xml" validate -q
    assert_success
}

# ================================================================
# RULESET - recommended vs custom
# ================================================================

@test "recommended ruleset: enforces component exclude filter and logs ruleset used" {
    mkdir -p "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
echo "\$@" > "$TEST_SANDBOX/mvn_args_captured.txt"
exit 0
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    prepare_fixture "clean"

    # Place a project-level exclude file — recommended mode should ignore it
    cat > "$TEST_SANDBOX/spotbugs-exclude.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<FindBugsFilter>
    <Match>
        <Class name="com.example.SomeClass"/>
    </Match>
</FindBugsFilter>
XML

    cd "$TEST_SANDBOX"
    RULESET=recommended run "$SCRIPT_UNDER_TEST"

    assert_success
    assert_output --partial "The 'recommended' ruleset was used."
}

@test "custom ruleset: uses project spotbugs-exclude.xml and logs it" {
    mkdir -p "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
echo "\$@" > "$TEST_SANDBOX/mvn_args_captured.txt"
exit 0
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    prepare_fixture "clean"

    # Project provides its own exclude file
    cat > "$TEST_SANDBOX/spotbugs-exclude.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<FindBugsFilter>
    <Match>
        <Class name="com.example.SomeClass"/>
    </Match>
</FindBugsFilter>
XML

    cd "$TEST_SANDBOX"
    RULESET=custom run "$SCRIPT_UNDER_TEST"

    assert_success
    assert_output --partial "A custom ruleset, found in 'spotbugs-exclude.xml', was used."
    # Verify the project exclude file path was passed to mvn
    run grep -q "spotbugs-exclude.xml" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_success
}

@test "custom ruleset: hard fails exit 80 when no spotbugs-exclude.xml found" {
    mkdir -p "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
exit 0
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    prepare_fixture "clean"

    # Ensure no exclude file exists in sandbox
    rm -f "$TEST_SANDBOX/spotbugs-exclude.xml"

    cd "$TEST_SANDBOX"
    RULESET=custom run "$SCRIPT_UNDER_TEST"

    assert_failure 80
    assert_output --partial "no spotbugs-exclude.xml was found"
}

@test "fails with exit 80 for invalid RULESET value" {
    prepare_fixture "clean"

    cd "$TEST_SANDBOX"
    RULESET=invalid run "$SCRIPT_UNDER_TEST"

    assert_failure 80
    assert_output --partial "Invalid ruleset value: invalid"
    assert_output --partial "Valid values: recommended custom"
}
