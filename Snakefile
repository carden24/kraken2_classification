# Snakefile for kraken2 classification
# Does classification, plotting, etc
from os.path import join
import sys
# output base directory
outdir = config['outdir']

def get_sample_reads(sample_file):
    sample_reads = {}
    paired_end = ''
    with open(sample_file) as sf:
        for l in sf.readlines():
            s = l.strip().split("\t")
            if len(s) == 1 or s[0] == 'Sample' or s[0] == '#Sample' or s[0].startswith('#'):
                continue
            sample = s[0]
            # paired end specified
            if (len(s)==3):
                reads = [s[1],s[2]]
                if paired_end != '' and not paired_end: 
                    sys.exit('All samples must be paired or single ended.')
                paired_end = True
            # single end specified
            elif len(s)==2:
                reads=s[1]
                if paired_end != '' and paired_end: 
                    sys.exit('All samples must be paired or single ended.')
                paired_end = False
            if sample in sample_reads:
                raise ValueError("Non-unique sample encountered!")
            sample_reads[sample] = reads
    return (sample_reads, paired_end)


# read in sample info and reads from the sample_file 
sample_reads, paired_end = get_sample_reads(config['sample_file'])
if paired_end: 
    paired_string = '--paired'
else: 
    paired_string = ''
sample_names = sample_reads.keys()

# extra specified files to generate from the config file
extra_run_list =[]
# Do we want to run bracken?
if config['database'] == '/labs/asbhatt/data/program_indices/kraken2/kraken_custom_jan2019/genbank_custom':
    print('NO Bracken database for this option yet. Disabling Bracken.')
    run_bracken = False
else: 
    run_bracken = config['run_bracken']
# add bracken to extra files
if run_bracken:
    extra_run_list.append('bracken')
    downsteam_processing_input = expand(join(outdir, "classification/{samp}.krak.report.bracken"), samp=sample_names)
else:
    downsteam_processing_input = expand(join(outdir, "classification/{samp}.krak.report"), samp=sample_names)
# Elis barplot workflow
if config['barplot_datasets'] != '':
    extra_run_list.append('barplot')
    
# additional outputs determined by whats specified in the readme
extra_files = {
    "bracken": expand(join(outdir, "classification/{samp}.krak.report.bracken"), samp=sample_names),
    "barplot": join(outdir, "plots/taxonomic_composition.pdf"),
    "krona": expand(join(outdir, "krona/{samp}.html"), samp = sample_names),
    "mpa_heatmap": join(outdir, "mpa_reports/merge_metaphlan_heatmap.png"),
    "biom_file": join(outdir, "table.biom")
}
run_extra = [extra_files[f] for f in extra_run_list]
# print("run Extra files: " + str(run_extra))

rule all:
    input:
        expand(join(outdir, "classification/{samp}.krak.report"), samp=sample_names),
        join(outdir, 'processed_results/plots/taxonomy_barplot_species.pdf'),
        run_extra
        # expand(join(outdir, "krona/{samp}.html"), samp = sample_names)

rule kraken:
    input: 
        reads = lambda wildcards: sample_reads[wildcards.samp],
        # r2 = lambda wildcards: sample_reads[wildcards.samp][1]
    output:
        krak = join(outdir, "classification/{samp}.krak"),
        krak_report = join(outdir, "classification/{samp}.krak.report")
    params: 
        db = config['database'],
        paired_string = paired_string
    threads: 8 
    resources:
        mem=48,
        time=6
    shell: """
        time kraken2 --db {params.db} --threads {threads} --output {output.krak} \
        --report {output.krak_report} {params.paired_string} {input.reads}
        # and 
        """

rule bracken: 
    input:
        rules.kraken.output
    output:
        join(outdir, "classification/{samp}.krak.report.bracken")
    params: 
        db = config['database'],
        readlen = config['read_length'],
        level = config['taxonomic_level'],
        threshold = 10
    threads: 1
    resources:
        mem = 64,
        time = 1
    shell: """
        bracken -d {params.db} -i {input[1]} -o {output} -r {params.readlen} \
        -l {params.level} -t {params.threshold}
        """

rule downsteam_processing:
    input:
        downsteam_processing_input
    params:
        sample_reads = config["sample_file"],
        sample_groups = config["sample_groups_file"],
        outdir = outdir,
        use_bracken_report = run_bracken
    output:
        join(outdir, 'processed_results/plots/taxonomy_barplot_species.pdf')
    script:
        'scripts/post_classification_workflow.R'

rule krona:
    input: rules.kraken.output.krak_report
    output: join(outdir, "krona/{samp}.html")
    shell: """
        ktImportTaxonomy -m 3 -s 0 -q 0 -t 5 -i {input} -o {output} \
        -tax $(which kraken2 | sed 's/envs\/classification2.*$//g')/envs/classification2/bin/taxonomy
        """

'''
# convert bracken to mpa syle report if desired 
rule convert_bracken_mpa:
    input:
        rules.bracken.output
    output:
        "outputs/mpa_reports/{samp}.krak.report.bracken.mpa"
    script:
        "scripts/convert_report_mpa_style.py"


rule norm_mpa:
    input: 
        rules.convert_bracken_mpa.output
    output:
        "outputs/mpa_reports/{samp}.krak.report.bracken.mpa.norm"
    shell:
        """
        sum=$(grep -vP "\\|" {input} | cut -f 2 | awk '{{sum += $1}} END {{printf ("%.2f\\n", sum/100)}}')
        awk -v sum="$sum" 'BEGIN {{FS="\\t"}} {{OFS="\\t"}} {{print $1,$2/sum}}' {input} > {output}
        """

rule merge_mpa:
    input: 
        expand("outputs/mpa_reports/{samp}.krak.report.bracken.mpa.norm", samp=sample_names)
    output:
        merge = "outputs/mpa_reports/merge_metaphlan.txt",
        merge_species = "outputs/mpa_reports/merge_metaphlan_species.txt"
    shell:
        """
        source activate biobakery2
        merge_metaphlan_tables.py {input} >  {output.merge}
        grep -E "(s__)|(^ID)"  {output.merge} | grep -v "t__" | sed 's/^.*s__//g' >  {output.merge_species}
        """

rule hclust_mpa:
    input:
        merge = "outputs/mpa_reports/merge_metaphlan.txt"
    output:
        heamap1 = "outputs/mpa_reports/merge_metaphlan_heatmap.png",
        heamap2 = "outputs/mpa_reports/merge_metaphlan_heatmap_big.png"
    shell:
        """
        source activate biobakery2
        metaphlan_hclust_heatmap.py --in {input} --top 25 --minv 0.1 -s log --out {output.heatmap1} -f braycurtis -d braycurtis -c viridis 
        metaphlan_hclust_heatmap.py --in {input} --top 150 --minv 0.1 -s log --out {output.heatmap2} -f braycurtis -d braycurtis -c viridis
        """

# make biom formatted tables for use with Qiime2
rule make_biom:
    input: 
        expand("outputs/{samp}.krak.report.bracken", samp=sample_names)
    output:
        "outputs/table.biom"
    shell:
        """
        kraken-biom outputs/*_bracken.report -o {output}
        """
'''