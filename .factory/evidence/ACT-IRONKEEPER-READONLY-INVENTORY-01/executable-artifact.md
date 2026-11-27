# The executable artefact

## The retrieval procedure

The CI build publishes the executable as part of the artefact
`build-evidence-<architecture>`, together with
`executable-identity.txt`, which records the file type, the SHA-256
digest and the size of the binary.

```sh
# 1. Download the artefact of the qualified run for the target
#    architecture and unpack it.
# 2. Verify the digest against the recorded identity.
sha256sum build/ironkeeper
cat executable-identity.txt
# 3. Only then run the binary.
./build/ironkeeper --version
```

A digest that does not match means the artefact is not the qualified
subject: stop.

## The artefact identity

The identity of the executable is recorded per run, in
`executable-identity.txt`, and it belongs to the **commit** that the run
executed. A run at a different commit is not evidence for a different
subject.

## The runtime dependency

```sh
ldconfig -p | grep libpcre
```

The binary needs the PCRE 1 runtime (`libpcre.so.3`) at run time.

## The local build

```sh
tools/build.sh          # the same compiler invocations as CI
```

The build script is the single implementation: the CI job, the local
workstation and the developer all drive it.
