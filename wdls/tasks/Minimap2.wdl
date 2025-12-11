version 1.0

import "../structs/Structs.wdl"
# swiped from a broad workflow ;)
task Minimap2 {
    meta {
        description: "A wrapper to minimap2 for mapping & aligning a single sequence file to a reference"
    }
    parameter_meta {
        reads_file:       "query sequence file to be mapped and aligned"
        ref_fasta:        "reference fasta"
        prefix:           "prefix to use in the output bam file. (e.g. sample1.prefix.bam)"
        # RG parameter removed as BAM already contains read group information from Dorado
        map_preset:       "[ Default: 'lr:hq' ] preset to be used for minimap2 parameter '-x'"
    }
    input {
        File reads_file
        File ref_fasta
        String prefix
        String map_preset = "lr:hq"
        Int cpus = 4
        Int mem = 32
        RuntimeAttr? runtime_attr_override
    }

    Int disk_size = 1 + 10*2*2*ceil(size(reads_file, "GB") + size(ref_fasta, "GB"))


    command <<<
        set -euxo pipefail

        NPROCS=$( grep '^processor' /proc/cpuinfo | tail -n1 | awk '{print $NF+1}' )
        RAM_IN_GB=$( free -g | grep "^Mem" | awk '{print $2}' )
        MEM_FOR_SORT=$( echo "" | awk "{print int(($RAM_IN_GB - 1)/$NPROCS)}" )

        # No RG parameter needed as it's already in the BAM
        # drop y since it's causing faulty bam issues >:|
        MAP_PARAMS="-aYL --MD --eqx -x ~{map_preset} -t $NPROCS ~{ref_fasta}"

        SORT_PARAMS="-@ $NPROCS -m${MEM_FOR_SORT}G --no-PG -o ~{prefix}.pre.bam"
        FILE="~{reads_file}"

        # Broad Notes:
        # We write to a SAM file before sorting and indexing because rarely, doing everything
        # in a single one-liner leads to a truncated file error and segmentation fault of unknown
        # origin.  Separating these commands requires more resources, but is more reliable overall.

        if [[ "$FILE" =~ \.fastq$ ]] || [[ "$FILE" =~ \.fq$ ]]; then
            cat $FILE | minimap2 $MAP_PARAMS - > tmp.sam
        elif [[ "$FILE" =~ \.fastq.gz$ ]] || [[ "$FILE" =~ \.fq.gz$ ]]; then
            zcat $FILE | minimap2 $MAP_PARAMS - > tmp.sam
        elif [[ "$FILE" =~ \.fasta$ ]] || [[ "$FILE" =~ \.fa$ ]]; then
            cat $FILE | python3 /usr/local/bin/cat_as_fastq.py | minimap2 $MAP_PARAMS - > tmp.sam
        elif [[ "$FILE" =~ \.fasta.gz$ ]] || [[ "$FILE" =~ \.fa.gz$ ]]; then
            zcat $FILE | python3 /usr/local/bin/cat_as_fastq.py | minimap2 $MAP_PARAMS - > tmp.sam
        elif [[ "$FILE" =~ \.bam$ ]]; then
            samtools fastq -T '*' "$FILE" | minimap2 "$MAP_PARAMS" - > tmp.sam # save all tags
        else
            echo "Did not understand file format for '$FILE'"
            exit 1
        fi

        samtools sort $SORT_PARAMS tmp.sam

        # Library entry modification removed since we're not fooling with RG

        # Run calmd on the pre-processed BAM
        samtools calmd -b --no-PG "~{prefix}.pre.bam" "~{ref_fasta}" > "~{prefix}.bam"
        samtools index -@ "$NPROCS" "~{prefix}.bam"
        rm ./*.pre.bam
    >>>

    output {
        # Use glob() to find the output BAM and index regardless of name
        File aligned_bam = glob("*.bam")[0]
        File aligned_bai = glob("*.bam.bai")[0]
    }

    #########################
    RuntimeAttr default_attr = object {
        cpu_cores:          cpus,
        mem_gb:             mem,
        disk_gb:            disk_size,
        boot_disk_gb:       25,
        preemptible_tries:  3,
        max_retries:        2,
        docker:             "mjfos2r/align-tools:latest"
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