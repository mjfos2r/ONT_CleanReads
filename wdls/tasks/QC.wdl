version 1.0
import "../structs/Structs.wdl"

task FastQC {
    meta {
        description: "Use FastQC to generate QC reports for a given input file of reads."
    }

    parameter_meta {
        reads: "Single file containing our reads. should be fastq.gz or bam"
        nanopore: "flag specifying if input is from nanopore [default: false]"
        runtime_attr_override: "Override the default runtime attributes."
    }

    input {
        File reads
        String? tag
        Boolean nanopore = true
        RuntimeAttr? runtime_attr_override
    }

    Int disk_size = 365 + 2*ceil(size(reads, "GB"))

    command <<<
        set -euo pipefail

        NPROCS=$(cat /proc/cpuinfo | grep '^processor' | tail -n1 | awk '{print $NF+1}')
        RAM_IN_MB=$( free -m | grep "^Mem" | awk '{print $2}' )
        MEM_PER_THREAD=$( echo "" | awk "{print int(($RAM_IN_MB - 1000)/$NPROCS)}" )
        mkdir outdir

        # TODO: Add filesize conditional where if there's too many reads, it just takes a subsample
        #       using seqkit sample or something similar. Something like 25% if it's a file over 20GiB...
        #       this is just ridiculous tbh.
        if [[ -n ~{tag} ]]; then
            reads_fn=~{reads}
            reads="${reads_fn%%.*}_~{tag}.fq.gz"
        else
            reads=~{reads}
        fi

        if ~{nanopore}; then
            echo "Beginning execution of FastQC in Nanopore mode!"
            fastqc \
                -t "$NPROCS" \
                --memory "$MEM_PER_THREAD" \
                --outdir outdir \
                --nano \
                ~{reads}
            echo "Finished!"
        else
            echo "Beginning execution of FastQC."
            fastqc \
                -t "$NPROCS" \
                --memory "$MEM_PER_THREAD" \
                --outdir outdir \
                ~{reads}
            echo "Finished!"
        fi
        echo "Files present in outdir:"
        ls -l outdir/
    >>>

    output {
        File fastqc_data = glob("outdir/*_fastqc.zip")[0]
        File fastqc_report = glob("outdir/*_fastqc.html")[0]
    }

    #########################
    # BEGONE PREEMPTION
    RuntimeAttr default_attr = object {
        cpu_cores:          16,
        mem_gb:             64,
        disk_gb:            disk_size,
        boot_disk_gb:       50,
        preemptible_tries:  0,
        max_retries:        1,
        docker:             "mjfos2r/fastqc:latest"
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

task MultiQC {
    meta {
        description: "Use multiqc to generate a single interactive report for an array of files."
    }

    parameter_meta {
        input_files: "Array of files to use in report creation."
        runtime_attr_override: "Override the default runtime attributes."
    }

    input {
        Array[File] input_files
        RuntimeAttr? runtime_attr_override
    }

    Int disk_size = 365 + ceil(size(input_files, "GB"))

    command <<<
        set -euxo pipefail

        NPROCS=$(cat /proc/cpuinfo | grep '^processor' | tail -n1 | awk '{print $NF+1}')

        mkdir input_data multiqc_out
        cp ~{sep=" " input_files} input_data/
        echo "Contents of input_data:"
        ls input_data/

        multiqc \
            --outdir multiqc_out \
            --fullnames \
            --zip-data-dir \
            --interactive \
            input_data

        echo "Finished!"
    >>>

    output {
        File multiqc_data = "multiqc_out/multiqc_data.zip"
        File multiqc_report = "multiqc_out/multiqc_report.html"
    }

    #########################
    # BEGONE PREEMPTION
    RuntimeAttr default_attr = object {
        cpu_cores:          4,
        mem_gb:             16,
        disk_gb:            disk_size,
        boot_disk_gb:       50,
        preemptible_tries:  0,
        max_retries:        1,
        docker:             "mjfos2r/fastqc:latest"
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