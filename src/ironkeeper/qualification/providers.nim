## The verdict providers of the validator qualification.
##
## A provider is the seam through which the harness obtains a verdict.
## There are two production providers:
##
##   * the **raw** provider drives the upstream validator directly, with no
##     Ironkeeper policy in the way. It measures the *library*.
##   * the **adapter** provider drives the Ironkeeper adapter, which adds
##     the supported schema policy, the reference policy and the
##     meta-validation gate. It measures *Ironkeeper*.
##
## The two are measured separately and reported separately. A case that the
## raw provider answers differently from the adapter is evidence about the
## adapter's policy, not about the validator library.

import std/[json, os]

import jschema

from ironkeeper/contracts/validator import newValidator, validateAgainst,
  ValidationOutcome, vfkSchemaPolicy, vfkReferencePolicy,
  vfkUnsupportedDialect, Draft2020_12
from ironkeeper/contracts/schemapolicy import checkSchemaPolicy
from ironkeeper/contracts/schemarefs import checkReferencePolicy
from ironkeeper/qualification/corpus import CorpusCase
from ironkeeper/qualification/harness import ProviderOutcome, Exclusion
from ironkeeper/qualification.remotes import readRemoteSchemas
from ironkeeper/qualification/verdict import ObservedVerdict

const
  RemoteBaseUri* = "http://localhost:1234"
    ## The retrieval base the official test suite documents for its remote
    ## schemas. See the suite's README, "Additional assumptions": a remote
    ## schema is retrieved at `http://localhost:1234` followed by its
    ## relative path inside the `remotes` directory.

proc newRawRegistry*(suiteDir: string): tuple[registry: SchemaRegistry,
                                               problems: seq[string]] =
  ## A registry for the raw provider, with the suite's remote schemas
  ## registered.
  ##
  ## The remote tree is read through the repository-owned reader, which
  ## refuses a malformed document instead of skipping it. The problems
  ## are returned to the caller, which must refuse to qualify against a
  ## remote tree that was not fully read.
  ##
  ## The registration is **offline**: the documents are read from the
  ## checkout. The registry never fetches, and no network access occurs.
  result.registry = newSchemaRegistry()
  let remote = readRemoteSchemas(suiteDir / "remotes", RemoteBaseUri)
  for problem in remote.problems:
    result.problems.add problem.file & ": " & problem.message
  for schema in remote.schemas:
    result.registry.add(schema.uri, schema.document)

proc rawProvider*(registry: SchemaRegistry): proc (c: CorpusCase): ProviderOutcome =
  ## The verdict of the upstream validator, with no Ironkeeper policy.
  ##
  ## The provider answers with a typed verdict. An exception raised by the
  ## library is reported as `ovError`; it is never reported as a rejection,
  ## because a library that failed to answer has not rejected anything.
  result = proc (c: CorpusCase): ProviderOutcome =
    try:
      let res = validate(c.data, c.schema, registry)
      ProviderOutcome(verdict: (if res.valid: ovAccepted else: ovRejected),
                      message: "")
    except CatchableError as e:
      ProviderOutcome(verdict: ovError, message: e.msg)
    except Exception as e:
      ProviderOutcome(verdict: ovError, message: e.msg)

proc adapterProvider*(): proc (c: CorpusCase): ProviderOutcome =
  ## The verdict of the Ironkeeper adapter.
  ##
  ## The adapter's *typed* failure kind decides the verdict. A schema that
  ## the adapter refuses because of the supported policy is reported as
  ## `ovUnsupported`; an internal defect is reported as `ovError`. Neither
  ## is reported as a rejection: a refusal is not a statement about the
  ## instance.
  let validator = newValidator()
  result = proc (c: CorpusCase): ProviderOutcome =
    try:
      let outcome = validator.validateAgainst(c.data, c.schema)
      if outcome.ok:
        return ProviderOutcome(verdict: ovAccepted, message: "")
      if outcome.failure in {vfkSchemaPolicy, vfkReferencePolicy,
                             vfkUnsupportedDialect}:
        return ProviderOutcome(verdict: ovUnsupported,
                               message: if outcome.error != nil:
                                          outcome.error.msg else: "")
      if outcome.error != nil:
        return ProviderOutcome(verdict: ovError, message: outcome.error.msg)
      ProviderOutcome(verdict: ovRejected, message: "")
    except CatchableError as e:
      ProviderOutcome(verdict: ovError, message: e.msg)
    except Exception as e:
      ProviderOutcome(verdict: ovError, message: e.msg)

proc subsetJudge*(): proc (c: CorpusCase): Exclusion =
  ## Decide, from the schema document alone, whether a case lies inside
  ## Ironkeeper's supported subset.
  ##
  ## The decision never observes the implementation's answer, so the
  ## implementation cannot exclude its own case. The reason is recorded
  ## verbatim.
  result = proc (c: CorpusCase): Exclusion =
    # The dialect is part of the supported subset. A schema that declares
    # a dialect this build does not implement is outside it, whether or
    # not its keywords are otherwise supported.
    if c.schema.kind == JObject and c.schema.hasKey("$schema"):
      let dialect = c.schema["$schema"]
      if dialect.kind == JString and dialect.getStr != Draft2020_12:
        return Exclusion(identity: c.identity,
                         reason: "the schema declares the dialect '" &
                                 dialect.getStr & "', which this build does not " &
                                 "implement")
    let policy = checkSchemaPolicy(c.schema)
    if not policy.ok:
      var parts = ""
      for issue in policy.issues:
        if parts.len > 0:
          parts.add "; "
        parts.add issue.location & ": " & issue.message
      return Exclusion(identity: c.identity,
                       reason: "the schema is outside the supported schema " &
                               "policy: " & parts)
    let references = checkReferencePolicy(c.schema)
    if not references.ok:
      var parts = ""
      for issue in references.issues:
        if parts.len > 0:
          parts.add "; "
        parts.add issue.location & ": " & issue.message
      return Exclusion(identity: c.identity,
                       reason: "the schema is outside the supported " &
                               "reference policy: " & parts)
    Exclusion(identity: c.identity, reason: "")

type
  ControlledProviderKind* = enum
    ## The controlled verdict providers used to witness the harness.
    ##
    ## A harness whose oracle cannot be shown to reject a wrong answer is
    ## not an oracle. These providers produce verdicts that are wrong in
    ## known ways, so that the harness's counting and terminal-verdict
    ## logic can be shown to detect them.
    cpAlwaysAccept
      ## Accepts every case.
    cpAlwaysReject
      ## Rejects every case.
    cpInverted
      ## Answers the opposite of the expected verdict.
    cpError
      ## Fails to answer at all.
    cpCorrect
      ## Answers the expected verdict.
    cpUnsupported
      ## Answers the expected verdict, except for the cases that lie
      ## outside the supported subset, for which it declares the case
      ## unsupported.
    cpWrongOutsideSubset
      ## Answers the expected verdict, except for the cases that lie
      ## outside the supported subset, for which it answers the *wrong*
      ## verdict.
      ##
      ## The provider witnesses that a wrong raw answer outside the
      ## adapter's subset is still a wrong answer, and is counted as a
      ## failure of the raw measurement.
    cpRefuseSupported
      ## Declares every case that lies *inside* the supported subset
      ## unsupported, and answers the expected verdict for the rest.
      ##
      ## The provider witnesses that a refusal of a supported case is a
      ## defect of the implementation, not an exclusion.

proc controlledProvider*(kind: ControlledProviderKind): proc (c: CorpusCase): ProviderOutcome =
  ## A controlled verdict provider.
  result = proc (c: CorpusCase): ProviderOutcome =
    case kind
    of cpAlwaysAccept:
      ProviderOutcome(verdict: ovAccepted, message: "the controlled provider accepts every case")
    of cpAlwaysReject:
      ProviderOutcome(verdict: ovRejected, message: "the controlled provider rejects every case")
    of cpInverted:
      let verdict = if c.expectedValid: ovRejected else: ovAccepted
      ProviderOutcome(verdict: verdict, message: "the controlled provider inverts the verdict")
    of cpError:
      ProviderOutcome(verdict: ovError, message: "the controlled provider raises")
    of cpCorrect:
      let verdict = if c.expectedValid: ovAccepted else: ovRejected
      ProviderOutcome(verdict: verdict, message: "")
    of cpUnsupported:
      let subset = subsetJudge()(c)
      if subset.reason.len > 0:
        return ProviderOutcome(verdict: ovUnsupported, message: subset.reason)
      let verdict = if c.expectedValid: ovAccepted else: ovRejected
      ProviderOutcome(verdict: verdict, message: "")
    of cpWrongOutsideSubset:
      let subset = subsetJudge()(c)
      if subset.reason.len > 0:
        # A wrong answer: the opposite of what the corpus expects.
        let wrong = if c.expectedValid: ovRejected else: ovAccepted
        return ProviderOutcome(verdict: wrong,
                               message: "the controlled provider answers wrongly")
      let verdict = if c.expectedValid: ovAccepted else: ovRejected
      ProviderOutcome(verdict: verdict, message: "")
    of cpRefuseSupported:
      let subset = subsetJudge()(c)
      if subset.reason.len == 0:
        return ProviderOutcome(verdict: ovUnsupported,
                               message: "the controlled provider refuses a " &
                                        "supported case")
      let verdict = if c.expectedValid: ovAccepted else: ovRejected
      ProviderOutcome(verdict: verdict, message: "")

proc controlledProviderByName*(name: string): ControlledProviderKind =
  ## The controlled provider with the given name.
  case name
  of "always-accept": cpAlwaysAccept
  of "always-reject": cpAlwaysReject
  of "inverted": cpInverted
  of "error": cpError
  of "correct": cpCorrect
  of "unsupported": cpUnsupported
  of "wrong-outside-subset": cpWrongOutsideSubset
  of "refuse-supported": cpRefuseSupported
  else:
    raise newException(ValueError, "unknown controlled provider: " & name)
