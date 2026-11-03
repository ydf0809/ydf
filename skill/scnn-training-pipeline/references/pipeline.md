# SCNN Training to FPGA ROM Pipeline

This guide adapts the repository's `training/scnn/` reference project. Read the model specification and current verification records before changing code or weights.

## Stage 0: Define the contract

Record the input shape, channel order, class order, timesteps, pooling order, flatten order, weight packing, fixed-point formats, LIF update, threshold, and reset behavior.

For the reference project, `model_spec.json` fixes:

- input `3 x 64 x 64` in B/G/R order;
- classes `not_drone`, `drone`;
- Conv 3->8, Conv 8->16, OR pooling, FC 1024->2;
- signed 16-bit Q4.12 weights and 26-bit Q13.12 membrane state;
- 50 timesteps and threshold integer 4096;
- different channel packing rules for convolution and FC words.

Failure condition: a change to any of these fields without a matching RTL and verification review.

## Stage 1: Prepare data

Use this directory schema:

```text
data/
  train/
    not_drone/
    drone/
  val/
    not_drone/
    drone/
```

Apply the same RGB565 expansion and 128->64 ROI preprocessing used at deployment. Split by video segment or scene to avoid near-duplicate leakage. Keep a file manifest with SHA-256 hashes.

Failure condition: missing class directories, wrong image shape, duplicated train/validation bytes, or preprocessing that does not match the RTL input.

## Stage 2: Train or fine-tune

Install dependencies:

```powershell
python -m pip install -r requirements.txt
```

Run a pipeline smoke test first:

```powershell
python train.py --smoke-test
```

Run real training only with an actual dataset and explicit configuration:

```powershell
python train.py --data data --from-scratch --epochs <epochs> --batch-size <batch> --lr <lr> --seed <seed>
```

Use `--weights <checkpoint>` instead of `--from-scratch` for fine-tuning. Preserve the training history, data manifest, seed, and checkpoint.

Failure condition: the smoke test fails, the data split is undocumented, or an accuracy claim is made without an independent test set.

## Stage 3: Export fixed-point assets

Decode canonical COE/MEM inputs:

```powershell
python convert_weights.py decode --source weights --format both --output recovered_weights.json
```

Export four COE/MEM pairs and the Verilog ROM:

```powershell
python convert_weights.py encode --input recovered_weights.json --output generated/weights --rom generated/drone_data_roms.v
```

For a trained checkpoint:

```powershell
python convert_weights.py encode --input generated/training/best.pt --output generated/trained_weights --rom generated/trained_drone_data_roms.v
```

Failure condition: non-finite values, out-of-range Q4.12 values, mixed COE/MEM sources, or a changed channel/lane order.

## Stage 4: Verify numerics

Run:

```powershell
python verify.py
python build/check_weights.py
```

Require:

- 3416 canonical parameters and the four MEM files agree;
- reference and black-frame 50-step outputs match an independent integer model;
- COE/MEM, generated ROM, and the ROM registered in the active upper XPR agree;
- exported ROM modules pass `xvlog` syntax compilation;
- moving the project does not change the result.

Failure condition: a mismatch in any packed lane, pooled feature, LIF transition, or the first differing timestep.

## Stage 5: Integrate and rebuild

After an intentional model replacement:

1. Review the generated ROM against the active `drone_data_roms.v`.
2. Confirm the ROM source is registered in the main upper XPR.
3. Run the relevant RTL simulations.
4. Rebuild the main XPR and check timing, DRC, clock coverage, and bit provenance.
5. Run the board-level checks separately; a successful bit generation is not physical validation.

Failure condition: the XPR compiles an unregistered or stale ROM, source changes after the build, or timing/DRC gates fail.

## Stage 6: Record evidence

Record the following in one report:

| Evidence | Minimum proof |
| --- | --- |
| data | split, class count, file hashes |
| training | command, seed, epochs, checkpoint hash |
| conversion | source format, output hash, parameter count |
| numerical | reference outputs, timestep, PASS marker |
| ROM | module widths/depths and XPR registration |
| simulation | test name, log hash, PASS/FAIL |
| build | top, part, WNS/WHS, DRC, bit SHA-256 |
| board | input, expected/actual output, repeated trials, raw evidence |

Do not use a simulator PASS to claim real sensor, motor, arm, power, or scene accuracy.
