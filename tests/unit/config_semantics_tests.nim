## Unit tests for configuration semantic validation.
##
## Semantic validation is separate from schema validation: the schema
## establishes shape, this module establishes the rules that a schema
## cannot express. The most important of those is that the mandatory
## safety values cannot be configured away.

import std/[json, strutils]

import testkit
import ironkeeper/config/semantics

const BaseConfig = """{
  "schema_version": 1,
  "daemon": {
    "state_directory": "/var/lib/ironkeeper",
    "socket_path": "/run/ironkeeper/control.sock"
  },
  "safety": {
    "require_explicit_enrollment": true,
    "allow_destructive_operations": false,
    "allow_tests_on_in_use_devices": false
  }
}"""

proc runSuite*(): int =
  var t = newTestSuite("config-semantics")

  # --- The reference configuration is valid -------------------------------
  let ok = validateConfigSemantics(parseJson(BaseConfig))
  t.check("accepts the reference configuration", ok.ok)
  t.checkEq("reports no issues", ok.issues.len, 0)

  # --- The mandatory safety values cannot be configured away ------------
  let destructive = validateConfigSemantics(
    parseJson(BaseConfig.replace("\"allow_destructive_operations\": false",
                                 "\"allow_destructive_operations\": true")))
  t.check("rejects destructive operations", not destructive.ok)
  t.checkEq("reports one issue", destructive.issues.len, 1)
  t.checkEq("uses a stable issue code", destructive.issues[0].code,
            "safety.destructive_operations_forbidden")
  t.checkEq("points at the offending member",
            destructive.issues[0].location,
            "/safety/allow_destructive_operations")

  let noEnroll = validateConfigSemantics(
    parseJson(BaseConfig.replace("\"require_explicit_enrollment\": true",
                                 "\"require_explicit_enrollment\": false")))
  t.check("rejects implicit enrollment", not noEnroll.ok)
  t.checkEq("uses a stable issue code", noEnroll.issues[0].code,
            "safety.enrollment_required")

  let testsInUse = validateConfigSemantics(
    parseJson(BaseConfig.replace("\"allow_tests_on_in_use_devices\": false",
                                 "\"allow_tests_on_in_use_devices\": true")))
  t.check("rejects tests on in-use devices", not testsInUse.ok)
  t.checkEq("uses a stable issue code", testsInUse.issues[0].code,
            "safety.tests_on_in_use_forbidden")

  # --- Paths must be absolute and clean ---------------------------------
  let relative = validateConfigSemantics(
    parseJson(BaseConfig.replace("\"/var/lib/ironkeeper\"",
                                 "\"var/lib/ironkeeper\"")))
  t.check("rejects a relative state directory", not relative.ok)
  t.checkEq("uses a stable issue code", relative.issues[0].code,
            "daemon.invalid_path")

  let dotDot = validateConfigSemantics(
    parseJson(BaseConfig.replace("\"/var/lib/ironkeeper\"",
                                 "\"/var/lib/../lib/ironkeeper\"")))
  t.check("rejects a path containing '..'", not dotDot.ok)

  # --- An unsupported schema version is reported as such -----------------
  let future = validateConfigSemantics(
    parseJson(BaseConfig.replace("\"schema_version\": 1",
                                 "\"schema_version\": 2")))
  t.check("rejects an unsupported schema version", not future.ok)
  t.checkEq("uses a stable issue code", future.issues[0].code,
            "config.unsupported_schema_version")
  t.checkEq("points at the version member", future.issues[0].location,
            "/schema_version")

  t.finish()

