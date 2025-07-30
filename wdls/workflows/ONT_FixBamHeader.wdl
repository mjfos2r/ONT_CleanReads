version 1.0
import "../tasks/BamUtils.wdl" as BAM

workflow ONT_FixBamHeaderRG {
    meta { description: "Simple workflow to sanitize the unused readgroups from the BAM file output by Dorado." }

    parameter_meta { input_bam: "merged bam file output by dorado" }

    input { File input_bam }

    call BAM.FixBamHeaderRG { input: input_bam = input_bam }

    output { File sanitized_bam = FixBamHeaderRG.sanitized_bam }
}