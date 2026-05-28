version 1.0
import "../tasks/Chopper.wdl" as CHP

workflow ONT_Chopper {

    meta {
        description: "Simple workflow to run Chopper for barcode trimming, length and quality filtering, and DNA_CS removal from ONT reads. Accepts fastq as input."
    }
    parameter_meta {
        reads_fastq: "raw reads to be pre-processed. must be in fastq format."
        contam_fa: "File containing sequences to filter against. Contains DNA_CS, barcode sequences, and adapters."
        min_quality: "Integer for the minimum quality to keep reads. [Default: 10]"
        max_quality: "Integer for the minimum quality to keep reads. [Optional]"
        min_length: "Integer for the minimum length to keep reads. [Default: 1]"
        max_length: "maximum length for filtering"
        compress_output: "Boolean flag to compress output reads? [Default: true]"
    }

    input {
        File reads_fastq
        Int min_quality
        Int? max_quality
        Int? min_length
        Int? max_length
        File contam_fa
        Boolean compress_output = true
    }

    call CHP.Chopper {
        input:
            input_reads = reads_fastq,
            min_quality = min_quality,
            max_quality = max_quality,
            min_length = min_length,
            max_length = max_length,
            contam_fa = contam_fa,
            compress_output = compress_output
    }

    output {
        File trimmed_reads = Chopper.trimmed_reads
        File chopper_stats = Chopper.stats
    }
}