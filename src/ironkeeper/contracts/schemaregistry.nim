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
    "device",
    "error",
    "evidence",
    "inventory",
    "observation",
    "report",
    "schemaindex",
    "validation",
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
  "$id": "https://ironkeeper.invalid/schemas/v1/device.schema.json",
  "title": "Ironkeeper device record",
  "description": "One discovered block device. The record describes what the kernel and udev reported; it carries no assessment and no admission verdict. An observation that the device did not provide is absent, never a zero.",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "schema_version",
    "kernel_name",
    "device_class",
    "transport",
    "identity"
  ],
  "properties": {
    "schema_version": {
      "description": "Version of this device contract. Only version 1 is implemented.",
      "type": "integer",
      "const": 1
    },
    "kernel_name": {
      "description": "The kernel name of the block device, for example `sdb`.",
      "type": "string",
      "minLength": 1,
      "maxLength": 128
    },
    "device_class": {
      "description": "The class of the device. Only `physical` devices are active-interrogation targets.",
      "type": "string",
      "enum": [
        "physical",
        "partition",
        "device_mapper",
        "raid",
        "loop",
        "ram",
        "optical",
        "virtual",
        "unknown"
      ]
    },
    "transport": {
      "description": "The transport the device is attached through.",
      "type": "string",
      "enum": ["sas", "sata", "nvme", "scsi", "unknown"]
    },
    "major": {
      "description": "The major device number.",
      "type": "string",
      "maxLength": 16
    },
    "minor": {
      "description": "The minor device number.",
      "type": "string",
      "maxLength": 16
    },
    "sysfs_path": {
      "description": "The sysfs path of the device.",
      "type": "string",
      "maxLength": 4096
    },
    "vendor": {
      "description": "The reported vendor. Absent when the device did not report one.",
      "type": "string",
      "maxLength": 256
    },
    "model": {
      "description": "The reported model. Absent when the device did not report one.",
      "type": "string",
      "maxLength": 256
    },
    "serial": {
      "description": "The reported serial number. A weak identifier on its own.",
      "type": "string",
      "maxLength": 256
    },
    "firmware": {
      "description": "The reported firmware revision.",
      "type": "string",
      "maxLength": 256
    },
    "wwn": {
      "description": "The observed world-wide name, in the form the source reported it.",
      "type": "string",
      "maxLength": 256
    },
    "capacity_bytes": {
      "description": "The capacity in bytes, as a canonical decimal string. A capacity beyond 2^53 bytes keeps every digit.",
      "type": "string",
      "pattern": "^[0-9]+$"
    },
    "logical_block_size": {
      "description": "The logical block size in bytes.",
      "type": "integer",
      "minimum": 0
    },
    "physical_block_size": {
      "description": "The physical block size in bytes.",
      "type": "integer",
      "minimum": 0
    },
    "rotational": {
      "description": "Whether the device reports itself as rotational. Absent when the kernel did not say.",
      "type": "boolean"
    },
    "paths": {
      "description": "The current access paths of the device.",
      "type": "array",
      "maxItems": 64,
      "items": { "type": "string", "minLength": 1, "maxLength": 4096 }
    },
    "aliases": {
      "description": "The persistent aliases of the device.",
      "type": "array",
      "maxItems": 64,
      "items": { "type": "string", "minLength": 1, "maxLength": 4096 }
    },
    "identity": {
      "description": "The reconciled identity of the device.",
      "type": "object",
      "additionalProperties": false,
      "required": ["confidence", "identifiers"],
      "properties": {
        "confidence": {
          "description": "How much authority the identity carries.",
          "type": "string",
          "enum": ["authoritative", "probable", "ambiguous", "unresolved"]
        },
        "identifiers": {
          "description": "The observed persistent identifiers.",
          "type": "array",
          "maxItems": 32,
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["kind", "namespace", "value", "original", "source"],
            "properties": {
              "kind": {
                "type": "string",
                "enum": [
                  "scsi_wwn",
                  "ata_wwn",
                  "nguid",
                  "eui64",
                  "nvme_uuid",
                  "serial",
                  "disk_sequence_number"
                ]
              },
              "namespace": {
                "description": "The object the identifier names.",
                "type": "string",
                "enum": ["logical_unit", "namespace", "controller"]
              },
              "value": {
                "description": "The canonical form of the identifier.",
                "type": "string",
                "maxLength": 512
              },
              "original": {
                "description": "The identifier exactly as it was observed.",
                "type": "string",
                "maxLength": 512
              },
              "source": {
                "description": "Where the identifier was observed.",
                "type": "string",
                "maxLength": 256
              }
            }
          }
        },
        "conflicts": {
          "description": "The contradictory identity observations.",
          "type": "array",
          "maxItems": 64,
          "items": { "type": "string", "maxLength": 1024 }
        },
        "duplicate_serial": {
          "description": "True when another discovered device carries the same serial number.",
          "type": "boolean"
        }
      }
    },
    "findings": {
      "description": "The findings that explain the classification and the exclusions.",
      "type": "array",
      "maxItems": 128,
      "items": { "type": "string", "maxLength": 1024 }
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
  "$id": "https://ironkeeper.invalid/schemas/v1/evidence.schema.json",
  "title": "Ironkeeper evidence manifest",
  "description": "The manifest of one invocation-scoped evidence bundle. The manifest lists the preserved artefacts with their exact byte length and their SHA-256 digest. A digest is an integrity check over the preserved bytes; it is not a proof of provenance or authenticity.",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "bundle_id", "created_at", "artifacts"],
  "properties": {
    "schema_version": {
      "description": "Version of this evidence contract. Only version 1 is implemented.",
      "type": "integer",
      "const": 1
    },
    "bundle_id": {
      "description": "The unique identity of this bundle.",
      "type": "string",
      "minLength": 1,
      "maxLength": 128
    },
    "created_at": {
      "type": "string",
      "minLength": 20,
      "maxLength": 64,
      "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"
    },
    "target": {
      "description": "The device the bundle belongs to.",
      "type": "object",
      "additionalProperties": false,
      "required": ["kernel_name", "paths", "identity_confidence"],
      "properties": {
        "kernel_name": { "type": "string", "minLength": 1, "maxLength": 128 },
        "paths": {
          "type": "array",
          "maxItems": 64,
          "items": { "type": "string", "minLength": 1, "maxLength": 4096 }
        },
        "identity_confidence": {
          "type": "string",
          "enum": ["authoritative", "probable", "ambiguous", "unresolved"]
        }
      }
    },
    "attribution": {
      "description": "Whether the evidence is bound to the selected device.",
      "type": "object",
      "additionalProperties": false,
      "required": ["status"],
      "properties": {
        "status": {
          "type": "string",
          "enum": ["bound", "refused"]
        },
        "reason": { "type": "string", "maxLength": 2048 }
      }
    },
    "completeness": {
      "description": "The completeness of the collection.",
      "type": "object",
      "additionalProperties": false,
      "required": ["status"],
      "properties": {
        "status": {
          "description": "Whether every requested observation was collected.",
          "type": "string",
          "enum": ["complete", "partial", "failed"]
        },
        "reason": { "type": "string", "maxLength": 2048 }
      }
    },
    "artifacts": {
      "description": "The preserved artefacts.",
      "type": "array",
      "maxItems": 256,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["name", "byte_length", "sha256", "kind"],
        "properties": {
          "name": {
            "description": "The file name of the artefact, relative to the bundle directory.",
            "type": "string",
            "minLength": 1,
            "maxLength": 256
          },
          "byte_length": {
            "description": "The exact length of the preserved bytes.",
            "type": "integer",
            "minimum": 0
          },
          "sha256": {
            "description": "The lowercase hex SHA-256 digest of the preserved bytes.",
            "type": "string",
            "pattern": "^[0-9a-f]{64}$"
          },
          "kind": {
            "description": "The kind of the artefact.",
            "type": "string",
            "enum": [
              "tool_stdout",
              "tool_stderr",
              "normalized_document",
              "other"
            ]
          },
          "tool": { "type": "string", "maxLength": 256 },
          "outcome": { "type": "string", "maxLength": 64 },
          "exit_status": { "type": "integer" },
          "collected_at": { "type": "string", "maxLength": 64 },
          "note": { "type": "string", "maxLength": 1024 }
        }
      }
    }
  }
}
""",
    """{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://ironkeeper.invalid/schemas/v1/inventory.schema.json",
  "title": "Ironkeeper storage inventory",
  "description": "The passive inventory of the block devices of one host. The inventory is produced without opening a physical device and without running an observation tool. An enumeration failure is reported as an incomplete inventory, never as a successful empty inventory.",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "generated_at", "complete", "devices"],
  "properties": {
    "schema_version": {
      "description": "Version of this inventory contract. Only version 1 is implemented.",
      "type": "integer",
      "const": 1
    },
    "generated_at": {
      "type": "string",
      "minLength": 20,
      "maxLength": 64,
      "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"
    },
    "complete": {
      "description": "False when the enumeration itself failed or a device disappeared during it.",
      "type": "boolean"
    },
    "root": {
      "description": "The discovery root that was read.",
      "type": "string",
      "maxLength": 4096
    },
    "devices": {
      "description": "The discovered block devices.",
      "type": "array",
      "maxItems": 4096,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": [
          "schema_version",
          "kernel_name",
          "device_class",
          "transport",
          "identity"
        ],
        "properties": {
          "schema_version": { "type": "integer", "const": 1 },
          "kernel_name": { "type": "string", "minLength": 1, "maxLength": 128 },
          "device_class": {
            "type": "string",
            "enum": [
              "physical",
              "partition",
              "device_mapper",
              "raid",
              "loop",
              "ram",
              "optical",
              "virtual",
              "unknown"
            ]
          },
          "transport": {
            "type": "string",
            "enum": ["sas", "sata", "nvme", "scsi", "unknown"]
          },
          "major": { "type": "string", "maxLength": 16 },
          "minor": { "type": "string", "maxLength": 16 },
          "sysfs_path": { "type": "string", "maxLength": 4096 },
          "vendor": { "type": "string", "maxLength": 256 },
          "model": { "type": "string", "maxLength": 256 },
          "serial": { "type": "string", "maxLength": 256 },
          "firmware": { "type": "string", "maxLength": 256 },
          "wwn": { "type": "string", "maxLength": 256 },
          "capacity_bytes": { "type": "string", "pattern": "^[0-9]+$" },
          "logical_block_size": { "type": "integer", "minimum": 0 },
          "physical_block_size": { "type": "integer", "minimum": 0 },
          "rotational": { "type": "boolean" },
          "paths": {
            "type": "array",
            "maxItems": 64,
            "items": { "type": "string", "minLength": 1, "maxLength": 4096 }
          },
          "aliases": {
            "type": "array",
            "maxItems": 64,
            "items": { "type": "string", "minLength": 1, "maxLength": 4096 }
          },
          "identity": {
            "type": "object",
            "additionalProperties": false,
            "required": ["confidence", "identifiers"],
            "properties": {
              "confidence": {
                "type": "string",
                "enum": ["authoritative", "probable", "ambiguous", "unresolved"]
              },
              "identifiers": {
                "type": "array",
                "maxItems": 32,
                "items": {
                  "type": "object",
                  "additionalProperties": false,
                  "required": ["kind", "namespace", "value", "original", "source"],
                  "properties": {
                    "kind": {
                      "type": "string",
                      "enum": [
                        "scsi_wwn",
                        "ata_wwn",
                        "nguid",
                        "eui64",
                        "nvme_uuid",
                        "serial",
                        "disk_sequence_number"
                      ]
                    },
                    "namespace": {
                      "type": "string",
                      "enum": ["logical_unit", "namespace", "controller"]
                    },
                    "value": { "type": "string", "maxLength": 512 },
                    "original": { "type": "string", "maxLength": 512 },
                    "source": { "type": "string", "maxLength": 256 }
                  }
                }
              },
              "conflicts": {
                "type": "array",
                "maxItems": 64,
                "items": { "type": "string", "maxLength": 1024 }
              },
              "duplicate_serial": { "type": "boolean" }
            }
          },
          "findings": {
            "type": "array",
            "maxItems": 128,
            "items": { "type": "string", "maxLength": 1024 }
          }
        }
      }
    },
    "findings": {
      "description": "The findings of the enumeration.",
      "type": "array",
      "maxItems": 1024,
      "items": { "type": "string", "maxLength": 2048 }
    }
  }
}
""",
    """{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://ironkeeper.invalid/schemas/v1/observation.schema.json",
  "title": "Ironkeeper device observation",
  "description": "The observations collected from one explicitly selected device. An observation is not an assessment: this document never carries an admission verdict and never reports PASS. A field that the device did not provide is represented by an observation whose status is unavailable or unsupported, never by a zero.",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "schema_version",
    "device",
    "observations"
  ],
  "properties": {
    "schema_version": {
      "description": "Version of this observation contract. Only version 1 is implemented.",
      "type": "integer",
      "const": 1
    },
    "generated_at": {
      "description": "RFC 3339 timestamp of the collection.",
      "type": "string",
      "minLength": 20,
      "maxLength": 64,
      "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"
    },
    "device": {
      "description": "The device the observations belong to.",
      "type": "object",
      "additionalProperties": false,
      "required": [
        "kernel_name",
        "device_class",
        "transport",
        "identity"
      ],
      "properties": {
        "kernel_name": {
          "type": "string",
          "minLength": 1,
          "maxLength": 128
        },
        "device_class": {
          "type": "string",
          "enum": [
            "physical",
            "partition",
            "device_mapper",
            "raid",
            "loop",
            "ram",
            "optical",
            "virtual",
            "unknown"
          ]
        },
        "transport": {
          "type": "string",
          "enum": [
            "sas",
            "sata",
            "nvme",
            "scsi",
            "unknown"
          ]
        },
        "major": {
          "type": "string",
          "maxLength": 16
        },
        "minor": {
          "type": "string",
          "maxLength": 16
        },
        "vendor": {
          "type": "string",
          "maxLength": 256
        },
        "model": {
          "type": "string",
          "maxLength": 256
        },
        "serial": {
          "type": "string",
          "maxLength": 256
        },
        "firmware": {
          "type": "string",
          "maxLength": 256
        },
        "wwn": {
          "type": "string",
          "maxLength": 256
        },
        "capacity_bytes": {
          "type": "string",
          "pattern": "^[0-9]+$"
        },
        "logical_block_size": {
          "type": "integer",
          "minimum": 0
        },
        "physical_block_size": {
          "type": "integer",
          "minimum": 0
        },
        "paths": {
          "type": "array",
          "maxItems": 64,
          "items": {
            "type": "string",
            "minLength": 1,
            "maxLength": 4096
          }
        },
        "aliases": {
          "type": "array",
          "maxItems": 64,
          "items": {
            "type": "string",
            "minLength": 1,
            "maxLength": 4096
          }
        },
        "identity": {
          "type": "object",
          "additionalProperties": false,
          "required": [
            "confidence",
            "identifiers"
          ],
          "properties": {
            "confidence": {
              "type": "string",
              "enum": [
                "authoritative",
                "probable",
                "ambiguous",
                "unresolved"
              ]
            },
            "identifiers": {
              "type": "array",
              "maxItems": 32,
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": [
                  "kind",
                  "namespace",
                  "value",
                  "original",
                  "source"
                ],
                "properties": {
                  "kind": {
                    "type": "string",
                    "enum": [
                      "scsi_wwn",
                      "ata_wwn",
                      "nguid",
                      "eui64",
                      "nvme_uuid",
                      "serial",
                      "disk_sequence_number"
                    ]
                  },
                  "namespace": {
                    "type": "string",
                    "enum": [
                      "logical_unit",
                      "namespace",
                      "controller"
                    ]
                  },
                  "value": {
                    "type": "string",
                    "maxLength": 512
                  },
                  "original": {
                    "type": "string",
                    "maxLength": 512
                  },
                  "source": {
                    "type": "string",
                    "maxLength": 256
                  }
                }
              }
            },
            "conflicts": {
              "type": "array",
              "maxItems": 64,
              "items": {
                "type": "string",
                "maxLength": 1024
              }
            },
            "duplicate_serial": {
              "type": "boolean"
            }
          }
        },
        "sysfs_path": {
          "type": "string",
          "maxLength": 4096
        },
        "findings": {
          "type": "array",
          "maxItems": 128,
          "items": {
            "type": "string",
            "maxLength": 1024
          }
        },
        "rotational": {
          "type": "boolean"
        }
      }
    },
    "observations": {
      "description": "The normalised observations.",
      "type": "array",
      "maxItems": 4096,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": [
          "name",
          "status",
          "source",
          "collected_at"
        ],
        "properties": {
          "name": {
            "description": "The stable name of the observed quantity.",
            "type": "string",
            "minLength": 1,
            "maxLength": 256
          },
          "status": {
            "description": "How the observation was obtained.",
            "type": "string",
            "enum": [
              "observed",
              "derived",
              "unavailable",
              "unsupported",
              "invalid",
              "conflicting"
            ]
          },
          "value": {
            "description": "The exact value, as a canonical decimal string or a documented token. Absent when the observation carries no value.",
            "type": "string",
            "maxLength": 4096
          },
          "unit": {
            "description": "The unit of the value.",
            "type": "string",
            "maxLength": 64
          },
          "source": {
            "description": "The backend that produced the observation.",
            "type": "string",
            "minLength": 1,
            "maxLength": 256
          },
          "source_field": {
            "description": "The field or derivation the value came from.",
            "type": "string",
            "maxLength": 512
          },
          "collected_at": {
            "type": "string",
            "minLength": 20,
            "maxLength": 64,
            "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"
          },
          "reason": {
            "description": "Why the value is unavailable, unsupported, invalid or conflicting.",
            "type": "string",
            "maxLength": 2048
          }
        }
      }
    },
    "executions": {
      "description": "The outcome of each external tool invocation.",
      "type": "array",
      "maxItems": 64,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": [
          "tool",
          "outcome",
          "exit_status"
        ],
        "properties": {
          "tool": {
            "type": "string",
            "minLength": 1,
            "maxLength": 256
          },
          "outcome": {
            "type": "string",
            "enum": [
              "succeeded",
              "non_zero_exit",
              "timed_out",
              "launch_failed",
              "output_limit_exceeded",
              "signalled"
            ]
          },
          "exit_status": {
            "type": "integer"
          },
          "signal": {
            "type": "integer"
          },
          "duration_ms": {
            "type": "integer",
            "minimum": 0
          },
          "message": {
            "type": "string",
            "maxLength": 2048
          }
        }
      }
    },
    "attribution": {
      "description": "Whether the observations are bound to the selected device.",
      "type": "object",
      "additionalProperties": false,
      "required": [
        "status"
      ],
      "properties": {
        "status": {
          "description": "The attribution status of the collected observations.",
          "type": "string",
          "enum": [
            "bound",
            "refused"
          ]
        },
        "reason": {
          "type": "string",
          "maxLength": 2048
        }
      }
    },
    "findings": {
      "description": "The findings of the collection.",
      "type": "array",
      "maxItems": 1024,
      "items": {
        "type": "string",
        "maxLength": 2048
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
  "$id": "https://ironkeeper.invalid/schemas/v1/schemaindex.schema.json",
  "title": "Ironkeeper schema index",
  "description": "Machine-readable index of the contracts that this build implements. Emitted by `ironkeeper schema list --json`.",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "schemas"],
  "properties": {
    "schema_version": {
      "description": "Version of this index contract. Only version 1 is implemented.",
      "type": "integer",
      "const": 1
    },
    "schemas": {
      "description": "The contracts this build implements.",
      "type": "array",
      "minItems": 1,
      "maxItems": 64,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["name", "version", "dialect"],
        "properties": {
          "name": {
            "description": "Name of the contract.",
            "type": "string",
            "minLength": 1,
            "maxLength": 128
          },
          "version": {
            "description": "Version of the contract.",
            "type": "integer",
            "minimum": 1
          },
          "dialect": {
            "description": "The JSON Schema dialect the contract is written in.",
            "type": "string",
            "const": "https://json-schema.org/draft/2020-12/schema"
          }
        }
      }
    }
  }
}
""",
    """{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://ironkeeper.invalid/schemas/v1/validation.schema.json",
  "title": "Ironkeeper validation result",
  "description": "Machine-readable result of a document validation. Emitted by `ironkeeper report validate --json` and by the machine-readable form of any validation that reports a set of issues. Structural validity, semantic validity and the authenticity of the cited evidence are distinct concerns: this document reports on the document, never on the truth of what it asserts.",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "valid", "issues"],
  "properties": {
    "schema_version": {
      "description": "Version of this validation contract. Only version 1 is implemented.",
      "type": "integer",
      "const": 1
    },
    "valid": {
      "description": "True when the validated document satisfied both the structural and the semantic contract.",
      "type": "boolean"
    },
    "structural_valid": {
      "description": "True when the validated document satisfied the structural contract. Absent when the structural check could not be completed.",
      "type": "boolean"
    },
    "semantic_valid": {
      "description": "True when the validated document satisfied the semantic contract. Absent when the semantic check could not be completed.",
      "type": "boolean"
    },
    "issues": {
      "description": "The issues that made the document invalid.",
      "type": "array",
      "maxItems": 1024,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["message"],
        "properties": {
          "location": {
            "description": "JSON Pointer into the validated document, when the issue refers to a specific position.",
            "type": "string",
            "maxLength": 1024
          },
          "keyword_location": {
            "description": "JSON Pointer to the keyword in the schema that produced the issue.",
            "type": "string",
            "maxLength": 1024
          },
          "code": {
            "description": "Stable machine-readable issue code.",
            "type": "string",
            "maxLength": 128
          },
          "message": {
            "description": "Human-readable description of the issue.",
            "type": "string",
            "minLength": 1,
            "maxLength": 4096
          }
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
