---
name: scnn-training-pipeline
description: "Build, verify, and deploy a spiking CNN from training data to FPGA COE/MEM/ROM files. Use when adapting an SCNN model, reviewing tensor and fixed-point mappings, diagnosing training-to-RTL mismatches, or preparing reproducible training evidence."
---

# FPGA SCNN Training and Deployment Pipeline

Use the repository's `training/scnn/` directory as the authoritative reference implementation. In this repository it is the working project; in another project, copy that directory as a starting template and change its data and model specification deliberately.

## Start with evidence

1. Locate the SCNN reference root. The default from this skill is `../../training/scnn`.
2. Run the structural checker:

   `python scripts/check_reference.py --root <reference-root>`

3. Read [references/pipeline.md](references/pipeline.md) for the six-stage workflow, expected outputs, and failure conditions.
4. When using a language model for implementation or review, start from [references/prompt-workflows.md](references/prompt-workflows.md). Treat model replies as hypotheses until commands, source links, hashes, or logs support them.

The optional `--run` flag executes the reference project's numerical verification and smoke test:

`python scripts/check_reference.py --root <reference-root> --run --output <report.json>`

For a packaged release that must already contain prior verification evidence, add `--require-record`.

## Operating rules

- Preserve the class order, input channel order, tensor layout, fixed-point format, LIF update, pooling order, flatten order, and packed-word lane order unless the model and RTL are changed together.
- Never copy COE files as a substitute for updating the compiled ROM. Verify model parameters, COE, MEM, generated ROM, and the ROM registered in the active XPR.
- A smoke test proves gradients and serialization work; it does not prove dataset accuracy, RTL equivalence, throughput, or hardware behavior.
- When a change reaches RTL or XPR inputs, rerun the relevant simulation, build the main XPR, and preserve source and bitstream hashes. Keep board validation separate.
- Report a failed stage and its first evidence before attempting a fix. Preserve the initial log when a rerun succeeds.

## Deliverables

Produce a short report containing:

1. the model and hardware mapping actually used;
2. data split, class order, and hashes;
3. commands and PASS/FAIL evidence for conversion, numerical verification, and training smoke test;
4. ROM/XPR integration status;
5. simulation, build, timing, and bitstream provenance;
6. explicit untested boundaries, especially dataset accuracy and physical-board behavior.
