---
name: photokit-node
description: Use when an agent needs safe read-only access to the macOS System Photo Library through photokit-node for authorization checks, bounded metadata discovery, thumbnails, or explicit still-photo export.
---

# PhotoKit Node

Use `photokit-node` as the read-only boundary to the current macOS System Photo
Library. It can expose Photos metadata and image content, but it does not grant
authority to analyze, retain, upload, publish, mutate, or delete anything.

## Establish the installed contract

Before acting:

1. Confirm that the `photokit-node` package or executable is available.
2. Read the README shipped with that installed package.
3. Read `photokit-node --help` and the relevant nested help before constructing
   a command.

Treat the installed documentation and help as authoritative for exact commands,
options, output, API types, platform support, and error contracts. This skill
may be newer than the installed package, so do not infer missing syntax from
this file or from repository source.

If the tool is unavailable, stop and tell the user what is missing. Do not
invoke private native-helper executables or reproduce the versioned protocol.

## Work from least access to most

Use this progression unless the user explicitly requests a narrower later step:

1. Inspect the current Photos authorization state without prompting.
2. If access is undetermined and the requested task needs it, explain that macOS
   may show a Photos prompt before requesting authorization.
3. List a small, explicit number of recent metadata records. Prefer
   machine-readable output for programmatic work.
4. Use opaque local identifiers exactly as returned. Do not parse them or treat
   them as portable identifiers.
5. Request a modestly bounded thumbnail before exporting a full photo whenever
   a thumbnail can answer the question.
6. Export still-photo content only when the task requires the additional data.
   Confirm the intended current or original representation and the
   caller-owned destination.

Authorization can expose the full System Photo Library or a user-selected
limited subset. Report that distinction when it affects completeness.

## Preserve explicit authority

Local-only reads and collision refusal are the safe defaults. Obtain explicit
user authority before:

- Permitting an iCloud download for a content operation.
- Replacing any existing caller-owned file.
- Exporting many assets or expanding a bounded request into a library-wide job.
- Sending photo bytes, metadata, identifiers, or derived results to another
  process, service, model, or person.
- Uploading, publishing, or otherwise disclosing any photo-library material.

Authority for one asset or operation does not imply authority for another.
Keep output inside the user-selected location, avoid personal data in logs, and
report created files.

## Keep analysis outside the PhotoKit boundary

`photokit-node` provides deterministic PhotoKit access. Hashing, embeddings,
vision or language models, metadata databases, duplicate detection, privacy
classification, ranking, storytelling, and publishing belong to caller-owned
systems.

Use those systems only when the user requested them and their data movement is
understood. Never present downstream analysis as behavior performed or secured
by `photokit-node`.

## Handle failures without broadening access

Preserve the tool's structured error code and guidance when reporting a
failure. In particular:

- For denied access, direct the user to the ordinary Photos permission control
  in System Settings.
- For restricted access, explain that a system policy prevents the tool from
  requesting permission.
- For iCloud-only content, ask before retrying with network retrieval.
- For an existing output, ask for a different destination or explicit
  replacement authority.
- For unsupported media or unavailable assets, report the limitation rather
  than substituting another asset.

Do not run or recommend a TCC reset as an automatic troubleshooting step. Do
not weaken collision, network, output, timeout, or protocol safeguards to make
an operation succeed.
