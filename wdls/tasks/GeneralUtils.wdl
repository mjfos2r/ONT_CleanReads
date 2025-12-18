version 1.0
# Some tasks pulled from github.com/broadinstitute/long-read-pipelines/wdl/tasks/Utility/GeneralUtils.wdl
# Others written by Michael J. Foster (github.com/mjfos2r)

import "../structs/Structs.wdl"

task CompressTarPigz {
    meta {
        description: "compress files into a tarball using parallel gzip and generate an md5 checksum"
        author: "Michael J. Foster"
    }

    parameter_meta {
        files: "List of files to zip up."
        name: "Name of the tar.gz file."
    }

    input {
        Array[File] files
        String name

        Int num_cpus = 16
        Int mem_gb = 32
        RuntimeAttr? runtime_attr_override
    }

    Int disk_size = 50 + ceil(size(files, "GB"))*2

    command <<<
        NUM_CPUS=$(cat /proc/cpuinfo | awk '/^processor/{print }' | wc -l)
        set -euxo pipefail # crash out
        mkdir -p tarpit/
        for ff in ~{sep=' ' files}; do cp "${ff}" tarpit/ ; done
        tar -cf - -C tarpit/ . | pigz -p "${NUM_CPUS}" > ~{name}.tar.gz
        md5sum ~{name}.tar.gz >~{name}.tar.gz.md5
    >>>

    output {
        File tarball = "~{name}.tar.gz"
        File checksum = "~{name}.tar.gz.md5"
    }
    # How about you preempt these hands GCP.
    #########################
    RuntimeAttr default_attr = object {
        cpu_cores:          num_cpus,
        mem_gb:             mem_gb,
        disk_gb:            disk_size,
        boot_disk_gb:       10,
        preemptible_tries:  0,
        max_retries:        1,
        docker:             "mjfos2r/basic:latest"
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

task GetTodayDate {
    meta {
        description: "Generates a YYYY-MM-DD date of today (when this task is called). UTC."
        volatile: true
    }

    input {
        Int num_cpus = 1
        Int mem_gb = 4
        Int disk_size = 10
        RuntimeAttr? runtime_attr_override
    }

    command <<<
        date '+%Y-%m-%d'
    >>>

    output {
        String yyyy_mm_dd = read_string(stdout())
    }

    #########################
    RuntimeAttr default_attr = object {
        cpu_cores:          num_cpus,
        mem_gb:             mem_gb,
        disk_gb:            disk_size,
        boot_disk_gb:       10,
        preemptible_tries:  2,
        max_retries:        1,
        docker:             "mjfos2r/basic:latest"
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

task ValidateMd5sum {
    meta {
        description: "simple task to validate checksum of a file"
        author: "Michael J. Foster"
    }
    parameter_meta {
        file: "input_file to validate"
        checksum: "file containing checksum"
    }
    input {
        File file
        File checksum
        RuntimeAttr? runtime_attr_override
    }

    # Estimate disk size - the compressed archive plus min disk size
    Int disk_size = 365 + ceil(size(file, "GB"))

    command <<<
    set -euxo pipefail # crash out

    EXPECTED_MD5=$(awk '{print $1}' "~{checksum}")
    # This is required as the awk command can hang.
    md5sum "~{file}" > actual_sum.txt
    ACTUAL_MD5=$(awk '{print $1}' actual_sum.txt)
    if [ "$EXPECTED_MD5" != "$ACTUAL_MD5" ]; then
        echo "ERROR: CHECKSUM VALIDATION FAILED FOR ~{file}"
        echo "ERROR: Expected: $EXPECTED_MD5"
        echo "ERROR:   Actual: $ACTUAL_MD5"
        echo "false" > valid.txt
    else
        echo "###################################################"
        echo "SUCCESS: Checksum validation successful for ~{file}"
        echo "###################################################"
        echo "true" > valid.txt
    fi
    >>>

    output {
        File is_valid = "valid.txt"
    }
    # DO NOT PREEMPT FTLOG.
    #########################
    RuntimeAttr default_attr = object {
        cpu_cores:          2,
        mem_gb:             8,
        disk_gb:            disk_size,
        boot_disk_gb:       10,
        preemptible_tries:  0,
        max_retries:        1,
        docker:             "mjfos2r/basic:latest"
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

task DecompressRunTarball {
    meta {
        description: "Decompress a validated run tarball using pigz"
    }

    parameter_meta {
        tarball: "validated tarball to decompress"
    }

    input {
        File tarball
        File tarball_hash
        File? raw_hash_file
        File? raw_hash_digest
        Boolean singleplex = false
        String? sample_id

        # Runtime parameters
        Int num_cpus = 16
        Int mem_gb = 64
        RuntimeAttr? runtime_attr_override
    }

    Int disk_size = 365 + 3*ceil(size(tarball, "GB"))

    command <<<
        set -euo pipefail

        NPROC=$(awk '/^processor/{print}' /proc/cpuinfo | wc -l)

        # check for the required args early before decomp.
        if [ -n "~{sample_id}" ] && [ "~{singleplex}" == "true" ]; then
            echo "[ INFO ]::[ Processing run as singleplex... ]::[ $(date) ]"
            EXTRACTED="extracted/~{sample_id}"
        elif [ "~{singleplex}" == "true" ] || [ -n "~{sample_id}" ]; then
            echo "[ FAIL ]::[ ERROR: Singleplex run or sample_id provided but not both!Check your args and try again! ]::[ $(date) ]"
            exit 1
        else
            echo "[ INFO ]::[ Processing run as multiplex... ]::[ $(date) ]"
            EXTRACTED="extracted"
        fi

        # now validate the big ole tarball.
        echo "[ INFO ]::[ Validating tarball checksum... ]::[ $(date) ]"
        EXPECTED_MD5=$(cat "~{tarball_hash}" | awk '{print $1}')
        md5sum "~{tarball}" > actual_sum.txt
        ACTUAL_MD5=$(cat actual_sum.txt | awk '{print $1}')
        if [ "$EXPECTED_MD5" != "$ACTUAL_MD5" ]; then
            echo "[ FAIL ]::[ CHECKSUM VALIDATION FAILED FOR ARCHIVE ]::[ $(date) ]"
            echo "[ HASH ]::[ tarball: EXPECTED_MD5: $EXPECTED_MD5 ]::[ $(date) ]"
            echo "[ HASH ]::[ tarball:   ACTUAL_MD5: $ACTUAL_MD5 ]::[ $(date) ]"
            VALID=false
            echo "false" > valid.txt
        else
            echo "[ PASS ]::[ CHECKSUM VALIDATION SUCCESSFUL FOR ARCHIVE ]::[ $(date) ]"
            echo "[ HASH ]::[ tarball: EXPECTED_MD5: $EXPECTED_MD5 ]::[ $(date) ]"
            echo "[ HASH ]::[ tarball:   ACTUAL_MD5: $ACTUAL_MD5 ]::[ $(date) ]"
            VALID=true
            echo "true" > valid.txt
        fi

        if ! "$VALID"; then
            echo "[ FAIL ]::[ Extracted reads validation failed! ]::[ $(date) ]"
            exit 1
        fi

        # todo: figure out a faster way to validate tarball integrity..should probably just do the md5sum checking here?
        # handy snippet from community post: 360073540652-Cromwell-execution-directory
        gcs_task_call_basepath=$(cat gcs_delocalization.sh | grep -o '"gs:\/\/.*/glob-.*/' | sed 's#^"##' |sed 's#/$##' | head -n 1)
        echo "[ INFO ]::[ gcs_task_call_basepath = $gcs_task_call_basepath ]::[ $(date) ]"
        true > gcs_merged_reads_paths.txt

        mkdir -p "$EXTRACTED"
        mkdir -p merged
        echo "[ INFO ]::[ Decompressing archive... ]::[ $(date) ]"
        # crack the tarball, strip the top bam_pass component so we're left with barcode dirs OR just bams in the sample_id dir.
        tar -xzf ~{tarball} -C "$EXTRACTED" --strip-components=1
        echo "[ INFO ]::[ Decompression finished! ]::[ $(date) ]"
        WD="$(pwd)"
        # if we've provided the hash and digest, validate em.
        if [[ -f "~{raw_hash_digest}" && -f "~{raw_hash_file}" ]]; then
            echo "[ INFO ]::[ Validating raw tarball contents via provided raw_hash and raw_hash_digest files ]::[ $(date) ]"
            # if we have the raw_hash and raw_digest, check all the reads!
            # idk if this is properly named, what is a better way to name the hash of many hashes?
            # file -> md5sum -> file.md5 (hash) -> md5sum -> file.md5.md5 (hash of hash)
            #                                                (or alternatively, file.md5.digest)
            #echo -e "\nCurrent location (PWD):               ${PWD}\n"
            #echo -e "\nCurrent location of files.md5:        $(realpath ~{raw_hash_file})\n"
            #echo -e "\nCurrent location of files.md5.digest: $(realpath ~{raw_hash_digest})\n"
            # you know what, actually we need to just pull the digest from hashes.
            echo "[ INFO ]::[ Validating archive contents hashfile. ]::[ $(date) ]"
            RAW_MD5_DIGEST_EXPECTED=$(cat "~{raw_hash_digest}" | awk '{print $1}')
            RAW_MD5_DIGEST_CALC=$(md5sum "~{raw_hash_file}" | awk '{print $1}')
            if [ "$RAW_MD5_DIGEST_EXPECTED" == "$RAW_MD5_DIGEST_CALC" ]; then
                echo "[ PASS ]::[ Archive contents hashfile is valid! ]::[ $(date) ]"
            else
                echo "[ FAIL ]::[ Archive contents hashfile is invalid! ]::[ $(date) ]"
                exit 1
            fi
            TMPFILE=$(mktemp)
            # if our hash file is valid, hop into the extracted dir, check everything, then hop back
            cd "$EXTRACTED"
            echo "[ INFO ]::[ Validating extracted contents... ]::[ $(date) ]"
            if md5sum -c "~{raw_hash_file}" 2>&1 | tee "$TMPFILE" | grep "FAILED"; then
                echo "[ FAIL ]::[ Extracted reads validation failed! ]::[ $(date) ]"
                cat "$TMPFILE" | grep "FAILED" > ../corrupted_files.txt
            else
                echo "[ PASS ]::[ Extracted content integrity: VALID! Continuing with processing! ]::[ $(date) ]"
                echo "NONE" > "${WD}/corrupted_files.txt"
            fi
            cd -
        else
            echo ""
            echo "[ WARN ]::[ no raw_hash_file/raw_hash_digest provided, skipping checks on extracted contents ]::[ $(date) ]"
        fi

        # Get a list of our directories, pull the barcode ID, all so we can make a list of files for each
        find extracted -mindepth 1 -maxdepth 1 -type d | sort > directory_list.txt
        echo "List of directories within $EXTRACTED"
        cat directory_list.txt
        echo ""
        cut -d'/' -f2 directory_list.txt > barcodes.txt
        mkdir -p file_lists

        # Count the number of directories for verification
        wc -l directory_list.txt | awk '{print $1}' > directory_count.txt
        # Create/clear the counts file before the loop
        true > file_counts.txt

        # do NOT use samtools merge as it will mangle the read groups and cause significant grief when
        # trying to use this file downstream.
        index=1
        num_barcodes=$(cat directory_list.txt|wc -l)
        while read -r DIR_PATH; do
            BARCODE="$(basename "$DIR_PATH")"
            # if we have bams, merge the bams.
            if [[ -n $(find "$DIR_PATH" -name "*.bam" -print -quit) ]]; then
                echo "[ ${BARCODE} ]::[ BAM input detected. Merging reads ]::[ ${index}/${num_barcodes} ]"
                BAM_LIST="file_lists/${BARCODE}_files.txt"
                find "$DIR_PATH" -name "*.bam" | sort > "file_lists/${BARCODE}_files.txt"
                cat "${BAM_LIST}" | wc -l >> file_counts.txt
                samtools cat -o merged/"${BARCODE}_raw.merged.bam" -b "$BAM_LIST"
                echo "${gcs_task_call_basepath}/${BARCODE}_raw.merged.bam" >> gcs_merged_reads_paths.txt
                (( index+=1 ))
            elif [[ -n $(find "$DIR_PATH" -name "*.f*q.gz" -print -quit) ]]; then
                echo "[ ${BARCODE} ]::[ Fastq input detected. Merging reads ]::[ ${index}/${num_barcodes} ]"
                FQ_LIST="file_lists/${BARCODE}_files.txt"
                find "$DIR_PATH" -name "*.f*q.gz" | sort > "file_lists/${BARCODE}_files.txt"
                cat "${FQ_LIST}" | wc -l >> file_counts.txt
                xargs zcat <"$FQ_LIST" | pigz -c -p "$NPROC" > "merged/${BARCODE}_raw.merged.fastq.gz"
                echo "${gcs_task_call_basepath}/${BARCODE}_raw.merged.fastq.gz" >> gcs_merged_reads_paths.txt
                (( index+=1 ))
            else
                echo "[ ERROR ]::[ NO BAM OR FASTQ FILES FOUND IN $DIR_PATH ]::[ $(date) ]"
                (( index+=1 ))
            fi
        done < directory_list.txt
        echo "[ INFO ]::[ Finished merging all reads. Task complete! ]::[ $(date) ]"
        >>>

    output {
        # how many barcodes we working with?
        Int directory_count = read_int("directory_count.txt")
        Array[String] directory_list = read_lines("directory_list.txt")
        # how many read files we got?
        Array[Int] file_counts = read_lines("file_counts.txt")
        # and what files did we merge?
        Array[File] file_list = glob("file_lists/*_files.txt")
        # output an array of our barcode_ids
        Array[String] barcode = read_lines("barcodes.txt")
        ### Actually, we don't need to mess with this, we need this output to merged_reads in the seqrun table and only changed in the samplesheet. easy enough!
        # depending on what input was fed into this, output either to:
        # merged_fastq or merged_bam column
        #Array[File]? merged_fastq = glob("merged/*.merged.fastq.gz")
        #Array[File]? merged_bam = glob("merged/*.merged.bam")
        Array[File] merged_reads = glob("merged/*.merged.*")
        File glob_paths = "gcs_merged_reads_paths.txt"
        Boolean is_valid = read_boolean("valid.txt")
        File corrupted_files = "corrupted_files.txt"
    }

    #########################
    # DO NOT PREEMPT THIS JOB FOR THE LOVE OF ALL THAT IS GOOD IN THIS WORLD.
    # Also use SSD please and thank you.
    RuntimeAttr default_attr = object {
        cpu_cores:          num_cpus,
        mem_gb:             mem_gb,
        disk_gb:            disk_size,
        boot_disk_gb:       50,
        preemptible_tries:  0,
        max_retries:        1,
        docker:             "mjfos2r/align-tools:latest"
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

task CreateMap {
    # gfys WDL1.0
    input {
        Array[String] keys
        Array[File] values
    }

    command <<<
        python3 <<CODE
        import json
        keys = ["~{sep='","' keys}"]
        values = ["~{sep='","' values}"]
        result = {}
        for i in range(len(keys)):
            result[keys[i]] = values[i]
        with open("map.json", "w") as f:
            json.dump(result, f)
        CODE
    >>>

    output {
        Map[String, File] mmap = read_json("map.json")
    }

    runtime {
        docker: "python:3.11-slim"
    }
}

task RenameFile {
    meta {
        description: "Decompress a validated run tarball using pigz"
    }

    parameter_meta {
        file: "file to rename"
        new_name: "new filename"
    }

    input {
        File file
        String new_name

        # Runtime parameters
        Int num_cpus = 2
        Int mem_gb = 8

        RuntimeAttr? runtime_attr_override
    }

    Int disk_size = 50 + 2*ceil(size(file, "GB"))

    command <<<
        set -euxo pipefail

        mkdir -p renamed

        NEWNAME="~{new_name}"
        FILE="~{file}"
        EXT="${FILE##*.}"
        echo "Original Filename: ${FILE}"
        echo "Extension: ${EXT}"
        echo "New Filename: renamed/${NEWNAME}.${EXT}"
        mv "$FILE" "renamed/${NEWNAME}.${EXT}"
        >>>

    output {
        File renamed_file = glob("renamed/*")[0]
    }

    #########################
    # DO NOT PREEMPT THIS JOB FOR THE LOVE OF ALL THAT IS GOOD IN THIS WORLD.
    # Also use SSD please and thank you.
    RuntimeAttr default_attr = object {
        cpu_cores:          num_cpus,
        mem_gb:             mem_gb,
        disk_gb:            disk_size,
        boot_disk_gb:       15,
        preemptible_tries:  0,
        max_retries:        1,
        docker:             "mjfos2r/basic:latest"
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

workflow GetGcpFileMd5 {
    # From broadinstitute/ops-terra-utils/wdl/GetGcpFileMd5.wdl
    input {
        String gcp_file_path
        Boolean create_cloud_md5_file
        String? md5_format
        String? docker
        Int? memory_gb
    }

    String docker_image = select_first([docker, "us-central1-docker.pkg.dev/operations-portal-427515/ops-toolbox/ops_terra_utils_slim:latest"])

    call GetFileMd5 {
        input:
            gcp_file_path = gcp_file_path,
            create_cloud_md5_file = create_cloud_md5_file,
            docker_image = docker_image,
            md5_format = md5_format,
            memory_gb = memory_gb
    }

    output {
        String md5_hash = GetFileMd5.md5_hash
    }
}

task GetFileMd5 {
    # From broadinstitute/ops-terra-utils/wdl/GetGcpFileMd5.wdl
    input {
        String gcp_file_path
        Boolean create_cloud_md5_file
        String docker_image
        String? md5_format
        Int? memory_gb
    }

    command <<<
        python /etc/terra_utils/python/get_file_md5.py \
        --gcp_file_path ~{gcp_file_path} \
        --output_file object_md5.txt \
        ~{if create_cloud_md5_file then "--create_cloud_md5_file" else ""} \
        ~{"--md5_format " + md5_format}
    >>>

    runtime {
        docker: docker_image
        memory: select_first([memory_gb, 4]) + " GB"
    }

    output {
        String md5_hash = read_string("object_md5.txt")
    }
}