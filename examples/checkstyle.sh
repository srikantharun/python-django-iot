#!/usr/bin/env bash

# Strict mode
set -euo pipefail

# Dependencies
# :nocov:
functions_dir="$(
      cd "$(dirname "${BASH_SOURCE[0]}")/../../shared/lib" || exit 1
      pwd
)"

component_dir="$(
      cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
      pwd
)"

shared_dir="$(
      cd "$(dirname "${BASH_SOURCE[0]}")/../../shared" || exit 1
      pwd
)"
# :nocov:

# shellcheck source=src/shared/lib/all.sh
. "$functions_dir/all.sh"

# shellcheck source=src/shared/compile-maven.sh
. "$shared_dir/compile-maven.sh"

# Troubleshooting guides.
# shellcheck disable=SC2329
troubleshoot_100() {
      local para1
      local para2

      # :nocov:
      { para1=$(cat); } <<-ENDMSG
            Your code has not passed the linting checks.

            The specific violations are shown above (prefixed with "[WARNING]"). If this pipeline is part of a Merge Request, they will also be shown in the Code Quality dashboard of that Merge Request.

            Try addressing all these violations, and letting another pipeline run to re-check.

      ENDMSG
      # :nocov:

      if [ "$TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_POM" == "1" ] || [ "$TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_FILE" == "1" ]; then
            # :nocov:
            { para2=$(cat); } <<-ENDMSG
                  Please note that this Component will ignore any custom Checkstyle suppressions and rules that you may have defined in your project.

                  If you'd like to suggest a change to these core rules, please raise an MR and submit for review in the component repository.

            ENDMSG
            # :nocov:
      fi

      echo "${para1}${para2:-}"
}

# Function to convert checkstyle report to GitLab format.
# Supports scenarios where there is a single file or a single error.
generate_gitlab_report() {
      local source_file="$1"
      local target_file="$2"

      # :nocov:
      { jq_query="$(cat)"; } <<-"EOF"
            .checkstyle.file
              | if type == "array" then .[] else . end as $file
              | $file.error
              | if type == "array" then .[] else . end
              | {
                  check_name: .["+@source"],
                  description: .["+@message"],
                  fingerprint: (
                    (
                      ($file["+@name"] | sub(".+?src/"; "src/")) + ":" +
                      .["+@line"] + ":" +
                      .["+@source"]
                    ) | @base64
                  ),
                  severity: (
                    if .["+@severity"] == "error" then "major"
                    elif .["+@severity"] == "warning" then "minor"
                    else "info"
                    end
                  ),
                  location: {
                    path: ($file["+@name"] | sub(".+?src/"; "src/")),
                    lines: {
                      begin: (.["+@line"] | tonumber)
                    }
                  }
                }
      EOF
      # :nocov:

      cat "$source_file" | yq -p xml -o json | jq "$jq_query" | jq -s >"$target_file"
}

# Main program.
main() {
      init_exit_handler
      init_component_environment "lint"

      # Script variables.
      local maven_settings_file="$shared_dir/settings.xml"
      local suppressions_file="$component_dir/checkstyle-suppressions.xml"
      local maven_repo_dir=".m2-local"

      # renovate: datasource=maven depName=org.apache.maven.plugins:maven-checkstyle-plugin
      local checkstyle_version="3.6.0"

      # Ruleset configuration — passed in via RULESET env var from lint.yml
      local ruleset="${RULESET:-recommended}"
      local valid_rulesets="recommended custom"

      # Define global context for conditional troubleshooting messaging.
      local TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_POM=0
      local TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_FILE=0

      # Validate ruleset is one of the allowed values
      if [[ " ${valid_rulesets} " != *" ${ruleset} "* ]]; then
            log_fail "Invalid ruleset value: ${ruleset}"
            log_info "Valid values: ${valid_rulesets}"
            exit 80
      fi

      # Apply ruleset
      if [[ "${ruleset}" == "recommended" ]]; then
            # Enforce component rules: remove any custom suppressionsLocation from consumer pom.xml
            if [[ -f "$(pwd)/pom.xml" ]] && grep -q '<suppressionsLocation>' "$(pwd)/pom.xml" 2>/dev/null; then
                  TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_POM=1
                  log_warn "Removing custom <suppressionsLocation> from pom.xml - component rules enforced"
                  awk '
      /<suppressionsLocation>/ { skip=1 }
      /<\/suppressionsLocation>/ { skip=0; next }
      !skip { print }
    ' "$(pwd)/pom.xml" >"$(pwd)/pom.xml.tmp" && mv "$(pwd)/pom.xml.tmp" "$(pwd)/pom.xml"
            fi

            # Detect if the project has a local checkstyle-suppressions.xml
            if [ -f "$(pwd)/checkstyle-suppressions.xml" ]; then
                  TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_FILE=1
            fi

            log_info "The 'recommended' ruleset was used."
      else
            # Custom: the project must provide its own checkstyle-suppressions.xml
            if [[ ! -f "$(pwd)/checkstyle-suppressions.xml" ]]; then
                  log_fail "ruleset is 'custom' but no checkstyle-suppressions.xml was found in: $(pwd)"
                  exit 80
            fi

            log_info "A custom ruleset, found in 'checkstyle-suppressions.xml', was used."
      fi

      # Debug
      log_debug "maven_settings_file = ${maven_settings_file}"
      log_debug "suppressions_file = ${suppressions_file}"
      log_debug "maven_repo_dir = ${maven_repo_dir}"
      log_debug "ruleset = ${ruleset}"
      log_debug "TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_POM = ${TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_POM}"
      log_debug "TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_FILE = ${TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_FILE}"
      log_debug "pwd = $(pwd)"

      # Build suppressions flag based on ruleset
      if [[ "${ruleset}" == "recommended" ]]; then
            suppressions_flag=$([ -f "$suppressions_file" ] && echo "-Dcheckstyle.suppressions.location=$suppressions_file" || true)
      else
            suppressions_flag="-Dcheckstyle.suppressions.location=$(pwd)/checkstyle-suppressions.xml"
      fi

      # Checkstyle-specific extra args
      checkstyle_args="-Dcheckstyle.config.location=google_checks.xml \
    -Dcheckstyle.violationSeverity=warning \
    -Dcheckstyle.failOnViolation=false \
    ${suppressions_flag}"

      echo "[]" >"gl-code-quality-checkstyle.json"

      # Call shared compile function
      # shellcheck disable=SC2086
      compile_maven \
            "$maven_settings_file" \
            "$maven_repo_dir" \
            "org.apache.maven.plugins:maven-checkstyle-plugin:${checkstyle_version}:check" \
            "$checkstyle_args" \
            "$(get_major_jdk_version)" || {
            exit_code=$?
            [[ "$exit_code" -eq 81 ]] && troubleshoot_81
            exit "$exit_code"
      }

      # Check report for violations
      if [ -f target/checkstyle-result.xml ] && grep -q '<error' target/checkstyle-result.xml 2>/dev/null; then
            log_fatal "Checkstyle violations detected"
            generate_gitlab_report "target/checkstyle-result.xml" "gl-code-quality-checkstyle.json"
            troubleshoot_100
            exit 100
      fi

      log_info "Checkstyle analysis completed successfully."
}

# Run main program.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
      main "$@"
fi
