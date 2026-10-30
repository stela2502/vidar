# Vidar — TraConMech model creation and application

Vidar is a Nextflow DSL2 pipeline for running `traconmech gene-model create` or `traconmech gene-model apply` across datasets, populations and experimental comparisons. It optionally splits an H5AD by an observation column using `sc-analyse split`. **This is an initial implementation, not yet validated with Nextflow or biological data.**

## 1. Prepare the input tables

Both files must be **tab-separated TSV files**, with the header exactly as shown (case-sensitive). Use absolute paths for inputs. The bundled examples in `config/` are placeholders; replace them before running.

### `config/datasets.tsv`

```tsv
dataset	input
own	/absolute/path/to/own/sc_analysis/analysis.h5ad
GSE156441	/absolute/path/to/GSE156441/sc_analysis_combined/analysis.h5ad
```

- `dataset`: unique identifier containing only letters, digits, `_`, or `-`. It becomes part of the output directory.
- `input`: existing, readable H5AD file (not a MEX directory). The pipeline checks that the path exists.

Every dataset is combined with **every row** in `analysis.tsv`; the current implementation cannot select different analysis rows for different datasets. Ensure that all sample IDs referenced by an analysis are appropriate for each dataset, or run the datasets separately with different tables.

### `config/analysis.tsv`

```tsv
AnalysisKind	Model	Control	Experiment
TOTAL	TP53	CTRL_BP03,CTRL_BP07,CTRL_Con3	DBA_RPS_1,DBA_RPS_3,DBA_RPS_4,DBA_RPL_1,DBA_RPL_8,DBA_RPL_4
RPS	TP53	CTRL_BP03,CTRL_BP07,CTRL_Con3	DBA_RPS_1,DBA_RPS_3,DBA_RPS_4
RPL	TP53	CTRL_BP03,CTRL_BP07,CTRL_Con3	DBA_RPL_1,DBA_RPL_8,DBA_RPL_4
TOTAL	GATA1	CTRL_BP03,CTRL_BP07,CTRL_Con3	DBA_RPS_1,DBA_RPS_3,DBA_RPS_4,DBA_RPL_1,DBA_RPL_8,DBA_RPL_4
```

- `AnalysisKind`: your name for the comparison (`TOTAL`, `RPS`, `RPL`, etc.); allowed characters are letters, digits, `_`, `-`.
- `Model`: gene/model identifier (`TP53`, `GATA1`), **not a file path**. The current implementation resolves it to `<models_dir>/<Model>.json`.
- `Control`: comma-separated sample IDs, with no spaces; passed to `--control`.
- `Experiment`: comma-separated sample IDs, with no spaces; passed to TraConMech as `--case`.

The H5AD must contain the observation metadata column named by `--condition` (default `sample`), with values matching the sample IDs **exactly**, and the column named by `--cluster` (default `phase`). If splitting, it must also contain `--split_by` (default `cell_type`). Check your H5AD column names before running. These group names are illustrative; replace them with names in your dataset.

To make a TSV without accidentally inserting spaces, you can use Python's `csv` module with `delimiter="\t"`, or edit the included examples in a TSV-aware editor.

## 2. Reference inputs and models

The current workflow requires all three reference arguments, even in apply mode:

- `--ommverse`: existing Ommverse reference path.
- `--string_info`: existing STRING protein information file.
- `--string_links`: existing STRING protein links file.

`--models_dir` is the directory containing `<Model>.json` for apply mode. For example, with `Model=TP53`, Vidar checks for `/data/models/TP53.json` when `--models_dir /data/models` is supplied. Model creation uses the same model path. Verify that this filename convention matches the actual files you use; it is an assumption in this initial pipeline.

## 3. Run

From the Vidar project directory, using installed local binaries:

```bash
nextflow run . -profile local -resume \
  --mode apply \
  --datasets "$PWD/config/datasets.tsv" \
  --analyses "$PWD/config/analysis.tsv" \
  --models_dir /absolute/path/to/models \
  --ommverse /absolute/path/to/ommverse \
  --string_info /absolute/path/to/protein.info.tsv \
  --string_links /absolute/path/to/protein.links.tsv \
  --condition sample --cluster phase \
  --traconmech /absolute/path/to/traconmech \
  --sc_analyse /absolute/path/to/sc-analyse \
  --outdir /absolute/path/to/vidar_results
```

To generate models instead, use `--mode create`. **Current limitation:** do not put multiple create rows for the same `Model` into one run, because they can target the same model file. Use one row per model. The create/apply CLI argument combinations and model-file handling still need end-to-end verification.

To analyze ALL cells **and** each cell-type subset, add `--split true --split_by cell_type`. Without `--split true`, only ALL is analyzed. Splitting creates new H5AD files; it does not change the original.

For cluster execution use `-profile slurm` or `-profile apptainer` with a **verified** `--lumrik_image` containing the required binaries. The default `ghcr.io/stela2502/lumrik:v0.9.2` is a proposed tag, not verified as available. There is no automatic image download in the workflow logic, but Apptainer may fetch a remote container reference when configured to do so; use a local SIF if you want to avoid that.

## 4. Outputs and execution behavior

With `--outdir /path/to/vidar_results`, results are published under:

```text
vidar_results/
  subsets/<dataset>/...                  # only with --split true
  analyses/<dataset>/<population>/<Model>_<AnalysisKind>/result/
    experiment.yaml
    module_trajectories.tsv
    module_*_trajectory.svg
    ...                                  # other TraConMech outputs
```

The exact contents of `result/` depend on TraConMech. Population `ALL` means the original H5AD. Other population identifiers are derived from the split filenames.

The current implementation combines **all datasets × all populations × all analysis rows**. It does not deduplicate analysis names, validate the sample IDs against the H5AD, or guarantee that every output directory is unique. Avoid duplicate `(Model, AnalysisKind)` rows and colliding dataset/population names.

Use `-resume` to reuse successful Nextflow tasks. Existing published outputs are not overwritten (`publishDir overwrite:false`), but this does not guarantee transactional publishing. Do **not** reuse an output directory for an unrelated new run. No old analysis directory or `experiment.yaml` is deliberately deleted. Do not purge legacy results until the new pipeline is validated.

## 5. Troubleshooting

- **Missing frozen model:** confirm `--models_dir` and `<Model>.json`.
- **No matching groups:** verify `--condition` and the exact `Control`/`Experiment` sample IDs in H5AD `obs`.
- **Missing grouping column:** set `--cluster` to an existing `obs` column, e.g. `phase`.
- **No subsets:** confirm `--split_by` exists and `sc-analyse split` produces `.h5ad` files.
- **Unexpected number of jobs:** remember that Vidar currently takes the Cartesian product of datasets, populations and analysis rows.

See `nextflow.config` and `main.nf` for the precise behavior of this initial implementation.
