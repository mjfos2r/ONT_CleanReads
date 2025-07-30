version 1.0

import "../structs/Structs.wdl"

task Chopper {
    input {
        File input_reads
        File contam_fa
        Int min_quality = 10
        Int min_length = 500
        Boolean compress_output = true
        # NO EXTRA ARGS NO NO NO
        # CHOPPER DOESNT LIKE EMPTY STRINGS AS ARGS.

        Int num_cpus = 4
        Int mem_gb = 8
        RuntimeAttr? runtime_attr_override
    }
    String basename = sub(basename(input_reads), "\\..*$", "")
    Boolean is_input_gzipped = sub(input_reads, ".*\\.", "") == "gz"
    String output_filename = basename + ".clean.fq" + (if compress_output then ".gz" else "")

    Int disk_size = 50 + 3*ceil(size(input_reads, "GB"))

    command <<<
        set -euo pipefail

        NPROCS=$( grep '^processor' /proc/cpuinfo | tail -n1 | awk '{print $NF+1}' )

        # Determine input type and run appropriate Chopper command
        if [ "~{is_input_gzipped}" == "true" ]; then
            # Input is gzipped
            gunzip -c "~{input_reads}" | \
            chopper --contam "~{contam_fa}" -q "~{min_quality}" -l "~{min_length}" --threads "$NPROCS" | \
            ~{if compress_output then "gzip" else "cat"} > "~{output_filename}"
        else
            # Input is not gzipped
            chopper --contam "~{contam_fa}" -q "~{min_quality}" -l "~{min_length}" -i "~{input_reads}" --threads "$NPROCS" | \
            ~{if compress_output then "gzip" else "cat"} > "~{output_filename}"
        fi

        # Calculate read stats before
        seqkit stats ~{input_reads} -b -a -T > "stats.tsv"
        seqkit stats ~{output_filename} -b -a -T | tail -n +2 >> "stats.tsv"
    >>>

    output {
        File trimmed_reads = "~{output_filename}"
        File stats = "stats.tsv"
    }
    # Do not preempt.
    #########################
    RuntimeAttr default_attr = object {
        cpu_cores:          num_cpus,
        mem_gb:             mem_gb,
        disk_gb:            disk_size,
        boot_disk_gb:       25,
        preemptible_tries:  0,
        max_retries:        1,
        docker:             "mjfos2r/chopper:latest"
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