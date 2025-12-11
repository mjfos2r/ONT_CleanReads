version 1.0

import "../structs/Structs.wdl"

task Chopper {
    meta {
        description: "Task to trim and filter ONT reads using Chopper."
        author: "Michael J. Foster"
    }
    parameter_meta {
        sample_id: "String containing the sample_id for these reads"
        input_reads: "File containing the raw reads to be trimmed and filtered."
        contam_fa: "File containing sequences to filter against. Contains DNA_CS, barcode sequences, and adapters."
        min_quality: "Integer for the minimum quality to keep reads. [Default: 10]"
        min_length: "Integer for the minimum length to keep reads. [Default: 500]"
        compress_output: "Boolean flag to compress output reads? [Default: true]"
        num_cpus: "Integer count of cpus to use in trimming. must be at least 16. [Default: 8]"
        mem_gb: "Integer for the amount of memory in GiB to use in trimming. [Default: 32]"
    }
    input {
        String sample_id
        File input_reads
        File contam_fa
        Int min_quality = 10
        Int min_length = 500
        Boolean compress_output = true
        Int num_cpus = 8
        Int mem_gb = 32
        RuntimeAttr? runtime_attr_override
    }

    String output_reads = sample_id + "_trimmed.fq" + (if compress_output then ".gz" else "")

    Int disk_size = 500 + 3*ceil(size(input_reads, "GB")) # refer to the GCP documentation on IOP by resources.

    command <<<
        set -euo pipefail
        shopt -s nullglob

        DECOMP_T=1 # one thread for reading the file
        STATS_T=4 # four per stats instance (is default)
        ALL_STATS_T=$(( STATS_T * 2 )) # eight threads total
        PIGZ_T=4
        RESERVED_T=$((DECOMP_T + ALL_STATS_T + PIGZ_T))
        NPROCS=$( cat /proc/cpuinfo | grep '^processor' | tail -n1 | awk '{print $NF+1}' || 1 )

        if [[ "${NPROCS}" -lt "${RESERVED_T}" ]]; then
            echo "ERROR: Number of CPUs provided is insufficient. Please specify more than (${RESERVED_T} + 4) and try again." >&2
        fi

        CHOPPER_T=$(( NPROCS - RESERVED_T ))

        in_name="$(basename ~{input_reads})"
        out_file="~{output_reads}"
        GZOUT="~{compress_output}"
        CHOPPER_ARGS=(
            --contam "~{contam_fa}"
            -q "~{min_quality}"
            -l "~{min_length}"
            --threads "${CHOPPER_T}"
        )
        # some helper functions
        stream() {
            case "$1" in
                *.gz) zcat -- "$1" ;;
                *)    cat -- "$1" ;;
            esac
        }
        writer() {
            local isgz="$GZOUT"
            local pgz_t="$PIGZ_T"
            case "$isgz" in
                true) pigz -1cp "$pgz_t" -- ;;
                false) cat -- ;;
            esac
        }
        # timing function for debugging and optimization
        timeit() {
            local start end rc cmd
            start="${EPOCHREALTIME}"
            "$@"; rc=$?; cmd="$1"
            end="${EPOCHREALTIME}"
            awk -v c="$cmd" -v s="$start" -v e="$end" 'BEGIN {printf "Elapsed: %s took %.3f s\n", c, (e-s)}' >&2
            return $rc
        }

        ## Actually process our reads now.

        #shellcheck disable=SC2094
        timeit stream ~{input_reads} \
            | tee >(timeit seqkit stats -i "${in_name}" -aT >raw_stats.tsv) \
            | timeit chopper "${CHOPPER_ARGS[@]}" \
            | tee >(timeit seqkit stats -i "${out_file}" -aT >trim_stats.tsv) \
            | writer > "${out_file}"

        cat raw_stats.tsv trim_stats.tsv > stats.tsv
    >>>

    output {
        File trimmed_reads = "~{output_reads}"
        File stats = "stats.tsv"
    }
    # Do not preempt.
    #########################
    RuntimeAttr default_attr = object {
        cpu_cores:          num_cpus,
        mem_gb:             mem_gb,
        disk_gb:            disk_size,
        boot_disk_gb:       25,
        preemptible_tries:  3,
        max_retries:        1,
        docker:             "mjfos2r/chopper:latest"
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