version 1.0

import "../structs/Structs.wdl"

task Classify {
    input {
        File reads_fq
        File kraken_db
        String sample_id
        String taxid_to_keep = "1643685" # borrelia genus taxid
        Int num_cpus = 32
        Int mem_gb = 128
        RuntimeAttr? runtime_attr_override
    }

    parameter_meta {
        reads_fq: "reads in fastq format to be classified"
        kraken_db: "kraken2 database to use in classification"
        sample_id: "sample_id for the reads being classified"
        taxid_to_keep: "This is the NCBI taxonomy ID that will be used to filter reads after kraken2 classification. It defaults to the family taxid for Borreliaceae: 1643685, change as desired."
    }

    # the db is compressed so it will run out of disk unless given plenty of room.
    Float total_input_size = 2 * size(kraken_db, "GB") + 2 * size(reads_fq, "GB")
    Int disk_size = 365 + ceil(total_input_size)
    command <<<
        set -euo pipefail
        shopt -s failglob

                # timing function for debugging and optimization
        timeit() {
            local start end rc cmd
            start="${EPOCHREALTIME}"
            "$@"; rc=$?; cmd="$1"
            end="${EPOCHREALTIME}"
            awk -v c="$cmd" -v s="$start" -v e="$end" 'BEGIN {printf "Elapsed: %s took %.3f s\n", c, (e-s)}' >&2
            return $rc
        }

        echo "Beginning Execution"
        NPROCS=$(cat /proc/cpuinfo | awk '/^processor/{print}' | wc -l)

        # first things first we gotta crack open our kraken2 db and get it setup where it needs to be
        KRAKEN2_DB_PATH="kraken2_db"
        mkdir -p "$KRAKEN2_DB_PATH"
        echo "Decompressing kraken2 database. please stand by."
        timeit rapidgzip -cP "${NPROCS}" -d ~{kraken_db} | timeit tar -xvf - -C "$KRAKEN2_DB_PATH" --strip-components=1
        echo "Kraken2 database successfully decompressed."

        # now let's classify our reads.
        echo "Classifying reads using kraken2! please stand by..."
        timeit k2 classify \
            --db "$KRAKEN2_DB_PATH" \
            --threads "$NPROCS" \
            --memory-mapping \
            --report kraken2_report.txt \
            --log kraken2_log.txt \
            ~{reads_fq} > kraken2_output.k2
        echo "Classification with k2 is finished!"

        timeit kreport2krona.py \
            -r kraken2_report.txt \
            -o krona_report.txt
        echo "txt krona report created!"

        timeit ktImportText krona_report.txt -o krona_report.html
        echo "HTML krona report created!"

        # set up output file
        OUTPUT_FQ="~{sample_id}_cleaned.fastq"
        # this script uses carriage returns which pollutes stdout.
        # pipe it through sed and strip all of the unnecessary lines
        # so that stdout is still readable.
        timeit extract_kraken_reads.py \
            -k kraken2_output.k2 \
            -r kraken2_report.txt \
            -s ~{reads_fq} \
            -o "$OUTPUT_FQ" \
            -t ~{taxid_to_keep} \
            --fastq-output \
            --include-children 2>&1 | sed '/\r/d'

        echo "Extraction of classified reads is finished!"
        echo "Gzipping filtered reads! Please stand by."
        timeit cat "$OUTPUT_FQ" | timeit pigz -1cp "$NPROCS" > "${OUTPUT_FQ}.gz"
        echo "Compression finished! Have a wonderful day!"
    >>>

    output {
        File kraken2_output = "kraken2_output.k2"
        File kraken2_report = "kraken2_report.txt"
        File kraken2_log = "kraken2_log.txt"
        File krona_report = "krona_report.txt"
        File krona_html = "krona_report.html"
        File filtered_reads = glob("*_cleaned.f*q.gz")[0]
    }

    #########################
    RuntimeAttr default_attr = object {
        cpu_cores:          num_cpus,
        mem_gb:             mem_gb,
        disk_gb:            disk_size,
        boot_disk_gb:       10,
        preemptible_tries:  0,
        max_retries:        1,
        docker:             "mjfos2r/kraken2:latest"
    }
    RuntimeAttr runtime_attr = select_first([runtime_attr_override, default_attr])
    runtime {
        cpu:                    select_first([runtime_attr.cpu_cores,         default_attr.cpu_cores])
        memory:                 select_first([runtime_attr.mem_gb,            default_attr.mem_gb]) + " GiB"
        disks: "local-disk " +  select_first([runtime_attr.disk_gb,           default_attr.disk_gb]) + " SSD"
        bootDiskSizeGb:         select_first([runtime_attr.boot_disk_gb,      default_attr.boot_disk_gb])
        preemptible:            select_first([runtime_attr.preemptible_tries, default_attr.preemptible_tries])
        maxRetries:             select_first([runtime_attr.max_retries,       default_attr.max_retries])
        docker:                 select_first([runtime_attr.docker,            default_attr.docker])
    }
}