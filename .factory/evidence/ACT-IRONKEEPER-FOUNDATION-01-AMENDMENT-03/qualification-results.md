# Qualification results

The complete, unabridged output of the corrected harness at the
subject commit. The per-class counts and the exact exclusions are
preserved here, not only a headline pass count.

```
suite_revision=245a45abc90190c0bff04d97e6d2b541b4bb9f12
draft=2020-12
corpus_files=80
corpus_cases=2374
corpus_digest_fnv1a64=7F5B47D94E68318F
mandatory_cases=1300
optional_cases=1074
corpus_representation_limited=9
[raw-upstream]
  denominator=1300
  passed=1300
  failed=0
  unauthorised_exclusions=0
  denominator=1300
  passed=1300
  failed=0
  unauthorised_exclusions=0
  correct_acceptance=763
  correct_rejection=537
  false_acceptance=0
  false_rejection=0
  execution_error=0
  unsupported_policy=0
  known_limitation=0
  invalid_evidence=0
  verdict=PASS
  exclusions=1074
  exclusion_reason: count=1015 reason=the case belongs to the optional part of the corpus
  exclusion_reason: count=2 reason=the schema declares the dialect 'http://localhost:1234/draft2020-12/format-assertion-false.json', which this build does not implement
  exclusion_reason: count=2 reason=the schema declares the dialect 'http://localhost:1234/draft2020-12/format-assertion-true.json', which this build does not implement
  exclusion_reason: count=3 reason=the schema is outside the supported reference policy: /$defs/real_id_in_schema/$id: a nested '$id' declaration is not permitted; /anyOf/1/$ref: the external reference 'https://localhost:1234/draft2020-12/id/my_identifier.json' is not permitted: it would require a network fetch
  exclusion_reason: count=1 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://localhost:1234/draft2019-09/ignore-prefixItems.json' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the local reference '#/examples/0' does not resolve to a schema-bearing position
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /$defs/bar/$defs/item/properties/content/$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper; /$defs/bar/$defs/item/$defs/defaultContent/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper; /$defs/bar/$defs/content/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper
  exclusion_reason: count=3 reason=the schema is outside the supported schema policy: /$defs/id_in_unknown0/not/array_of_schemas: the keyword 'array_of_schemas' is not supported by Ironkeeper; /$defs/id_in_unknown1/not/object_of_schemas: the keyword 'object_of_schemas' is not supported by Ironkeeper
  exclusion_reason: count=36 reason=the schema is outside the supported schema policy: /dependencies: the keyword 'dependencies' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /properties/foo/unknown-keyword: the keyword 'unknown-keyword' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /properties/foo/unknown~1keyword: the keyword 'unknown/keyword' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /unknown-keyword: the keyword 'unknown-keyword' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /unknown~1keyword: the keyword 'unknown/keyword' is not supported by Ironkeeper
[ironkeeper-adapter]
  denominator=949
  passed=949
  failed=0
  unauthorised_exclusions=0
  denominator=949
  passed=949
  failed=0
  unauthorised_exclusions=0
  correct_acceptance=570
  correct_rejection=379
  false_acceptance=0
  false_rejection=0
  execution_error=0
  unsupported_policy=0
  known_limitation=0
  invalid_evidence=0
  verdict=PASS
  exclusions=1425
  exclusion_reason: count=1015 reason=the case belongs to the optional part of the corpus
  exclusion_reason: count=2 reason=the schema declares the dialect 'http://localhost:1234/draft2020-12/format-assertion-false.json', which this build does not implement
  exclusion_reason: count=2 reason=the schema declares the dialect 'http://localhost:1234/draft2020-12/format-assertion-true.json', which this build does not implement
  exclusion_reason: count=3 reason=the schema declares the dialect 'http://localhost:1234/draft2020-12/metaschema-no-validation.json', which this build does not implement
  exclusion_reason: count=2 reason=the schema declares the dialect 'http://localhost:1234/draft2020-12/metaschema-optional-vocabulary.json', which this build does not implement
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$defs/A/$id: a nested '$id' declaration is not permitted; /$defs/A/allOf/0/$id: a nested '$id' declaration is not permitted; /$ref: the external reference 'child1#my_anchor' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$defs/a/$id: a nested '$id' declaration is not permitted; /$defs/b/$id: a nested '$id' declaration is not permitted; /$ref: the external reference '/absref/foobar.json' is not permitted: it would require a network fetch
  exclusion_reason: count=3 reason=the schema is outside the supported reference policy: /$defs/real_id_in_schema/$id: a nested '$id' declaration is not permitted; /anyOf/1/$ref: the external reference 'https://localhost:1234/draft2020-12/id/my_identifier.json' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$defs/smallint/$id: a nested '$id' declaration is not permitted
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$defs/x/$id: a nested '$id' declaration is not permitted; /$defs/x/not/$defs/y/$id: a nested '$id' declaration is not permitted; /allOf/0/$ref: the external reference 'http://example.com/b/d.json' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://example.com/ref/else' is not permitted: it would require a network fetch; /else/$id: a nested '$id' declaration is not permitted
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://example.com/ref/if' is not permitted: it would require a network fetch; /if/$id: a nested '$id' declaration is not permitted
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://example.com/ref/then' is not permitted: it would require a network fetch; /then/$id: a nested '$id' declaration is not permitted
  exclusion_reason: count=1 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://localhost:1234/draft2019-09/ignore-prefixItems.json' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://localhost:1234/draft2020-12/bar#foo' is not permitted: it would require a network fetch; /$defs/A/$id: a nested '$id' declaration is not permitted
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://localhost:1234/draft2020-12/detached-dynamicref.json#/$defs/foo' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://localhost:1234/draft2020-12/detached-ref.json#/$defs/foo' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://localhost:1234/draft2020-12/different-id-ref-string.json' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://localhost:1234/draft2020-12/integer.json' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://localhost:1234/draft2020-12/locationIndependentIdentifier.json#/$defs/refToInteger' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://localhost:1234/draft2020-12/locationIndependentIdentifier.json#foo' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://localhost:1234/draft2020-12/nested-absolute-ref-to-string.json' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://localhost:1234/draft2020-12/nested.json#foo' is not permitted: it would require a network fetch; /$defs/A/$id: a nested '$id' declaration is not permitted
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://localhost:1234/draft2020-12/subSchemas.json#/$defs/integer' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://localhost:1234/draft2020-12/subSchemas.json#/$defs/refToInteger' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'http://localhost:1234/draft2020-12/urn-ref-string.json' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'int.json' is not permitted: it would require a network fetch; /$defs/bigint/$id: a nested '$id' declaration is not permitted; /$defs/smallint/$id: a nested '$id' declaration is not permitted
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'nested/foo.json' is not permitted: it would require a network fetch; /$defs/foo/$id: a nested '$id' declaration is not permitted; /$defs/foo/$ref: the external reference './bar.json' is not permitted: it would require a network fetch; /$defs/bar/$id: a nested '$id' declaration is not permitted
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'ref-and-defs.json' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the external reference 'urn:uuid:deadbeef-4321-ffff-ffff-1234feebdaed' is not permitted: it would require a network fetch; /$defs/foo/$id: a nested '$id' declaration is not permitted; /$defs/foo/$ref: the local reference '#/$defs/bar' does not resolve within this document
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /$ref: the local reference '#/examples/0' does not resolve to a schema-bearing position
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /items/$id: a nested '$id' declaration is not permitted; /items/items/$ref: the external reference 'folderInteger.json' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /properties/foo"bar/$ref: the local reference '#/$defs/foo%22bar' does not resolve within this document
  exclusion_reason: count=3 reason=the schema is outside the supported reference policy: /properties/foo/$id: a nested '$id' declaration is not permitted; /properties/foo/$ref: the local reference '#/$defs/inner' does not resolve within this document; /$ref: the external reference 'schema-refs-absolute-uris-defs2.json' is not permitted: it would require a network fetch
  exclusion_reason: count=3 reason=the schema is outside the supported reference policy: /properties/foo/$id: a nested '$id' declaration is not permitted; /properties/foo/$ref: the local reference '#/$defs/inner' does not resolve within this document; /$ref: the external reference 'schema-relative-uri-defs2.json' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /properties/foo/$ref: the external reference 'urn:uuid:deadbeef-1234-0000-0000-4321feebdaed#/$defs/bar' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /properties/foo/$ref: the external reference 'urn:uuid:deadbeef-1234-ff00-00ff-4321feebdaed#something' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /properties/foo/$ref: the external reference 'urn:uuid:deadbeef-1234-ffff-ffff-4321feebdaed' is not permitted: it would require a network fetch
  exclusion_reason: count=4 reason=the schema is outside the supported reference policy: /properties/foo/$ref: the local reference '#' does not resolve to an '$anchor' of this document
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /properties/list/$ref: the external reference 'baseUriChangeFolder/' is not permitted: it would require a network fetch; /$defs/baz/$id: a nested '$id' declaration is not permitted; /$defs/baz/items/$ref: the external reference 'folderInteger.json' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /properties/list/$ref: the external reference 'baseUriChangeFolderInSubschema/#/$defs/bar' is not permitted: it would require a network fetch; /$defs/baz/$id: a nested '$id' declaration is not permitted; /$defs/baz/$defs/bar/items/$ref: the external reference 'folderInteger.json' is not permitted: it would require a network fetch
  exclusion_reason: count=3 reason=the schema is outside the supported reference policy: /properties/name/$ref: the external reference 'name-defs.json#/$defs/orNull' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /properties/name/$ref: the external reference 'nested/foo-ref-string.json' is not permitted: it would require a network fetch
  exclusion_reason: count=2 reason=the schema is outside the supported reference policy: /properties/nodes/items/$ref: the external reference 'node' is not permitted: it would require a network fetch; /$defs/node/$id: a nested '$id' declaration is not permitted; /$defs/node/properties/subtree/$ref: the external reference 'tree' is not permitted: it would require a network fetch
  exclusion_reason: count=6 reason=the schema is outside the supported reference policy: /properties/percent/$ref: the local reference '#/$defs/percent%25field' does not resolve within this document
  exclusion_reason: count=1 reason=the schema is outside the supported schema policy: /$defs/A/unevaluatedProperties: the keyword 'unevaluatedProperties' is not supported by Ironkeeper
  exclusion_reason: count=4 reason=the schema is outside the supported schema policy: /$defs/bar/$defs/item/properties/content/$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper; /$defs/bar/$defs/item/$defs/defaultContent/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper; /$defs/bar/$defs/content/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /$defs/derived/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper; /$defs/baseSchema/unevaluatedItems: the keyword 'unevaluatedItems' is not supported by Ironkeeper; /$defs/baseSchema/$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper; /$defs/baseSchema/$defs/defaultAddons/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /$defs/derived/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper; /$defs/baseSchema/unevaluatedProperties: the keyword 'unevaluatedProperties' is not supported by Ironkeeper; /$defs/baseSchema/$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper; /$defs/baseSchema/$defs/defaultAddons/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper
  exclusion_reason: count=3 reason=the schema is outside the supported schema policy: /$defs/elements/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /$defs/foo/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper
  exclusion_reason: count=1 reason=the schema is outside the supported schema policy: /$defs/foo/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper; /$defs/list/items/$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper
  exclusion_reason: count=7 reason=the schema is outside the supported schema policy: /$defs/foo/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper; /$defs/list/items/$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper; /$defs/list/$defs/items/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper
  exclusion_reason: count=4 reason=the schema is outside the supported schema policy: /$defs/genericList/properties/list/items/$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper; /$defs/genericList/$defs/defaultItemType/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper; /$defs/numberList/$defs/itemType/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper; /$defs/stringList/$defs/itemType/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper
  exclusion_reason: count=3 reason=the schema is outside the supported schema policy: /$defs/id_in_unknown0/not/array_of_schemas: the keyword 'array_of_schemas' is not supported by Ironkeeper; /$defs/id_in_unknown1/not/object_of_schemas: the keyword 'object_of_schemas' is not supported by Ironkeeper
  exclusion_reason: count=1 reason=the schema is outside the supported schema policy: /$defs/list/items/$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper; /$defs/list/$defs/items/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper
  exclusion_reason: count=21 reason=the schema is outside the supported schema policy: /$defs/one/oneOf/3/unevaluatedProperties: the keyword 'unevaluatedProperties' is not supported by Ironkeeper; /unevaluatedProperties: the keyword 'unevaluatedProperties' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /$defs/second/$defs/length/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper; /$defs/third/$defs/stuff/$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper; /$defs/third/$defs/length/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper
  exclusion_reason: count=1 reason=the schema is outside the supported schema policy: /$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper; /$defs/bar/properties/baz/$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper; /$defs/extended/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper; /$defs/bar/properties/baz/$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper; /unevaluatedProperties: the keyword 'unevaluatedProperties' is not supported by Ironkeeper
  exclusion_reason: count=3 reason=the schema is outside the supported schema policy: /allOf/0/$defs/elements/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper
  exclusion_reason: count=4 reason=the schema is outside the supported schema policy: /allOf/0/unevaluatedProperties: the keyword 'unevaluatedProperties' is not supported by Ironkeeper
  exclusion_reason: count=4 reason=the schema is outside the supported schema policy: /allOf/0/unevaluatedProperties: the keyword 'unevaluatedProperties' is not supported by Ironkeeper; /allOf/1/unevaluatedProperties: the keyword 'unevaluatedProperties' is not supported by Ironkeeper
  exclusion_reason: count=10 reason=the schema is outside the supported schema policy: /allOf/0/unevaluatedProperties: the keyword 'unevaluatedProperties' is not supported by Ironkeeper; /unevaluatedProperties: the keyword 'unevaluatedProperties' is not supported by Ironkeeper
  exclusion_reason: count=3 reason=the schema is outside the supported schema policy: /allOf/1/$defs/elements/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper
  exclusion_reason: count=1 reason=the schema is outside the supported schema policy: /allOf/1/unevaluatedItems: the keyword 'unevaluatedItems' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /allOf/1/unevaluatedItems: the keyword 'unevaluatedItems' is not supported by Ironkeeper; /unevaluatedItems: the keyword 'unevaluatedItems' is not supported by Ironkeeper
  exclusion_reason: count=1 reason=the schema is outside the supported schema policy: /allOf/1/unevaluatedProperties: the keyword 'unevaluatedProperties' is not supported by Ironkeeper
  exclusion_reason: count=3 reason=the schema is outside the supported schema policy: /anyOf/0/unevaluatedProperties: the keyword 'unevaluatedProperties' is not supported by Ironkeeper
  exclusion_reason: count=3 reason=the schema is outside the supported schema policy: /contentEncoding: the keyword 'contentEncoding' is not supported by Ironkeeper
  exclusion_reason: count=3 reason=the schema is outside the supported schema policy: /contentMediaType: the keyword 'contentMediaType' is not supported by Ironkeeper
  exclusion_reason: count=4 reason=the schema is outside the supported schema policy: /contentMediaType: the keyword 'contentMediaType' is not supported by Ironkeeper; /contentEncoding: the keyword 'contentEncoding' is not supported by Ironkeeper
  exclusion_reason: count=8 reason=the schema is outside the supported schema policy: /contentMediaType: the keyword 'contentMediaType' is not supported by Ironkeeper; /contentEncoding: the keyword 'contentEncoding' is not supported by Ironkeeper; /contentSchema: the keyword 'contentSchema' is not supported by Ironkeeper
  exclusion_reason: count=36 reason=the schema is outside the supported schema policy: /dependencies: the keyword 'dependencies' is not supported by Ironkeeper
  exclusion_reason: count=3 reason=the schema is outside the supported schema policy: /if/$defs/thingy/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper; /then/$defs/thingy/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper; /$defs/start/$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper; /$defs/thingy/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /items/$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /items/$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper; /$defs/foo/$dynamicAnchor: the keyword '$dynamicAnchor' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /not/unevaluatedProperties: the keyword 'unevaluatedProperties' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /properties/foo/unevaluatedItems: the keyword 'unevaluatedItems' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /properties/foo/unevaluatedProperties: the keyword 'unevaluatedProperties' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /properties/foo/unknown-keyword: the keyword 'unknown-keyword' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /properties/foo/unknown~1keyword: the keyword 'unknown/keyword' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /properties/true/$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper; /properties/false/$dynamicRef: the keyword '$dynamicRef' is not supported by Ironkeeper
  exclusion_reason: count=64 reason=the schema is outside the supported schema policy: /unevaluatedItems: the keyword 'unevaluatedItems' is not supported by Ironkeeper
  exclusion_reason: count=82 reason=the schema is outside the supported schema policy: /unevaluatedProperties: the keyword 'unevaluatedProperties' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /unknown-keyword: the keyword 'unknown-keyword' is not supported by Ironkeeper
  exclusion_reason: count=2 reason=the schema is outside the supported schema policy: /unknown~1keyword: the keyword 'unknown/keyword' is not supported by Ironkeeper
raw_verdict=PASS
adapter_verdict=PASS
raw_mandatory_cases=1300
raw_optional_cases=1074
adapter_mandatory_cases=1300
adapter_optional_cases=1074
```

## The counts, in one table

| Measurement | Corpus | Denominator | Passed | Failed | Correct acceptance | Correct rejection | False acceptance | False rejection | Execution error | Unsupported policy | Known limitation | Invalid evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Raw upstream | mandatory draft 2020-12 | 1300 | 1300 | 0 | 763 | 537 | 0 | 0 | 0 | 0 | 0 | 0 |
| Ironkeeper adapter | mandatory, supported subset | 949 | 949 | 0 | 570 | 379 | 0 | 0 | 0 | 0 | 0 | 0 |

The excluded cases are the ones the harness placed outside the
denominator. Every one of them carries its exact identity and its
exact reason in the output above. The reasons are grouped by their
exact text, so two different reasons are never merged.

The optional corpus is 1074 cases; the mandatory corpus is 1300.
The difference between the two denominators (1300 and 949) is the
supported subset at work on the mandatory corpus.
