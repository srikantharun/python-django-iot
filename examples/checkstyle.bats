#!/usr/bin/env bats
# ================================================================
# checkstyle.bats – Bats tests for src/lint/jobs/checkstyle.sh
#
# Tests the Checkstyle linting script which runs checkstyle:check
# via Maven.
#
# Exit codes:
#   0  - clean code, no violations
#   80 - invalid ruleset or custom ruleset missing suppressions file
#   100 - checkstyle violations detected
#   1  - Maven/infrastructure failure
#
# Requirements: Maven + JDK on PATH (use 'mise install' to set up)
#
# Run with: mise exec - bats tests/lint/checkstyle.bats
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
    SCRIPT_UNDER_TEST="$PROJECT_ROOT/src/lint/jobs/checkstyle.sh"
    export FIXTURES_DIR="$PROJECT_ROOT/tests/lint/fixtures"

    REPORT_FILE="checkstyle-result.xml"
    VIOLATION_PATTERN="<error "

    # Load vendor libraries if available
    if [ -d "$PROJECT_ROOT/vendor/bats-support" ]; then
        load "$PROJECT_ROOT/vendor/bats-support/load"
        load "$PROJECT_ROOT/vendor/bats-assert/load"
        load "$PROJECT_ROOT/vendor/bats-file/load"
    fi

    # Load shared helpers (common helpers only)
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

# ================================================================
# 1. CLEAN CODE - generates report with 0 violations (exit 0)
# ================================================================

@test "clean code generates report with 0 violations" {
    prepare_fixture "clean"

    run "$SCRIPT_UNDER_TEST"

    assert_success
    assert_report_exists
    assert_no_violations
}

# ================================================================
# CHECKSTYLE VIOLATIONS - all exit 100
# ================================================================

# ================================================================
# 2. STAR IMPORTS (AvoidStarImport)
#    Rule: Wildcard imports like 'import java.util.*' are forbidden.
# ================================================================

@test "star import generates report with AvoidStarImport violation" {
    prepare_fixture "star-import"

    run "$SCRIPT_UNDER_TEST"

    assert_failure 100
    assert_report_exists
    assert_has_violations
    assert_violation_in_report "AvoidStarImport"
}

# ================================================================
# 3. MISSING BRACES (NeedBraces)
#    Rule: if/else/for/while must use braces even for single statements.
# ================================================================

@test "missing braces generates report with NeedBraces violation" {
    prepare_fixture "missing-braces"

    run "$SCRIPT_UNDER_TEST"

    assert_failure 100
    assert_report_exists
    assert_has_violations
    assert_violation_in_report "NeedBraces"
}

# ================================================================
# 4. LINE TOO LONG (LineLength)
#    Rule: Lines must not exceed 100 characters.
# ================================================================

@test "long line generates report with LineLength violation" {
    prepare_fixture "line-too-long"

    run "$SCRIPT_UNDER_TEST"

    assert_failure 100
    assert_report_exists
    assert_has_violations
    assert_violation_in_report "LineLength"
}

# ================================================================
# 5. WRONG INDENTATION (Indentation)
#    Rule: Google style requires 2-space indentation, not 4.
# ================================================================

@test "4-space indentation generates report with Indentation violation" {
    prepare_fixture "wrong-indentation"

    run "$SCRIPT_UNDER_TEST"

    assert_failure 100
    assert_report_exists
    assert_has_violations
    assert_violation_in_report "Indentation"
}

# ================================================================
# 6. EMPTY CATCH BLOCK (EmptyCatchBlock)
#    Rule: Catch blocks must not be empty – at minimum add a comment.
# ================================================================

@test "empty catch generates report with EmptyCatchBlock violation" {
    prepare_fixture "empty-catch"

    run "$SCRIPT_UNDER_TEST"

    assert_failure 100
    assert_report_exists
    assert_has_violations
    assert_violation_in_report "EmptyCatchBlock"
}

# ================================================================
# 7. MISSING JAVADOC (MissingJavadocType)
#    Rule: Public classes and interfaces must have a javadoc comment.
# ================================================================

@test "missing javadoc generates report with MissingJavadocType violation" {
    prepare_fixture "missing-javadoc"

    run "$SCRIPT_UNDER_TEST"

    assert_failure 100
    assert_report_exists
    assert_has_violations
    assert_violation_in_report "MissingJavadocType"
}

# ================================================================
# CHECKSTYLE SUPPRESSIONS
# ================================================================

@test "suppressions file suppresses violations" {
    prepare_fixture "missing-javadoc"

    local component_dir
    component_dir="$(cd "$(dirname "$SCRIPT_UNDER_TEST")/.." && pwd)"

    cat >"$component_dir/checkstyle-suppressions.xml" <<XML
<?xml version="1.0"?>
<!DOCTYPE suppressions PUBLIC
    "-//Checkstyle//DTD SuppressionFilter Configuration 1.0//EN"
    "https://checkstyle.org/dtds/suppressions_1_0.dtd">
<suppressions>
    <suppress checks="MissingJavadocType" files=".*"/>
    <suppress checks="MissingJavadocMethod" files=".*"/>
</suppressions>
XML

    run "$SCRIPT_UNDER_TEST"

    rm -f "$component_dir/checkstyle-suppressions.xml"

    assert_report_exists
    assert_no_violations
}

@test "component-level suppressions file is used as fallback" {
    prepare_fixture "missing-javadoc"

    local component_dir
    component_dir="$(cd "$(dirname "$SCRIPT_UNDER_TEST")/.." && pwd)"

    cat >"$component_dir/checkstyle-suppressions.xml" <<XML
<?xml version="1.0"?>
<!DOCTYPE suppressions PUBLIC
    "-//Checkstyle//DTD SuppressionFilter Configuration 1.0//EN"
    "https://checkstyle.org/dtds/suppressions_1_0.dtd">
<suppressions>
    <suppress checks="MissingJavadocType" files=".*"/>
    <suppress checks="MissingJavadocMethod" files=".*"/>
</suppressions>
XML

    run "$SCRIPT_UNDER_TEST"

    rm -f "$component_dir/checkstyle-suppressions.xml"

    assert_report_exists
    assert_no_violations
}

# ================================================================
# MVN COMMAND VERIFICATION - mock mvn to verify args
# ================================================================

@test "uses default CHECKSTYLE_VERSION 3.6.0 when not overridden" {
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

    run grep -q "maven-checkstyle-plugin:3.6.0:check" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_success
    run grep -q "compile" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_success
}

@test "mvn command includes compile and checkstyle plugin" {
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
    run grep -q "maven-checkstyle-plugin" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_success
    # Verify spotbugs is NOT present (separate job now)
    run grep -q "spotbugs-maven-plugin" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_failure
}

@test "mvn command includes failOnViolation=false" {
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

    run grep -q "checkstyle.failOnViolation=false" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_success
}

@test "mvn command includes google_checks.xml config" {
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

    run grep -q "checkstyle.config.location=google_checks.xml" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_success
    run grep -q "checkstyle.violationSeverity=warning" "$TEST_SANDBOX/mvn_args_captured.txt"
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
# SUPPRESSION ENFORCEMENT - removes custom suppressionsLocation
# from pom.xml
# ================================================================

@test "removes custom suppressionsLocation from pom.xml" {
    prepare_fixture "clean"

    cat > "$TEST_SANDBOX/pom.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>test</artifactId>
    <version>1.0.0</version>
    <suppressionsLocation>custom/path.xml</suppressionsLocation>
</project>
XML

    grep 'suppressionsLocation' "$TEST_SANDBOX/pom.xml" >&3 || echo "# WARNING: tag not inserted!" >&3

    cd "$TEST_SANDBOX"

    run "$SCRIPT_UNDER_TEST"

    run grep -q '<suppressionsLocation>' "$TEST_SANDBOX/pom.xml"
    assert_failure
}

@test "pom.xml remains valid after suppressionsLocation removal" {
    prepare_fixture "clean"

    cat > "$TEST_SANDBOX/pom.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>test</artifactId>
    <version>1.0.0</version>
    <suppressionsLocation>custom/path.xml</suppressionsLocation>
</project>
XML

    cd "$TEST_SANDBOX"

    run "$SCRIPT_UNDER_TEST"

    run mvn -f "$TEST_SANDBOX/pom.xml" validate -q
    assert_success
}

@test "removes multi-line suppressionsLocation from pom.xml" {
    prepare_fixture "clean"

    cat > "$TEST_SANDBOX/pom.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>test</artifactId>
    <version>1.0.0</version>
    <suppressionsLocation>
        custom/path.xml
    </suppressionsLocation>
</project>
XML

    cd "$TEST_SANDBOX"

    run "$SCRIPT_UNDER_TEST"

    run grep -q '<suppressionsLocation>' "$TEST_SANDBOX/pom.xml"
    assert_failure

    run mvn -f "$TEST_SANDBOX/pom.xml" validate -q
    assert_success
}

# ================================================================
# TROUBLESHOOT & OUTPUT COVERAGE - mock mvn with fake reports
# ================================================================

@test "troubleshoot_100 outputs guidance when checkstyle violations detected" {
    mkdir -p "$TEST_SANDBOX/bin" "$TEST_SANDBOX/target"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
mkdir -p target
cat > target/checkstyle-result.xml <<'REPORT'
<?xml version="1.0" encoding="UTF-8"?>
<checkstyle>
  <file name="Example.java">
    <error line="1" column="1" severity="warning" message="Missing Javadoc" source="MissingJavadocType"/>
  </file>
</checkstyle>
REPORT
exit 0
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    prepare_fixture "clean"

    run "$SCRIPT_UNDER_TEST"

    assert_failure 100
    assert_output --partial "not passed the linting checks"
}

@test "troubleshoot_100 shows suppression notice when custom suppressionsLocation was in pom" {
    mkdir -p "$TEST_SANDBOX/bin" "$TEST_SANDBOX/target"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
mkdir -p target
cat > target/checkstyle-result.xml <<'REPORT'
<?xml version="1.0" encoding="UTF-8"?>
<checkstyle>
  <file name="Example.java">
    <error line="1" column="1" severity="warning" message="Missing Javadoc" source="MissingJavadocType"/>
  </file>
</checkstyle>
REPORT
exit 0
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    prepare_fixture "clean"

    cat > "$TEST_SANDBOX/pom.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>test</artifactId>
    <version>1.0.0</version>
    <suppressionsLocation>custom/path.xml</suppressionsLocation>
</project>
XML

    cd "$TEST_SANDBOX"

    run "$SCRIPT_UNDER_TEST"

    assert_failure 100
    assert_output --partial "ignore any custom Checkstyle suppressions"
}

@test "troubleshoot_100 shows suppression notice when local suppressions file exists" {
    mkdir -p "$TEST_SANDBOX/bin" "$TEST_SANDBOX/target"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
mkdir -p target
cat > target/checkstyle-result.xml <<'REPORT'
<?xml version="1.0" encoding="UTF-8"?>
<checkstyle>
  <file name="Example.java">
    <error line="1" column="1" severity="warning" message="Missing Javadoc" source="MissingJavadocType"/>
  </file>
</checkstyle>
REPORT
exit 0
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    prepare_fixture "clean"

    touch "$TEST_SANDBOX/checkstyle-suppressions.xml"

    cd "$TEST_SANDBOX"

    run "$SCRIPT_UNDER_TEST"

    assert_failure 100
    assert_output --partial "ignore any custom Checkstyle suppressions"
}

@test "success path outputs completion message" {
    mkdir -p "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
mkdir -p target
cat > target/checkstyle-result.xml <<'REPORT'
<?xml version="1.0" encoding="UTF-8"?>
<checkstyle>
  <file name="Example.java"/>
</checkstyle>
REPORT
exit 0
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    prepare_fixture "clean"

    run "$SCRIPT_UNDER_TEST"

    assert_success
    assert_output --partial "Checkstyle analysis completed successfully"
}

# ================================================================
# Always create gl-code-quality-checkstyle.json report file
# ================================================================

@test "pre-create empty gl-code-quality-checkstyle.json on success" {
    mkdir -p "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
mkdir -p target
cat > target/checkstyle-result.xml <<'REPORT'
<?xml version="1.0" encoding="UTF-8"?>
<checkstyle>
  <file name="Example.java"/>
</checkstyle>
REPORT
exit 0
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    cd "$TEST_SANDBOX"
    run "$SCRIPT_UNDER_TEST"

    assert_success
    assert [ -f "$TEST_SANDBOX/gl-code-quality-checkstyle.json" ]
    assert_equal "$(cat "$TEST_SANDBOX/gl-code-quality-checkstyle.json")" "[]"
}

@test "pre-create empty gl-code-quality-checkstyle.json when mvn fails" {
    mkdir -p "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
exit 1
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    cd "$TEST_SANDBOX"
    run "$SCRIPT_UNDER_TEST"

    assert_failure
    assert [ -f "$TEST_SANDBOX/gl-code-quality-checkstyle.json" ]
    assert_equal "$(cat "$TEST_SANDBOX/gl-code-quality-checkstyle.json")" "[]"
}

# ================================================================
# RULESET - recommended vs custom
# ================================================================

@test "recommended ruleset: enforces component suppressions and logs ruleset used" {
    mkdir -p "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
echo "\$@" > "$TEST_SANDBOX/mvn_args_captured.txt"
mkdir -p target
cat > target/checkstyle-result.xml <<'REPORT'
<?xml version="1.0" encoding="UTF-8"?>
<checkstyle>
  <file name="Example.java"/>
</checkstyle>
REPORT
exit 0
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    prepare_fixture "clean"

    # Place a project-level suppressions file — recommended mode should ignore it
    cat > "$TEST_SANDBOX/checkstyle-suppressions.xml" <<XML
<?xml version="1.0"?>
<suppressions>
    <suppress checks="MissingJavadocType" files=".*"/>
</suppressions>
XML

    cd "$TEST_SANDBOX"
    RULESET=recommended run "$SCRIPT_UNDER_TEST"

    assert_success
    assert_output --partial "The 'recommended' ruleset was used."
}

@test "custom ruleset: uses project checkstyle-suppressions.xml and logs it" {
    mkdir -p "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
echo "\$@" > "$TEST_SANDBOX/mvn_args_captured.txt"
mkdir -p target
cat > target/checkstyle-result.xml <<'REPORT'
<?xml version="1.0" encoding="UTF-8"?>
<checkstyle>
  <file name="Example.java"/>
</checkstyle>
REPORT
exit 0
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    prepare_fixture "clean"

    # Project provides its own suppressions file
    cat > "$TEST_SANDBOX/checkstyle-suppressions.xml" <<XML
<?xml version="1.0"?>
<suppressions>
    <suppress checks="MissingJavadocType" files=".*"/>
</suppressions>
XML

    cd "$TEST_SANDBOX"
    RULESET=custom run "$SCRIPT_UNDER_TEST"

    assert_success
    assert_output --partial "A custom ruleset, found in 'checkstyle-suppressions.xml', was used."
    # Verify the project suppressions file path was passed to mvn
    run grep -q "checkstyle-suppressions.xml" "$TEST_SANDBOX/mvn_args_captured.txt"
    assert_success
}

@test "custom ruleset: hard fails exit 80 when no checkstyle-suppressions.xml found" {
    mkdir -p "$TEST_SANDBOX/bin"
    cat > "$TEST_SANDBOX/bin/mvn" <<MOCK
#!/usr/bin/env bash
exit 0
MOCK
    chmod +x "$TEST_SANDBOX/bin/mvn"
    PATH="$TEST_SANDBOX/bin:$PATH"

    prepare_fixture "clean"

    # Ensure no suppressions file exists in sandbox
    rm -f "$TEST_SANDBOX/checkstyle-suppressions.xml"

    cd "$TEST_SANDBOX"
    RULESET=custom run "$SCRIPT_UNDER_TEST"

    assert_failure 80
    assert_output --partial "no checkstyle-suppressions.xml was found"
}

@test "fails with exit 80 for invalid RULESET value" {
    prepare_fixture "clean"

    cd "$TEST_SANDBOX"
    RULESET=invalid run "$SCRIPT_UNDER_TEST"

    assert_failure 80
    assert_output --partial "Invalid ruleset value: invalid"
    assert_output --partial "Valid values: recommended custom"
}
