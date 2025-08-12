version 1.0
import "../structs/Structs.wdl"
import "../tasks/Chopper.wdl" as CHP
import "../tasks/Minimap2.wdl" as MM2
import "../tasks/BamUtils.wdl" as BAM
import "../tasks/GeneralUtils.wdl" as UTILS
import "../tasks/QC.wdl" as QC
import "../tasks/Kraken2.wdl" as K2

workflow ONT_CleanReads {

    meta {
        description: "Workflow to trim and filter reads for assembly and downstream processing"
    }

    input {
        String sample_id
        File reads_fastq
        File contam_fa
        Int filt_min_len = 1000
        Int filt_min_qual = 20
        Boolean compress_chopper_output = true
        File ref_genome # pass it whatever you want.
        File kraken2_db
        String taxid_to_keep = "1643685" #taxid for genus: Borrelia
        String map_preset = "lr:hq"
    }

    call QC.FastQC as FastQC_raw { input: reads = reads_fastq } # basename(reads)_raw

    call CHP.Chopper {
        input:
            sample_id = sample_id,
            input_reads = reads_fastq,
            contam_fa = contam_fa,
            min_length = filt_min_len,
            min_quality = filt_min_qual,
            compress_output = compress_chopper_output
    }

    call QC.FastQC as FastQC_trimmed { input: reads = Chopper.trimmed_reads }

    call K2.Classify as Kraken2 {
        input:
            reads_fq = Chopper.trimmed_reads,
            kraken_db = kraken2_db,
            sample_id = sample_id,
            taxid_to_keep = taxid_to_keep
    }

    # check for reference assembly passed as input.
    Boolean have_reference= defined(ref_genome)

    # if we have it, align our cleaned reads against it and get some bamstats.
    if (have_reference) {
        call MM2.Minimap2 as RefAln {
            input:
                reads_file = Kraken2.filtered_reads,
                ref_fasta = ref_genome,
                prefix = sample_id,
                map_preset = map_preset
        }
        call BAM.BamStats as RefAlnBamStats {
            input:
                input_bam = RefAln.aligned_bam,
                input_bai = RefAln.aligned_bai,
                ref_fasta = ref_genome,
        }
    }

    call QC.FastQC as FastQC_filtered { input: reads = Kraken2.filtered_reads }

    Array[File] reports = select_all([
        FastQC_raw.fastqc_data,
        FastQC_trimmed.fastqc_data,
        FastQC_filtered.fastqc_data,
        Kraken2.kraken2_report,
        RefAlnBamStats.stats,
    ]) # select_all(Array[T?] -> Array[T]) handle it for me.

    call QC.MultiQC { input: input_files = reports }

    output {
        # fastqc_raw output
        File fastqc_raw_data = FastQC_raw.fastqc_data
        File fastqc_raw_report = FastQC_raw.fastqc_report
        # chopper output + stats
        File trimmed_reads = Chopper.trimmed_reads
        File trimmed_reads_chopper_stats = Chopper.stats
        # fastqc_trimmed output
        File fastqc_trimmed_data = FastQC_raw.fastqc_data
        File fastqc_trimmed_report = FastQC_raw.fastqc_report
        # alignment of trimmed reads against reference genome. (if provided)
        File? ReadsVsRef_bam = RefAln.aligned_bam
        File? ReadsVsRef_bai = RefAln.aligned_bai
        File? ReadsVsRef_stats = RefAlnBamStats.stats
        # kraken2 output
        File kraken2_output = Kraken2.kraken2_output
        File kraken2_report = Kraken2.kraken2_report
        File kraken2_log = Kraken2.kraken2_log
        File krona_report = Kraken2.krona_report
        File krona_html = Kraken2.krona_html
        # we're sticking with raw -> trimmed -> filtered -> cleaned
        File cleaned_reads = Kraken2.filtered_reads
        # MultiQC report
        File multiqc_data_preprocessing = MultiQC.multiqc_data
        File multiqc_report_preprocessing = MultiQC.multiqc_report
    }
}