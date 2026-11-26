## Embedded JSON Schema registry.
##
## THIS FILE IS GENERATED. Do not edit it by hand.
##
## Regenerate with:  nim r tools/embed_schemas.nim
## Verify with:      nim r tools/embed_schemas.nim --check
##
## Source: `schemas/v1/*.schema.json`. The embedded bytes are byte-for-byte
## identical to the repository files.

import std/json

const
  EmbeddedSchemaNames* = [
    "config",
    "error",
    "report",
    "version",
  ]
    ## Names of the schemas embedded in the binary.

let
  embeddedSchemaTexts = [
    """{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://ironkeeper.invalid/schemas/v1/config.schema.json",
  "title": "Ironkeeper configuration",
  "description": "Strict, versioned configuration document for the Ironkeeper daemon. Every object boundary rejects unknown properties. The safety block is deliberately minimal and its mandatory values are enforced semantically, not only structurally.",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "daemon", "safety"],
  "properties": {
    "schema_version": {
      "description": "Version of this configuration contract. Only version 1 is implemented.",
      "type": "integer",
      "const": 1
    },
    "daemon": {
      "description": "Runtime locations used by the daemon.",
      "type": "object",
      "additionalProperties": false,
      "required": ["state_directory", "socket_path"],
      "properties": {
        "state_directory": {
          "description": "Absolute path of the directory holding durable state and evidence.",
          "type": "string",
          "minLength": 1,
          "maxLength": 4096,
          "pattern": "^/"
        },
        "socket_path": {
          "description": "Absolute path of the AF_UNIX control socket.",
          "type": "string",
          "minLength": 1,
          "maxLength": 4096,
          "pattern": "^/"
        }
      }
    },
    "safety": {
      "description": "Safety policy. The values in this block are mandatory and are not configurable away in milestone M0: allow_destructive_operations must be false, require_explicit_enrollment must be true, and allow_tests_on_in_use_devices must be false.",
      "type": "object",
      "additionalProperties": false,
      "required": [
        "require_explicit_enrollment",
        "allow_destructive_operations",
        "allow_tests_on_in_use_devices"
      ],
      "properties": {
        "require_explicit_enrollment": {
          "description": "Devices must be explicitly enrolled before any assessment. Must be true.",
          "type": "boolean"
        },
        "allow_destructive_operations": {
          "description": "Whether destructive operations are permitted. Must be false in milestone M0; the schema accepts only false so that the value cannot be configured away.",
          "type": "boolean",
          "const": false
        },
        "allow_tests_on_in_use_devices": {
          "description": "Whether self-tests may be started on devices that are in use. Must be false in milestone M0.",
          "type": "boolean",
          "const": false
        }
      }
    }
  }
}
""",
    """{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://ironkeeper.invalid/schemas/v1/error.schema.json",
  "title": "Ironkeeper error",
  "description": "Machine-readable error document. Emitted on stdout only when the caller asked for JSON output; otherwise the same information is rendered as human-readable text on stderr.",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "error"],
  "properties": {
    "schema_version": {
      "description": "Version of this error contract. Only version 1 is implemented.",
      "type": "integer",
      "const": 1
    },
    "error": {
      "type": "object",
      "additionalProperties": false,
      "required": ["code", "message"],
      "properties": {
        "code": {
          "description": "Stable machine-readable error class.",
          "type": "string",
          "enum": [
            "invalid_invocation",
            "input_unavailable",
            "invalid_json_syntax",
            "schema_validation_failed",
            "semantic_validation_failed",
            "unsupported_schema_version",
            "unsupported_operation",
            "internal_failure"
          ]
        },
        "message": {
          "description": "Human-readable description of the failure.",
          "type": "string",
          "minLength": 1,
          "maxLength": 4096
        },
        "detail": {
          "description": "Optional secondary information, for example a JSON Pointer or a byte offset.",
          "type": "string",
          "maxLength": 4096
        }
      }
    }
  }
}
""",
    """{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://ironkeeper.invalid/schemas/v1/report.schema.json",
  "title": "Ironkeeper report",
  "description": "Strict, versioned report document produced by Ironkeeper. A report describes what was executed, what was observed, and what was concluded. Execution state, assessment verdict and device lifecycle state are separate concepts and are never collapsed into one another. An operation may execute successfully and still report a FAIL assessment; an operation that failed to obtain mandatory evidence reports INCONCLUSIVE, never PASS.",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "schema_version",
    "report_type",
    "report_id",
    "producer",
    "execution",
    "findings"
  ],
  "properties": {
    "schema_version": {
      "description": "Version of this report contract. Only version 1 is implemented.",
      "type": "integer",
      "const": 1
    },
    "report_type": {
      "description": "Kind of report. Only configuration_validation is implemented in milestone M0.",
      "type": "string",
      "enum": ["configuration_validation"]
    },
    "report_id": {
      "description": "Stable identity of this report instance.",
      "type": "object",
      "additionalProperties": false,
      "required": ["id", "created_at"],
      "properties": {
        "id": {
          "description": "Opaque, unique identifier for this report.",
          "type": "string",
          "minLength": 1,
          "maxLength": 128
        },
        "created_at": {
          "description": "RFC 3339 timestamp with an explicit UTC offset, for example 2026-01-02T03:04:05Z. Validated semantically, not by the schema alone.",
          "type": "string",
          "minLength": 20,
          "maxLength": 64,
          "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"
        }
      }
    },
    "producer": {
      "description": "Identity of the software that produced this report.",
      "type": "object",
      "additionalProperties": false,
      "required": ["name", "version"],
      "properties": {
        "name": {
          "type": "string",
          "const": "ironkeeper"
        },
        "version": {
          "type": "string",
          "minLength": 1,
          "maxLength": 64
        }
      }
    },
    "execution": {
      "description": "Outcome of the operation that produced this report. The state describes what happened to the operation, not the health of any device.",
      "type": "object",
      "additionalProperties": false,
      "required": ["state", "started_at", "finished_at"],
      "properties": {
        "state": {
          "description": "Execution state of the operation.",
          "type": "string",
          "enum": [
            "QUEUED",
            "PREFLIGHT",
            "RUNNING",
            "WAITING",
            "VERIFYING",
            "SUCCEEDED",
            "FAILED",
            "CANCELLED",
            "INTERRUPTED"
          ]
        },
        "started_at": {
          "type": "string",
          "minLength": 20,
          "maxLength": 64,
          "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"
        },
        "finished_at": {
          "type": "string",
          "minLength": 20,
          "maxLength": 64,
          "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"
        },
        "message": {
          "description": "Optional human-readable summary of the execution outcome.",
          "type": "string",
          "maxLength": 2048
        }
      }
    },
    "assessment": {
      "description": "Assessment verdict. Present only when the operation was able to reach a conclusion. Absent means no verdict was reached, which is not the same as PASS.",
      "type": "object",
      "additionalProperties": false,
      "required": ["verdict", "summary"],
      "properties": {
        "verdict": {
          "description": "Assessment verdict.",
          "type": "string",
          "enum": ["PASS", "WARN", "FAIL", "INCONCLUSIVE"]
        },
        "summary": {
          "description": "Human-readable summary of the verdict.",
          "type": "string",
          "minLength": 1,
          "maxLength": 4096
        },
        "policy_revision": {
          "description": "Identifier of the policy revision the verdict was computed against, so that a verdict can be recomputed from preserved evidence.",
          "type": "string",
          "maxLength": 128
        }
      }
    },
    "findings": {
      "description": "Structured findings. Each finding records an observation and, where applicable, the evidence it rests on.",
      "type": "array",
      "maxItems": 1024,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["code", "severity", "message"],
        "properties": {
          "code": {
            "description": "Stable machine-readable finding code.",
            "type": "string",
            "minLength": 1,
            "maxLength": 128
          },
          "severity": {
            "description": "Severity of the finding.",
            "type": "string",
            "enum": ["info", "warning", "error"]
          },
          "message": {
            "description": "Human-readable description of the finding.",
            "type": "string",
            "minLength": 1,
            "maxLength": 4096
          },
          "location": {
            "description": "JSON Pointer into the validated document, when the finding refers to a specific position.",
            "type": "string",
            "maxLength": 1024
          },
          "evidence_refs": {
            "description": "References to the evidence records that support this finding.",
            "type": "array",
            "maxItems": 64,
            "items": { "type": "string", "minLength": 1, "maxLength": 512 }
          }
        }
      }
    },
    "evidence": {
      "description": "Evidence records referenced by the findings. Evidence preserves the original observation together with its provenance.",
      "type": "array",
      "maxItems": 4096,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "kind", "collected_at", "provenance"],
        "properties": {
          "id": {
            "type": "string",
            "minLength": 1,
            "maxLength": 128
          },
          "kind": {
            "description": "Kind of evidence record.",
            "type": "string",
            "enum": ["config_document", "schema_validation", "tool_output", "device_observation"]
          },
          "collected_at": {
            "type": "string",
            "minLength": 20,
            "maxLength": 64,
            "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"
          },
          "provenance": {
            "type": "object",
            "additionalProperties": false,
            "required": ["source"],
            "properties": {
              "source": {
                "description": "Description of where the observation came from.",
                "type": "string",
                "minLength": 1,
                "maxLength": 1024
              },
              "tool": {
                "description": "Name and version of the tool that produced the observation, when a tool was used.",
                "type": "string",
                "maxLength": 256
              },
              "digest": {
                "description": "Lowercase hex SHA-256 digest of the original bytes. This is an integrity check over the preserved bytes, not a cryptographic proof of provenance.",
                "type": "string",
                "pattern": "^[0-9a-f]{64}$"
              }
            }
          },
          "content": {
            "description": "The preserved observation itself.",
            "type": ["object", "array", "string", "number", "boolean", "null"]
          }
        }
      }
    },
    "subject": {
      "description": "Optional description of what the report is about, for example the configuration file that was validated.",
      "type": "object",
      "additionalProperties": false,
      "required": ["kind"],
      "properties": {
        "kind": {
          "type": "string",
          "enum": ["configuration_file"]
        },
        "identifier": {
          "description": "Path or identifier of the subject.",
          "type": "string",
          "maxLength": 4096
        }
      }
    }
  }
}
""",
    """{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://ironkeeper.invalid/schemas/v1/version.schema.json",
  "title": "Ironkeeper version",
  "description": "Machine-readable version identity of an Ironkeeper build.",
  "type": "object",
  "additionalProperties": false,
  "required": ["name", "version", "schema_versions"],
  "properties": {
    "name": {
      "description": "Program name.",
      "type": "string",
      "const": "ironkeeper"
    },
    "version": {
      "description": "Application version of this build.",
      "type": "string",
      "minLength": 1,
      "maxLength": 64
    },
    "schema_versions": {
      "description": "Contract schema versions this build implements.",
      "type": "array",
      "minItems": 1,
      "maxItems": 32,
      "uniqueItems": true,
      "items": {
        "type": "integer",
        "minimum": 1
      }
    },
    "contract": {
      "description": "The JSON Schema dialect used by the contracts of this build.",
      "type": "string",
      "const": "https://json-schema.org/draft/2020-12/schema"
    }
  }
}
""",
  ]

proc schemaText*(name: string): string =
  ## Raw JSON text of the embedded schema called `name`.
  ##
  ## Raises `ValueError` if the name is unknown. Callers that accept
  ## user-supplied names must check membership first.
  for i in 0 ..< EmbeddedSchemaNames.len:
    if EmbeddedSchemaNames[i] == name:
      return embeddedSchemaTexts[i]
  raise newException(ValueError, "unknown embedded schema: " & name)

proc schemaNode*(name: string): JsonNode =
  ## Parsed form of the embedded schema called `name`.
  ##
  ## The embedded documents are produced by the build step and are known to be
  ## well-formed; a parse failure here is an internal defect.
  parseJson(schemaText(name))
