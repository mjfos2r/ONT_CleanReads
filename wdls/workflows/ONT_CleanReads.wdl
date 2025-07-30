version 1.0
import "../structs/Structs.wdl"
import "../tasks/Minimap2.wdl" as MM2
import "../tasks/BamUtils.wdl" as BAM
import "../tasks/GeneralUtils.wdl" as UTILS

workflow WorkflowName {

    meta {
        description: "Description of the workflow"
    }
    parameter_meta {
        input_file: "description of input"
    }

    input {
        File input_file
    }
    output {
    }
}