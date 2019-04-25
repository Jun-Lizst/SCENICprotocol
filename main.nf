#!/usr/bin/env nextflow

println( "\n***\nParameters in use:")
params.each { println "${it}" }
println( "***\n")


// process importData {
// 
// }

file( "${params.outdir}" ).mkdirs()


/*
 * basic filtering
 */

process filter {
    cache 'deep'
    container params.scanpy_container

    input:
    file loomUnfiltered from file( params.loom_input )

    output:
    file params.loom_filtered into expr

    """
    filtering-basic.py \
        --loom_input ${loomUnfiltered} \
        --loom_filtered ${params.loom_filtered} \
        --thr_min_genes ${params.thr_min_genes} \
        --thr_min_cells ${params.thr_min_cells} \
        --thr_n_genes ${params.thr_n_genes} \
        --thr_pct_mito ${params.thr_pct_mito}
    """
}
expr.last().collectFile(storeDir:params.outdir)

/*
 * end of basic filtering
 */


/*
 * preprocess, visualize, project, cluster processing steps
 */

process preprocess {
    cache 'deep'
    container params.scanpy_container
    input:
    file params.loom_filtered from expr
    output:
    file '01_preprocessed.h5ad' into SCpreprocess
    """
    preprocess_visualize_project_scanpy.py \
        preprocess \
        --loom_filtered ${params.loom_filtered} \
        --ad_preprocessed 01_preprocessed.h5ad \
        --threads ${params.threads}
    """
}

process pca {
    cache 'deep'
    container params.scanpy_container
    input:
    file '01_preprocessed.h5ad' from SCpreprocess
    output:
    file '02_pca.h5ad' into SCpca
    """
    preprocess_visualize_project_scanpy.py \
        pca \
        --ad_pca 02_pca.h5ad \
        --threads ${params.threads}
    """
}

process visualize {
    cache 'deep'
    container params.scanpy_container
    input:
    file '02_pca.h5ad' from SCpca
    output:
    file '03_visualize.h5ad' into SCvisualize
    """
    preprocess_visualize_project_scanpy.py \
        visualize \
        --ad_visualize 03_visualize.h5ad \
        --threads ${params.threads}
    """
}

process cluster {
    cache 'deep'
    container params.scanpy_container
    input:
    file '03_visualize.h5ad' from SCvisualize
    output:
    file '03_visualize.h5ad' into SCcluster
    """
    preprocess_visualize_project_scanpy.py \
        cluster \
        --ad_cluster 04_cluster.h5ad \
        --threads ${params.threads}
    """
}


/*
 * End of preprocess, visualize, project, cluster processing steps
 */


/*
 * SCENIC steps
 */

// channel for SCENIC databases resources:
featherDB = Channel
    .fromPath( params.db )
    .collect() // use all files together in the ctx command

n = Channel.fromPath(params.db).count().get()
if( n==1 ) {
    println( "***\nWARNING: only using a single feather database:\n  ${featherDB.get()[0]}.\nTo include all database files using pattern matching, make sure the value for the '--db' parameter is enclosed in quotes!\n***\n" )
} else {
    println( "***\nUsing $n feather databases:")
    featherDB.get().each {
        println "  ${it}"
    }
    println( "***\n")
}

// expr = file(params.expr)
tfs = file(params.TFs)
motifs = file(params.motifs)

process GRNinference {
    cache 'deep'
    container params.pyscenic_container

    input:
    file TFs from tfs
    file params.loom_filtered from expr
    // file exprMat from expr

    output:
    file 'adj.tsv' into GRN

    """
    pyscenic grn \
        --num_workers ${params.threads} \
        -o adj.tsv \
        --method ${params.grn} \
        --cell_id_attribute ${params.cell_id_attribute} \
        --gene_attribute ${params.gene_attribute} \
        ${params.loom_filtered} \
        ${TFs}
    """
}

process cisTarget {
    cache 'deep'
    container params.pyscenic_container

    input:
    file exprMat from expr
    file 'adj.tsv' from GRN
    file feather from featherDB
    file motif from motifs

    output:
    file 'reg.csv' into regulons

    """
    pyscenic ctx \
        adj.tsv \
        ${feather} \
        --annotations_fname ${motif} \
        --expression_mtx_fname ${exprMat} \
        --cell_id_attribute ${params.cell_id_attribute} \
        --gene_attribute ${params.gene_attribute} \
        --mode "dask_multiprocessing" \
        --output reg.csv \
        --num_workers ${params.threads} \
    """
}

process AUCell {
    cache 'deep'
    container params.pyscenic_container

    input:
    file exprMat from expr
    file 'reg.csv' from regulons

    output:
    file params.pyscenic_output into AUCmat

    """
    pyscenic aucell \
        $exprMat \
        reg.csv \
        -o ${params.output} \
        --cell_id_attribute ${params.cell_id_attribute} \
        --gene_attribute ${params.gene_attribute} \
        --num_workers ${params.threads}
    """
}

AUCmat.last().collectFile(storeDir:params.outdir)

/*
 * end of SCENIC steps
 */



/*
 * results integration
 */

/*
 * end of results integration
 */

