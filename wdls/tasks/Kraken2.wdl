version 1.0

import "../structs/Structs.wdl"

task Classify {
    input {
        File reads_fq
        File kraken_db
        String sample_id
        String taxid_to_keep = "1643685" # borrelia genus taxid
        RuntimeAttr? runtime_attr_override
    }

    parameter_meta {
        reads_fq: "reads in fastq format to be classified"
        kraken_db: "kraken2 database to use in classification"
        sample_id: "sample_id for the reads being classified"
        taxid_to_keep: "This is the NCBI taxonomy ID that will be used to filter reads after kraken2 classification. It defaults to the family taxid for Borreliaceae: 1643685, change as desired."
    }

    Float total_input_size = 2 * size(reads_fq, "GB") + size(kraken_db, "GB")
    Int disk_size = 100 + ceil(total_input_size)
    command <<<
        set -euo pipefail
        shopt -s failglob

        NPROCS=$(cat /proc/cpuinfo | awk '/^processor/{print}' | wc -l)

        # first things first we gotta crack open our kraken2 db and get it setup where it needs to be
        KRAKEN2_DB_PATH="/kraken2_dbs"
        tar -xvzf ~{kraken_db} -C "$KRAKEN2_DB_PATH" --strip-components=1

        # ok now lets just get some simple stats on our input reads
        echo "Generating basic stats on our input reads using seqkit..."
        seqkit stats ~{reads_fq} > prefilter_reads_stats.tsv

        # now let's classify our reads.
        echo "Classifying reads using kraken2! please stand by..."
        k2 classify \
            --db "$KRAKEN2_DB_PATH" \
            --threads "$NPROCS" \
            --memory-mapping \
            --report kraken2_report.txt \
            --log kraken2_log.txt \
            ~{reads_fq} > kraken2_output.k2

        kreport2krona.py \
            -r kraken2_report.txt \
            -o krona_report.txt

        echo "txt krona report created!"

        ktImportText krona_report.txt -o krona_report.html

        echo "HTML krona report created!"

        OUTPUT_FQ="~{sample_id}_filtered.fastq"

        extract_kraken_reads.py \
            -k kraken2_output.k2 \
            -r kraken2_report.txt \
            -s ~{reads_fq} \
            -o "$OUTPUT_FQ" \
            -t ~{taxid_to_keep} \
            --include-children

        echo "Extraction of classified reads is finished!"
        echo "Counting filtered reads using seqkit..."
        seqkit stats "$OUTPUT_FQ" > filtered_reads_stats.tsv
        echo "Gzipping filtered reads! Please stand by."
        gzip "$OUTPUT_FQ"
        echo "Compression finished! Have a wonderful day!"
    >>>

    output {
        File kraken2_output = "kraken2_output.k2"
        File kraken2_report = "kraken2_report.txt"
        File kraken2_log = "kraken2_log.txt"
        File krona_report = "krona_report.txt"
        File krona_html = "krona_report.html"
        File filtered_reads = glob("*_filtered.fastq.gz")[0]
        File prefilter_stats = "prefilter_reads.stats.tsv"
        File filter_stats = "filtered_reads.stats.tsv"
    }

    #########################
    RuntimeAttr default_attr = object {
        cpu_cores:          32,
        mem_gb:             128,
        disk_gb:            disk_size,
        boot_disk_gb:       10,
        preemptible_tries:  3,
        max_retries:        1,
        docker:             "mjfos2r/kraken2:latest"
    }
    RuntimeAttr runtime_attr = select_first([runtime_attr_override, default_attr])
    runtime {
        cpu:                    select_first([runtime_attr.cpu_cores,         default_attr.cpu_cores])
        memory:                 select_first([runtime_attr.mem_gb,            default_attr.mem_gb]) + " GiB"
        disks: "local-disk " +  select_first([runtime_attr.disk_gb,           default_attr.disk_gb]) + " HDD"
        bootDiskSizeGb:         select_first([runtime_attr.boot_disk_gb,      default_attr.boot_disk_gb])
        preemptible:            select_first([runtime_attr.preemptible_tries, default_attr.preemptible_tries])
        maxRetries:             select_first([runtime_attr.max_retries,       default_attr.max_retries])
        docker:                 select_first([runtime_attr.docker,            default_attr.docker])
    }
}