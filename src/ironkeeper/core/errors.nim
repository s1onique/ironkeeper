## Ironkeeper error taxonomy.
##
## Every failure that the application can report to a user is represented by
## `IrkErrorKind`. The kind determines:
##
##   * the process exit code (see `exitCodeFor`),
##   * the machine-readable `code` field of the JSON error document,
##   * the human-readable rendering.
##
## The taxonomy is intentionally small and closed. New failure modes must be
## mapped onto an existing kind, or the kind set must be extended together
## with the documented exit-code table in `docs/architecture/overview.md`.

type
  IrkErrorKind* = enum
    ## Stable, documented failure classes.
    EInvalidInvocation
      ## The command line was malformed: unknown command, unknown flag,
      ## missing required argument, or contradictory arguments.
    EInputUnavailable
      ## A required input file was absent, unreadable, or not a regular file.
    EInvalidJsonSyntax
      ## The document was not syntactically valid JSON, or violated one of the
      ## strict-ingestion preconditions (invalid UTF-8, trailing content,
      ## duplicate member names, non-finite numbers).
    ESchemaValidation
      ## The document parsed as JSON but did not satisfy the JSON Schema it
      ## was validated against.
    ESemanticValidation
      ## The document satisfied the JSON Schema but violated a rule that the
      ## schema cannot express, for example a mandatory safety policy value.
    EUnsupportedSchemaVersion
      ## The document declared a `schema_version` (or `$schema`) that this
      ## build of Ironkeeper does not implement.
    EUnsupportedOperation
      ## The requested operation is not implemented by this build.
    EInternalFailure
      ## An unexpected internal condition. These are bugs; they are reported
      ## distinctly so that they can be triaged separately from user error.

  IrkErrorData* = object
    ## The payload of a classified failure.
    kind*: IrkErrorKind
    message*: string
      ## Human-readable description. Never contains stack traces.
    detail*: string
      ## Optional secondary location information, e.g. a JSON Pointer.
    exitCode*: int
      ## Cached process exit code for this failure.

  IrkError* = ref object of CatchableError
    ## A single, fully classified failure.
    ##
    ## The classification lives in `data`; this wrapper exists only so that
    ## the failure can be raised and caught as an exception.
    data*: IrkErrorData

  IrkErrorImpl* = object of CatchableError
    ## Concrete exception carrier. `newException` needs a plain object type.
    data*: IrkErrorData

const
  ExitOk* = 0
    ## Successful completion.

  ExitInvalidInvocation* = 2
    ## The command line could not be interpreted.

  ExitInputUnavailable* = 3
    ## A required input could not be obtained.

  ExitInvalidJsonSyntax* = 4
    ## Strict JSON ingestion rejected the document.

  ExitSchemaValidation* = 5
    ## Schema validation rejected the document.

  ExitSemanticValidation* = 6
    ## Semantic validation rejected the document.

  ExitUnsupportedSchemaVersion* = 7
    ## The document declares an unsupported schema version.

  ExitUnsupportedOperation* = 8
    ## The requested operation is not implemented.

  ExitInternalFailure* = 70
    ## An internal application failure.

proc codeFor*(kind: IrkErrorKind): string =
  ## Stable machine-readable identifier for an error kind.
  ##
  ## These strings are part of the public error contract and must remain
  ## backward compatible within schema version 1.
  case kind
  of EInvalidInvocation: "invalid_invocation"
  of EInputUnavailable: "input_unavailable"
  of EInvalidJsonSyntax: "invalid_json_syntax"
  of ESchemaValidation: "schema_validation_failed"
  of ESemanticValidation: "semantic_validation_failed"
  of EUnsupportedSchemaVersion: "unsupported_schema_version"
  of EUnsupportedOperation: "unsupported_operation"
  of EInternalFailure: "internal_failure"

proc exitCodeFor*(kind: IrkErrorKind): int =
  ## Process exit code for an error kind.
  case kind
  of EInvalidInvocation: ExitInvalidInvocation
  of EInputUnavailable: ExitInputUnavailable
  of EInvalidJsonSyntax: ExitInvalidJsonSyntax
  of ESchemaValidation: ExitSchemaValidation
  of ESemanticValidation: ExitSemanticValidation
  of EUnsupportedSchemaVersion: ExitUnsupportedSchemaVersion
  of EUnsupportedOperation: ExitUnsupportedOperation
  of EInternalFailure: ExitInternalFailure

proc newIrkError*(kind: IrkErrorKind, message: string,
                  detail = ""): ref IrkErrorImpl =
  ## Construct a classified error with a consistent exit code.
  ##
  ## The returned value can be raised directly. `msg` carries the
  ## human-readable message; `detail` is available separately and is not
  ## folded into `msg`.
  result = newException(IrkErrorImpl, message)
  result.data = IrkErrorData(kind: kind, message: message, detail: detail,
                              exitCode: exitCodeFor(kind))

proc kindOf*(err: IrkError): IrkErrorKind =
  err.data.kind

proc detailOf*(err: IrkError): string =
  err.data.detail

proc exitCodeOf*(err: IrkError): int =
  err.data.exitCode
