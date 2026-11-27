# Entry identity and M0 acceptance

## Repository

* Repository: `https://github.com/s1onique/ironkeeper`
* Entry HEAD: `c2c34e34721fced22080a3b6ead6d7c3c77041bd`
* Development branch: `act/ironkeeper-readonly-inventory-01`
* The branch was created from the accepted `main` baseline
  `c2c34e34721fced22080a3b6ead6d7c3c77041bd`.

## M0 acceptance

The M0 acceptance authority was re-verified against the recorded
evidence before any implementation work started.

* CI run `45935432045`: all four jobs successful.
* CI run `45935427044`: successful.
* Both runs qualified commit `b85fa0bb9b7f50e3ce170cf6ab9ae776207a4336`.
* The GitHub comparison between the qualified commit and
  `c2c34e34721fced22080a3b6ead6d7c3c77041bd` contains no changed files.
* CI run `45935586165` on `main` failed **only** in the amd64
  dependency-installation step, because `packages.microsoft.com` returned
  HTTP 403. The other three jobs succeeded.

**Classification.** The main-run failure is an **external environment
failure**, not a product defect: the failing step is the installation of
a dependency from an external package repository, and the failure is a
refusal by that repository. The mandatory gates were not weakened and no
package-integrity check was disabled.

**M0 is recorded as accepted** on the basis of the qualified identical
tree: the qualified commit and the current `main` have no changed files
between them, so the successful runs of the qualified commit are
evidence for the tree that `main` holds.

## Intervening commits

The expected entry HEAD was not advanced during the ACT: the working
tree was created from `c2c34e34721fced22080a3b6ead6d7c3c77041bd` and no
other commit was merged into it.

## Execution discipline

* The toolchain bootstrap, the validator selection, the generic schema
  conformance and the previous closure ACTs were **not** reopened.
* The implementation reuses the qualified contracts, the qualified
  validator adapter, the qualified CI workflow and the engineering
  doctrine.
