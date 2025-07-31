version 1.0
# Pulled from github.com/broadinstitute/long-read-pipelines/wdl/tasks/Utility/GeneralUtils.wdl
# With some changes

import "../structs/Structs.wdl"

task MergeBams {
    meta {
        desciption: "when provided with a directory of bam files for a given barcode, merge them all into a single file, sort it, and index it. also return flagstats"
    }

    parameter_meta {
        input_bams: "list of bams to merge"
        name: "name for merged bam. do not specify .bam"
    }

    input {
        Array[File] input_bams
        String name # should be something like Barcode##
        RuntimeAttr? runtime_attr_override
    }

    String output_bam ="~{name}.bam"

    Int disk_size = 50 + 2*ceil(size(input_bams, "GB"))

    command <<<
    set -euo pipefail # if anything breaks crash out

    # get the number of procs we have available
    NPROCS=$( grep '^processor' /proc/cpuinfo | tail -n1 | awk '{print $NF+1}' )

    # list our bams that we're merging
    echo "[INFO] :: Merging BAMs ::"
    for bam in "~{sep=' ' input_bams}"; do
        echo "  - $bam"
    done

    # merge and sort em
    samtools merge \
        -f \
        -@ "$NPROCS" \
        -o merged.tmp.bam \
        "~{sep=' ' input_bams}"

    samtools sort \
        -@ "$NPROCS" \
        -m $(( 8 / "$NPROCS"))G \
        -o "~{output_bam}" \
        merged.tmp.bam

    # get the index
    samtools index "~{output_bam}"

    # and get some stats
    samtools flagstat "~{output_bam}"

    # cleanup
    rm merged.tmp.bam
    >>>

    output {
        File merged_bam = "~{output_bam}"
        File merged_bam_index = "~{output_bam}.bai"
        File stats = "~{output_bam}.stats"
    }
    # no preempt.
    #########################
    RuntimeAttr default_attr = object {
        cpu_cores:          4,
        mem_gb:             8,
        disk_gb:            disk_size,
        boot_disk_gb:       10,
        preemptible_tries:  0,
        max_retries:        1,
        docker:             "mjfos2r/samtools:latest"
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

task Bam2Fastq {
    meta {
        description: "convert bam to fastq.gz file and preserve all tags written by Dorado basecaller."
    }

    parameter_meta {
        input_bam: "Bam file to convert to fastq"
        sample_id: "Optional: our sample id                          [Default: basename(input_bam)]"
        st_params: "Parameters to pass to samtools during conversion [Default: -T '*']"
        num_cpus:  "how many cores to use for conversion             [Default: 8]"
        mem_gb:    "how much memory to use for conversion            [Default: 32]"
    }

    input {
        File input_bam
        String? sample_id
        String st_params = "-T '*'"
        Int num_cpus = 8
        Int mem_gb = 32
        RuntimeAttr? runtime_attr_override
    }

    String bn_input = basename(input_bam)
    String fn_raw = select_first([sample_id, bn_input])
    String fn_clean = sub(fn_raw, "\\.bam$", "")
    Float input_size = size(input_bam, "GB")
    Int disk_size = 365 + 3*ceil(input_size)

    command <<<
    set -euo pipefail # if anything breaks crash out

    # get the number of procs we have available
    NPROCS=$( cat /proc/cpuinfo | grep '^processor' | tail -n1 | awk '{print $NF+1}' )
    echo "Input BAM File: ~{input_bam}"
    echo "Output Fastq File: ~{fn_clean}_R1.fastq.gz"
    echo "Input BAM Size: ~{input_size}"
    echo "Disk Size: ~{disk_size}"
    echo "NPROCS: $NPROCS"
    echo "Samtools parameters: ~{st_params}"
    echo "*****"
    echo "Sorting input bam!"
    samtools sort -@ "$NPROCS" -n -o sorted.bam ~{input_bam}
    echo "Sorting finished! Beginning conversion of sorted.bam to fastq..."
    # preserve all tags that dorado puts in the BAM.
    # and add _R1 to keep things consistent with the thiagen workflow
    samtools fastq -@ "$NPROCS" ~{st_params} -0 "~{fn_clean}_R1.fastq.gz" sorted.bam
    echo "Conversion finished!"
    >>>

    output {
        File fastq = "~{fn_clean}_R1.fastq.gz"
    }
    # no preempt.
    #########################
    RuntimeAttr default_attr = object {
        cpu_cores:          num_cpus,
        mem_gb:             mem_gb,
        disk_gb:            disk_size,
        boot_disk_gb:       50,
        preemptible_tries:  0,
        max_retries:        1,
        docker:             "mjfos2r/samtools:latest"
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

task FixBamHeaderRG {
    input {
        File input_bam
        String? RG

        RuntimeAttr? runtime_attr_override
    }

    parameter_meta {
        input_bam: "raw bam with dirty header, filled with unused RGs"
        RG: "Optional: read group to keep? Not implemented." # nah no need, unless?
    }

    Int disk_size = 365 +  2 * ceil(size(input_bam, "GB"))

    command <<<
        set -euo pipefail
        shopt -s failglob

        # first things first, lets make an output directory, pull our basename, and set up the final output filename
        fname="$(basename ~{input_bam})"
        output_bam="${fname%.bam}.f.bam"
        mkdir -p fixed

        # okay, pull the current header with a simple grep and save it to a file, also separate just the readgroups to a separate file
        samtools view --no-PG -H ~{input_bam} | tee dirty_header.sam | grep "^@RG" > rgs_in_header.txt
        # now pull these headers and count how many of each we've got in this file
        samtools view --no-PG ~{input_bam} | \
        awk -F'\t' \
        '{
            for (i=12; i<=NF; i++)
            {
                if ($i ~ /^RG:Z:/)
                {
                    rg = substr($i, 6)
                    count[rg]++
                    break
                }
            }
        } END {
            for (rg in count) print rg "\t" count[rg]
        }' > rgs_counts.txt

        # check that we actually have RGs in this bam file.
        if [[ ! -s rgs_counts.txt ]]; then
            echo "ERROR: rgs_counts.txt is empty! there appear to be no RGs counted in this bam file. Something has gone wrong."
            exit 1
        fi

        # since files merged with samtools merge have UUIDs appended to each RG:ID we need to strip that and collapse the duplicate RGs
        cat rgs_counts.txt | cut -f1 | sed -E 's/(.*)+(-[A-Z0-9]+)$/\1/'| uniq > uniq_rgs.txt
        NUMUNIQ="$(cat uniq_rgs.txt | wc -l)"
        if [[ "$NUMUNIQ" -ne 1 ]]; then
            echo "ERROR: More than one unique RG has been identified in this BAM file. Something has gone wrong.\nNum Uniq RGs: $NUMUNIQ"
            exit 1
        else
            new_rg_id="$(cat uniq_rgs_present.txt)"
            echo "New RG for BAM file repair: $new_rg_id"
        fi

        # now we need to prep the actual RG line for samtools. grep the line we want into a new file.
        cat dirty_header.sam | grep "^@RG" | grep "$new_rg_id\s" | tee new_rg_line.txt

        # and now we actually fix the readgroups in our bam.
        samtools addreplacerg \
            -w \
            -m overwrite_all \
            -r "$(cat new_rg_line.txt)" \
            -o fixed_rg.bam \
            ~{input_bam}

        # we also need to deal with @PG lines.
        samtools view --no-PG -H fixed_rg.bam | sed -E 's/(.*)+(-[A-Z0-9]+\s)+(.*)$/\1\t\3/' | uniq > clean_header.sam
        # and finally, we reheader our original bamfile.
        samtools reheader \
            clean_header.sam \
            fixed_rg.bam > "fixed/${output_bam}"

        echo "BAM file successfully repaired. Have a wonderful day."
    >>>

    output {
        File sanitized_bam = glob("fixed/*.f.bam")[0]
    }

    #########################
    RuntimeAttr default_attr = object {
        cpu_cores:          2,
        mem_gb:             4,
        disk_gb:            disk_size,
        boot_disk_gb:       10,
        preemptible_tries:  3,
        max_retries:        1,
        docker:             "mjfos2r/samtools:latest"
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

task BamStats {
    meta {
        desciption: "generate bamstats file for a given alignment."
    }

    parameter_meta {
        input_bam: "input bam"
        input_bai: "input bai"
    }

    input {
        File input_bam
        File input_bai
        File? ref_fasta
        RuntimeAttr? runtime_attr_override
    }

    Int disk_size = 50 + 2*ceil(size(input_bam, "GB"))

    command <<<
    set -euo pipefail # if anything breaks crash out

    # get the number of procs we have available
    NPROCS=$(cat /proc/cpuinfo | grep '^processor' | tail -n1 | awk '{print $NF+1}' )

    mkdir -p stats

    echo "generating stats for the provided input bam. please stand by."

    if [[ -s ~{ref_fasta} ]]; then
        PARAMS="--reference ~{ref_fasta}"
    else
        PARAMS=""
    fi

    OUTFILE="$(basename ~{input_bam})"
    samtools stats --threads "$NPROCS" $PARAMS ~{input_bam} >"stats/${OUTFILE}.stats"
    echo "Finished! Have a wonderful day!"
    >>>

    output {
        File stats = glob("stats/*.stats")[0]
    }
    # no preempt.
    #########################
    RuntimeAttr default_attr = object {
        cpu_cores:          4,
        mem_gb:             8,
        disk_gb:            disk_size,
        boot_disk_gb:       10,
        preemptible_tries:  0,
        max_retries:        1,
        docker:             "mjfos2r/samtools:latest"
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