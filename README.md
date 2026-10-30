# Vidar — TraConMech orchestration (initial implementation)

Modes: `--mode create` and `--mode apply`. TSV columns are case-sensitive.

- `config/datasets.tsv`: `dataset`, `input` (absolute H5AD path).
- `config/analysis.tsv`: `AnalysisKind`, `Model` (gene symbol), `Control`, `Experiment` (comma-separated sample IDs).
- Frozen model path: `--models_dir /path/to/models` containing `<Model>.json`.
- `--split true` runs `sc-analyse split --by cell_type` once per dataset and also analyzes ALL.
- `--cluster phase` chooses the plotted grouping; `--condition sample` selects the sample metadata column.

Run (adjust paths and profiles):

    nextflow run . -profile local --mode apply --models_dir /absolute/models --ommverse /absolute/reference --string_info /absolute/info.tsv --string_links /absolute/links.tsv --condition sample --cluster phase

For creation, set `--mode create`; models are written to `--models_dir/<Model>.json`. Do not run two create jobs for the same model concurrently; use one analysis row per model when creating.

**Safety:** Existing published outputs are not overwritten. Nextflow work directories are separate. No deletion of legacy results or experiment.yaml. `-resume` reuses completed tasks. Use an empty output directory for each new version; publication into an existing directory can otherwise mix old and new files.

**Limitations:** This initial version assumes the current CLI model filename convention `<gene>.json` and requires STRING and Ommverse reference paths even for application, as required by the Rust CLI. It has not been exercised against real H5AD data or tested with Nextflow (not installed here). The `create` mode requires additional care if repeated model names occur in analysis.tsv; use a single row per model. No automated legacy directory purge.
