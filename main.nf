nextflow.enable.dsl = 2

// Paths in the TSVs are absolute. A row's Model is the gene symbol;
// portable model path is models_dir/<Model>.json.
process SPLIT_H5AD {
  tag "$dataset"
  cpus 2
  memory '16 GB'
  publishDir "${params.outdir}/subsets/${dataset}", mode: 'copy', overwrite: false, failOnError: true
  input:
  tuple val(dataset), path(h5ad)
  output:
  tuple val(dataset), path('subsets/*.h5ad')
  script:
  """
  set -euo pipefail
  ${params.sc_analyse} split --data '${h5ad}' --by '${params.split_by}' --out subsets
  test -n "\$(find subsets -maxdepth 1 -name '*.h5ad' -print -quit)" || { echo 'ERROR: no subsets produced' >&2; exit 1; }
  """
}

process RUN_MODEL {
  tag "${dataset}/${population}/${model}/${kind}"
  cpus 8
  memory '48 GB'
  publishDir "${params.outdir}/analyses/${dataset}/${population}/${model}_${kind}", mode: 'copy', pattern: 'result/**', overwrite: false, failOnError: true
  input:
  tuple val(dataset), val(population), path(h5ad), val(kind), val(model), val(control), val(experiment), val(model_file)
  output:
  path('result')
  script:
  def action = params.mode.toString()
  def ctl = control.split(',').collect { it.trim() }.findAll { it }.join(' ')
  def exp = experiment.split(',').collect { it.trim() }.findAll { it }.join(' ')
  """
  set -euo pipefail
  mkdir result
  mkdir -p "\$(dirname '${model_file}')"
  ${params.traconmech} gene-model ${action} \\
    --data '${h5ad}' --gene '${model}' --model '${model_file}' \\
    --ommverse '${params.ommverse}' --string-info '${params.string_info}' --string-links '${params.string_links}' \\
    --condition '${params.condition}' --cluster '${params.cluster}' \\
    --control ${ctl} --case ${exp} --out result --non-interactive
  test -s result/experiment.yaml || { echo 'ERROR: missing experiment.yaml' >&2; exit 1; }
  """
}

workflow {
  if (!(params.mode.toString() in ['create','apply'])) error 'mode must be create or apply'
  for (key in ['ommverse','string_info','string_links']) {
    if (!params[key] || !file(params[key].toString()).exists()) error "Missing required reference --${key}: ${params[key]}"
  }
  def datasets = Channel.fromPath(params.datasets, checkIfExists: true)
    .splitCsv(header: true, sep: '\t')
    .map { r ->
      def id = r.dataset?.trim(); def input = r.input?.trim()
      if (!(id ==~ /[A-Za-z0-9_-]+/)) error "Invalid dataset ID: ${id}"
      if (!input || !file(input).isFile()) error "Missing H5AD for ${id}: ${input}"
      tuple(id, file(input))
    }
  def rows = Channel.fromPath(params.analyses, checkIfExists: true)
    .splitCsv(header: true, sep: '\t')
    .map { r ->
      def kind = r.AnalysisKind?.trim(); def model = r.Model?.trim()
      def control = r.Control?.trim(); def experiment = r.Experiment?.trim()
      if (!(kind ==~ /[A-Za-z0-9_-]+/) || !(model ==~ /[A-Za-z0-9_-]+/)) error "Invalid analysis/model: ${r}"
      if (!control || !experiment) error "Empty control/experiment in ${r}"
      if (!([control,experiment].every { it ==~ /[A-Za-z0-9_,.-]+/ })) error "Unsafe sample names in ${r}"
      def modelPath = file("${params.models_dir}/${model}.json")
      if (params.mode == 'apply' && !modelPath.isFile()) error "Missing frozen model: ${modelPath}"
      tuple(kind,model,control,experiment,modelPath)
    }
  def populations = datasets.map { id, h5ad -> tuple(id,'ALL',h5ad) }
  if (params.split) {
    def parts = SPLIT_H5AD(datasets)
      .flatMap { id, files -> files.collect { f -> tuple(id, f.baseName, f) } }
    populations = populations.mix(parts)
  }
  def jobs = populations.combine(rows)
    .map { id,pop,h5ad,kind,model,control,experiment,modelPath ->
      tuple(id,pop,h5ad,kind,model,control,experiment,modelPath)
    }
  RUN_MODEL(jobs)
}
