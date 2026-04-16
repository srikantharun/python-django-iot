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

# shellcheck disable=SC2329
troubleshoot_101() {
      local para1
      local para2

      # :nocov:
      { para1=$(cat); } <<-ENDMSG
            SpotBugs has detected potential bugs in your code.

            The specific issues will be listed above. If this pipeline is part of a Merge Request, they will also be shown in the Code Quality dashboard of that Merge Request.

            Try addressing all these violations, and letting another pipeline run to re-check.

      ENDMSG
      # :nocov:

      if [ "$TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_POM" == "1" ] || [ "$TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_FILE" == "1" ]; then
            # :nocov:
            { para2=$(cat); } <<-ENDMSG
                  Please note that this Component will ignore any custom SpotBugs exclusion rules that you may have defined in your pom.xml.

                  If you'd like to suggest a change to this behaviour, please raise an MR and submit for review in the component repository.

            ENDMSG
            # :nocov:
      fi

      echo "${para1}${para2:-}"
}

# Function to convert spotbugs report to GitLab format.
# Supports scenarios where there is a single file or a single error.
generate_gitlab_report() {
      local source_file="$1"
      local target_file="$2"

      # :nocov:
      { jq_query="$(cat)"; } <<-"EOF"
            .BugCollection.BugInstance
              | if type == "array" then .[] else . end
              | . as $bug
              | ($bug.SourceLine
                  | if type == "array" then .[] else . end
                  | select(.["+@primary"] == "true")) as $loc
              | {
                  check_name: $bug["+@type"],
                  description: (
                    $bug["+@type"] + ": " +
                    ($bug.LongMessage // $bug.ShortMessage // $bug["+@type"])
                  ),
                  fingerprint: (
                    (
                      ($loc["+@sourcepath"] // "unknown") + ":" +
                      ($loc["+@start"] // "0") + ":" +
                      $bug["+@type"] + ":" +
                      $bug["+@category"]
                    ) | @base64
                  ),
                  severity: (
                    if $bug["+@priority"] == "1" then "critical"
                    elif $bug["+@priority"] == "2" then "major"
                    elif $bug["+@priority"] == "3" then "minor"
                    else "info"
                    end
                  ),
                  location: {
                    path: (
                      if $loc["+@sourcepath"] != null
                      then "src/main/java/" + $loc["+@sourcepath"]
                      else "unknown"
                      end
                    ),
                    lines: {
                        begin: ($loc["+@start"] // "0" | tonumber)
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

      # Script variables
      local maven_settings_file="$shared_dir/settings.xml"
      local exclude_file="$component_dir/spotbugs-exclude.xml"
      local maven_repo_dir=".m2-local"

      # renovate: datasource=maven depName=com.github.spotbugs:spotbugs-maven-plugin
      local spotbugs_version="4.9.8.2"

      # Ruleset configuration — passed in via RULESET env var from lint.yml
      local ruleset="${RULESET:-recommended}"
      local valid_rulesets="recommended custom"

      # Define global context for conditional troubleshooting messaging.
      local TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_POM=0
      local TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_FILE=0

      # SpotBugs configuration. These should only be overridden during testing.
      local spotbugs_config_effort="${SPOTBUGS_EFFORT:-Max}"
      local spotbugs_config_threshold="${SPOTBUGS_THRESHOLD:-Low}"

      # Validate ruleset is one of the allowed values
      if [[ " ${valid_rulesets} " != *" ${ruleset} "* ]]; then
            log_fail "Invalid ruleset value: ${ruleset}"
            log_info "Valid values: ${valid_rulesets}"
            exit 80
      fi

      # Apply ruleset
      if [[ "${ruleset}" == "recommended" ]]; then
            # Enforce component rules: remove any custom excludeFilterFile from consumer pom.xml
            if [[ -f "$(pwd)/pom.xml" ]] && grep -q '<excludeFilterFile>' "$(pwd)/pom.xml" 2>/dev/null; then
                  TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_POM=1
                  log_warn "Removing custom <excludeFilterFile> from pom.xml - component rules enforced"
                  awk '
      /<excludeFilterFile>/ { skip=1 }
      /<\/excludeFilterFile>/ { skip=0; next }
      !skip { print }
    ' "$(pwd)/pom.xml" >"$(pwd)/pom.xml.tmp" && mv "$(pwd)/pom.xml.tmp" "$(pwd)/pom.xml"
            fi

            log_info "The 'recommended' ruleset was used."
      else
            # Custom: the project must provide its own spotbugs-exclude.xml
            if [[ ! -f "$(pwd)/spotbugs-exclude.xml" ]]; then
                  log_fail "ruleset is 'custom' but no spotbugs-exclude.xml was found in: $(pwd)"
                  exit 80
            fi

            log_info "A custom ruleset, found in 'spotbugs-exclude.xml', was used."
      fi

      # Debug
      log_debug "maven_settings_file = ${maven_settings_file}"
      log_debug "exclude_file = ${exclude_file}"
      log_debug "maven_repo_dir = ${maven_repo_dir}"
      log_debug "ruleset = ${ruleset}"
      log_debug "TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_POM = ${TROUBLESHOOT_CONTEXT__HAS_CUSTOM_SUPPRESSIONS_POM}"
      log_debug "pwd = $(pwd)"

      # Build exclude filter flag based on ruleset
      if [[ "${ruleset}" == "recommended" ]]; then
            exclude_filter_flag=$([ -f "$exclude_file" ] && echo "-Dspotbugs.excludeFilterFile=$exclude_file" || true)
      else
            exclude_filter_flag="-Dspotbugs.excludeFilterFile=$(pwd)/spotbugs-exclude.xml"
      fi

      # SpotBugs-specific extra args
      spotbugs_args="-Dspotbugs.failOnError=false \
    -Dspotbugs.effort=$spotbugs_config_effort \
    -Dspotbugs.threshold=$spotbugs_config_threshold \
    ${exclude_filter_flag}"

      echo "[]" >"gl-code-quality-spotbugs.json"

      # SpotBugs analyses bytecode, so compile phase is required.
      # shellcheck disable=SC2086
      compile_maven \
            "$maven_settings_file" \
            "$maven_repo_dir" \
            "com.github.spotbugs:spotbugs-maven-plugin:${spotbugs_version}:check" \
            "$spotbugs_args" \
            "$(get_major_jdk_version)" || {
            exit_code=$?
            [[ "$exit_code" -eq 81 ]] && troubleshoot_81
            exit "$exit_code"
      }

      # Check report for violations
      if [ -f target/spotbugsXml.xml ] && grep -q '<BugInstance' target/spotbugsXml.xml 2>/dev/null; then
            log_fatal "SpotBugs violations detected"
            generate_gitlab_report "target/spotbugsXml.xml" "gl-code-quality-spotbugs.json"
            troubleshoot_101
            exit 101
      fi

      log_info "SpotBugs analysis completed successfully."
}

# Run main program.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
      main "$@"
fi
